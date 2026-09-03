import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/medgemma_files.dart';

/// Status of a GGUF file on disk.
class FileStatus {
  FileStatus(this.def, this.length, this.complete);

  final MedGemmaFile def;
  final int length;

  /// True if present and byte count matches the expected size.
  final bool complete;

  bool get exists => length > 0;
}

/// Locates model files and downloads them from Hugging Face.
///
/// Primary workflow is `adb push` straight into the app's external files dir.
/// In-app download from Hugging Face is provided as a backup.
class DownloadService {
  static Future<Directory> modelDir() async {
    Directory? ext;
    try {
      ext = await getExternalStorageDirectory();
    } catch (_) {/* ignore */}
    if (ext != null && ext.path.isNotEmpty) {
      return Directory('${ext.path}/models')..createSync(recursive: true);
    }
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/models')..createSync(recursive: true);
  }

  static Future<FileStatus> status(MedGemmaFile def) async {
    final dir = await modelDir();
    final file = File('${dir.path}/${def.filename}');
    if (!await file.exists()) return FileStatus(def, 0, false);
    final length = await file.length();
    return FileStatus(def, length, length == def.expectedBytes);
  }

  static Future<List<FileStatus>> statuses() async {
    final results = <FileStatus>[];
    for (final def in MedGemmaFiles.all) {
      results.add(await status(def));
    }
    return results;
  }

  /// Streaming / resumable download with progress in 0..1.
  static Stream<double> download(MedGemmaFile def) async* {
    final dir = await modelDir();
    final target = File('${dir.path}/${def.filename}');
    final part = File('${dir.path}/${def.filename}.part');

    int offset = 0;
    if (await part.exists()) {
      offset = await part.length();
      if (offset >= def.expectedBytes) offset = 0;
    }

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(def.hfUrl));
    if (offset > 0) {
      request.headers['Range'] = 'bytes=$offset-';
    }
    final response = await client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final sink = part.openWrite(mode: FileMode.append);
    var written = offset;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        written += chunk.length;
        yield (written / def.expectedBytes).clamp(0.0, 1.0);
      }
      await sink.flush();
    } finally {
      await sink.close();
      client.close();
    }

    final finalLength = await part.length();
    if (finalLength != def.expectedBytes) {
      throw Exception('Incomplete download: $finalLength/${def.expectedBytes}');
    }
    if (await target.exists()) {
      await target.delete();
    }
    await part.rename(target.path);
  }
}
