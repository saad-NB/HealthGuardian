import 'package:flutter/material.dart';

import '../services/llm_service.dart';
import '../state/app_state.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  String _output = 'Response will appear here.';
  bool _running = false;
  int _tokenHint = 0;
  int _elapsedMs = 0;
  String? _lastError;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) return;

    final app = widget.app;
    if (!app.modelReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model GGUF not present. Go to the Models tab first.'),
          ),
        );
      }
      return;
    }

    final service = LlmService(
      modelPath: app.modelPath!,
      mmprojPath: app.mmprojPath,
      numGpuLayers: 0,
      maxTokens: 512,
      contextSize: 4096,
    );

    setState(() {
      _running = true;
      _tokenHint = 0;
      _elapsedMs = 0;
      _lastError = null;
      _output = '';
    });

    final stopwatch = Stopwatch()..start();
    try {
      await for (final delta in service.chat(prompt)) {
        setState(() {
          _output += delta;
          _tokenHint++;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
      stopwatch.stop();
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  _output,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 8),
                if (_lastError != null)
                  Text(
                    _lastError!,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_running,
                      maxLines: 2,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Describe symptoms or ask a medical question...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _running ? null : _send,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _running
                    ? 'Streaming... $_tokenHint tokens · $_elapsedMs ms'
                    : (_lastError != null
                        ? 'Failed with an error.'
                        : (_output.trim().isNotEmpty &&
                                _output != 'Response will appear here.'
                            ? 'Done - ~$_tokenHint tokens · $_elapsedMs ms (incl. load)'
                            : ' ')),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
