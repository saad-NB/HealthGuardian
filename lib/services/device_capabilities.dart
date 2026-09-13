import 'package:device_info_plus/device_info_plus.dart';

/// Memory-derived inference limits for the on-device MedGemma worker.
///
/// fllama hardcodes `n_parallel = 4` (`ServerManager::DEFAULT_N_PARALLEL`) and
/// never enables the unified KV cache, so llama.cpp gives every sequence only
/// `n_ctx / 4` cells (`n_ctx_seq`). A single conversation therefore only sees a
/// quarter of the requested context. To compensate, budgets are expressed as a
/// *usable* per-sequence window and the `contextSize` handed to fllama is
/// `usable * parallelSlots`.
///
/// Gemma 3 uses interleaved sliding-window attention (5 dense + 29 windowed
/// layers for MedGemma-1.5-4B), so the KV cache is dominated by a fixed
/// sliding-window floor; a larger window costs comparatively little extra RAM.
class InferenceProfile {
  const InferenceProfile({
    required this.totalRamMb,
    required this.usableContext,
    this.parallelSlots = DeviceCapabilities.parallelSlots,
  });

  /// Total physical RAM in MB (0 when unknown).
  final int totalRamMb;

  /// Tokens available to a single conversation (`n_ctx_seq`).
  final int usableContext;

  /// fllama's hardcoded number of parallel sequences.
  final int parallelSlots;

  /// The `contextSize` (n_ctx) passed to fllama so one conversation gets
  /// [usableContext] tokens.
  int get requestedContext => usableContext * parallelSlots;

  /// Whether Tier 2 may run at all on this device.
  bool get tier2Enabled => usableContext > 0;

  /// Conservative default used when the platform has no Android RAM info.
  static const fallback = InferenceProfile(totalRamMb: 0, usableContext: 2048);
}

/// Detects device RAM and turns it into an [InferenceProfile].
class DeviceCapabilities {
  DeviceCapabilities._();

  /// Must match fllama's `ServerManager::DEFAULT_N_PARALLEL`.
  static const int parallelSlots = 4;

  /// Maps total physical RAM (MB) to a per-sequence usable context window.
  ///
  /// Tiers are deliberately conservative: the model is ~2.4 GiB and the KV
  /// cache adds roughly 0.5-1.0 GiB at these windows, so Tier 2 is disabled on
  /// devices that cannot hold both without risking an OOM kill.
  static InferenceProfile fromTotalRamMb(
    int? totalRamMb, {
    bool isLowRam = false,
  }) {
    if (isLowRam) {
      return const InferenceProfile(totalRamMb: 0, usableContext: 0);
    }
    if (totalRamMb == null) return InferenceProfile.fallback;
    final usable = switch (totalRamMb) {
      >= 8000 => 4096,
      >= 7000 => 3072,
      >= 6000 => 2048,
      >= 4000 => 1024,
      _ => 0,
    };
    return InferenceProfile(totalRamMb: totalRamMb, usableContext: usable);
  }

  /// Reads Android RAM info; falls back to a safe profile elsewhere.
  static Future<InferenceProfile> detect() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return fromTotalRamMb(
        info.physicalRamSize,
        isLowRam: info.isLowRamDevice,
      );
    } catch (_) {
      return InferenceProfile.fallback;
    }
  }
}
