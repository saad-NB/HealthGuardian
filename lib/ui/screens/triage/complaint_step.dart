import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../../triage/probes.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';

/// Section D1 — main-problem picker (spec §7, UI/UX plan §7.5).
///
/// Every complaint the patient answers gets a green tick. The menu stays open
/// so multiple main problems can be selected; Continue confirms the round and
/// the walkthrough asks "any other problems?" to collect more. Free-text
/// complaints are stored for the Tier 2 context only (never the engine).
class ComplaintStep extends StatefulWidget {
  const ComplaintStep({
    super.key,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onAdvance,
    required this.onRefresh,
    required this.onBack,
    required this.onRestart,
  });

  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onAdvance;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  @override
  State<ComplaintStep> createState() => _ComplaintStepState();
}

class _ComplaintStepState extends State<ComplaintStep> {
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: widget.answers.extraComplaintNotes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QuestionScaffold(
      progress: widget.progress + 1,
      steps: widget.steps,
      onBack: widget.onBack,
      onUndo: widget.onBack ?? () {},
      onRestart: widget.onRestart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is the problem?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Choose one or more. Green ticks mark problems you already covered.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          for (final c in ChiefComplaint.values) ...[
            _chip(c),
            const SizedBox(height: AppMetrics.answerGap),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 2,
            minLines: 1,
            onChanged: (v) => widget.answers.extraComplaintNotes = v,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Any other complaints (optional)',
              hintText: 'Anything else that is bothering the patient...',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: widget.onAdvance,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _chip(ChiefComplaint c) {
    final answered = widget.answers.hasComplaint(c);
    return AnswerChip(
      label: c.label,
      selected: answered,
      icon: _iconFor(c),
      onSelected: () {
        if (answered) {
          // Second tap unselects and drops this complaint's probe answers so
          // stale Section E scores cannot leak into the engine.
          widget.answers.deselectComplaint(c);
          for (final q in probeQuestions(c.branch)) {
            widget.answers.probeAnswers.remove(q.id);
          }
        } else {
          widget.answers.selectComplaint(c);
        }
        widget.onRefresh();
      },
    );
  }

  IconData _iconFor(ChiefComplaint c) => switch (c) {
        ChiefComplaint.fever => Icons.thermostat,
        ChiefComplaint.breathing => Icons.air,
        ChiefComplaint.chest => Icons.favorite,
        ChiefComplaint.abdo => Icons.abc,
        ChiefComplaint.gastrointestinal => Icons.sick,
        ChiefComplaint.throat => Icons.volume_off,
        ChiefComplaint.ear => Icons.hearing,
        ChiefComplaint.eye => Icons.remove_red_eye,
        ChiefComplaint.skin => Icons.brush,
        ChiefComplaint.wound => Icons.content_cut,
        ChiefComplaint.headache => Icons.psychology,
        ChiefComplaint.weakness => Icons.back_hand,
        ChiefComplaint.urinary => Icons.water_drop,
        ChiefComplaint.pregnancy => Icons.pregnant_woman,
        ChiefComplaint.injury => Icons.warning,
        ChiefComplaint.poisoning => Icons.science,
        ChiefComplaint.mentalHealth => Icons.psychology_alt,
        ChiefComplaint.other => Icons.help_outline,
      };
}