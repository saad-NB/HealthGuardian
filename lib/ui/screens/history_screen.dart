import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/app_state.dart';
import '../../triage/record.dart';
import '../../triage/record_store.dart';
import '../theme/app_tokens.dart';
import 'settings_action.dart';

/// History tab (UI/UX plan §7.7, spec §15/§19-2). Lists completed triages
/// from the encrypted local store, newest first. Each entry shows the patient
/// name (when captured at the start) + timestamp; tapping opens a detail card
/// with the findings, vitals, AI summary and triage, plus an "Ask AI" handoff
/// that re-opens the chat with the case context attached. Carries the
/// top-left Settings gear when [app] is provided (ADR-017).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.store, this.onAskAi, this.app});

  /// Injected in tests; defaults to the real encrypted store.
  final TriageRecordStore? store;

  /// Called by the detail card's "Ask AI" button (RootShell switches tabs).
  final void Function(TriageRecord record)? onAskAi;

  /// Shared app state, used for the top-left Settings gear. Optional so tests
  /// can drive the screen without an [AppState].
  final AppState? app;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final TriageRecordStore _store = widget.store ?? TriageRecordStore();
  late Future<List<TriageRecord>> _records = _store.loadAll();

  void _reload() => setState(() {
        _records = _store.loadAll();
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<TriageRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data ?? const [];
          if (records.isEmpty) return _emptyState();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.margin,
                  12,
                  AppMetrics.margin,
                  4,
                ),
                child: Row(
                  children: [
                    if (widget.app != null) ...[
                      SettingsAction(app: widget.app!),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      'Triage history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppMetrics.margin),
                  itemCount: records.length,
                  itemBuilder: (context, i) => _recordTile(records[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _recordTile(TriageRecord record) {
    final tier = record.finalTier;
    final name = record.patientName;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: AppMetrics.answerGap),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tier.color,
          child: Text(
            tier.urgencyIndex + 1 == 1 ? '!' : 'P${tier.urgencyIndex + 1}',
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name.isNotEmpty ? name : tier.shortLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (record.aiEscalated) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_upward,
                  size: 14, color: AppColors.textSubdued),
              Text('AI ↑', style: Theme.of(context).textTheme.labelSmall),
            ],
          ],
        ),
        subtitle: Text(_subtitle(record)),
        isThreeLine: true,
        onTap: () => _showRecord(context, record),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () => _delete(record.triageId),
        ),
      ),
    );
  }

  /// Line 1: tier + date/time; line 2: first finding / missing params.
  String _subtitle(TriageRecord record) {
    final firstReason = record.mergeReasons.isNotEmpty
        ? record.mergeReasons.first
        : 'No escalation reasons.';
    final timeLabel = '${record.finalTier.label}  ·  ${_formatTimestamp(record.timestamp)}';
    final details = record.missingParams.isNotEmpty
        ? '\nMissing: ${record.missingParams.join(', ')}'
        : '';
    return '$timeLabel\n$firstReason$details'.trim();
  }

  String _formatTimestamp(DateTime ts) {
    final local = ts.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _delete(String triageId) async {
    await _store.delete(triageId);
    _reload();
  }

  Future<void> _showRecord(BuildContext context, TriageRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.margin,
              0,
              AppMetrics.margin,
              AppMetrics.margin,
            ),
            children: [
              _header(record),
              const Divider(),
              _sectionTitle('Major findings'),
              if (record.mergeReasons.isEmpty)
                Text('No escalation reasons.',
                    style: Theme.of(context).textTheme.bodyMedium),
              for (final reason in record.mergeReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(color: AppColors.textSubdued)),
                      Expanded(
                        child: Text(reason,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              if (record.missingParams.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Missing: ${record.missingParams.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              _sectionTitle('Vitals & complaints'),
              _vitalsChips(record),
              const SizedBox(height: 8),
              _complaints(record),
              const Divider(),
              _sectionTitle('AI analysis'),
              if (record.tier2 == null)
                Text(
                  'No AI analysis was attached to this record.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else ...[
                Text(
                  record.tier2!.hasSuggestion
                      ? 'Suggestion: ${record.tier2!.suggestion!.name.toUpperCase()}'
                      : 'Suggestion: no change',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (record.aiEscalated) ...[
                  const SizedBox(height: 4),
                  Text(
                    'AI raised urgency vs Tier 1 '
                    '(${record.finalTier.name.toUpperCase()}) — clinical '
                    'review required.',
                    style: const TextStyle(
                      color: Color(0xFFD32F2F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (record.tier2!.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    record.tier2!.summary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onAskAi?.call(record);
                },
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('Ask AI about this case'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _shareRecord(record),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share this record'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the OS share sheet with the whole record card — tier, major
  /// findings, vitals/complaints and the AI analysis — so it can go to
  /// WhatsApp, Instagram, Facebook, SMS, etc.
  Future<void> _shareRecord(TriageRecord record) async {
    final tier = record.finalTier;
    final vitals = (record.inputs['vitals'] as Map?) ?? const {};
    final vitalItems = <String>[
      if (vitals['rr'] != null)
        'Resp. rate: ${vitals['rr']}/min'
      else if (record.missingParams.contains('respiratory rate'))
        'Resp. rate: Not measured',
      if (vitals['spo2'] != null)
        'SpO2: ${vitals['spo2']}%'
      else if (vitals['spo2Missing'] == true)
        'SpO2: Not measured',
      if (vitals['sbp'] != null) 'BP: ${vitals['sbp']} mmHg',
      if (vitals['hr'] != null) 'Heart rate: ${vitals['hr']}/min',
      if (vitals['temp'] != null)
        'Temp: ${vitals['temp']} °C'
      else if (vitals['tempMissing'] == true)
        'Temp: Not measured',
      if (vitals['consciousness'] != null)
        'Consciousness: ${vitals['consciousness']}',
      if (vitals['capillaryRefill'] != null)
        'Cap refill: ${vitals['capillaryRefill']}',
      if (vitals['neonatalConsciousness'] != null)
        'Neonatal state: ${vitals['neonatalConsciousness']}',
      if (vitals['onOxygen'] == true) 'Oxygen: Yes',
      if (vitals['copdCo2Retention'] == true) 'COPD: Yes',
    ];
    final complaints = <String>[
      if (record.inputs['complaint'] is String)
        record.inputs['complaint'] as String,
      for (final c in (record.inputs['additionalComplaints'] as List?) ??
          const <dynamic>[])
        if (c is String) c,
    ];
    final notes = record.inputs['extraComplaintNotes'] as String?;

    final buffer = StringBuffer()
      ..writeln('Sehat Nigraan triage record')
      ..writeln('${tier.label} - action ${tier.response}.')
      ..writeln('Date: ${_formatTimestamp(record.timestamp)}');
    if (record.patientName.isNotEmpty) {
      buffer.writeln('Patient: ${record.patientName}');
    }
    buffer
      ..writeln()
      ..writeln('Major findings:');
    if (record.mergeReasons.isEmpty) {
      buffer.writeln('- No escalation reasons.');
    } else {
      for (final reason in record.mergeReasons) {
        buffer.writeln('- $reason');
      }
    }
    if (record.missingParams.isNotEmpty) {
      buffer.writeln('Missing: ${record.missingParams.join(', ')}');
    }
    buffer
      ..writeln()
      ..writeln('Vitals:');
    if (vitalItems.isEmpty) {
      buffer.writeln('- None recorded.');
    } else {
      for (final item in vitalItems) {
        buffer.writeln('- $item');
      }
    }
    if (complaints.isNotEmpty) {
      buffer.writeln('Complaints: ${complaints.join(', ')}');
    }
    if (notes != null && notes.trim().isNotEmpty) {
      buffer.writeln('Notes: ${notes.trim()}');
    }
    buffer
      ..writeln()
      ..writeln('AI analysis:');
    final tier2 = record.tier2;
    if (tier2 == null) {
      buffer.writeln('- None attached.');
    } else {
      buffer.writeln(
        '- Suggestion: '
        '${tier2.hasSuggestion ? tier2.suggestion!.name.toUpperCase() : 'no change'}',
      );
      if (record.aiEscalated) {
        buffer.writeln(
          '- AI raised urgency vs Tier 1 '
          '(${record.finalTier.name.toUpperCase()}) - clinical review required.',
        );
      }
      if (tier2.summary.isNotEmpty) buffer.writeln(tier2.summary);
    }
    buffer
      ..writeln()
      ..writeln('Decision support, not a diagnosis.');

    await SharePlus.instance.share(
      ShareParams(
        subject: 'Triage record - ${record.finalTier.label}',
        text: buffer.toString().trim(),
      ),
    );
  }

  Widget _header(TriageRecord record) {
    final name = record.patientName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name.isNotEmpty ? name : record.finalTier.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Chip(
              label: Text(record.finalTier.shortLabel),
              backgroundColor: record.finalTier.color,
              labelStyle: TextStyle(
                color: record.finalTier.useDarkText
                    ? Colors.black
                    : Colors.white,
                fontWeight: FontWeight.w700,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${record.finalTier.response}  ·  ${_formatTimestamp(record.timestamp)}',
          style: const TextStyle(color: AppColors.textSubdued),
        ),
        const SizedBox(height: 4),
        Text(
          'Record ${record.triageId}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _vitalsChips(TriageRecord record) {
    final vitals = (record.inputs['vitals'] as Map?) ?? const {};
    final items = <(String, String)>[
      if (vitals['rr'] != null)
        ('Resp. rate', '${vitals['rr']}/min')
      else if (record.missingParams.contains('respiratory rate'))
        ('Resp. rate', 'Not measured'),
      if (vitals['spo2'] != null)
        ('SpO2', '${vitals['spo2']}%')
      else if (vitals['spo2Missing'] == true)
        ('SpO2', 'Not measured'),
      if (vitals['sbp'] != null) ('BP', '${vitals['sbp']} mmHg'),
      if (vitals['hr'] != null) ('Heart rate', '${vitals['hr']}/min'),
      if (vitals['temp'] != null)
        ('Temp', '${vitals['temp']} °C')
      else if (vitals['tempMissing'] == true)
        ('Temp', 'Not measured'),
      if (vitals['consciousness'] != null)
        ('Consciousness', '${vitals['consciousness']}'),
      if (vitals['capillaryRefill'] != null)
        ('Cap refill', '${vitals['capillaryRefill']}'),
      if (vitals['neonatalConsciousness'] != null)
        ('Neonatal state', '${vitals['neonatalConsciousness']}'),
      if (vitals['onOxygen'] == true) ('Oxygen', 'Yes'),
      if (vitals['copdCo2Retention'] == true) ('COPD', 'Yes'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, value) in items)
          Chip(
            label: Text('$label: $value'),
            visualDensity: VisualDensity.compact,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
      ],
    );
  }

  Widget _complaints(TriageRecord record) {
    final complaints = <String>[
      if (record.inputs['complaint'] is String)
        record.inputs['complaint'] as String,
      for (final c in (record.inputs['additionalComplaints'] as List?) ??
          const <dynamic>[])
        if (c is String) c,
    ];
    final notes = record.inputs['extraComplaintNotes'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          complaints.isEmpty ? 'No complaint recorded.' : 'Complaints: ${complaints.join(', ')}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (notes != null && notes.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Notes: ${notes.trim()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 72,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No triage records yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Completed triages are saved here so you can share them with '
              'a clinic.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}