import 'dart:async';

import 'package:flutter/material.dart';

import '../services/tier2_service.dart';
import '../state/app_state.dart';
import '../ui/screens/settings_action.dart';
import '../ui/theme/app_tokens.dart';
import 'dataset.dart';
import 'drug_check_store.dart';
import 'engine.dart';
import 'models.dart';
import 'severity_style.dart';

/// Drugs tab (ADR-018): enter generic medicine names, check them against the
/// bundled offline interaction dataset, and optionally have MedGemma explain a
/// detected interaction on-device.
class DrugCheckScreen extends StatefulWidget {
  const DrugCheckScreen({
    super.key,
    required this.app,
    this.dataset,
    this.store,
    this.tier2Service,
    this.onAskAi,
  });

  final AppState app;

  /// Injectable reference data (tests); defaults to the bundled assets.
  final InteractionDataset? dataset;

  /// Injectable backing store (tests); defaults to the real file store.
  final DrugCheckStore? store;

  /// Injectable Tier 2 service (tests); defaults to one bound to [app].
  final Tier2Service? tier2Service;

  /// Opens the Ask AI tab with this check attached as read-only context
  /// (title, context). Null in tests / when no chat surface is available.
  final void Function(String title, String context)? onAskAi;

  @override
  State<DrugCheckScreen> createState() => _DrugCheckScreenState();
}

class _DrugCheckScreenState extends State<DrugCheckScreen> {
  InteractionDataset? _dataset;
  InteractionEngine? _engine;
  DrugCheckStore? _store;

  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  final List<String> _drugs = [];
  List<Drug> _suggestions = const [];
  List<DrugInteraction> _results = const [];
  List<String> _unknown = const [];
  List<SavedDrugCheck> _recent = const [];
  bool _loading = true;
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dataset = widget.dataset ?? await InteractionDataset.load();
    final store = widget.store ?? DrugCheckStore();
    final recent = await store.loadRecent();
    if (!mounted) return;
    setState(() {
      _dataset = dataset;
      _engine = InteractionEngine(dataset);
      _store = store;
      _recent = recent;
      _loading = false;
    });
  }

  void _onQueryChanged(String value) {
    final dataset = _dataset;
    if (dataset == null) return;
    setState(() {
      _suggestions =
          value.trim().isEmpty ? const [] : dataset.search(value, limit: 6);
    });
  }

  void _addDrug([String? name]) {
    final raw = (name ?? _query.text).trim();
    if (raw.isEmpty) return;
    final dataset = _dataset;
    var display = raw;
    if (dataset != null) {
      final exact = dataset
          .search(raw, limit: 25)
          .where((d) => normalizeDrugName(d.name) == normalizeDrugName(raw));
      if (exact.isNotEmpty) display = exact.first.name;
    }
    final key = normalizeDrugName(display);
    setState(() {
      if (!_drugs.any((d) => normalizeDrugName(d) == key)) {
        _drugs.add(display);
      }
      _query.clear();
      _suggestions = const [];
      _results = const [];
      _unknown = const [];
      _hasChecked = false;
    });
    _queryFocus.requestFocus();
  }

  void _removeDrug(String name) {
    setState(() {
      _drugs.removeWhere((d) => normalizeDrugName(d) == normalizeDrugName(name));
      _results = const [];
      _unknown = const [];
      _hasChecked = false;
    });
  }

  Future<void> _evaluate({required bool save}) async {
    final engine = _engine;
    if (engine == null || _drugs.length < 2) return;
    final results = engine.check(_drugs);
    final unknown = engine.unknownDrugs(_drugs);
    setState(() {
      _results = results;
      _unknown = unknown;
      _hasChecked = true;
    });
    if (save) {
      await _store?.save(
        SavedDrugCheck(
          drugs: List.of(_drugs),
          checkedAt: DateTime.now(),
          interactions: results,
        ),
      );
      await _reloadRecent();
    }
    if (engine.hasBlocking(results) && mounted) {
      await _showBlockingDialog(results);
    }
  }

  Future<void> _reloadRecent() async {
    final store = _store;
    if (store == null) return;
    final recent = await store.loadRecent();
    if (mounted) setState(() => _recent = recent);
  }

  Future<void> _deleteCheck(SavedDrugCheck check) async {
    await _store?.remove(check);
    await _reloadRecent();
  }

  void _restore(SavedDrugCheck check) {
    setState(() {
      _drugs
        ..clear()
        ..addAll(check.drugs);
    });
    _evaluate(save: false);
  }

  Future<void> _showBlockingDialog(List<DrugInteraction> results) {
    final blocking = results.where((r) => r.severity.blocks).toList();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.tierP1,
          size: 40,
        ),
        title: const Text('Serious interaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in blocking)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.drugA} + ${r.drugB} — ${r.severity.headline}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.severity.advice,
                      style: const TextStyle(color: AppColors.textSubdued),
                    ),
                  ],
                ),
              ),
            const Text(
              'Talk to a doctor or pharmacist before taking these together.',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  void _explain(DrugInteraction interaction) {
    final service = widget.tier2Service ?? Tier2Service(app: widget.app);
    if (!service.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Download the MedGemma model in Settings to use AI explanations.',
          ),
        ),
      );
      return;
    }
    final stream = service.explainInteraction(
      drugA: interaction.drugA,
      drugB: interaction.drugB,
      severityLabel: interaction.severity.label,
      referenceAdvice: interaction.severity.advice,
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExplainSheet(
        title: '${interaction.drugA} + ${interaction.drugB}',
        stream: stream,
      ),
    );
  }

  void _askAi() {
    final onAskAi = widget.onAskAi;
    if (onAskAi == null || _drugs.length < 2) return;
    onAskAi(_drugs.join(' + '), _askAiContext());
  }

  String _askAiContext() {
    final buffer = StringBuffer()
      ..writeln('The patient entered these medicines (generic names): '
          '${_drugs.join(', ')}.')
      ..writeln('An offline drug-interaction screening found:');
    if (_results.isEmpty) {
      buffer.writeln('- No known interactions in the bundled reference data.');
    } else {
      for (final result in _results) {
        buffer.writeln('- ${result.drugA} + ${result.drugB}: '
            '${result.severity.label} — ${result.severity.advice}');
      }
    }
    if (_unknown.isNotEmpty) {
      buffer.writeln('Not checked (not in the reference data): '
          '${_unknown.join(', ')}.');
    }
    buffer.writeln(
      'The patient wants to ask questions about this combination. This is '
      'screening information only — give decision support, not a prescription.',
    );
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: SettingsAction(app: widget.app),
        automaticallyImplyLeading: false,
        title: const Text('Drug Check'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppMetrics.margin),
              children: [
                Text(
                  'Add your medicines using their generic names to check for '
                  'known interactions. Works fully offline.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _queryRow(context),
                if (_suggestions.isNotEmpty) _suggestionsList(context),
                const SizedBox(height: 12),
                if (_drugs.isNotEmpty) _selectedChips(context),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _drugs.length < 2 ? null : () => _evaluate(save: true),
                  icon: const Icon(Icons.search),
                  label: const Text('Check interactions'),
                ),
                if (_hasChecked) ...[
                  const SizedBox(height: 24),
                  _resultsSection(context),
                  if (widget.onAskAi != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _askAi,
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Ask AI about these medicines'),
                    ),
                  ],
                ],
                const SizedBox(height: 28),
                _recentSection(context),
                const SizedBox(height: 20),
                Text(
                  'For screening purposes only. Data: US public-domain sources '
                  '(VA NDF-RT, the ONC high-priority list, and openFDA labels). '
                  '"Reported" means an interaction is on record without a '
                  'published severity. This is decision support, not a '
                  'prescription — absence of a warning does not prove a '
                  'combination is safe. Always ask a pharmacist.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _queryRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _query,
            focusNode: _queryFocus,
            textInputAction: TextInputAction.done,
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _addDrug(),
            decoration: const InputDecoration(
              labelText: 'Medicine name',
              hintText: 'e.g. warfarin',
              prefixIcon: Icon(Icons.medication_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: AppMetrics.minTouch,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 56)),
            onPressed: () => _addDrug(),
            child: const Text('Add'),
          ),
        ),
      ],
    );
  }

  Widget _suggestionsList(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          for (final drug in _suggestions)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.medication_outlined,
                color: AppColors.teal700,
              ),
              title: Text(drug.name),
              onTap: () => _addDrug(drug.name),
            ),
        ],
      ),
    );
  }

  Widget _selectedChips(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final drug in _drugs)
            InputChip(
              label: Text(drug),
              onDeleted: () => _removeDrug(drug),
              deleteButtonTooltipMessage: 'Remove $drug',
              backgroundColor: AppColors.optionFill,
              side: const BorderSide(color: AppColors.border),
            ),
        ],
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Results', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_results.isEmpty)
          Text(
            'No known interactions found for these medicines in the reference '
            'data.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          for (final interaction in _results) _resultCard(context, interaction),
        if (_unknown.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Not recognised: ${_unknown.join(', ')}. These were not checked.',
            style: const TextStyle(
              color: AppColors.reviewBanner,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  Widget _resultCard(BuildContext context, DrugInteraction interaction) {
    final color = interactionSeverityColor(interaction.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(interactionSeverityIcon(interaction.severity), color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${interaction.drugA} + ${interaction.drugB}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  interaction.severity.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            interaction.severity.headline,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            interaction.severity.advice,
            style: const TextStyle(color: AppColors.textSubdued, height: 1.4),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _explain(interaction),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Explain'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent checks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_recent.isEmpty)
          Text(
            'Checks you run will be saved here.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final check in _recent) _recentTile(context, check),
      ],
    );
  }

  Widget _recentTile(BuildContext context, SavedDrugCheck check) {
    final count = check.interactions.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: () => _restore(check),
          title: Text(
            check.drugs.join(' + '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          subtitle: Text(
            '${_formatTimestamp(check.checkedAt)} · '
            '${count == 0 ? 'no interactions' : '$count found'}',
            style: const TextStyle(color: AppColors.textSubdued, fontSize: 12),
          ),
          trailing: IconButton(
            onPressed: () => _deleteCheck(check),
            tooltip: 'Delete saved check',
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppColors.textSubdued,
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year} · $hh:$mm';
  }
}

/// Bottom sheet that streams a MedGemma interaction explanation.
class _ExplainSheet extends StatefulWidget {
  const _ExplainSheet({required this.title, required this.stream});

  final String title;
  final Stream<String> stream;

  @override
  State<_ExplainSheet> createState() => _ExplainSheetState();
}

class _ExplainSheetState extends State<_ExplainSheet> {
  final StringBuffer _text = StringBuffer();
  StreamSubscription<String>? _subscription;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.stream.listen(
      (delta) => setState(() => _text.write(delta)),
      onError: (Object error) => setState(() {
        _error = error.toString();
        _done = true;
      }),
      onDone: () => setState(() => _done = true),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text.toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppMetrics.margin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(
                'Could not generate an explanation: $_error',
                style: const TextStyle(color: AppColors.tierP1),
              )
            else if (text.isEmpty && !_done)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'AI explanation — decision support only, not a prescription.',
              style: TextStyle(fontSize: 12, color: AppColors.textSubdued),
            ),
          ],
        ),
      ),
    );
  }
}
