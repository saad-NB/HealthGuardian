import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/services/device_capabilities.dart';

void main() {
  group('DeviceCapabilities.fromTotalRamMb', () {
    test('disables Tier 2 below the minimum RAM', () {
      expect(DeviceCapabilities.fromTotalRamMb(3900).tier2Enabled, isFalse);
      expect(DeviceCapabilities.fromTotalRamMb(3900).usableContext, 0);
    });

    test('maps RAM tiers to a usable per-sequence window', () {
      expect(DeviceCapabilities.fromTotalRamMb(4096).usableContext, 1024);
      expect(DeviceCapabilities.fromTotalRamMb(6000).usableContext, 2048);
      expect(DeviceCapabilities.fromTotalRamMb(7000).usableContext, 3072);
      expect(DeviceCapabilities.fromTotalRamMb(8000).usableContext, 4096);
      expect(DeviceCapabilities.fromTotalRamMb(16000).usableContext, 4096);
    });

    test('requests four times the usable window (fllama n_parallel = 4)', () {
      final profile = DeviceCapabilities.fromTotalRamMb(7000);
      expect(profile.parallelSlots, 4);
      expect(profile.requestedContext, 3072 * 4);
    });

    test('a low-RAM device is disabled', () {
      final profile =
          DeviceCapabilities.fromTotalRamMb(8000, isLowRam: true);
      expect(profile.tier2Enabled, isFalse);
    });

    test('unknown RAM falls back to a safe enabled profile', () {
      final profile = DeviceCapabilities.fromTotalRamMb(null);
      expect(profile.tier2Enabled, isTrue);
      expect(profile.usableContext, InferenceProfile.fallback.usableContext);
    });
  });
}
