import 'package:flutter/material.dart';

import '../../triage/models.dart';

/// Full-bleed tier result banner (UI/UX plan §8, §9.1).
/// Tier is communicated by color + shape icon + label + response target so it
/// works for colour-blind users and is scannable at a glance.
class TierBanner extends StatelessWidget {
  const TierBanner({
    super.key,
    required this.tier,
    this.onShare,
    this.compact = false,
  });

  final TriageTier tier;
  final VoidCallback? onShare;
  final bool compact;

  IconData get _shape {
    switch (tier) {
      case TriageTier.p1:
        return Icons.dangerous;
      case TriageTier.p2:
        return Icons.notification_important;
      case TriageTier.p3:
        return Icons.warning_amber_rounded;
      case TriageTier.p4:
        return Icons.check_circle;
      case TriageTier.p5:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = tier.useDarkText ? Colors.black : Colors.white;
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Triage result: ${tier.label}. Response ${tier.response}.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: tier.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_shape, size: 44, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    tier.label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Action: ${tier.response}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (!compact && onShare != null) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onShare,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  backgroundColor: Colors.black.withValues(alpha: 0.18),
                  minimumSize: const Size(120, 48),
                ),
                icon: const Icon(Icons.share),
                label: const Text('Share with hospital'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}