import 'package:flutter/foundation.dart';

import '../models/medgemma_files.dart';
import '../services/device_capabilities.dart';
import '../services/download_service.dart';
import '../triage/inference_budget.dart';

/// Shared runtime state: where the GGUF files live and whether they exist.
class AppState extends ChangeNotifier {
  String? modelDirPath;
  List<FileStatus>? statuses;

  /// Device-derived inference limits (RAM → usable context window).
  InferenceProfile inferenceProfile = InferenceProfile.fallback;

  Future<void> refresh() async {
    final dir = await DownloadService.modelDir();
    modelDirPath = dir.path;
    statuses = await DownloadService.statuses();
    inferenceProfile = await DeviceCapabilities.detect();
    InferenceBudget.configure(usableContext: inferenceProfile.usableContext);
    notifyListeners();
  }

  FileStatus? statusOf(MedGemmaFile def) {
    for (final s in statuses ?? const <FileStatus>[]) {
      if (s.def.filename == def.filename) return s;
    }
    return null;
  }

  String? get modelPath {
    final s = statusOf(MedGemmaFiles.model);
    if (s != null && s.complete && modelDirPath != null) {
      return '${modelDirPath!}/${MedGemmaFiles.model.filename}';
    }
    return null;
  }

  String? get mmprojPath {
    final s = statusOf(MedGemmaFiles.mmproj);
    if (s != null && s.complete && modelDirPath != null) {
      return '${modelDirPath!}/${MedGemmaFiles.mmproj.filename}';
    }
    return null;
  }

  bool get modelReady => modelPath != null;
  bool get mmprojReady => mmprojPath != null;
}
