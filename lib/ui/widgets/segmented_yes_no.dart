import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Two giant Yes / No segments (danger gates, toggles).
/// Selection is persistent between rebuilds via [value].
class SegmentedYesNo extends StatelessWidget {
  const SegmentedYesNo({
    super.key,
    required this.value,
    required this.onChanged,
    this.yesLabel = 'Yes',
    this.noLabel = 'No',
  });

  final bool? value;
  final ValueChanged<bool> onChanged;
  final String yesLabel;
  final String noLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _segment(true, yesLabel)),
        const SizedBox(width: AppMetrics.gap),
        Expanded(child: _segment(false, noLabel)),
      ],
    );
  }

  Widget _segment(bool test, String label) {
    final selected = value == test;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.teal700 : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => onChanged(test),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: AppMetrics.minTouch,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.teal700
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  test ? Icons.check : Icons.close,
                  size: 26,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}