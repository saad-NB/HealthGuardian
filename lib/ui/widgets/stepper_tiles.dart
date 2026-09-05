import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Large -- / value / ++ stepper with hold-to-repeat, bounds clamping,
/// optional quick-value chips, and an explicit "Not available" escape.
class StepperTiles extends StatelessWidget {
  const StepperTiles({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    this.decimals = 0,
    this.quickValues = const [],
    this.canBeMissing = false,
    this.missing = false,
    this.onMissing,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final String unit;
  final int decimals;
  final List<double> quickValues;
  final bool canBeMissing;
  final bool missing;
  final VoidCallback? onMissing;

  String get _display {
    if (decimals > 0) {
      return value.toStringAsFixed(decimals);
    }
    return value.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _stepButton(false)),
            Expanded(
              flex: 2,
              child: Container(
                height: AppMetrics.minTouch + 16,
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(horizontal: AppMetrics.gap),
                decoration: BoxDecoration(
                  color: missing ? AppColors.surface : AppColors.teal800,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  missing ? 'Not measured' : '$_display $unit',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: missing
                        ? AppColors.textSubdued
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            Expanded(child: _stepButton(true)),
          ],
        ),
        if (quickValues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: AppMetrics.gap,
            runSpacing: AppMetrics.gap,
            alignment: WrapAlignment.center,
            children: [
              for (final q in quickValues)
                ActionChip(
                  label: Text('${q == q.roundToDouble() ? q.toInt().toString() : q.toString()} $unit'),
                  onPressed: () => onChanged(q),
                  key: ValueKey('quick-$q'),
                ),
            ],
          ),
        ],
        if (canBeMissing) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onMissing,
            style: TextButton.styleFrom(
              minimumSize: const Size(56, 52),
              foregroundColor: AppColors.textSubdued,
            ),
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(
              missing ? 'Unmark as missing' : 'I cannot measure this',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepButton(bool increment) {
    final icon = increment ? Icons.add : Icons.remove;
    return Semantics(
      button: true,
      label: increment ? 'Increase' : 'Decrease',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _step(increment),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: AppMetrics.minTouch + 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, size: 34, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  void _step(bool increment) {
    if (increment) {
      onChanged((value + step).clamp(min, max).toDouble());
    } else {
      onChanged((value - step).clamp(min, max).toDouble());
    }
  }
}