import '../dsp/spectral_denoise.dart';

/// In-memory holder for the most recent breathing-rate background-noise
/// profile.
///
/// A noise profile is specific to the current device + room, so it is
/// deliberately not persisted: the RR flow asks the user to run a background
/// measurement once, and every following breathing measurement in the same app
/// session reuses the accepted profile. Call [clear] to force a recalibration
/// (e.g. from tests or when the user changes rooms).
class NoiseProfileStore {
  NoiseProfileStore._();

  static NoiseProfile? _profile;

  static NoiseProfile? get profile => _profile;
  static bool get hasProfile => _profile != null;

  static void set(NoiseProfile profile) => _profile = profile;
  static void clear() => _profile = null;
}
