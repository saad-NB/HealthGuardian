import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Yellow, non-dismissible banner shown when any vital is missing or invalid
/// (spec §21: review required). Subclasses layout; content is always visible.
class ReviewBanner extends StatelessWidget {
  const ReviewBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.reviewBanner.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.reviewBanner),
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_information,
              color: AppColors.reviewBanner, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}