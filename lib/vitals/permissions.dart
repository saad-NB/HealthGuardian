import 'package:permission_handler/permission_handler.dart';

import 'models.dart';

/// Single place that asks for and verifies the runtime permissions a vitals
/// measurement needs (ADR-017 §8.1).
///
///   - Heart rate (camera PPG)   -> CAMERA
///   - Breathing rate (mic)      -> RECORD_AUDIO
///
/// The e2e harness pre-grants the same permissions via adb so on-device
/// scenarios never stall on a system dialog.
class VitalPermissions {
  const VitalPermissions();

  /// True when [kind]'s permission is already granted.
  Future<bool> isGranted(VitalKind kind) async =>
      await _permission(kind).status == PermissionStatus.granted;

  /// Requests [kind]'s permission if needed; true when usable after.
  Future<bool> ensure(VitalKind kind) async =>
      await _permission(kind).status == PermissionStatus.granted
          ? true
          : await request(kind);

  /// Requests [kind]'s permission (no-op when already granted).
  Future<bool> request(VitalKind kind) async {
    final permission = _permission(kind);
    if (await permission.status == PermissionStatus.granted) return true;
    final status = await permission.request();
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  /// Permission denied permanently → point the user at system settings.
  Future<bool> isPermanentlyDenied(VitalKind kind) async =>
      await _permission(kind).status == PermissionStatus.permanentlyDenied;

  /// Opens the OS app-settings screen for the user to grant manually.
  Future<bool> openSettings() => openAppSettings();

  static Permission _permission(VitalKind kind) => switch (kind) {
        VitalKind.heartRate => Permission.camera,
        VitalKind.breathingRate => Permission.microphone,
      };
}