import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../ui/screens/settings_action.dart';
import '../../ui/theme/app_tokens.dart';
import '../measurement_session.dart';
import '../measurement_session_view.dart';
import '../models.dart';
import 'monitor_store.dart';

/// Monitor tab (ADR-017): on-device vitals sensing. Measurement cards launch
/// the shared session; accepted readings persist to [MonitorStore] and render
/// below, newest first.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, required this.app, this.sessionFor, this.store});

  final AppState app;

  /// Builds a measurement session for a vital kind. Null unless the HR / RR
  /// sensor pipelines are wired in — cards then hint "not available yet".
  final MeasurementSession? Function(VitalKind kind)? sessionFor;

  /// Injectable backing store (tests); defaults to the real file store.
  final MonitorStore? store;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  MonitorStore? _store;
  List<VitalReading> _recent = const [];

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? MonitorStore();
    _loadRecent();
  }

  void _loadRecent() async {
    final store = _store;
    if (store == null) return;
    final recent = await store.loadRecent();
    if (mounted) setState(() => _recent = recent);
  }

  Future<void> _deleteReading(VitalReading reading) async {
    final store = _store;
    if (store == null) return;
    await store.remove(reading);
    if (!mounted) return;
    _loadRecent();
  }

  Future<void> _measure(BuildContext context, VitalKind kind) async {
    final session = widget.sessionFor?.call(kind);
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${kind.label} sensing is not available yet.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final reading = await launchMeasurementSession(
      context,
      session: session,
      cancelLabel: 'Back',
    );
    if (reading == null) return;
    final store = _store;
    if (store != null) await store.save(reading);
    if (!context.mounted) return;
    _loadRecent();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${kind.label}: ${reading.value.round()} ${kind.shortUnit} '
          '(${reading.confidence.label.toLowerCase()} confidence)',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: SettingsAction(app: widget.app),
        automaticallyImplyLeading: false,
        title: const Text('Monitor'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppMetrics.margin),
        children: [
          Text(
            'Measure a vital with the phone\'s sensors — camera flash for '
            'heart rate, microphone for breathing. Works fully offline.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _measureCard(
            context,
            kind: VitalKind.heartRate,
            icon: Icons.favorite_outline,
          ),
          const SizedBox(height: AppMetrics.answerGap),
          _measureCard(
            context,
            kind: VitalKind.breathingRate,
            icon: Icons.air,
          ),
          const SizedBox(height: 28),
          Text(
            'Recent readings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_recent.isEmpty)
            Text(
              'Readings you accept will appear here.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._recent.map(
              (r) => _readingTile(context, r),
            ),
        ],
      ),
    );
  }

  Widget _readingTile(BuildContext context, VitalReading reading) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                reading.kind == VitalKind.heartRate
                    ? Icons.favorite_outline
                    : Icons.air,
                size: 20,
                color: AppColors.teal700,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reading.kind.label} — '
                      '${reading.value.round()} ${reading.kind.shortUnit}',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTimestamp(reading.measuredAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSubdued,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                reading.confidence.label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSubdued,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _deleteReading(reading),
                tooltip: 'Delete ${reading.kind.label} reading',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppColors.textSubdued,
                ),
              ),
            ],
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

  Widget _measureCard(
    BuildContext context, {
    required VitalKind kind,
    required IconData icon,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 34, color: AppColors.teal700),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kind == VitalKind.heartRate
                        ? 'Fingertip on the rear camera'
                        : 'Phone near the mouth or nose',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSubdued,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              // The app theme widens every FilledButton to fill its parent
              // (minimumSize Size.fromHeight), which an unbounded Row can't
              // satisfy — give this card's compact button a real size.
              style: FilledButton.styleFrom(
                minimumSize: const Size(104, 44),
              ),
              onPressed: () => _measure(context, kind),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Measure'),
            ),
          ],
        ),
      ),
    );
  }
}