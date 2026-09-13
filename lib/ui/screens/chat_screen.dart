import 'package:fllama/fllama.dart' show Message, Role;
import 'package:flutter/material.dart';

import '../../config/emergency_numbers.dart';
import '../../prompts/tier2_prompts.dart';
import '../../services/tier2_service.dart';
import '../../state/app_state.dart';
import '../../triage/inference_budget.dart';
import '../../triage/reasoning_trace.dart';
import '../text/markdown_lite.dart';
import '../theme/app_tokens.dart';
import 'settings_action.dart';

/// Chat surface for MedGemma (ADR-014). Used two ways:
///
/// 1. The main "Ask AI" tab (RootShell) — generic assistant, no context.
/// 2. Pushed from the result screen with [patientContext] attached — a
///    read-only triage context seeds the conversation; transcripts stay
///    ephemeral (never persisted) per ADR-014.
/// 3. Opened from History via [RootShell] with [patientContext] = a rebuilt
///    record context and [attachedTitle] = the case name + timestamp.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.app,
    this.service,
    this.patientContext,
    this.attachedTitle,
    this.contextLabel,
  });

  final AppState app;

  /// Inject a fake in tests; defaults to a real [Tier2Service] for [app].
  final Tier2Service? service;

  /// Optional read-only context attached to this session (a triage record or a
  /// drug-interaction check).
  final String? patientContext;

  /// Optional case label shown in the app bar when [patientContext] is set.
  final String? attachedTitle;

  /// Optional chip label for the attached context; defaults to the triage
  /// wording so existing triage sessions are unchanged.
  final String? contextLabel;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  const _ChatMessage({
    required this.fromUser,
    required this.text,
    this.isTruncated = false,
  });

  final bool fromUser;
  final String text;

  /// True when this is a notice that the previous reply hit its length limit.
  final bool isTruncated;
}

class _ChatScreenState extends State<ChatScreen> {
  late final Tier2Service _service = widget.service ?? Tier2Service(app: widget.app);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  final List<Message> _history = [];
  bool _busy = false;
  String _lastFinishReason = 'unknown';

  bool get _contextAttached => widget.patientContext != null && widget.patientContext!.isNotEmpty;

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new attached context (e.g. a different History record) must start a
    // fresh, disposable conversation — never carry over the previous case.
    if (oldWidget.patientContext != widget.patientContext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startNewChat();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _history.clear();
      _lastFinishReason = 'unknown';
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    final systemPrompt = chatSystemPrompt(patientContext: widget.patientContext);

    // Keep the prompt inside the chat budget: drop the oldest history turns
    // (never the system prompt / attached triage context) until it fits.
    var newPromptTokens = InferenceBudget.estimateTokens(text);
    while (_history.isNotEmpty &&
        InferenceBudget.chatPromptTokens(systemText: systemPrompt, history: _history) +
                newPromptTokens >
            InferenceBudget.chatPromptCap) {
      _history.removeAt(0);
      newPromptTokens = InferenceBudget.estimateTokens(text);
    }

    final historyForTurn = List<Message>.of(_history);
    _history.add(Message(Role.user, text));

    setState(() {
      _messages.add(_ChatMessage(fromUser: true, text: text));
      _messages.add(const _ChatMessage(fromUser: false, text: ''));
      _busy = true;
      _controller.clear();
    });
    _scrollToBottom();

    final buffer = StringBuffer();
    try {
      await for (final delta in _service.chatTurn(
        prompt: text,
        patientContext: widget.patientContext,
        history: historyForTurn,
        onFinished: (_, _, reason) => _lastFinishReason = reason,
      )) {
        buffer.write(delta);
        if (mounted) {
          // Hide MedGemma's Draft/Critique/Revise trace while it streams; the
          // final answer is extracted once generation stops.
          final shown = ReasoningTrace.hasTrace(buffer.toString())
              ? ''
              : buffer.toString();
          setState(() {
            _messages[_messages.length - 1] =
                _ChatMessage(fromUser: false, text: shown);
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages[_messages.length - 1] = const _ChatMessage(
            fromUser: false,
            text: 'Sorry, the local model could not respond. Please try again.',
          );
        });
      }
    } finally {
      final raw = buffer.toString().trim();
      final hadTrace = ReasoningTrace.hasTrace(raw);
      final answer = ReasoningTrace.extractAnswer(raw);
      if (answer.isNotEmpty) {
        _history.add(Message(Role.assistant, answer));
      } else if (raw.isEmpty) {
        _history.removeLast();
      }
      if (mounted) {
        setState(() {
          _messages[_messages.length - 1] = _ChatMessage(
            fromUser: false,
            text: answer.isNotEmpty
                ? answer
                : (raw.isEmpty
                    ? 'Sorry, the local model could not respond. Please try again.'
                    : 'The model could not produce a final answer. Please try again.'),
          );
          _busy = false;
          if (!hadTrace && answer.isNotEmpty && _lastFinishReason == 'length') {
            _messages.add(const _ChatMessage(
              fromUser: false,
              text: '',
              isTruncated: true,
            ));
          }
        });
      }
      _lastFinishReason = 'unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // As the Ask AI tab (shell) the leading slot is the Settings gear;
        // when pushed as a route (from a result or History) it's a back arrow.
        leading: Navigator.of(context).canPop()
            ? null
            : SettingsAction(app: widget.app),
        automaticallyImplyLeading: !Navigator.of(context).canPop(),
        title: Text(_contextAttached
            ? (widget.attachedTitle?.isNotEmpty == true
                ? widget.attachedTitle!
                : 'Ask about this result')
            : 'Ask AI'),
        actions: [
          if (_messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _busy
                  ? const SizedBox.shrink()
                  : TextButton.icon(
                      onPressed: _startNewChat,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('New chat'),
                    ),
            ),
          if (_contextAttached)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.folder_copy_outlined, size: 18),
                  label: Text(widget.contextLabel ?? 'Triage context attached'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: !_service.available
          ? _modelNeededView()
          : Column(
              children: [
                if (_contextAttached) _contextBanner(context),
                Expanded(
                  child: _messages.isEmpty
                      ? _emptyState()
                      : _messageList(),
                ),
                _inputBar(context),
              ],
            ),
    );
  }

  Widget _contextBanner(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: AppColors.textSubdued),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This chat can see the details attached from the app. It is disposable — answers are not saved.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final msg = _messages[i];
        if (msg.isTruncated) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Reply reached its length limit — keep it short, or start a new chat.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSubdued, fontStyle: FontStyle.italic),
              ),
            ),
          );
        }
        final mine = msg.fromUser;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              color: mine ? Theme.of(context).colorScheme.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: mine
                      ? Theme.of(context).colorScheme.onPrimary
                      : AppColors.textPrimary,
                ),
                children: msg.text.isEmpty && !mine
                    ? const [TextSpan(text: '…')]
                    : MarkdownLite.buildSpans(
                        msg.text,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: mine
                              ? Theme.of(context).colorScheme.onPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_outlined, size: 64, color: AppColors.textSubdued),
            const SizedBox(height: 16),
            Text(
              _contextAttached
                  ? 'Ask about the attached details — it runs on your phone.'
                  : 'Ask a health question — answers run on this phone (offline).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Decision support, not a diagnosis. For emergencies call '
              '$emergencyNumbers.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelNeededView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download, size: 64, color: AppColors.textSubdued),
            const SizedBox(height: 16),
            Text(
              'AI model not downloaded yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Open the Models tab and download MedGemma (about 2.3 GB). '
              'Until then the app still works on Tier 1 triage.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('Thinking…', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'Type your question…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  onPressed: _busy ? null : _send,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}