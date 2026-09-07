import 'package:flutter/material.dart';

import '../../triage/record.dart';
import '../../triage/record_store.dart';
import '../theme/app_tokens.dart';

/// History tab (UI/UX plan §7.7, spec §15/§19-2). Lists completed triages
/// from the encrypted local store, newest first, with delete + tap-to-share.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.store});

  /// Injected in tests; defaults to the real encrypted store.
  final TriageRecordStore? store;

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
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: AppMetrics.answerGap),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tier.color,
          child: Text(tier.urgencyIndex + 1 == 1 ? '!' : 'P${tier.urgencyIndex + 1}'),
        ),
        title: Text(_title(record)),
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

  String _title(TriageRecord record) {
    final local = record.timestamp.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(local.day)}-${two(local.month)}-${local.year}';
    final time = '${two(local.hour)}:${two(local.minute)}';
    return '${record.finalTier.label}  ·  $date $time';
  }

  String _subtitle(TriageRecord record) {
    final firstReason = record.mergeReasons.isNotEmpty
        ? record.mergeReasons.first
        : 'No escalation reasons.';
    final secondLine = record.missingParams.isNotEmpty
        ? 'Missing: ${record.missingParams.join(', ')}'
        : '';
    return '$firstReason\n$secondLine'.trim();
  }

  Future<void> _delete(String triageId) async {
    await _store.delete(triageId);
    _reload();
  }

  Future<void> _showRecord(BuildContext context, TriageRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppMetrics.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                record.finalTier.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              for (final reason in record.mergeReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(reason,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              if (record.mergeReasons.isEmpty)
                Text('No escalation reasons.',
                    style: Theme.of(context).textTheme.bodyMedium),
              if (record.missingParams.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Missing: ${record.missingParams.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Record ${record.triageId}\n${record.timestamp.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
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