import 'models.dart';

/// Section E — scored complaint probes (spec §8).
/// Only the six detailed branches carry probes in this increment; other
/// chief complaints map to no probe list (E-Generic fallback).
const Map<ProbeBranch, List<ProbeQuestion>> branchProbes = {
  ProbeBranch.chest: [
    ProbeQuestion(
      id: 'E-C1',
      text: 'Does the pain spread to the arm, jaw, or back?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-C2',
      text: 'Is the pain worse with activity or walking?',
      score: 1,
    ),
    ProbeQuestion(
      id: 'E-C3',
      text: 'Is there sweating, nausea, or vomiting with the pain?',
      score: 1,
    ),
    ProbeQuestion(
      id: 'E-C4',
      text: 'Is the pain a tearing pain felt in the back?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-C5',
      text: 'Known heart disease, or risk factors (smoking, diabetes, high BP)?',
      score: 1,
    ),
  ],
  ProbeBranch.breathing: [
    ProbeQuestion(
      id: 'E-B1',
      text: 'Can the patient speak in full sentences?',
      score: 3,
      // Yes = 0, No = triggers the score (handled in engine).
    ),
    ProbeQuestion(
      id: 'E-B3',
      text: 'Is the patient using extra chest/neck muscles or sitting forward to breathe?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-B4',
      text: 'Is the patient confused or drowsy while breathless?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-B5',
      text: 'Is there chest pain when breathing?',
      score: 1,
    ),
  ],
  ProbeBranch.fever: [
    ProbeQuestion(
      id: 'E-F1',
      text: 'Was a temperature of 39°C or higher measured?',
      score: 1,
    ),
    ProbeQuestion(
      id: 'E-F2',
      text: 'Is there a rash that stays red when a glass is pressed on it?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-F3',
      text: 'Is there a stiff neck or painful light in the eyes?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-F4',
      text: 'Recent travel to an area with malaria or dengue?',
      score: 1,
    ),
    ProbeQuestion(
      id: 'E-F5',
      text: 'Is the patient immunocompromised (weak infection defence)?',
      score: 2,
    ),
  ],
  ProbeBranch.headache: [
    ProbeQuestion(
      id: 'E-H1',
      text: 'Did the headache start suddenly, like a thunderclap?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-H2',
      text: 'Is this the worst headache the patient has ever had?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-H3',
      text: 'Is there fever with a stiff neck?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-H4',
      text: 'Is there weakness, numbness, or a change in vision?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-H5',
      text: 'Is the patient pregnant or recently given birth?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-H6',
      text: 'Is the patient on blood thinners or known to have a bleeding problem?',
      score: 2,
    ),
  ],
  ProbeBranch.abdo: [
    ProbeQuestion(
      id: 'E-A1',
      text: 'Is the belly rigid or painful to the touch?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-A2',
      text: 'Vomiting with no bowel movement or gas for a while?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-A3',
      text: 'Is there blood in vomit or black, tarry stool?',
      score: 2,
    ),
    ProbeQuestion(
      id: 'E-A4',
      text: 'Is the patient pregnant (ectopic-pregnancy risk)?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-A5',
      text: 'Is there severe testicular pain?',
      score: 2,
    ),
  ],
  ProbeBranch.psych: [
    ProbeQuestion(
      id: 'E-P1',
      text: 'Any suicidal thoughts with a plan?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-P2',
      text: 'Self-harm in the last 24 hours?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-P3',
      text: 'Psychosis with a risk of harm to others?',
      score: 3,
    ),
    ProbeQuestion(
      id: 'E-P4',
      text: 'Severe agitation needing restraint?',
      score: 2,
    ),
  ],
};

/// Returns the scored probe list for a branch (empty when not detailed).
List<ProbeQuestion> probeQuestions(ProbeBranch? branch) =>
    branch == null ? const [] : (branchProbes[branch] ?? const []);

/// Returns true for a Yes answer to a probe whose true meaning is "concern
/// confirmed". Questions where Yes is the concerning answer use this directly;
/// inverted questions (e.g. "speak in full sentences") invert in the engine.
bool probeYes(TriageAnswers a, String id) => a.probeAnswers[id] ?? false;