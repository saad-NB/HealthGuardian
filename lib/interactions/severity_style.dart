import 'package:flutter/material.dart';

import '../ui/theme/app_tokens.dart';
import 'models.dart';

/// Shared severity styling for the Drugs tab, reusing the locked tier palette
/// (spec §14) so urgency colours stay consistent across the app.
Color interactionSeverityColor(InteractionSeverity severity) =>
    switch (severity) {
      InteractionSeverity.reported => AppColors.textSubdued,
      InteractionSeverity.moderate => AppColors.tierP3,
      InteractionSeverity.severe => AppColors.tierP2,
      InteractionSeverity.contraindicated => AppColors.tierP1,
    };

IconData interactionSeverityIcon(InteractionSeverity severity) =>
    switch (severity) {
      InteractionSeverity.reported => Icons.info_outline,
      InteractionSeverity.moderate => Icons.warning_amber_outlined,
      InteractionSeverity.severe => Icons.warning_amber_rounded,
      InteractionSeverity.contraindicated => Icons.dangerous_outlined,
    };
