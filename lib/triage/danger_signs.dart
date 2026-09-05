/// Section A — Emergency Danger Signs (gates), spec §4 and §10 output.
/// Any YES bypasses all scoring and forces P1.
class DangerSignDefinition {
  const DangerSignDefinition({
    required this.id,
    required this.text,
    required this.explain,
  });

  final String id;
  final String text;

  /// Plain-language expansion shown by the Explain affordance.
  final String explain;
}

const List<DangerSignDefinition> dangerSigns = [
  DangerSignDefinition(
    id: 'A1',
    text: 'Not responding normally, very drowsy, or unconscious',
    explain:
        'The person does not wake up when spoken to, is hard to wake, or '
        'does not respond at all.',
  ),
  DangerSignDefinition(
    id: 'A2',
    text: 'Convulsing now, or convulsed during this illness',
    explain:
        'Fits / shaking spells of the whole body, eyes rolling up, or a '
        'history of such a fit during this same sickness.',
  ),
  DangerSignDefinition(
    id: 'A3',
    text: 'Cannot drink or feed, or vomiting everything',
    explain:
        'Unable to keep down any fluids or food. For a baby: cannot '
        'breastfeed at all.',
  ),
  DangerSignDefinition(
    id: 'A4',
    text: 'Noisy breathing or stridor when calm',
    explain:
        'Whistling, crowing or harsh sound when breathing in, even while '
        'resting quietly.',
  ),
  DangerSignDefinition(
    id: 'A5',
    text: 'Severe breathing difficulty',
    explain:
        'Cannot speak in full sentences because of breathlessness. For a '
        'baby: feeds weakly or cries weakly.',
  ),
  DangerSignDefinition(
    id: 'A6',
    text: 'Swollen lips/tongue/face or hives WITH breathing difficulty',
    explain:
        'Rapid swelling of the face or throat together with trouble '
        'breathing or a tight throat.',
  ),
  DangerSignDefinition(
    id: 'A7',
    text: 'Bleeding that will not stop with pressure after 10 minutes',
    explain:
        'Wound or nose bleeding that still soaks through a cloth held '
        'firmly for ten minutes.',
  ),
  DangerSignDefinition(
    id: 'A8',
    text: 'Severe chest pain with sweating or breathlessness',
    explain:
        'Crushing chest pain or pressure, with sweating, nausea, or '
        'difficult breathing.',
  ),
  DangerSignDefinition(
    id: 'A9',
    text: 'Fever with stiff neck or a rash that does not fade under a glass',
    explain:
        'Fever plus inability to bend the neck, or a rash that stays red '
        'when a clear glass is pressed on it.',
  ),
  DangerSignDefinition(
    id: 'A10',
    text: 'Suspected poisoning or overdose',
    explain:
        'Possible swallowing of poison, chemicals, medicines beyond the '
        'dose, or wrong medicine.',
  ),
  DangerSignDefinition(
    id: 'A11',
    text: 'Severe abdominal pain, rigid or swollen belly',
    explain:
        'Hard, board-like or visibly swollen belly with strong pain, '
        'especially after an injury.',
  ),
  DangerSignDefinition(
    id: 'A12',
    text: 'Unable to stand or walk, or unusually weak on one side',
    explain:
        'Sudden loss of movement or weakness of an arm, leg, or one side '
        'of the face. For a baby: does not move a limb normally.',
  ),
  DangerSignDefinition(
    id: 'A13',
    text: 'Severe injury: head, spine, chest, abdomen, or multiple fractures',
    explain:
        'A heavy blow to the head, back, chest or belly, or several broken '
        'bones from one accident.',
  ),
  DangerSignDefinition(
    id: 'A14',
    text: 'Severe dehydration: sunken eyes, no urine for 12+ hours, lethargic',
    explain:
        'Very dry mouth, sunken eyes, no urine all day/night, or too weak '
        'to sit up. For a child: no tears and dry mouth.',
  ),
  DangerSignDefinition(
    id: 'A15',
    text: 'Suspected sepsis: fever or low temperature with altered mental state',
    explain:
        'Fever (or cold skin) together with being confused, sleepier than '
        'usual, or not like themselves.',
  ),
];