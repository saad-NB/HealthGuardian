# Clinical Scales, Vitals & Tier 1 Decision Algorithm — Reference Document

**Status: DRAFT for manual review.** All thresholds sourced from published/official references where noted. Verify against `docs/CLINICAL_SOURCES.md` before treating any value here as final — this file is the research basis for that document, not a replacement for it.

---

## 1. Vitals — what to collect and why

| Vital | Why it's collected | Input method |
|---|---|---|
| Respiratory rate (RR) | Early, sensitive marker of deterioration — often abnormal before other vitals change | Manual count (guided timer in-app) or caregiver-entered |
| Oxygen saturation (SpO2) | Direct measure of oxygenation | Pulse oximeter reading, manually entered (Bluetooth device integration is a future enhancement) |
| Systolic blood pressure | Circulatory status | Manual entry (BP cuff reading) |
| Heart rate / pulse | Circulatory/cardiac status | Manual entry or guided manual pulse count |
| Temperature | Infection/sepsis marker | Manual entry |
| Level of consciousness | Neurological status, sepsis/deterioration marker | ACVPU assessment (see §2.2) — distinct from full GCS, used within NEWS2 |
| Supplemental oxygen (yes/no) | Required to correctly score SpO2 in NEWS2 | Simple toggle |
| GCS (Eye/Verbal/Motor) | Detailed neurological/consciousness assessment, esp. for trauma/reduced consciousness | Guided 3-question form (see §2) |

**Data quality note (important, from official NEWS2 guidance):** an incomplete set of vitals cannot be reliably scored. The official guidance is explicit that missing parameters should not simply be skipped silently — either prompt the user to complete the missing value, or apply a documented imputation rule (see §3.5) and clearly flag in the output that a value was imputed, not measured.

---

## 2. Glasgow Coma Scale (GCS)

### 2.1 Scoring criteria

| Component | Response | Points |
|---|---|---|
| **Eye opening (E)** | Spontaneous | 4 |
| | To speech | 3 |
| | To pain | 2 |
| | None | 1 |
| **Verbal response (V)** | Oriented | 5 |
| | Confused | 4 |
| | Inappropriate words | 3 |
| | Incomprehensible sounds | 2 |
| | None | 1 |
| **Motor response (M)** | Obeys commands | 6 |
| | Localizes pain | 5 |
| | Withdraws from pain | 4 |
| | Abnormal flexion (decorticate posturing) | 3 |
| | Extension (decerebrate posturing) | 2 |
| | None | 1 |

**Total score = E + V + M, range 3–15.**

### 2.2 Interpretation

| Band | Score | Meaning |
|---|---|---|
| Mild impairment | 13–15 | — |
| Moderate impairment | 9–12 | Red flag if <13 in a trauma context |
| Severe impairment | ≤8 | Classic threshold for "unable to protect airway" — hard override |

### 2.3 Implementation notes
- Pure arithmetic — three guided inputs, sum, band lookup. No ML, no external dataset.
- **Non-verbal/intubated/language-barrier patients**: GCS verbal scoring assumes the patient can attempt speech in a shared language. For a multilingual, elderly, possibly non-verbal-at-baseline population, the UI needs a documented fallback path (e.g., caregiver-reported baseline, or explicit "unable to assess verbal" input) rather than forcing a score that may misrepresent the patient's true status — **flag this as an open item for manual review**, since standard GCS doesn't natively solve this ambiguity.
- **Pediatric note**: standard GCS assumes an age where the verbal/motor criteria are meaningful (roughly school-age+); a Pediatric GCS variant exists with different verbal criteria for younger children. Out of scope per current MVP (adults only) but flag if pediatric support is ever added.

---

## 3. NEWS2 (National Early Warning Score 2)

Source: Royal College of Physicians (RCP), UK — the current NHS-mandated standard for adult acute deterioration scoring.

### 3.1 Parameters and scoring

| Parameter | 3 | 2 | 1 | 0 | 1 | 2 | 3 |
|---|---|---|---|---|---|---|---|
| Respiratory rate (breaths/min) | ≤8 | | 9–11 | 12–20 | | 21–24 | ≥25 |
| SpO2 **Scale 1** (%) — standard patients | ≤91 | 92–93 | 94–95 | ≥96 | | | |
| SpO2 **Scale 2** (%) — patients with hypercapnic respiratory failure (e.g., target sat 88–92%) | ≤83 | 84–85 | 86–87 | 88–92 (or ≥93 on air) | 93–94 on O2 | 95–96 on O2 | ≥97 on O2 |
| Air or supplemental oxygen? | | On oxygen | | On air | | | |
| Systolic BP (mmHg) | ≤90 | 91–100 | 101–110 | 111–219 | | | ≥220 |
| Heart rate (bpm) | ≤40 | | 41–50 | 51–90 | 91–110 | 111–130 | ≥131 |
| Consciousness (ACVPU) | | | | Alert | | | Confusion/Voice/Pain/Unresponsive (any new change) |
| Temperature (°C) | ≤35.0 | | 35.1–36.0 | 36.1–38.0 | 38.1–39.0 | ≥39.1 | |

**Important, easy to miss**: NEWS2 has **two SpO2 scales**. Scale 1 is default for nearly all patients. Scale 2 is only used when a clinician/authorized prescriber has specifically set a target saturation of 88–92% (typically for patients with known chronic hypercapnic respiratory failure, e.g., certain COPD patients). **Decision needed on manual review**: given this app has no clinician setting that target in real time, default to Scale 1 always, and treat Scale 2 as an out-of-scope edge case unless the patient/caregiver can explicitly confirm a clinician-set target — do not let the app or MedGemma infer this on its own.

**ACVPU** (an extension of the older AVPU scale, official NEWS2 update): Alert, Confusion (new), Voice, Pain, Unresponsive. The addition of "C" (new confusion) versus the older AVPU is specifically important — new-onset confusion alone scores 3 even if the patient is otherwise "responsive to voice," and this is one of the most commonly under-recognized triggers per official guidance.

### 3.2 Aggregate scoring and clinical risk

- **Total score = sum of all 6 parameter scores** (0–20 range), **plus** a +2 point uplift specifically for any patient requiring supplemental oxygen to maintain their target saturation (this uplift is separate from — and in addition to — the oxygen-related scoring already embedded in the SpO2/oxygen rows above; confirm exact aggregation order against the official RCP chart during implementation, since sources vary slightly in how the uplift is described vs. tabulated).

| Aggregate score | Clinical risk | Response |
|---|---|---|
| 0–4 | Low | Routine monitoring (minimum 12-hourly observations) |
| Any single parameter = 3 ("Red score") | Low–medium | **Urgent response required regardless of aggregate total** — this is the single most commonly overlooked rule and should be implemented as an explicit, separate check, not just folded into the aggregate |
| 5–6 | Medium | Key threshold for urgent response; minimum hourly observations |
| ≥7 | High | Urgent or emergency response; continuous/near-continuous monitoring |

### 3.3 Observation frequency (relevant if this app supports repeated/tracked monitoring over time, not just a single assessment)
- Low (0–4): minimum every 12 hours
- Medium (5–6): minimum hourly
- High (≥7): continuous or near-continuous

*(Flag for manual review: does the MVP support repeat/tracked assessments over time, or is this a single-session tool? If the latter, this section is informational only for now but worth designing the data model to support later.)*

### 3.4 The single-parameter rule — implementation priority
This is explicitly called out across multiple official/clinical sources as the rule most often missed in both human practice and naive implementations: **a patient can have a low aggregate NEWS2 (e.g., 2) but still require urgent review if any one parameter alone scores 3** (e.g., newly confused, or RR ≥25). Implement this as an independent, always-checked boolean flag (`single_parameter_red_flag`), not something that only emerges from summing.

### 3.5 Missing/incomplete data
Official guidance treats an incomplete NEWS2 as **not reliably scoreable**. Two documented approaches exist in practice: (a) prompt the user to complete missing fields before scoring, or (b) last-observation-carried-forward imputation (used in some clinical trial protocols, not universal clinical practice). **Recommendation for manual review**: prefer (a) — prompt for completion — as the primary UX, since this app doesn't have a "last observation" to carry forward in a first-time single-session assessment the way a hospital admission does. If a field is truly unobtainable (e.g., no BP cuff available), the output should explicitly flag "NEWS2 partial — missing [parameter]" rather than silently substituting a default, especially since silently defaulting a missing SpO2 or RR to "normal" would be a dangerous silent failure mode.

---

## 4. Burn Assessment (guided UI/questions, not image classification)

### 4.1 Total Body Surface Area (%TBSA) — Rule of Nines (adult)

| Region | % |
|---|---|
| Head & neck | 9% |
| Each arm (full) | 9% |
| Anterior torso | 18% |
| Posterior torso | 18% |
| Each leg (full) | 18% |
| Groin/perineum | 1% |

**Implementation**: user/caregiver marks affected regions on a body-map UI (front/back silhouette); app sums the corresponding percentages. For partial-region burns, consider whether to support fractional marking (e.g., "half of one arm") — **flag for manual review**: full-region-only marking is simpler to implement but less accurate; a finer-grained region map (e.g., palm-sized sub-regions, following the "patient's palm ≈ 1% TBSA" rule of thumb used clinically for small/scattered burns) may be worth the added UI complexity.

### 4.2 Depth classification via guided questions

| Degree | Clinical criteria to ask about | Severity signal |
|---|---|---|
| Superficial (1st) | Red, painful, dry, no blisters, blanches with pressure | Low |
| Superficial partial-thickness (2nd) | Blisters present, moist/weeping, very painful, blanches with pressure | Moderate |
| Deep partial-thickness (2nd) | Pale/mottled, less painful than superficial (nerve involvement), may not blanch | High |
| Full-thickness (3rd) | White/charred/leathery appearance, painless, does not blanch | Critical — hard override |

**Question sequence (draft, refine on review)**:
1. "Are there blisters?" (yes/no)
2. "Is the area red, or is it pale/white, or black/charred?" (multiple choice)
3. "Is the area painful to touch, or numb/less painful than expected?" (multiple choice)
4. "Does the skin turn white then pink again when you press it gently, or stay the same color?" (blanching test — may need a short guided instruction, since a caregiver may not know this technique unprompted)

Map answers to the depth table above via a small decision tree (deterministic, same pattern as GCS/NEWS2 — no ML).

### 4.3 Red-flag thresholds (hard override, regardless of other scores)
- >10% TBSA (adult)
- Any full-thickness (3rd degree) burn, any size
- Burn involving face, hands, feet, genitals/perineum, or suspected airway involvement (ask specifically: "was this burn near the face, mouth, or from smoke/steam inhalation?")

---

## 5. Combined Final Decision Algorithm (Tier 1)

This is the deterministic, auditable decision logic that produces `triage_level_base` — no LLM involvement.

```
INPUT:
  gcs_score, gcs_context (trauma / non-trauma)
  news2_aggregate, news2_single_param_flag (bool)
  burn_tbsa_percent, burn_depth, burn_location_flags[]
  free_text_keyword_flags[] ("cannot breathe", "severe bleeding", "chest pain", etc.)
  data_completeness_flags[] (which inputs are missing/partial)

STEP 1 — Hard Red-Flag Check (evaluated first, independent of all other logic):
  IF gcs_score <= 8: RETURN Emergency
  IF gcs_context == trauma AND gcs_score < 13: RETURN Emergency
  IF news2_single_param_flag == true: escalate_to >= Urgent  (see Step 3 — does not
      immediately return, but guarantees a floor)
  IF news2_aggregate >= 7: RETURN Emergency
  IF burn_depth == full_thickness: RETURN Emergency
  IF burn_tbsa_percent > 10: RETURN Emergency
  IF burn_location_flags includes face/airway/hands/genitals: RETURN Emergency
  IF any free_text_keyword_flags present: RETURN Emergency

STEP 2 — Data completeness check:
  IF critical fields missing (e.g., SpO2 or RR absent from NEWS2 inputs):
      prompt for completion before finalizing; if user proceeds anyway,
      mark output as "partial assessment" and bias the eventual banding
      toward the more cautious interpretation, never the more lenient one

STEP 3 — Aggregate/Moderate-Tier Evaluation (only reached if Step 1 found no hard Emergency):
  level = Routine   # default
  IF news2_aggregate in [5,6]: level = max(level, Urgent)
  IF news2_single_param_flag == true: level = max(level, Urgent)
  IF burn_depth == deep_partial_thickness: level = max(level, Urgent)
  IF burn_depth == superficial_partial_thickness: level = max(level, Urgent-if-combined-with-other-factor
      else informational)
  IF gcs_score in [9,12]: level = max(level, Urgent) [if trauma context, already
      covered by Step 1's <13 trauma rule — this branch mainly covers non-trauma context]

STEP 4 — Routine/Self-care fallthrough:
  IF level still == Routine AND news2_aggregate in [0,4] AND no burn AND
      gcs_score in [13,15]:
      RETURN Routine / Self-care
  ELSE:
      RETURN level  (Urgent, from Step 3)

OUTPUT: triage_level_base, with a full list of which specific rule(s) fired
        (for auditability — never return a bare label with no attached reasoning trail)
```

**Design principles baked into this algorithm (carry into implementation, don't lose in translation to code):**
- Hard flags are checked **first** and **independently** — a low NEWS2 total can never mask a single severely abnormal parameter or an unambiguous red flag.
- The algorithm always returns **which rule(s) fired**, not just a final label — this is what makes `triage_level_base` explainable to Tier 2/MedGemma and to a human reviewer, and is required for the audit-trail principle established in the project README.
- Missing/incomplete data biases toward caution, never toward a lenient default — this needs explicit handling, not an implicit "treat missing as normal" fallback, which would be a dangerous silent behavior.
- This entire algorithm should be implemented as **pure, side-effect-free functions**, directly unit-testable per the boundary-value and hard-flag-coverage tests specified in the project README.

---

## 6. Open Items for Manual Review

1. Confirm exact NEWS2 +2 oxygen-uplift aggregation order against the official RCP chart (source documents reviewed give slightly different presentations of this — resolve against the primary RCP publication before finalizing `clinical_thresholds` config).
2. Decide Scale 1 vs. Scale 2 SpO2 handling — recommendation above is Scale 1 always, confirm or override.
3. Non-verbal/language-barrier GCS fallback path — needs explicit UX design, not just scoring logic.
4. Fractional vs. whole-region burn TBSA marking — UI complexity vs. accuracy tradeoff.
5. Whether repeat/tracked assessments (not just single-session) are in scope — affects whether NEWS2 observation-frequency guidance (§3.3) needs to be implemented as active app behavior or stays informational.
6. Step 3's handling of superficial-partial-thickness burns ("Urgent if combined with other factor, else informational") needs a concrete rule, not a soft description — decide and encode explicitly.
