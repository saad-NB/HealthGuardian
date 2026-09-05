import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// One selectable answer tile: icon + label + detail, >= 56 dp tall.
/// Selecting calls [onSelected]; the tile fills with the brand color.
class AnswerChip extends StatelessWidget {
  const AnswerChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.detail,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final String? detail;
  final IconData? icon;
  final bool selected;
  final VoidCallback onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.teal700 : AppColors.surface;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onSelected,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppMetrics.minTouch),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 30, color: AppColors.textPrimary),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            )),
                        if (detail != null) ...[
                          const SizedBox(height: 2),
                          Text(detail!,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textSubdued,
                              )),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle,
                        color: AppColors.textPrimary, size: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}