/// Metadata for the MedGemma-4B GGUF files this app expects on device.
///
/// Source repo (public, not gated): https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF
/// Model:    medgemma-1.5-4b-it-Q4_K_M.gguf   (2,489,894,976 B ≈ 2.32 GiB)
/// mmproj:   mmproj-F16.gguf                  (   851,252,224 B ≈ 0.79 GiB)
class MedGemmaFile {
  const MedGemmaFile({
    required this.filename,
    required this.expectedBytes,
    required this.hfUrl,
    required this.isMmproj,
  });

  final String filename;
  final int expectedBytes;
  final String hfUrl;

  /// True for the vision projector (mmproj); false for the language model.
  final bool isMmproj;

  String get label => isMmproj ? 'Vision projector (mmproj)' : 'Language model';

  String get friendlySize {
    final gb = expectedBytes / (1024 * 1024 * 1024);
    return gb > 1
        ? '${gb.toStringAsFixed(2)} GiB'
        : '${(expectedBytes ~/ (1024 * 1024)).toStringAsFixed(0)} MiB';
  }
}

class MedGemmaFiles {
  static const model = MedGemmaFile(
    filename: 'medgemma-1.5-4b-it-Q4_K_M.gguf',
    expectedBytes: 2489894976,
    hfUrl:
        'https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF/resolve/main/medgemma-1.5-4b-it-Q4_K_M.gguf',
    isMmproj: false,
  );

  static const mmproj = MedGemmaFile(
    filename: 'mmproj-F16.gguf',
    expectedBytes: 851252224,
    hfUrl:
        'https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF/resolve/main/mmproj-F16.gguf',
    isMmproj: true,
  );

  static const all = <MedGemmaFile>[model, mmproj];

  static final int totalBytes = model.expectedBytes + mmproj.expectedBytes;

  static MedGemmaFile byFilename(String name) {
    for (final f in all) {
      if (f.filename == name) return f;
    }
    throw ArgumentError('Unknown file: $name');
  }
}
