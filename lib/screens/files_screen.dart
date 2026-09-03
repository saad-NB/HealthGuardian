import 'dart:async';

import 'package:flutter/material.dart';

import '../models/medgemma_files.dart';
import '../services/download_service.dart';
import '../state/app_state.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.app});

  final AppState app;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final Map<String, double> _progress = {};
  final Set<String> _active = {};

  Future<void> _reload() async {
    await widget.app.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _download(MedGemmaFile def) async {
    setState(() => _active.add(def.filename));
    try {
      await for (final pct in DownloadService.download(def)) {
        if (mounted) setState(() => _progress[def.filename] = pct);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _active.remove(def.filename);
          _progress.remove(def.filename);
        });
      }
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final statuses = widget.app.statuses ?? const <FileStatus>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Model Files',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'MedGemma-4B-it Q4_K_M + mmproj-F16 (from '
              'unsloth/medgemma-4b-it-GGUF).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final s in statuses) ...[
              _fileCard(s),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            _instructionsCard(),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _fileCard(FileStatus s) {
    final downloading = _active.contains(s.def.filename);
    final pct = _progress[s.def.filename];
    final IconData icon;
    final Color color;
    if (downloading) {
      icon = Icons.downloading;
      color = Colors.orange;
    } else if (s.complete) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (s.exists) {
      icon = Icons.warning_amber;
      color = Colors.orange;
    } else {
      icon = Icons.download_for_offline_outlined;
      color = Theme.of(context).colorScheme.outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.def.filename,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${s.def.label} - ${s.def.friendlySize}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!downloading)
                  IconButton(
                    onPressed: s.complete ? null : () => _download(s.def),
                    tooltip: s.complete ? 'Present' : 'Download from HF',
                    icon: Icon(s.complete ? Icons.done_all : Icons.download),
                  ),
              ],
            ),
            if (s.exists)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'On disk: ${(s.length / (1024 * 1024)).toStringAsFixed(0)} MiB '
                  '${s.complete ? '' : '(size mismatch - re-download)'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (downloading && pct != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: pct),
              const SizedBox(height: 4),
              Text('${(pct * 100).toStringAsFixed(1)} %',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _instructionsCard() {
    final dir = widget.app.modelDirPath ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fastest path (adb push)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Copy the GGUFs to this folder on the phone (USB, no permissions '
              'needed), then press Refresh:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              dir.isEmpty ? '(resolving model dir...)' : dir,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.lightBlueAccent,
              ),
            ),
            if (dir.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                'adb push medgemma-1.5-4b-it-Q4_K_M.gguf "$dir/"',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              SelectableText(
                'adb push mmproj-F16.gguf "$dir/"',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Total needed: ${(MedGemmaFiles.totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB. '
              'Required RAM on device: roughly the model size, so a 6 GB phone '
              'is OK but tight.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
