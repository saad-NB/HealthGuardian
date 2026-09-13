# Sehat Nigraan — Complete Project Specification

**Sehat Nigraan (صحت نگران · "Health Guardian")**
**Offline-first, two-tier AI patient triage for elderly and rural populations.**

**Version:** 1.0 (presentation master)
**Date:** 2026-09-13
**Status:** Consolidates the current shipped state of the project for presentation
and specification purposes.

> This document is a single, self-contained specification of the whole project,
> written so it can be used directly to build a presentation. It synthesises the
> authoritative reference files kept in `docs/` (architecture, decisions,
> prompts, clinical sources, vitals sensing, drug interactions, UI plan,
> roadmap, model cards) with the shipped codebase. Where this document glosses
> over detail, the linked reference file carries the exact, up-to-date
> specification.

---

## Contents

1. Executive Summary
2. Problem & Opportunity
3. Product Vision & Audiences
4. Non-Negotiable Design Constraints
5. Scope (In / Out / Non-Goals)
6. System Architecture
7. Tier 1 — Deterministic Triage Engine
   7.1 Design Principles
   7.2 Clinical Scales by Age
   7.3 Hard Red-Flag Gates
   7.4 Vitals Scoring (NEWS2 / Peds-NEWS2 / PEWS)
   7.5 Consciousness (GCS / AVPU)
   7.6 Chief Complaint & Scored Probes
   7.7 Sepsis Screen (qSOFA / pedSIRS)
   7.8 Burn Module
   7.9 Modifiers
   7.10 Merge & Escalation Rules
   7.11 Missing-Vitals Policy
   7.12 Engine Implementation
8. Tier 2 — MedGemma LLM Advisories
   8.1 Model & Runtime
   8.2 Text-Only Pathway
   8.3 Prompt Architecture
   8.4 Structured Output & Fail-Closed Parser
   8.5 Escalation-Only Merge & Both-Flags Display
   8.6 Token Budgets & Truncation Control
   8.7 Device-Aware Context Window
   8.8 Reasoning-Trace Handling
   8.9 Chat Surfaces (Ephemeral)
9. On-Device Vitals Sensing
   9.1 Heart Rate via Camera PPG
   9.2 Breathing Rate via Microphone
   9.3 Confidence Policy
   9.4 Calibration & Pilot
   9.5 Tunable Constants
   9.6 Failure Modes & Handling
   9.7 Calibration Sessions
10. Drug Interaction Checker
   10.1 What it does
   10.2 Severity Model
   10.3 Bundled Data
   10.4 Data Pipeline & Provenance
   10.5 Safety & Limitations
   10.6 Dataset Licensing Record
   10.7 openFDA Enrichment Methodology
   10.8 Code Map
11. Data Model & Local Storage
12. Privacy & Permissions
13. UI/UX Specification
   13.1 Design Vision & Principles
   13.2 Visual Identity
   13.3 Information Architecture
   13.4 Triage Walkthrough Flow
   13.5 Screen-by-Screen
   13.6 Missing-Data UX
   13.7 Accessibility & Localization
   13.8 Performance Budgets
   13.9 Component Library
   13.10 Result & Emergency States
   13.11 Accessibility Checklist
   13.12 Walkthrough Error Cases
14. Testing & Quality Strategy
   14.1 Test Pyramid
   14.2 Coverage Gates
   14.3 On-Device E2E Harness
   14.4 Test Inventory
   14.5 Test Inventory by Module
   14.6 Tier 2 On-Device Failure Matrix
15. Deployment & Build
16. Safety & Clinical Governance
17. Architecture Decision Records (Summary)
18. Project Status & Roadmap
19. Presentation Key Numbers
20. Presentation Narrative (Talk-Track & Demo Flow)
21. Glossary

---

# 1. Executive Summary

**Sehat Nigraan** is an offline-first, two-tier AI *decision-support* app for
patient triage, built for caregivers of elderly and rural patients. The person
holding the phone in an emergency is **not a clinician** — a daughter checking
on her mother in a village, a first responder, or the elderly patient
themselves. The app turns a guided, giant-button questionnaire into a
**risk-banded urgency result** (P1–P5, Emergency → Minor) plus a plain-language
clinical summary, **entirely on the device**, with **zero server dependency**.

The system has two cooperating tiers:

- **Tier 1 — deterministic rule engine (always runs, < 1 s, offline).** Uses
  age-appropriate, published clinical scales (NEWS2, Peds-NEWS2, PEWS, GCS),
  hard red-flag gates, complaint-driven scored probes, a sepsis screen, and a
  burn module, then merges every sub-score with an escalation-only `max()`
  rule and a fails-closed safety floor.
- **Tier 2 — MedGemma-1.5-4B (optional, text-only).** A small LLM running
  on-device via fllama (llama.cpp) that receives the structured Tier 1 payload
  and either **confirms or raises** the urgency, plus a 4–6 line
  caregiver-friendly summary. It can never downgrade Tier 1.

Two further offline modules round out the product:

- **On-device vitals sensing** — heart rate from the rear camera (PPG) and
  breathing rate from the microphone, with confidence scoring and a
  never-blocking policy, so caregivers without a pulse oximeter can still
  complete vitals.
- **Drug interaction checker** — a bundled, public-domain dataset
  (NDF-RT + ONC + openFDA) screened entirely on-device, with severity labels
  and optional AI explanations.

Every output carries `requires_human_verification: true`. The app **does not
diagnose and never prescribes**; it is decision support for the clinician, and
a first-line urgency guide for the family.

**Current state:** all core features are implemented and device-verified.
**383 automated tests pass** and `flutter analyze` is clean. The app has been
built and verified as an Android APK on a budget device (Vivo V2061) and as a
Windows desktop release.

---

# 2. Problem & Opportunity

## 2.1 The clinical setting

In rural Pakistan and comparable low-resource settings:

- The nearest functional facility can be **hours away**; connectivity is
  unreliable.
- Caregivers have **no systematic way to decide**: "Is this urgent enough to
  travel now, or can we wait and watch?"
- A paediatric or elderly patient's deterioration is often missed because the
  family has **no reference for "normal"**, and because warning signs are
  subtle.
- Devices in the household are **low-to-mid-range Android phones** — and there
  is usually **no pocket pulse oximeter or thermometer** within reach of the
  decision.

## 2.2 The information gap

Emergency triage in clinics is anchored by **published, validated clinical
scores** (e.g., NEWS2 for early warning, GCS for consciousness, qSOFA/pedSIRS
for sepsis, Rule of Nines/ABA referral criteria for burns). Families rarely
have access to these scores, and even when they can compute one, they cannot
combine several sources of risk into a single urgency band under stress.

## 2.3 The opportunity

A phone already in the family's hand can:

1. **Walk the caregiver** through a structured assessment using published
   scores (Tier 1).
2. **Sense** heart rate and breathing rate from the phone's own camera and
   microphone (no extra hardware).
3. **Explain** the result in plain, spoken language the family understands.
4. Do all of it **offline**, so the decision never waits on the network.
5. Optionally add an **on-device AI** advisory (Tier 2) that confirms urgency
   and frames what to do next.

## 2.4 User journeys (design-through-e2e)

**Journey A — "Is it urgent tonight?"**
Night, village, mother is febrile and confused. Daughter opens the app (cold
start, no network). Age/sex first → green PEWS? (no — mother is adult) →
danger-gate screen (confusion is a red-flag symptom → she taps it) → **P1:
"Call 1122 / hospital now."** System still collects vitals and complaints to
fill the record the sister hands the doctor. < 3 minutes, zero typing.

**Journey B — "No thermometer, no oximeter."**
First responder at a clinic doorstep. SpO₂ and temp are unmeasurable → both
answered **"Not available"** → the engine floors at P3 (fail-closed), flags
the review banner, and **forcibly engages the sepsis screen** (end of §7.11).
The caregiver still gets a careful recommendation and the clinician sees the
missing-data trail in the record.

**Journey C — "Measure the pulse, count the breaths."**
Caregiver has no devices but the phone. On the HR step: **"Measure with
phone"** → fingertip on camera, flash on, live preview → 30 s → "HR 84 · medium
confidence". On the RR step: **"Measure background noise"** (6 s) → "Measure
with phone" → 45 s → "RR 18 · high". Both auto-filled into the same vital
fields the steppers would fill; scoring is identical to manual entry; the
record's `inputs.vitals` notes the sensor provenance for the clinician.

**Journey D — "Are these two medicines safe together?"**
Elderly man holds two packets, both generic names known to the app. Adds them
under **Drugs**, taps Check → a **severe** pair raises the non-dismissible
blocking dialog. He taps **Explain** → MedGemma writes a plain-language
explanation on-device; **Ask AI about these medicines** opens a chat that
already holds the pairing + screening result. The check is saved to Recent
checks. All offline.

These four journeys map 1:1 onto the on-device e2e scenarios (§14.3), so the
product claims are also the automated regression claims.

---

# 3. Product Vision & Audiences

**Vision (one sentence):** *"A calm, giant-button questionnaire that tells a
family exactly what to do next — in their own language, with or without
network, and with or without a clinician in the room."*

**Primary audience:** elderly patients, their daughters/sons, and family
caregivers in Pakistan (and other low-resource settings).

**Primary personas**

| Persona | Context | What they need |
|---|---|---|
| Daughter checking on her mother | Village home, internet drops in/out, busy on the farm | A fast answer: urgent or not, and a plan |
| First responder with first-aid training | Any setting, under time pressure | A structured checklist that never forgets a red flag |
| The elderly patient themself | Poor eyesight, tremor, low tech-literacy | Giant buttons, one question at a time, read-aloud |
| A nurse at a rural clinic | Pre-registration of walk-ins | A consistent, scoreable start to care; a record to pass on |

**Design posture (in contrast to consumer apps):**

| Typical app goal | Sehat Nigraan goal |
|---|---|
| Maximise time in app | Minimise time-to-decision (≤ 3 min) |
| Discover features | Hide everything except the next step |
| Account/personalisation | Zero setup; runs from cold start |
| Dense, rich UI | Giant, sparse, high-contrast, foolproof |

---

# 4. Non-Negotiable Design Constraints

These constraints drive every architectural choice in this project:

1. **Offline-first, zero server dependency.** The safety-critical path must
   work with no connectivity at all. Not "graceful degradation" — offline is
   the expected state.
2. **Safety over convenience, always.** Any missing/invalid/ambiguous input
   defaults to a *more* conservative tier (fail-closed). Under-triage is the
   cardinal error; its rate is the single most-tracked metric and any non-zero
   miss on the vignette set is a release blocker.
3. **Escalation-only merging.** Tier 2 can raise Tier 1, never lower it. This is
   a hard architectural invariant, not a guideline.
4. **Deterministic Tier 1.** The rule engine is pure, synchronous Dart with no
   async, no I/O, no randomisation — fully unit-testable headlessly.
5. **Published, cited thresholds.** Every clinical threshold is traceable to a
   published source (`docs/CLINICAL_SOURCES.md`); any deviation is a recorded
   ADR. Changing a threshold requires a DECISIONS entry.
6. **No diagnosis, no prescribing.** The app and its AI are decision support.
   Every AI output is flagged with `requires_human_verification: true` at the
   schema level.
7. **Commercial-clean data.** Bundled datasets (drug interactions) use only
   public-domain / license-free sources.
8. **Privacy by architecture.** Patient data stays on-device: encrypted local
   store, ephemeral AI transcripts, minimal sensor persistence.

---

# 5. Scope

## In scope (MVP — all shipped)

- **Tier 1 triage engine** — multi-scale vitals, GCS/AVPU, 18 complaint chips
  with scored probes, sepsis screen, burn module, danger gates, modifier bumps,
  `max()` merge, missing-vitals policy.
- **Tier 2 MedGemma advisories** — structured JSON output, escalation-only
  merge, both-flags result display, summary + Ask-AI chat, dynamic token
  budgets, device-aware context.
- **On-device vitals sensing** — camera PPG heart rate, microphone breathing
  rate, Monitor tab, in-triage measure + "use latest reading".
- **Drug Interaction Checker** — Drugs tab, bundled public-domain dataset,
  severity model, blocking dialogs, AI explanations, saved checks.
- **Local history & records** — encrypted local store, record detail view,
  Ask-AI handoff.
- **Multi-platform shell** — Android (primary), Windows desktop (dev/demo).
- **Multilingual structure** — locale-aware shell; Urdu (default, RTL), English,
  Roman Urdu accessibility variant (copy itself partially roadmap).

## Out of scope for MVP (documented in `docs/ROADMAP.md`)

- Eye and throat/anaemia **vision classifiers** (dataset research completed;
  vision input dropped entirely per ADR-020).
- Full pill recognition / medication-adherence tracking.
- Live server-side APIs (RxNav DDI API permanently discontinued Jan 2024; any
  interaction source must be a static bundled dataset).
- Voice STT/TTS (roadmap), accelerometer "precision mode" breathing (roadmap),
  camera-based SpO₂ (rejected: not reliable via phone sensors).

## Explicit non-goal

The app does **not** diagnose and does **not** replace professional medical
judgment. Every AI Tier 2 output includes `requires_human_verification: true`
enforced at the schema level, not just in UI copy.

---

# 6. System Architecture

```
 Input Layer (Flutter, on-device)
    │
    ▼
 Tier 1 — Core Engine (deterministic, always runs, <1s, offline)
    ├─ Danger-sign gates            -> P1 override (any YES, binary)
    ├─ Vitals: NEWS2 (16+) · Peds-NEWS2 (1–15y) · PEWS (<1 mo)
    ├─ GCS / AVPU                   -> consciousness tier
    ├─ Chief complaint (18 chips) + scored probes (6 branches)
    ├─ Sepsis screen: qSOFA (adult) / pedSIRS (child)
    ├─ Burn module: TBSA + depth + airway + location
    ├─ Modifiers: age/pregnancy/immunocompromise/MUAC/CFS
    └─ max() merge  +  modifier bump  +  P3 floor + vitalReviewRequired
        -> triage_level_base (P1–P5) + reasons + contributing scores
    │
    ▼
 Device capability check (RAM / GGUF present)
    │
    ├─ capable ─▶ Tier 2 — MedGemma-1.5-4B (Q4_K_M GGUF, fllama, text-only)
    │              triage_level_final = max(triage_level_base, AI suggestion)
    │              + 4–6 line summary (strict-JSON, fail-closed parser)
    │              + both-flags display (Tier 1 first, then AI)
    │
    └─ not capable / declined ─▶ Tier 1 result stands alone
    │
    ▼
 Output Layer — tier banner + reasons + summary + next steps + record (v2.1)
```

**Independent companion modules (offline):**

- **Vitals Sensing** (`lib/vitals/`) — HR (camera PPG) + RR (microphone),
  values feed the same `TriageAnswers` fields the manual steppers drive, so the
  engine, scoring, thresholds, and records are untouched.
- **Drug Interaction Checker** (`lib/interactions/`) — Drugs tab, bundled JSON
  assets, pure-Dart engine, optional MedGemma explain.

**State management:** BLoC was chosen at ADR-004 for explicit, traceable state
transitions in safety-critical flow; the triage walkthrough currently ships with
vanilla state in a local flow controller (ADR-011), with `TriageAnswers` as the
single state object. The rule engine itself is framework-free pure Dart.

**Tech stack summary**

| Layer | Choice |
|---|---|
| App framework | Flutter (Android primary; Windows desktop secondary) |
| On-device LLM | fllama (wraps llama.cpp), MedGemma-1.5-4B GGUF |
| State management | BLoC (architecture) / vanilla flow controller (current walkthrough) |
| Vitals sensing | official `camera` plugin + `record` plugin, custom pure-Dart DSP |
| Storage | encrypted local record store (not SQLite); JSON stores for monitor/drugs |
| Datasets | public-domain static JSON assets bundled in the APK |

## 6.1 Repository layout (as shipped)

```
lib/
  main.dart                          App entry; wires RootShell + AppState
  config/clinical_thresholds.dart    Scale thresholds with inline citations
  models/medgemma_files.dart         GGUF metadata (filenames, sizes, HF URLs)
  prompts/
    tier2_prompts.dart               Tier 2 system/user prompt templates
    interaction_prompts.dart         Drug-interaction explain prompt (ADR-018)
  screens/files_screen.dart          Model-file download/verify UI (under Settings)
  services/
    llm_service.dart                 fllama OpenAI-style chat wrapper, streaming
    download_service.dart            Resumable model download w/ size checks
    device_capabilities.dart         RAM -> usable context profile (ADR-019)
    tier2_service.dart               Tier 2 orchestrator (prompt -> LLM -> parser -> merge)
                                     + interaction explain (ADR-018)
  state/app_state.dart               Shared state (model paths, logs)
  triage/
    engine.dart                      Pure synchronous multi-scale Tier 1 engine
    models.dart                      TriageAnswers, AgeGroup, scales, thresholds
    probes.dart / danger_signs.dart / burn_profile.dart   Question/burn definitions
    record.dart / record_store.dart  TriageRecord (v2.1) + encrypted local store
    tier2.dart / tier2_parser.dart   Tier 2 types + tolerant fail-closed parser
    reasoning_trace.dart             Draft/Critique/Revise + answer extraction (ADR-019)
    inference_budget.dart            Token-budget single source of truth (ADR-015/019)
  ui/
    screens/
      root_shell.dart                Bottom nav: Start / History / Monitor / Drugs / Ask AI
                                     + top-left Settings route (ADR-016/017/018)
      start_screen.dart / history_screen.dart / settings_screen.dart / chat_screen.dart
      triage/                        Walkthrough steps (flow, complaints, probes, GCS,
                                     vitals, danger, sepsis, burn, modifiers, result)
    text/markdown_lite.dart          Bullet/bold/italic/code renderer (ADR-015)
    theme/ widgets/                  Design tokens + StepperTiles, segmented Yes/No, chips, banners
  vitals/                            On-device sensing (ADR-017, docs/VITALS_SENSING.md)
    measurement_session.*            Shared session state machine + view (HR/RR)
    dsp/                             Pure-Dart filters (biquad, envelope, peaks, windows, fft)
    heart_rate/ breathing_rate/      Camera PPG / microphone pipelines + services
    monitor/                         Monitor tab UI + compact store (value/confidence/time)
  interactions/                      Drug interaction checker (ADR-018)
    models.dart / dataset.dart / engine.dart / severity_style.dart
    drug_check_screen.dart / drug_check_store.dart
scripts/device_e2e.ps1               adb harness: 9 triage scenarios + monitor smokes
tools/hr_log.dart                    HR/RR supervised-calibration collector/analyzer
datasets/scripts/                    DDI provenance pipeline (verify/fetch/mine/build/emit)
assets/
  data/                              Bundled DDI assets (ddi.json, drug_names.json)
  icon/  app icon.svg                Launcher icon source + raster work
docs/                                This spec + reference docs + model cards
```

---

# 7. Tier 1 — Deterministic Triage Engine

## 7.1 Design principles

| # | Principle | Rationale |
|---|---|---|
| 1 | **Gate-first, always.** Binary emergency gates short-circuit all scoring | A patient in extremis never waits for arithmetic |
| 2 | **Max() merge, escalate-only.** Final tier = most urgent of all sub-scores | Guarantees conservative triage |
| 3 | **Age-appropriate scales.** NEWS2 (adult), Peds-NEWS2 (child), adapted PEWS (neonate) | Wrong-scale scoring is a dangerous error |
| 4 | **Nearly-free inputs.** Every field feeds at least one score; no orphaned questions | Minimises caregiver burden |
| 5 | **Fail-closed.** Missing/invalid/ambiguous input → more conservative tier | No unsafe operation under uncertainty |
| 6 | **Auditability.** Every decision stores contributing sub-scores and triggering items | Clinician review + quality improvement |
| 7 | **Low-resource realism.** Palm-method TBSA, AVPU fallback, minimal free text, optional paediatric BP | Deploys where labs/cuffs/oximeters are scarce |

## 7.2 Clinical scales by age bracket

| Bracket | Age | Scale |
|---|---|---|
| Neonate | 0–30 days | Adapted PEWS |
| Infant / Toddler / Preschool | 1 month–4 years | Peds-NEWS2 |
| School-age | 5–11 years | Peds-NEWS2 |
| Adolescent | 12–15 years | Peds-NEWS2 |
| Adult | ≥ 16 years | NEWS2 |

The correct bracket is determined **before** any vital scoring; all subsequent
pickers adjust ranges and thresholds by bracket. Age is collected first in the
walkthrough (ADR-016) and the modifiers step only re-asks fields not already
answered.

## 7.3 Hard red-flag gates (Section A)

Any **YES** forces **P1 (Emergency)** immediately, bypassing all scoring. Six
binary gates (danger signs): severe impairment of consciousness, hypotension
(SBP ≤ 90), severe hypoxia (SpO₂ ≤ 91% room air), critical respiratory rate
(≤ 8 or ≥ 25), critical heart rate (≤ 40 or ≥ 131), critical temperature
(≤ 35.0 or ≥ 39.1). A gait/«airway»-type check and stridor-like presentations
also route to P1 (spec §4). Gates are never overridden by score aggregation.

## 7.4 Vitals scoring

**NEWS2 (adults, ≥16 y)** — Royal College of Physicians, NEWS2 2017.
Seven physiological parameters scored 0–3:
SpO₂, inspired oxygen (on O₂ = 2), systolic BP, heart rate, temperature,
respiratory rate, consciousness. Special handling:

- **NEWS2 Scale 1** is used (COPD/CO₂ retention is a recorded modifier that
  drives the doctor's interpretation; see ADR-010).
- **AVPU gradient (project deviation, ADR-009):** A=0, V=2, P/U=3 (the spec
  shares this gradient with the pediatric scales). This is a documented,
  isolated deviation from standard NEWS2's "any non-alert = 3" and is
  isolated to one function so clinical review can flip it.

**Tier mapping (spec §5.1, ADR-010 — conservative interpretation):**

| NEWS2 aggregate | Any single parameter | Tier |
|---|---|---|
| ≥ 7 | or = 3 | **P1** |
| 5–6 | | P2 |
| 3–4 | | P3 |
| 1–2 | | P4 |
| 0 | | P5 |

A lone score-3 parameter (e.g., temp ≤ 35.0, HR ≥ 131, RR ≥ 25) yields P1.

**Peds-NEWS2 (1–15 y)** — per-bracket thresholds for six pediatric brackets
(from age-group charts, with cited reference tables); collects RR, SpO₂, HR,
temp, capillary refill, on-O₂, AVPU. **Systolic BP is optional** for children
(ADR-013): it is scored if provided, but its absence never sets the
missing-vitals floor — removing a chronic false P3 flag for the target
population.

**Neonatal adapted PEWS (<1 month)** — collects RR, SpO₂, HR, temp, feeding,
consciousness (AVPU); BP optional. Includes an age-based floor (healthy neonate
maps to P4, not P5) reflecting the accepted fragility baseline of the
population.

**Single-parameter escalation:** any parameter hitting its score-3 band triggers
P1 (ureas: HR ≤ 40 or ≥ 131, RR ≤ 8 or ≥ 25, temp ≤ 35.0 or ≥ 39.1, SBP
≤ 90 or ≥ 220, SpO₂ ≤ 91) — this doubles as the hard red-flag override layer.

## 7.5 Consciousness (GCS / AVPU)

- **AVPU default** — four giant tiles (Alert/Voice/Pain/Unresponsive), the
  day-to-day consciousness question.
- **Full GCS** is asked only when the spec requires it: danger sign, AVPU ≠
  Alert, or relevant complaint/age (e.g., head injury, headache danger).
- GCS is stored as three integers (eye/verbal/motor) so a partial assessment
  never counts as complete (ADR-012).
- Tier map: 3–8 → P1, 9–12 → P2, 13 + deficit → P3, 14 → P4, 15 → P5;
  head-injury context escalates 9–12 → P1 and gives 14+ a P4 floor.

## 7.6 Chief complaint & scored probes (Sections D & E)

- **18 complaint chips** (2 screens max): fever, breathing difficulty, chest
  pain, abdominal pain, vomiting/diarrhoea, sore throat, ear pain, eye problem,
  skin/rash, wound/burn, headache, weakness/numbness, urinary problem,
  pregnancy-related, injury/trauma, poisoning/overdose, mental-health crisis,
  other.
- **6 branches carry scored probes.** Branch tier maps (examples):
  - Chest pain: ≥ 6 → P1, ≥ 4 → P2
  - Breathing: ≥ 6 → P1, ≥ 3 → P2
  - Fever / Headache / Abdominal: ≥ 5 → P1, ≥ 3 → P2
  - Mental health: ≥ 6 → P1, ≥ 3 → P2
  - E-C4 (tearing back pain) forces P1 regardless; E-B1 ("speak in full
    sentences") is inverted — "No" = concern (+3).
- **Aggregation across complaints (ADR-016):** the engine escalates from
  **every** answered complaint (primary + "More problems?" round-robin loop);
  most-urgent branch tier wins and its label is recorded. Unanswered probes
  never escalate.
- Free-text `extraComplaintNotes` flows **only** to the Tier 2 payload/context
  block, never the deterministic engine.

## 7.7 Sepsis screen (Section F)

- Appears when engaged: fever complaint, unmeasured temp/SpO₂, or the uber
  unease answer is "Yes".
- **Adults:** qSOFA = F2 + F3 + F4 (hypotension, tachypnoea, AMS); ≥ 2 → P1,
  == 1 → P2. F1 (suspected infection) gates escalation.
- **Children:** pedSIRS from measured vitals (temp/RR/HR vs age-adjusted 95th
  percentiles, with the F-screen as fallback); ≥ 2 + infection → P1, 1 +
  infection → P2.
- **Neonates:** no F-screen sepsis tier (clinical judgement via danger gates).
- **Fail-closed (ADR-016):** every row starts un-answered; the engine treats
  `null` as "No"; qSOFA computed only from answered rows. (Fixes an earlier
  on-device bug where uppercase field ids silently no-op'd the screen.)

## 7.8 Burn module (Section H)

Guided UI (no image classification): mechanism → time → body map → TBSA →
depth → airway/circumferential.

- **P1 rules:** any airway sign (hoarseness/soot/singed hair), electrical or
  chemical cause, chemical/electrical to eyes or mouth, circumferential
  full-thickness burn.
- **P2 rules:** >10% TBSA child / >20% adult (fluid-resuscitation threshold),
  full-thickness >1% anywhere, face/hands/feet/genitals/joints, any burn with
  age <5 or >60.
- **P4/P5:** <5% TBSA partial thickness no risk areas → P4; superficial only
  <1% → P5.
- **TBSA via palm method** (entire open hand ≈ 1%); stepper 0–40%. Critical
  locations auto-flag (face, hands, feet, genitals/perineum, circumferential,
  joints). Sources: Wallace "Rule of Nines", ABA Burn Referral Criteria.

## 7.9 Modifiers (Section I)

| Modifier | Input | Bump |
|---|---|---|
| Age <5 or >65 | Stepper (years; <1 in months) | +1 tier |
| Pregnancy (any; 2nd/3rd trimester/complication) | Y/N/unsure + weeks | +1 tier |
| Immunocompromised | HIV/AIDS, chemo, steroids >20 mg, transplant | +1 tier |
| MUAC < 11.5 cm (<5y) | Tape measure | +1 tier |
| CFS ≥ 5 (≥65y) | 1–7 pictorial | +1 tier |
| COPD/CO₂ retention | Y/N | (drives Interpretation) |

Single bump per qualifying modifier, applied after `max()` merge, capped at P1.
The UI shows a live "will bump the result" badge.

## 7.10 Merge & escalation rules (Section 13)

1. Compute every sub-tier: vital, GCS, complaint, sepsis, burn (missing/silent
   modules contribute a P5 no-op).
2. `merged = max(all sub-tiers)` (most urgent wins).
3. Apply modifier bump (one, cap P1).
4. Apply safety checks: physiologically-impossible values and high-tier-with-
   missing-vitals both set `vitalReviewRequired` regardless of tier.
5. Emit `TriageResult`: `tier`, `reasons[]`, `allScores{...}` (every
   contributing score with provenance), `timestamp`, `vitalReviewRequired`.
6. `triage_level_final = max(triage_level_base, Tier 2 suggestion)` — the
   escalation-only invariant enforced **in code** (invariant-tested every
   build).

## 7.11 Missing-vitals policy (spec §21, ADR-008)

Replaces the old all-or-nothing "any missing → P3 only" rule, which discarded
grossly abnormal *present* parameters and risked under-triage:

- Compute the scale score from **all present parameters**; never score a
  missing parameter as 0.
- **Conservative substitution** in defined contexts: SpO₂ concern → score 3;
  temperature concern → score 3 (2 in fever-only, clinical review pending).
- **Any missing vital → tier floor P3** and mandatory `vitalReviewRequired`.
- Danger gates and single-parameter escalation (from present values) take
  precedence.
- **Missing SpO₂ AND temperature together → sepsis screen becomes mandatory**
  (the safety net; spec Appendix C).
- UX: the vitals stepper shows an explicit **"Not available"** for SpO₂/temp —
  the system never invents a value, and the result screen always shows a
  yellow ReviewBanner when data was incomplete. (spec §10 of the UI plan).

## 7.12 Engine implementation

- `lib/triage/engine.dart` — single pure synchronous `TriageEngine`, no Flutter
  dependencies, dispatches by `AgeGroup.scale` (NEWS2/Peds-NEWS2/PEWS).
- `lib/config/clinical_thresholds.dart` — every threshold with an inline source
  citation; single versioned config file, **never scattered magic numbers**.
- `lib/triage/models.dart` — `TriageAnswers`, age groups, scales, thresholds.
- `lib/triage/record.dart` (+ `record_store.dart`) — `TriageRecord` v2.1 and the
  encrypted local store.
- Latency target: **< 1 s on any device** (pure synchronous chat, no async, no
  network in Tier 1).

## 7.13 Reference tables (sources in `docs/CLINICAL_SOURCES.md`)

The published tables below are the exact value sets encoded in
`lib/config/clinical_thresholds.dart` (each with an inline citation).

### NEWS2 scoring table (adults)

| Parameter | 3 | 2 | 1 | 0 | 1 | 2 | 3 |
|---|---|---|---|---|---|---|---|
| SpO₂ Scale 1 (%) | ≤ 91 | 92–93 | 94–95 | ≥ 96 | — | — | — |
| Air or oxygen | — | Oxygen | — | Air | — | — | — |
| Systolic BP (mmHg) | ≤ 90 | 91–100 | 101–110 | 111–219 | — | — | ≥ 220 |
| Heart rate (bpm) | ≤ 40 | — | 41–50 | 51–90 | 91–110 | 111–130 | ≥ 131 |
| Temperature (°C) | ≤ 35.0 | — | 35.1–36.0 | 36.1–38.0 | 38.1–39.0 | ≥ 39.1 | — |
| Respiratory rate | ≤ 8 | — | 9–11 | 12–20 | 21–24 | — | ≥ 25 |
| Consciousness | — | — | — | Alert | — | — | V/P/U |

**Project AVPU gradient (ADR-009):** Alert = 0, Voice = 2, Pain/Unresponsive = 3
(shared with the pediatric scales; a documented deviation, isolated to one
function).

**Clinical risk bands → tiers (ADR-010 conservative reading):**

| Aggregate | Single param = 3 | Tier |
|---|---|---|
| 0 | — | P5 |
| 1–2 | — | P4 |
| 3–4 | — | P3 |
| 5–6 | — | P2 |
| ≥ 7 | yes | P1 |

### Peds-NEWS2 (1–15 years)

Age is split into pediatric brackets (infant/toddler/preschool, school-age,
adolescent) with per-bracket threshold tables derived from the cited pediatric
reference. Collects RR, SpO₂, HR, temp, capillary refill, on-O₂, AVPU;
aggregate→tier mapping shares the adult band structure (0→P5 … ≥7 or any=3→P1).
**Systolic BP is optional (ADR-013)** — scored if provided (pediatric SBP bands
apply, a score-3 fires single-parameter P1), never part of the missing-set.

### Neonatal adapted PEWS (< 1 month)

Collects RR, HR, SpO₂, temp, blood pressure (optional), consciousness, feeding;
threshold bands target the neonate's narrower physiological ranges.
Aggregate mapping: ≥ 4 → P1, 2–3 → P2, 1 → P3, 0 → P4 (a P4 floor for the
normal neonate reflects the population's accepted fragility baseline).

### GCS (Teasdale & Jennett, 1974)

| Component | Score | Description |
|---|---|---|
| Eye | 4 / 3 / 2 / 1 | Spontaneous / To voice / To pain / None |
| Verbal | 5 / 4 / 3 / 2 / 1 | Oriented / Confused / Inappropriate words / Incomprehensible sounds / None |
| Motor | 6 / 5 / 4 / 3 / 2 / 1 | Obeys / Localises pain / Withdraws / Abnormal flexion / Extension / None |

Total 3–15. Tier: 3–8 → P1; 9–12 → P2 (head-injury context → P1); 13 + deficit
→ P3; 14 → P4 (head-injury floor P4); 15 → P5. Partial GCS never counts
(three integers stored).

### Sepsis screen (Section F)

- **Adult qSOFA:** hypotension (SBP ≤ 100), tachypnoea (RR ≥ 22), altered
  mentation. Score from answered rows only (unanswered = No). ≥ 2 → P1, == 1 →
  P2, gated by F1 "suspected infection" = Yes.
- **Child pedSIRS:** fever/hypothermia, tachypnoea, tachycardia (age-adjusted
  95th percentiles), leukocyte/band abnormalities (F-screen fallback). ≥ 2 +
  infection → P1; 1 + infection → P2.
- **Neonate:** no F-screen sepsis tier — clinical judgement via danger gates.
- **Fallback standard:** both SpO₂ and temp missing → sepsis screen becomes
  mandatory (spec §21.7 / Appendix C).

### Burn rules (Wallace 1951; ABA Referral Criteria)

| Condition | Tier |
|---|---|
| Airway sign (hoarseness, soot, singed hair) | P1 |
| Electrical or chemical cause | P1 |
| Chemical/electrical to eyes or mouth | P1 |
| Circumferential full-thickness | P1 |
| > 10% TBSA (child < 16 y) / > 20% (adult ≥ 16 y) | P2 |
| Full-thickness > 1% any location | P2 |
| Face / hands / feet / genitals / major joints | P2 |
| Any burn + age < 5 or > 60 | P2 (bump) |
| < 5% TBSA, partial thickness, no risk areas | P4 |
| Superficial only, < 1% | P5 |

TBSA input is the **palm method** (entire open hand ≈ 1%), stepper 0–40%.

### Modifier bump matrix

| Modifier | Condition | Effect |
|---|---|---|
| Age | < 5 or > 65 | +1 tier |
| Pregnancy | any; weeks for 2nd/3rd + complication | +1 tier |
| Immunocompromised | HIV/AIDS, chemo, steroids > 20 mg, transplant | +1 tier |
| MUAC | < 11.5 cm (age < 5 y) | +1 tier |
| CFS | ≥ 5 (age ≥ 65 y), 1–7 pictorial | +1 tier |
| COPD/CO₂ retention | Yes | Drives NEWS2 interpretation |

One bump total (no stacking), applied after `max()`, capped at P1.

## 7.14 Worked Tier 1 examples (presentation-ready)

**Example A — Adult, chest pain, normal vitals.**
Vitals: RR 16 / SpO₂ 97% (air) / SBP 130 / HR 78 / temp 36.8 / Alert → NEWS2
aggregate **0 → P5**. GCS 15 → P5. Complaint chest pain, probes: sub-sternal,
worse on exertion, eased by rest → chest score 4 → **P2**. Sepsis not scored.
Burn none. Modifiers: age 61 → no bump. **Final: P2** — reasons: NEW2 0 (P5),
GCS 15 (P5), complaint chest-pain branch ≥ 4 → P2; merged = max = P2.
Tier 2 may keep P2 or raise to P1; it may never lower.

**Example B — Child (7 y), fever + abnormal cap refill.**
Age bracket school-age → Peds-NEWS2. RR 24 (score 2), SpO₂ 96%, HR 120
(age-band score 2), temp 38.6 (score 1), cap refill 3 s (score 2), on O₂: no →
aggregate **7 + a single = 2? (any=3 absent) → aggregate ≥ 7 → P1**.
Danger-sign screen: none of the six fired, but the vitals aggregate itself
crosses the P1 line. Complaint fever probes ≥ 5 → P1 as well. **Final P1** —
max across scales; missing BP is *not* listed (optional per ADR-013), no
review banner.

**Example C — Newborn (9 days), feeding poor, full vitals unmeasurable.**
Neonate PEWS scale. HR 150 (score 2), RR 44 (score 2), temp not measured,
feeding "poor" (score 1) → partial aggregate 5, temp missing → conservative
substitution path: any missing vital → **floor P3** + `vitalReviewRequired`.
SpO₂ also missing → **sepsis screen becomes mandatory**; pedSIRS fallback
answers: fever "yes" + tachypnoea → SIRS ≥ 2 + suspected infection → **P1**.
Final P1, review banner flagged. The record carries the missing-parameter trail
and the review flag into the Tier 2 payload.

**Example D — Elderly (72 y), CFS 6, minor wound.**
Burn module not engaged (wound, not burn). Vitals near-normal but temp 39.2 →
single parameter = 3 → **P1**. Modifiers: age > 65, CFS 6 → both "bump to P1"
(cap). **Final P1** (already P1 from single-parameter). Reasons list both the
vital trigger and both modifiers for auditability.

## 7.15 Complaint probe book (verbatim — `lib/triage/probes.dart` + engine)

Six detailed branches carry **scored** probes; a probe's score is added when
its answer is the *concerning* one (inverted questions are inverted in the
engine). Unanswered probes never escalate (null = No).

**Chest** (≥ 6 → P1; ≥ 4 → P2; E-C4 alone → P1):

| ID | Question | Score |
|---|---|---|
| E-C1 | Does the pain spread to the arm, jaw, or back? | 2 |
| E-C2 | Is the pain worse with activity or walking? | 1 |
| E-C3 | Is there sweating, nausea, or vomiting with the pain? | 1 |
| E-C4 | Is the pain a tearing pain felt in the back? | 3 (any Yes → P1) |
| E-C5 | Known heart disease, or risk factors (smoking, diabetes, high BP)? | 1 |

**Breathing** (≥ 6 → P1; ≥ 3 → P2):

| ID | Question | Score |
|---|---|---|
| E-B1 | Can the patient speak in full sentences? (**inverted** — No = concern) | 3 |
| E-B3 | Using extra chest/neck muscles or sitting forward to breathe? | 3 |
| E-B4 | Confused or drowsy while breathless? | 2 |
| E-B5 | Chest pain when breathing? | 1 |

**Fever** (≥ 5 → P1; ≥ 3 → P2):

| ID | Question | Score |
|---|---|---|
| E-F1 | Temperature of 39 °C or higher measured? | 1 |
| E-F2 | Rash that stays red when a glass is pressed on it? | 3 |
| E-F3 | Stiff neck or painful light in the eyes? | 3 |
| E-F4 | Recent travel to a malaria/dengue area? | 1 |
| E-F5 | Immunocompromised (weak infection defence)? | 2 |

**Headache** (≥ 5 → P1; ≥ 3 → P2):

| ID | Question | Score |
|---|---|---|
| E-H1 | Started suddenly, like a thunderclap? | 3 |
| E-H2 | Worst headache ever? | 2 |
| E-H3 | Fever with a stiff neck? | 3 |
| E-H4 | Weakness, numbness, or change in vision? | 2 |
| E-H5 | Pregnant or recently given birth? | 2 |
| E-H6 | On blood thinners or known bleeding problem? | 2 |

**Abdominal** (≥ 5 → P1; ≥ 3 → P2):

| ID | Question | Score |
|---|---|---|
| E-A1 | Belly rigid or painful to the touch? | 3 |
| E-A2 | Vomiting with no bowel movement/gas for a while? | 2 |
| E-A3 | Blood in vomit or black, tarry stool? | 2 |
| E-A4 | Pregnant (ectopic-pregnancy risk)? | 3 |
| E-A5 | Severe testicular pain? | 2 |

**Mental health** (≥ 6 → P1; ≥ 3 → P2):

| ID | Question | Score |
|---|---|---|
| E-P1 | Suicidal thoughts with a plan? | 3 |
| E-P2 | Self-harm in the last 24 hours? | 3 |
| E-P3 | Psychosis with risk of harm to others? | 3 |
| E-P4 | Severe agitation needing restraint? | 2 |

**Aggregation across complaints (ADR-016):** every answered complaint's branch
is scored; the **most-urgent** branch tier wins and its label is stored
(`best = min urgencyIndex`).

---

# 8. Tier 2 — MedGemma LLM Advisories

## 8.1 Model & runtime

| Property | Value |
|---|---|
| Model | MedGemma-1.5-4B-IT |
| Quantization | Q4_K_M GGUF |
| Size | ~2.32 GiB (2,489,894,976 bytes) |
| Source | HuggingFace, unsloth/medgemma-1.5-4b-it-GGUF |
| Runtime | fllama (wraps llama.cpp), OpenAI-style chat API, background isolate, streaming |
| Temperature | 0.1 |
| Vision projector (mmproj) | ~0.79 GiB — shipped for dev/testing only; **not used in production** |

## 8.2 Text-only pathway (ADR-003)

MedGemma supports vision via mmproj, but the vision/multimodal pathway is
**evaluated and dropped** for production: upstream mmproj reliability is
unresolved in the current llama.cpp Gemma ecosystem, and loading both GGUFs
strains low-RAM devices. On-device vision/classifier input is dropped entirely
from product scope (ADR-020). **Tier 2 is text-only.**

## 8.3 Prompt architecture (see `docs/PROMPTS.md` — verbatim)

**Tier 2 summary (system):** "…Your entire reply is exactly ONE JSON object.
Start your reply with '{'…" — mandates the exact shape
`{"triage_level": "P5", "summary": "- …\n- …", "requires_human_verification": true}`,
forbids analysis/reasoning/`thought`/`Draft`/`Critique`/`Revise` blocks, says
the Tier 1 result is authoritative and may only be **agreed with or raised**,
demands 4–6 plain caregiver-friendly lines, and insists
`requires_human_verification: true` in every reply.

**Tier 2 summary (user):** the spec §16 structured payload (patient context,
vitals, GCS, complaints, probe answers, sepsis screen, burn data, Tier 1
result, readable `patientSummary`), built by `Tier2Payload.from(...)`.

**Chat assistant (system):** reply-style rules (direct answer, no
Draft/Critique/Revise, no reasoning display), safety boundaries (decision
support, never a certain diagnosis, never prescribe or name medicines/doses/
treatments), emergency/first-aid guidance (call 1122 in Pakistan / 911 / 112;
permitted **safe, non-medication** first aid — pressure on a bleeding wound,
cooling a burn under room-temp water, safe positioning for choking/fainting/
seizure/fracture — strictly never medication and never a diagnosis), and scope
(direct Tier 1 questions to the app's guided triage).

**Attached triage context:** post-triage chat / History hand-off append a
read-only `--- TRIAGE CONTEXT ---` block (confidential, used for follow-ups).

**Interaction explain (system/user):** pharmacist-style, 4–6 short sentences,
no headings/JSON, never "safe to combine", never dose/dose-advice.

## 8.4 Structured output & fail-closed parser (ADR-014)

fllama exposes **no GBNF grammar parameter**, so grammar-constrained JSON is
impossible without forking. The decision: **strict-JSON system prompt +
tolerant parser + fail-closed fallback**.

- `Tier2Parser` extracts **every** brace-balanced object in document order; a
  decodable block carrying a triage/summary key wins over reasoning-only
  (`{"thought":...}`) blocks.
- Regex fallback uses the **last** key match and masks leading reasoning
  objects so thinking-stanza text can't steer the tier.
- Invalid/off-schema output → `suggestion: null` → **Tier 1 stands untouched**.
  The parser never guesses an escalation.
- Early stop via `fllamaCancelInference` once a complete object with a
  triage/summary key is detected (`hasCompleteObject`).

## 8.5 Escalation-only merge & both-flags display (ADR-005, ADR-014)

- `triage_level_final = max(triage_level_base, tier2_suggestion)` — enforced in
  `Tier2Assessment.merge`, invariant-tested on every build.
- The result screen shows **both flags**: the Tier 1 banner first (flag +
  description), then an "AI analysis" card with the AI flag + description +
  summary. When the AI raises the tier, a one-line merge note renders e.g.
  `Tier 1: P2 · AI: P1 → final P1`.
- The record's `finalTier` remains the authoritative Tier 1; the `tier2` block
  is advisory. History shows an "AI ↑" indicator on escalation.

## 8.6 Token budgets & truncation control (ADR-015)

On-device verification exposed four failure modes; all are fixed:

1. fllama's `chat` callback surfaced only content deltas and dropped the final
   cumulative response at `done` → replies could be silently empty. **Fix:**
   `LlmService` captures the cumulative output to `done` and reports
   `(fullOutput, elapsedMs, reason)`.
2. Fixed `maxTokens` 512 truncated MedGemma's leading thinking stanza → empty
   replies. **Fix: dynamic completion budgets** in `InferenceBudget` (single
   source of truth, unit-tested):
   - Chat: context **3072**; `completion = clamp(3072 − prompt − 192, 512, 1536)`;
     `chatPromptCap = 2368`.
   - Summary: context **4096**; `completion = clamp(4096 − prompt − 384, 1024, 1536)`.
   - Token estimate = `ceil(chars / 3.5)`.
3. The tolerant parser stopped at the *first* brace-balanced object. **Fix:**
   multi-brace scan (see §8.4).
4. Long multi-turn chat grew unbounded until context eviction cut replies
   (`finish_reason: "length"`). **Fixes:** `parseFinishedReason` from fllama's
   chunks; only a real `"length"` counts as truncation; chat gets a
   "Reply reached its length limit" note; the **summary retries once at max
   budget (1536)** and also once on cold-start error/empty reply; **chat
   history compaction** drops the oldest turns (never the medical context);
   "Start new chat" resets the ephemeral transcript.

## 8.7 Device-aware context window (ADR-019)

On-device verification found fllama hardcodes `n_parallel = 4` and never sets
`kv_unified`, so a conversation only received a **quarter** of its requested
context (summary 4096 → 1024 usable, chat 3072 → 768). Root cause confirmed in
bundled llama.cpp source (`n_ctx_seq = n_ctx / 4`). Fixes:

- **KV-cache math (MedGemma Q4_K_M):** 34 layers, 4 KV heads × head_dim 256,
  sliding window 1024, 5 dense + 29 SWA layers; with the 4× duplication,
  **~1 GiB ≈ ~4,200 usable tokens**.
- **Correction without forking:** `requestedContext = usableContext × 4`; all
  calls hand fllama `requestedContext`, so a conversation gets the full
  intended window.
- **Device-aware profile** (`DeviceCapabilities`): `physicalRamSize` →
  usable context:

| RAM | Usable context |
|---|---|
| < 4 GB | Tier 2 disabled |
| 4–6 GB | 1024 |
| 6–7 GB | 2048 |
| 7–8 GB | 3072 |
| ≥ 8 GB | 4096 |

  (Test device Vivo V2061: 7.5 GB reported → 3072 usable, `contextSize` 12288.)
- **Completion that always fits:** `completion = clamp(usable − prompt −
  headroom, floor, cap)`; token heuristic lowered to **3.0 chars/token** for
  medical JSON. Summary retry re-runs at the same fitting budget.

## 8.8 Reasoning-trace handling (ADR-019)

MedGemma-1.5-4B tends to answer with a visible `Draft n / Critique n / Revise n`
self-critique loop that never terminates and consumed the window.

- `ReasoningTrace` **detects** the Draft/Critique/Revise headings, **hides the
  trace while streaming**, and **extracts the final answer** from the last
  `Revise` section.
- `LlmService.chat` takes a `stopWhen(accumulated)` predicate; the **chat
  cancels on a second Draft round** (`isLooping`).
- The system prompt additionally asks the model to answer directly — the trace
  is handled even if the model ignores it.

## 8.9 Chat surfaces (ephemeral)

- Three surfaces: the **Ask AI** tab, **post-triage chat** on the result, and
  the **History "Ask AI"** hand-off.
- All transcripts are **ephemeral and never persisted** (ADR-014). Only the
  triage summary (`tier2` block) is stored in the record.
- Summary card + chat bubbles render via `MarkdownLite` (real bullets, `bold`,
  `italic`, `code`); share/copy strips markdown via `stripMarkdown`.

## 8.10 Shipped prompts (verbatim — source: `docs/PROMPTS.md`)

The exact strings below are shipped in `lib/prompts/`. They are reproduced here
in full because review boards and presentations both need the literal contract
the model is held to.

**Tier 2 summary — system:**

```text
You are a decision-support triage assistant for low-resource, offline settings. You review a structured Tier 1 triage payload and either confirm or refine the urgency.

Your entire reply is exactly ONE JSON object. Start your reply with the character '{'. No analysis, no reasoning, no "thought" block, no "Draft"/"Critique"/"Revise" sections, no markdown, no preamble, and no words before or after the object. Example of the exact shape:
{"triage_level": "P5", "summary": "- line one\n- line two\n- line three", "requires_human_verification": true}

Rules:
1. The Tier 1 result in the payload is authoritative and safety-conservative. You may AGREE with it or RAISE urgency (a more urgent tier). You must NEVER lower it, even if the case looks mild. If unsure, keep it or raise it by one step. Never under-triage.
2. P1 = immediate emergency. P2 = very urgent. P3 = urgent. P4 = standard. P5 = minor.
3. "summary" must be 4 to 6 short lines of plain, caregiver-friendly language. Start each line with a dash. Cover: why the urgency was chosen, the most important signs, what the caregiver should do next, and any red flags to re-check.
4. "requires_human_verification" must be true in every reply.
5. You are decision support, not a doctor. Never claim a diagnosis as certain. Never invent measurements that are not in the payload.

Begin now with '{'.
```

> Note: `\n` in the example is a literal backslash-n sequence the model emits
> *inside* the `summary` string — the JSON parser decodes it to newlines.

**Tier 2 summary — user:**

```text
Structured Tier 1 payload:
<json-encoded spec §16 payload>

Return exactly one JSON object now.
```

**Chat assistant — system** (every chat surface; reproduced verbatim):

```text
You are a health triage assistant in a low-resource, offline setting. You help caregivers understand a possible health problem and decide whether to seek care.

How to reply:
- Reply directly with your answer. Never output "Draft", "Critique", or "Revise" sections, and never restate, summarise, or continue these instructions. Do not show your reasoning.
- Answer concisely and in plain language. Prefer short paragraphs or bullet lists.

Safety boundaries:
- You are decision support, not a doctor. Never claim a diagnosis as certain, and never prescribe or name medicines, doses, or treatments.
- Do not ask for or store personal data beyond what the user volunteers.

Emergencies and first aid:
- If a described situation sounds like an emergency (breathing trouble, severe bleeding, unresponsiveness, chest pain, seizure, poisoning), say so clearly and advise calling the local emergency number (1122 in Pakistan, 911 in the USA, 112 in Europe) or going to the nearest hospital now.
- While help is on the way, you may explain safe, non-medication first-aid steps the caregiver can do immediately, for example:
  - Bleeding: press firmly on the wound with a clean cloth and keep pressing; do not remove the cloth.
  - Burn: cool the area under room-temperature running water for several minutes (up to 20 if possible); do not apply ice, butter, or toothpaste.
  - Choking, fainting, seizure, or a suspected broken bone: describe the safe position or action, and what not to do.
- Keep first-aid steps short, practical, and strictly non-medication. Never suggest a medicine or dose, and never turn first aid into a diagnosis.

Scope:
- For Tier 1 triage questions, direct the user to run the app's guided triage.
```

**Chat — attached triage context** (appended to the system prompt when a
completed record is attached):

```text
<kChatAssistantSystem>

A completed triage context is attached to this conversation. Treat it as confidential and use it to answer follow-up questions.
--- TRIAGE CONTEXT ---
<readable context from buildPatientContext(...)>
--- END TRIAGE CONTEXT ---
```

**Drug-interaction explain — system:**

```text
You are a pharmacist-style helper in a low-resource, offline setting. You explain a known drug-drug interaction in plain, caregiver-friendly language.

Rules:
- Write 4 to 6 short sentences. No markdown headings, no JSON.
- Explain why the two medicines interact, what could happen if they are taken together, and what the person should do next (for example: ask a doctor or pharmacist before combining them, or watch for specific signs).
- Never say it is safe to combine them. Never give a dose or tell the user to stop a prescribed medicine.
- You are decision support, not a doctor. Never claim certainty and never invent data.
```

**Drug-interaction explain — user:**

```text
Medicine 1: <drugA>
Medicine 2: <drugB>
Reference severity: <severityLabel>
Reference advice: <referenceAdvice>

Explain this interaction to the patient in plain language.
```

## 8.11 Worked token-budget examples

**Assumption:** 3.0 chars/token for medical JSON (ADR-019); budgets live in
`InferenceBudget`; all constancy unit-tested.

**Summary call on the 8 GB-class device (usable 3072):**
- Prompt ≈ 1,900 chars ≈ 633 tokens.
- Completion = `clamp(3072 − 633 − headroom, floor 1024, cap 1536)`.
  With headroom 320 → `clamp(2119, 1024, 1536)` = **1536**.
- If the reply truncates (`finish_reason: "length"`), the call **retries once
  at the max budget (1536)** — a warm second attempt usually succeeds; two
  failures fail closed (AI ignored).

**Chat call (context 3072, device usable 3072):**
- Prompt (system + attached context + history + new question) ≈ 2,400 chars ≈
  800 tokens.
- Completion = `clamp(3072 − 800 − 192, floor 512, cap 1536)` = `clamp(2080,
  512, 1536)` = **1536**.
- Compaction: while `promptTokens(system + history + current) > 2368`, the
  **oldest** turns are dropped — never the medical context block.
- If the turn hits `"length"`, a "Reply reached its length limit" note is
  appended. A second `Draft` round cancels generation (`ReasoningTrace`).

**How `n_parallel = 4` was diagnosed (ADR-019):** fllama hardcodes
`DEFAULT_N_PARALLEL = 4` and never sets `kv_unified`, so in llama.cpp
`n_ctx_seq = n_ctx / 4`. Requesting 4096 summary yielded only **1024 usable**;
requesting 3072 chat yielded only **768 usable**. The Dart fix requests
`usable × 4` (e.g. 3072 usable → `contextSize` 12288), restoring the full
intended window. KV cache math: MedGemma Q4_K_M = 34 layers, 4 KV heads ×
head_dim 256 = 1024 KV dim, sliding-window 1024 (5 dense + 29 SWA layers);
f16 KV = 4096 B/cell/layer; SWA layers cache caps at 1536 cells/stream × 4
streams; dense scale with `n_ctx` → `KV ≈ 696 MiB + 20,480 B × n_ctx` and with
the 4× duplication **1 GiB ≈ ~4,200 usable tokens**. A unified cache /
`n_parallel = 1` (noted for a future fork) would drop the SWA floor to 174 MiB
and give ~43,000 tokens per GiB.

## 8.12 Parser behaviour worked

Tolerant, **fail-closed** `Tier2Parser`:

1. Collect **every** brace-balanced block in document order (not the first).
2. Try each block in order; the first decodable block carrying a `triage_level`
   and/or `summary` key **wins**.
3. Reasoning-only blocks (`{"thought": "..."}`) never win; a leading
   thinking-stanza is masked in the regex fallback.
4. Regex fallback uses the **last** key match (post-reasoning).
5. Validate the tier against the P1–P5 enum; `requires_human_verification`
   must read true; `summary` handed to `MarkdownLite`/`stripMarkdown`.
6. Any violation → `suggestion: null`; Tier 1 stands untouched; the result
   screen simply shows no AI card. The parser **never guesses an escalation**,
   preserving the ADR-005 invariant by construction.

## 8.13 Tier 2 payload (spec §16, verbatim shape)

`Tier2Payload.from(TriageAnswers, TriageResult)` (`lib/triage/tier2.dart`)
emits exactly:

```json
{
  "spec": "spec-16-tier2-payload",
  "patientContext": {
    "ageGroup": "adult", "ageBand": "16-64 years",
    "sex": "F", "pregnant": false, "immunocompromised": false,
    "muacCm": null, "cfsFrailty": null
  },
  "vitals": {
    "respiratoryRatePerMin": 16, "spo2Percent": 97, "spo2Missing": false,
    "systolicBpMmHg": 130, "heartRatePerMin": 78, "temperatureC": 36.8,
    "temperatureMissing": false, "onOxygen": false, "copdCo2Retention": false,
    "consciousness": "Alert", "capillaryRefill": null, "neonatalState": null
  },
  "gcs": {"eye": 4, "verbal": 5, "motor": 6, "total": 15},
  "chiefComplaint": "Chest pain",
  "additionalComplaints": [],
  "probeAnswers": {"E-C1": true, "E-C2": true},
  "sepsisScreen": {
    "f1InfectionSuspected": false, "f2AlteredMentation": false,
    "f3HighRespRate": false, "f4LowSystolicBp": false, "f5Age65Plus": false,
    "f6Immunocompromised": false, "f7AbnormalTemp": false, "qsofa": 0
  },
  "burn": {
    "cause": null, "tbsaPercent": null, "areas": [],
    "hasCriticalArea": false, "depth": null,
    "airwaySigns": false, "circumferential": false
  },
  "modifiers": {"requiresBump": false},
  "tier1Result": {
    "tier": "P2", "urgency": 2, "label": "Very urgent",
    "vitalAggregate": 0, "scale": "NEWS2",
    "reasons": ["Vitals: 0 -> P5", "Complaint: Chest pain -> P2"],
    "vitalReviewRequired": false
  },
  "patientSummary": "<readable caregiver-friendly block from buildPatientContext>"
}
```

The same `buildPatientContext(...)` readable block (framed "decision support -
not a diagnosis") seeds the post-triage chat and the History hand-off.

---

# 9. On-Device Vitals Sensing

Status: implemented and pilot-calibrated on the target device; multi-device
pilot is a pre-launch gate. This is a *triage aid*, not a diagnostic device:
every measurement is shown with a **confidence indicator**, carries the
standing disclaimer "Screening estimate only — not a substitute for clinical
assessment", and **never blocks** the flow (manual entry always available).

## 9.1 Heart rate — camera PPG

- **Method:** fingertip over the rear camera with flash. Blood-volume changes
  modulate light absorption; the **mean red-channel intensity per frame**
  (~30 fps) is the pulse waveform.
- **Capture (`ppg_capture.dart`):** official `camera` plugin; flash enabled
  *after* the stream starts (a flash command before CameraX is streaming is
  silently dropped on budget devices); exposure/focus/WB locked on finger
  contact; handles both I420 (3-plane) and NV21 (2-plane) YUV with luma-mean
  fallback; torch verified against `flashMode` and retried; torch off during
  teardown.
- **Pipeline (`ppg_pipeline.dart`):** detrend (moving average) → band-pass
  0.7–3.5 Hz (42–210 BPM) → peak detection with refractory window → IBI → BPM
  (EMA over rolling window).
- **Quality index:** `0.5·regularity + 0.3·periodicity + 0.2·peakSNR`.
  - Regularity over a **trailing 12-IBI window** (placement transients don't
    drag the whole session).
  - Confidence cutoffs: **high ≥ 0.75**; **medium ≥ 0.50** (calibrated on
    labeled device data; raised from 0.45 to reject a chaotic reading's spike
    without touching real readings).
  - **Settled-estimate gate:** per-beat BPM drift over the recent window
    **≤ 4.0 bpm** required (clean: 0.3–2.6; chaotic: 4.8–9.2).
  - **Weak-autocorrelation fallback:** accept the peak cadence when regularity
    ≥ 0.7 AND quality ≥ medium AND drift settled (a strongly regular beat train
    is its own rhythm evidence).
- **Session:** full **30 s**, position-then-start with live camera preview;
  early-finish **only when confidence is already high** (medium signals run the
  full window to converge, then auto-accept as medium).
- **Calibration data (supervised, device ee783d64):** 3 clean readings matched a
  pulse oximeter within **mean |err| ≈ 0.7 bpm** (78/82/79 vs 78.4/80.5/78.7);
  3 chaotic (movement) readings all rejected.
- **Diagnostics:** every measuring second logged to logcat (`HG_HR`, one JSON
  line: `v, sec, bpm, reg, corr, amp, drift, q, usable, outcome, conf`);
  `tools/hr_log.dart` collects/analyzes and reports gate anomalies; a
  supervised calibration protocol (3–4 clean + 2–3 noisy, threshold search,
  FP/FN counts) gates each quality-constant change via a DECISIONS entry.

## 9.2 Breathing rate — microphone

- **Method:** phone near mouth/nose; 16 kHz mono PCM16 capture with
  autoGain/echoCancel/noiseSuppress **all off** (we measure the room's
  envelope, not the on-device DSP's).
- **Background calibration + spectral subtraction** (`fft.dart`,
  `spectral_denoise.dart`, `BreathingCalibrationService`): a separate **6 s
  "Measure background noise"** pre-step averages the STFT magnitude spectrum
  into a per-bin profile; each breath measurement subtracts `α × noise`
  (α = 2, spectral floor β = 0.05), 512-pt Hann STFT, 50% overlap,
  COLA-exact, output length preserved. Removing stationary noise
  device-independently before envelope work.
- **Pipeline (`breath_pipeline.dart`):** audio band-pass ~100–1000 Hz (550 Hz
  center, Q 0.6) → short-time RMS envelope (30 ms frames, detrend-normalised,
  seeded at first nonzero level to avoid NaN poisoning) → envelope band-pass
  ~0.07–1 Hz (cuts 3 bpm drift) → peak detection (hard refractory = 60 bpm
  ceiling, fall ratio 0.35, echo guard ~12% EMA) → RR.
- **Rate from the peak train** (drift-free, not the autocorrelation maximum):
  median IBI, or pair-sum when intervals alternate short/long by
  `minPairSwing = 0.12`; correlation search capped at periods completing
  ≥ 3 cycles.
- **Subharmonic/octave disambiguation:** phone-at-mouth breathing yields an
  **inhale + exhale burst per breath**, so the raw peak cadence is the burst
  rate (~2× the breath rate). A Hann-windowed **Goertzel** test compares
  envelope energy at half the cadence vs the cadence; the period is doubled
  only when a genuine fundamental is present (`subharmonicEnergyRatio = 0.08`);
  a pristine single-burst rhythm is never doubled. This prevents 30+ true rates
  being halved to ~15.
- **Confidence:** low/med/high from regularity + periodicity + amplitude;
  always **insufficient** (never a forced number) under high ambient noise,
  out-of-band energy, or sub-band-dominant envelopes.
- **Session:** 45 s, early finish at 28 s for high-quality signals.
- **Calibration result:** five supervised sessions (10/11/15/16/18 cpm) read
  ~1.9× high pre-fix and **within ~±1–2 cpm post-fix** (10.4/9.3/13.9/14.9/18.5);
  three further on-device sessions agreed within ±2 bpm.
- **Diagnostics:** `HG_RR` JSON log lines (`cpm, reg, corr, amp, q, usable,
  ibis, lag, breath, noisy, sub, env_sub`) + a final reason line
  (`noisy / sub / env_sub / no-validate / no-breath / short`) for
  field-precise tuning.

## 9.3 Confidence policy (never-block)

- **Medium/high** → accepted, shown with an indicator.
- **Low** → value shown with an amber/red badge + explicit **"Accept anyway"**
  button; the record input carries `confidence: low`.
- **Insufficient / failed** → "unable to get a reliable reading"; the manual
  stepper is always reachable. **No tier score is silently influenced by a
  rejected sensor value.**

## 9.4 Calibration & pilot protocol (pre-launch gate)

- Validate on **3–5 target phones**: HR vs a reference pulse oximeter
  (±5 bpm within ±2σ over two trials); RR vs a manual 60 s breath count
  (±2 breaths/min).
- Worst cases: low light / flashlight-off, poor-perfusion imitation, motion
  (HR), talking/alarm noise (RR).
- Any filter/quality-constant change requires a DECISIONS entry.
- **Deferred:** accelerometer/gyroscope "precision mode" RR (`sensors_plus`),
  camera-based SpO₂ (rejected as unreliable).

## 9.5 Tunable constants (single source: `lib/vitals/` + DECISIONS entries)

Every numeric gate below is a **named constant**, calibrated on-device and
locked until pilot; changing any of them requires a `docs/DECISIONS.md` entry
(pre-launch policy).

### Heart rate (PPG)

| Constant | Value | Purpose | Calibration |
|---|---|---|---|
| Band-pass range | 0.7–3.5 Hz | 42–210 BPM isolation | Standard |
| Session length | 30 s | Minimum convergence | Early-finish only when high |
| `earlyFinishUsableSeconds` | (pass) | Early acceptance bar | High-confidence only |
| Quality weights | 0.5 reg / 0.3 periodicity / 0.2 peakSNR | Score composition | 2026-09-12c fit |
| `qualityHigh` | ≥ 0.75 | High confidence | —
| `qualityMedium` | ≥ 0.50 | Medium confidence | 2026-09-12d → 0.45 → 12e → **0.50** |
| `maxAcceptableDriftBpm` | 4.0 | Settled-estimate gate | 2026-09-12d (clean 0.3–2.6 / chaotic 4.8–9.2) |
| Regularity window | trailing 12 IBIs | Score immunity to placement transients | 2026-09-12b |
| Weak-autocorrelation fallback | regularity ≥ 0.7 ∧ q ≥ medium ∧ drift ≤ 4 | Rescue clean trains | 2026-09-12c |

### Breathing rate (microphone)

| Constant | Value | Purpose | Calibration |
|---|---|---|---|
| Capture rate | 16 kHz PCM16, DSP off | Raw envelope measurement | —
| Noise profile | 6 s background, spectral subtraction | Stationary-noise removal | 2026-09-12h |
| Spectral α / β | 2 / 0.05 | Over-subtraction / floor | 2026-09-12h |
| FFT | 512-pt Hann, 50% overlap, COLA | Analysis window | —
| Audio band-pass | ~100–1000 Hz (550 center, Q 0.6) | Speech hum removal | —
| Envelope frame | 30 ms RMS | Time resolution | —
| Envelope band-pass | ~0.07–1 Hz | Kills 3 cpm drift | —
| Refractory | = 60 bpm ceiling | Peak minimum separation | —
| Fall ratio | 0.35 | Rounded-crest anti-double-count | —
| Echo floor | ~12% recent-accepted (EMA) | Startup-transient guard | —
| `minPairSwing` | 0.12 | Short/long alternation gate | 2026-09-12i |
| `subharmonicEnergyRatio` | 0.08 | Octave disambiguation (Goertzel) | 2026-09-12j |
| `singleBurstCorrFloor` | (pristine-rhythm bar) | Never double a single-burst train | 2026-09-12j |
| Session | 45 s (28 s early when high) | Long enough to converge | —

## 9.6 Failure modes and their handling

| Failure | Handling |
|---|---|
| NaN from silent-start frames | Skip `det ≤ 1e-9` frames; `Biquad.process` self-heals non-finite state (2026-09-12f) |
| Startup transient inflates echo floor | Seed running mean at first nonzero; EMA echo floor not monotonic |
| Envelope drift read as 4 cpm | Rate from peak train; correlation capped at ≥ 3 cycles |
| Double-burst (inhale+exhale per breath) | Subharmonic Goertzel decides doubling (2026-09-12g → ±1 cpm) |
| High-rate halving (30+ → ~15) | Octave disambiguation (2026-09-12j); never halve a pristine single-burst train |
| Chaotic HR near medium threshold | Drift gate + medium 0.50 (2026-09-12e) |
| Torch silently dropped pre-stream | Enable after stream, verify `flashMode`, retry after full disposal |
| 2-plane YUV assumption | I420 + NV21 both handled; luma fallback |
| No torch / poor perfusion / ambient noise | Graceful **insufficient-signal**; manual entry always reachable |

## 9.7 Calibration sessions (recorded in ADR-017)

**HR, supervised, device ee783d64** (tools/hr_log.dart, labels clean/chaotic):

| label | bpm (oximeter) | reg | drift | q | result |
|---|---|---|---|---|---|
| clean | 78.4 (78) | 0.98 | 0.3 | 0.56 | ok medium |
| clean | 80.5 (82) | 0.95 | 0.7 | 0.55 | ok medium |
| clean | 78.7 (79) | 0.97 | 2.6 | 0.55 | ok medium |
| chaotic | 81 (81) | 0.51 | 4.8 | 0.31 | insufficient |
| chaotic | 110 | 0.52 | 9.2 | 0.32 | insufficient |
| chaotic | 77 | 0.67 | 7.9 | 0.39 | insufficient |

Clean mean |err| ≈ **0.7 bpm**; clean sessions clear medium with cushion; 3/3
chaotic rejected.

**RR, five supervised sessions** (phone at mouth/nose):

| counted (cpm) | pre-fix reading | post-fix reading |
|---|---|---|
| 10 | ~19 | 10.4 |
| 11 | ~21 | 9.3 |
| 15 | ~28.5 | 13.9 |
| 16 | ~30 | 14.9 |
| 18 | ~34 | 18.5 |

Post-fix mean |err| ≈ 1 cpm; three further on-device sessions within ±2 bpm.

---

# 10. Drug Interaction Checker

## 10.1 What it does

An offline, on-device drug-drug interaction (DDI) **screening** aid for generic
medicine names (ADR-018):

1. Add medicines by generic name (autocomplete over the bundled reference set).
2. "Check interactions" evaluates every unordered pair locally.
3. Results list most-urgent first, coloured by the locked tier palette.
4. **Moderate** pairs → inline warning; **severe / contraindicated** pairs →
   a non-dismissible blocking dialog.
5. Each result can be **explained in plain language by MedGemma on-device**
   (optional; requires the GGUF).
6. **"Ask AI about these medicines"** hand-off attaches the medicines + result
   as read-only chat context.
7. Checks are saved locally ("Recent checks": names, matched severities,
   timestamp).

Everything works with **no network**.

## 10.2 Severity model

| Severity | Source | Meaning | Blocks |
|---|---|---|---|
| `contraindicated` | ONC high-priority list | Do not use together | Yes |
| `severe` | openFDA / DailyMed label context | Serious interaction | Yes |
| `moderate` | openFDA / DailyMed label context | Monitor / may need adjustment | No |
| `reported` | NDF-RT pair (ungraded) | Interaction on record, severity not graded | No |

`reported` is deliberately kept below `moderate` and **never presented as
"safe"**. Absence of any result is explicitly **not** proof of safety.

## 10.3 Bundled data

| Asset | Size | Contents |
|---|---|---|
| `assets/data/ddi.json` | ~555 KB | 16,593 pairs as `[nameA, nameB, severityIndex]` |
| `assets/data/drug_names.json` | ~30 KB | 1,193 generic names + RxCUI |

`severityIndex` indexes `["reported","moderate","severe","contraindicated"]`.
Loaded once via `rootBundle`; `InteractionDataset` (data) + `InteractionEngine`
(pure, synchronous: normalised dedupe, all unordered pairs, most-urgent-first
sort, unknown-name reporting) are fully unit-testable headless.

## 10.4 Data pipeline & provenance

Pipeline: `verify_medrt_ddi.ps1` (gate: MED-RT carries no DDI pairs/severity) →
`fetch_openfda_bulk.ps1` (static bulk export: 14 parts, ~1.8 GB, 262,842
records; the API is used only to read the file manifest, so no rate limits) →
`mine_openfda.py` → `build_ddi.ps1` (NDF-RT + ONC + names + openFDA overlay) →
`emit_assets.ps1`.

- **Sources:** VA NDF-RT (2018.02.05 pair table), ONC high-priority list,
  openFDA static bulk, NDFRT → RxNorm name map. **Commercial-clean only** — no
  NC sources (DDI, full DrugBank, SIDER, TWOSIDES), per the locked license
  policy.
- **openFDA pass results:** re-graded **2,295** existing pairs and strictly
  discovered **+869 new pairs (243 severe, 626 moderate)**, growing the asset
  from 528 KB to 555 KB. Discovered pairs are **regex-mined and
  lower-confidence (~15% expected false positives)** and presented as a
  screening aid, not a curated table.
- Raw upstream downloads are git-ignored; authored/derived files are tracked.

## 10.5 Safety & limitations

- Decision support, not a prescription; never replaces a doctor/pharmacist.
- Ingredient-level reference set is finite; unlisted medicines are flagged
  "not recognised" and not checked.
- No dosage, indication, or interaction-timing advice.
- Only generic names, matched severities, and timestamps are stored locally.

## 10.6 Dataset licensing record (locked policy)

The bundled dataset is **commercial-clean only**. Compliance is a hard gate —
no source may be used without an explicit license permitting distribution and
commercial use:

| Source | What it provides | License posture |
|---|---|---|
| VA NDF-RT (2018.02.05) | Pair table (the bulk of `reported`) | Public-domain US government |
| ONC high-priority list | `contraindicated` pairs | Public-domain |
| openFDA (drug/label, static bulk) | Severity enrichment (`severe`/`moderate`; new pairs) | Public-domain, openFDA terms |
| NDFRT → RxNorm name map | Generic names + RxCUI | Public-domain/UMLS-restricted usage reviewed |
| **MED-RT** | **Classes only — verified to carry no DDI severity** | Used for classes; gate script enforces |

**Rejected (not license-clean):** full DrugBank, SIDER, TWOSIDES, DDI (the
NLM product that originally motivated the naming). The pipeline's
`verify_medrt_ddi.ps1` enforces the MED-RT class-only fact so it can't silently
regress.

## 10.7 openFDA enrichment methodology

1. **Static bulk manifest** = the API's file list (no live per-record calls, no
   rate limits); download ~1.8 GB across 14 parts, 262,842 records into the
   git-ignored `datasets/` tree.
2. `mine_openfda.py` scans label text for interaction statements between two
   **recognised generic names**, near a severity cue (serious/severe/contra-/
   caution wording), producing:
   - `ddi_openfda.csv` — **re-grades** existing NDF-RT pairs (2,295 pairs),
   - `ddi_openfda_new.csv` — **strictly-discovered** pairs (869: 243 severe,
     626 moderate).
3. `build_ddi.ps1` layers the re-grade and new pairs over the NDF-RT + ONC
   base; `-SkipEnrich` omits openFDA for a minimal build.
4. `emit_assets.ps1` writes `assets/data/ddi.json` + `drug_names.json`.
5. **Confidence labelling:** discovered pairs are regex-mined →
   **lower-confidence (~15% expected false positives)**; the UI presents the
   whole feature as a *screening aid*, and the record never claims safety on a
   "no result". The dataset ships `severity` metadata so the app can colour and
   gate exactly.

## 10.8 Code map

```
lib/interactions/
  models.dart             InteractionSeverity, Drug, DrugInteraction
  dataset.dart            normalizeDrugName(), InteractionDataset (load/fromJson/search)
  engine.dart             InteractionEngine (check / unknownDrugs / hasBlocking)
  severity_style.dart     severity -> tier-palette colour/icon
  drug_check_store.dart   SavedDrugCheck + DrugCheckStore (local JSON, cap 20)
  drug_check_screen.dart  Drugs tab UI + blocking dialog + AI explain sheet
lib/prompts/interaction_prompts.dart
lib/services/tier2_service.dart      explainInteraction() streaming
```

`InteractionDataset` is plain data (normalised pair→severity map + name list);
`InteractionEngine` is pure and synchronous (normalised dedupe → all unordered
pairs → most-urgent-first sort → unknown names); `DrugCheckScreen` takes
injectable `dataset`, `store`, and `tier2Service` for widget tests.

---

# 11. Data Model & Local Storage

## 11.1 Triage record (v2.1)

`TriageRecord` v2.1 (additive). Key blocks:

```
{
  triageId, timestamp, version,
  finalTier: {tier, urgency, label},           // authoritative Tier 1
  contributingScores: {vital, gcs, complaint, sepsis, burn, merged, modifiers},
  modifiers: {age, cfs, bumpApplied, ...},
  mergeReasons[],
  gates: {passed, triggered[]},
  safetyFlags: {vitalReviewRequired},
  inputs: { /* patient, vitals (+ hrSource/rrSource/confidence), complaints,
              probes, sepsis, burn, modifiers */ },
  tier2?: {suggestion, summary, escalated, latencyMs}   // advisory (v2.1+)
}
```

- `tier2` is a **read-only advisory block**; `finalTier` stays Tier 1.
- `fromJson` is tolerant — legacy v2.0 records load unchanged.
- The content fingerprint strips the `tier2` block, so the Tier-1 save and the
  post-Tier-2 upsert dedupe to one entry keyed by `triageId`.
- Stored in an **encrypted local store** (not SQLite).

## 11.2 Vitals & monitor store

- `measurementMeta` on `TriageAnswers` records `source: manual|sensor`,
  `confidence`, `measuredAt` per vital — **additive only, no record-version
  bump**; the engine never reads provenance.
- `MonitorStore` persists only `{kind, value, confidence, timestamp}` (no raw
  frames/audio) — compact JSON, newest-first, capped at 50. Powers the Monitor
  list and the in-triage "Use latest reading" offer.

## 11.3 Drug check store

`DrugCheckStore` saves `{names, matched severities, timestamp}`, capped at 20,
corrupt-tolerant.

## 11.4 Example stored record

```json
{
  "triageId": "uuid",
  "timestamp": "2026-09-05T14:30:00Z",
  "version": "2.1",
  "finalTier": {"tier": "P1", "urgency": 1, "label": "Emergency"},
  "contributingScores": {
    "news2": {"score": 6, "tier": "P2", "components": {"rr": 2, "spo2": 0, "sbp": 1, "hr": 2, "temp": 0, "avpu": 1}},
    "gcs": {"score": 15, "tier": "P5", "assumed": false},
    "complaint": {"branch": "chest_pain", "score": 4, "tier": "P2"},
    "sepsis": {"qsofa": 1, "tier": "P2"},
    "burn": null,
    "merged": 1,
    "modifiers": {"age": 72, "cfs": 6, "bumpApplied": true}
  },
  "modifiers": {"age": 72, "sex": "F", "cfs": 6, "bumpApplied": true},
  "mergeReasons": [
    "Vitals: 6 -> P2",
    "Complaint: Chest pain -> P2",
    "Modifier bump: P2 -> P1 (Age >65, CFS 6)"
  ],
  "gates": {"passed": false, "triggered": []},
  "safetyFlags": {"vitalReviewRequired": false},
  "inputs": {
    "ageGroup": "olderAdult",
    "vitals": {"rr": 22, "spo2": 94, "spo2Missing": false, "sbp": 96, "hr": 112, "temp": 38.2, "onOxygen": false,
               "hrSource": "sensor", "hrConfidence": "medium", "rrSource": "sensor", "rrConfidence": "high"},
    "complaints": {"chief": "chest_pain", "additional": []},
    "probeAnswers": {"E-C1": true, "E-C2": true},
    "sepsis": {"f1": true, "f2": false, "f3": false, "f4": true, "qsofa": 1},
    "burn": {},
    "modifiers": {"age": 72, "cfs": 6}
  },
  "tier2": {
    "suggestion": "P1",
    "summary": "- Urgency P1...\n- Next steps...",
    "escalated": true,
    "latencyMs": 4120
  }
}
```

Notes: `tier2` is additive v2.1 (legacy v2.0 loads via tolerant `fromJson`);
the content fingerprint strips `tier2` so the pre-/post-Tier-2 upsert dedupes to
one entry keyed by `triageId`; `inputs.vitals` carries provenance
(`hrSource`/`rrSource`/confidence) without touching the engine.

---

# 12. Privacy & Permissions

**Privacy posture (by design):**

- Patient data stays on-device (encrypted record store).
- AI chat transcripts and post-triage context are **ephemeral, never
  persisted** — only the triage summary is stored in the record.
- Raw sensor frames/audio **never leave the device**; the Monitor store holds
  only the tiny `{kind, value, confidence, timestamp}` tuple.
- Drug checks persist only entered generic names + severities + timestamps.

**Android permissions (all runtime-requested, none at launch, all optional):**

```
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.flash" android:required="false" />
```

- Camera/microphone are requested **only when the user reaches the
  vitals-sensing screen** — never at launch, never for advertising features.
- The e2e harness pre-grants via `adb shell pm grant`, so on-device scenarios
  never stall on dialogs.

---

# 13. UI/UX Specification

## 13.1 Design vision & principles

The person holding the phone is **not a clinician, and is likely under
stress**. Principles that follow:

1. **One task per screen** — no scrolling questionnaires.
2. **Never ask users to type** — large steppers/chips; free text only in Tier 2
   notes and optional.
3. **Every answer is revisitable** (persistent Back / Change).
4. **Idempotent and undoable** — Start over / Undo last always available.
5. **Progress is visible and calming** — "Question 4 of 9", never a countdown
   alarm.
6. **The machine is humble** — "Support tool" framing on every result;
   clinician overrides loud.
7. **Fail-visible, not fail-silent** — missing vitals = yellow banner, never
   hidden.
8. **Offline == invisible** — no network indicators in the main path.
9. **Voice-first where it helps** — STT/TTS on roadmap.
10. **Trust through transparency** — every tier result shows the exact reasons
    that produced it.

**One clear sentence:** *"A calm, giant-button questionnaire that tells a
family exactly what to do next — in their own language, with or without
network, and with or without a clinician in the room."*

## 13.2 Visual identity

- App title: **Sehat Nigraan — صحت نگران** ("Health Guardian").
- Tagline: *"Pehle janch, phir aaram"* (Check first, then rest).
- Icon: shield enclosing a heart waveform + a hand; minimal, high-contrast,
  legible at 48 px; adaptive Android icon (inset 0%, white background);
  Windows app icon 256 px.
- Brand palette (authored for wet-ink legibility + color-vision safety):
  primary teal `#0D7377` (`--teal-700`), pressed `#0A5A5E`, light surface
  `#F7F9FA` / dark `#121416`, cards white / `#1D2125`.
- **Tier palette (LOCKED):** P1 red, P2 orange, P3 yellow, P4 green, P5 blue —
  used consistently for the result banner, reason chips, and drug-check
  severity colours.

## 13.3 Information architecture

Bottom navigation (IndexedStack):

- **Start** — hero + "Start Triage" CTA + "View past records" link.
- **History** — record list + detail card + Ask AI hand-off.
- **Monitor** — heart-rate / breathing-rate measure cards + recent readings.
- **Drugs** — the interaction checker.
- **Ask AI** — a session carried by the shell.
- **Settings** — top-left gear *route* (model management lives deep under
  Settings so family users never land on it).

## 13.4 Triage walkthrough flow

1. **Patient info first (ADR-016)** — age stepper + sex; determines the age
   bracket that drives all scoring.
2. **Danger-sign gates** (Section A).
3. **Vitals** (scale-aware field list; HR/RR steps offer "Measure with phone"
   + "Use latest reading"). **SpO₂/temp offer "Not available"** (never guessed).
4. **Consciousness** — AVPU default; GCS only when indicated.
5. **Chief complaint** — 18 chips (2 screens); then the branch's probes
   (2–6 questions, one per screen), then **"More problems?"** round-robin loop
   (additional complaints feed the engine's aggregation).
6. **Sepsis screen** when engaged.
7. **Burn module** when selected (no image classification — guided Q&A + body
   map).
8. **Modifiers** — only the fields not answered at step 1; live "will bump"
   badges.
9. **Result** — tier banner + reason chips + next steps; optional Generate
   Tier 2 summary; Edit / Start over.

Navigation is **forward-only, linear**, identity-based (`_next()` matches node
type+field — fixes skipped/clipped nodes on device); Back edits the previous
question; the walkthrough is modal over the shell.

## 13.5 Screen-by-screen (key patterns)

- **One-question-per-card skeleton** — invariant layout: progress `● 4/9`,
  single ≤14-word question, `(i)` plain-language explain, big answer options,
  Back + Next-skip; auto-advance on answer; question read aloud (TTS, roadmap).
- **Vitals steppers** — giant −/＋ tiles, hold-to-repeat, quick-chips for common
  values ('12 • 16 • 20 • 24'), and **"Not available"** for SpO₂/temp.
- **Result screen** — full-bleed **TierBanner** (shape + label + response time +
  read-aloud), **ReasonChips** (tap to expand contribution), **ReviewBanner**
  (yellow `#FBC02D`: "Some readings missing — clinician review recommended"),
  then the **AI analysis card** (both-flags, §8.5), summary, share/copy,
  "Ask about this result".
- **History detail** — vitals chips, complaints, escalation reasons, missing
  params, AI summary + "AI ↑" indicator, Ask AI button.

## 13.6 Missing-data UX (fail-visible)

- SpO₂/temp: explicit **"Not available"** capture (§6.3); never a presumed
  value.
- ReviewBanner shows **always** when vitals were incomplete — even if the tier
  is high for other reasons; not dismissible on the result screen; recorded in
  the stored record (spec §21.9).
- Missing values render as **"— (not measured)"**, never 0/blank; the recap
  shows a dashed outline.
- The result still gives a careful recommendation (P3 floor + vitalReview).

## 13.7 Accessibility & localization

- **Languages:** Urdu (default, RTL), English, and **Roman Urdu** as an
  accessibility variant. Chosen once, stored locally, switched from the
  overflow menu. Strings in one `arb` set; pseudo-locale tested for growth.
- **Color-vision-safe** teal palette + non-color tier duotones (shape + label).
- Target: giant 56–64 dp+ tap targets, text 20 sp+, reduced-motion-safe
  progress bar, no options-icon-only.
- **Voice (roadmap):** STT → free text (Tier 2 notes), TTS → read
  questions/options and the result banner; all offline (Vosk / on-device).

## 13.8 Performance budgets

| Metric | Budget |
|---|---|
| Cold start → Start button | ≤ 2 s |
| First tap → first question | ≤ 500 ms |
| Tier 1 compute | ≤ 1 s |
| Question advance | ≤ 200 ms perceived |
| Complete walkthrough | ≤ 3 min, ≤ 35 taps |
| Tier 2 | Device-dependent, async, non-blocking |

Techniques: no network in Tier 1; singleton pure-Dart scoring (no async);
`RepaintBoundary` on the banner; `const` widget trees; image decode only when
gallery picked.

## 13.9 Component library

| Component | Rules |
|---|---|
| **BigButton** | Full-width, ≥ 64 dp, label ≥ 20 sp, ripple, never icon-only |
| **AnswerChip** | ≥ 56 dp, icon + text; selected = filled brand + check |
| **StepperTiles** | − / value / + each ≥ 56 dp; hold-to-repeat; optional quick-chips; value-less labels itself "Not measured <unit>" |
| **SegmentedYesNo** | Two giant segments; selected teal-on-teal (contrast-verified by pixel sample in e2e) |
| **OptionalSkip** | Visually equals primary options; never a grey "pass" |
| **ExplainSheet** | Bottom sheet, plain-language expansion + speaker icon |
| **ProgressDots** | "4 of 9" text label, bar grows, no slide when reduced motion |
| **TierBanner** | Full-bleed tinted block: shape + label + response time + read-aloud |
| **ReasonChip** | Small chips composing "why"; tap expands the contributing score |
| **ReviewBanner** | Yellow `#FBC02D` card: "Some readings missing — clinician review recommended"; non-dismissible on result |
| **OverflowMenu** | ⋯ → Undo last / Start over / About |

## 13.10 Result & emergency states

- **P1** — red full-bleed banner, "Immediate emergency", response "now",
  explicit call-to-action: call 1122 / go to hospital now; reasons + AI card
  below; clinician override reachable.
- **P2/P3** — orange/yellow "Very urgent / Urgent", ≤ 10 / 30–60 min framing,
  monitored-area language.
- **P4/P5** — green/blue "Standard / Minor", routine + self-care framing with
  re-check advice.
- **Offline state:** no network indicator anywhere in the main path; the file
  system prompt, sensors, and datasets already operate with zero connectivity.
- **Interruption (call/leave):** session state is single-`TriageAnswers`;
  re-entry resumes from the last answered question; "Start over" always
  available. (Session persistence is an open ADR-011 debt item.)

**Missing-data copy examples (Urdu/EN bilingual):**

| Case | Message |
|---|---|
| SpO₂ missing, no concern | "Oxygen level not measured — no concern was otherwise obvious." |
| SpO₂ missing + breathing problem | "Oxygen level not measured, and breathing is a concern — treated as serious." |
| Temp missing + fever complaint | "Temperature not measured — fever symptoms noted, treated as serious." |
| Both missing | "Oxygen and temperature missing — cannot rule out serious infection. Sepsis check included." |

## 13.11 Accessibility checklist

- Giant targets (≥ 56 dp chips, ≥ 64 dp buttons); text ≥ 20 sp on controls.
- Color-vision-safe brand palette + tier duotones (shape + label, not colour
  alone); contrast chosen for wet ink and screen.
- Reduced-motion-safe progress (dimension animation, never sliding).
- RTL-first Urdu strings in one `arb` set; pseudo-locale growth testing.
- TTS read-aloud (questions/options/result) and STT for free text on the
  roadmap — all offline (Vosk / on-device).
- No keyboard-typing requirement in the triage path.

## 13.12 Walkthrough error cases (from on-device e2e fixes, ADR-016)

| Bug found on device | Fix |
|---|---|
| Age chip auto-advanced past nodes (reported `@ 0,0`) | Identity-based `_next()` (type + field match), explicit Continue |
| Vulnerable-age bump missed (age asked late) | Patient info first; modifier step only re-asks unanswered fields |
| Additional complaints invisible to engine | Aggregation across all answered complaints; most-urgent branch wins |
| Sepsis F-screen silent no-op (uppercase ids vs lowercase switch) | Case-fixed + regression test `F1+F2 Yes reach the engine`; rows start un-answered; null = No |
| Off-screen/absent steppers failed harness | `Not measured <unit>` fallback + `-ViewableOnly` resolution & tap guards |

## 13.13 Screen inventory (final feature set)

| Screen | Purpose | Key elements |
|---|---|---|
| Start | Entry | Hero shield+heart, "Start Triage" CTA, past-records link, models/settings link |
| Triage walkthrough | One-question-per-card flow | Danger gates → vitals (steppers / measure-with-phone / use-latest) → AVPU/GCS → complaints → probes → sepsis → burn → modifiers → result |
| Result | Outcome + next steps | TierBanner (both-flags), ReasonChips, ReviewBanner, AI summary card, share/copy, "Ask about this result", Edit / Start over |
| History | Past records | List; detail card (vitals chips, complaints, reasons, missing params, AI summary + "AI ↑"); Ask AI hand-off |
| Monitor | Sensor readings | HR / RR measure cards, recent-readings list, session UI (countdown, live preview, diagnostics) |
| Drugs | Interaction checker | Autocomplete, chips, check, results list, blocking dialog, per-result AI explain, "Ask AI about these medicines", recent checks |
| Ask AI | General chat vs MedGemma | Streaming bubbles (MarkdownLite), read-only triage context when attached, "Start new chat" |
| Settings | App/model management | Package info; hosts Model Files (download/verify/refresh GGUF) — deliberately not a nav destination |
| Files (hosted) | Model management | Downloaded-model list, sizes, delete; Hugging Face download; adb-push hint |

All screens run **offline**; no permission prompt at launch; a top-left gear
provides Settings on every tab.

---

# 14. Testing & Quality Strategy

## 14.1 Test pyramid

```
        ┌────────────────┐
        │  Vignette E2E  │   release-gated scenario suite (backlog in progress)
        ├────────────────┤
        │ Merge/bump     │   cross-scale integrity tests
        ├────────────────┤
        │ Grading        │   reference-table + boundary tests  ── highest strength
        ├────────────────┤
        │ Red flags      │   isolation per-flag tests
        └────────────────┘
```

- **Pillar A — Red flags:** one synthetic case per hard flag; composites.
- **Pillar B — Grading correctness:** boundary-value sweeps at every threshold
  edge (the anomaly detector: any off-by-one at a clinical threshold turns
  red).
- **Pillar C — Merge & bump integrity:** `max()` invariant tests so
  `triage_level_final >= triage_level_base` on every build (CI-blocking).
- **Pillar D — Vignettes:** synthetic patients spanning severity bands,
  weighted to boundary/ambiguous cases; **under-triage rate is the most
  important tracked metric; any non-zero miss is a release blocker.**

## 14.2 Coverage gates

- `RedFlags` (all leaves + composite): **100% — mandatory**.
- Scorers (`News2` / `Gcs` / `Burn` thresholds): **100% branch** on every
  scorer (target; gaps flagged).
- Tier 1 decision logic: **100% branch — non-negotiable** (spec §5.1).
- Rest of app: conventional (≥ 80% line).
- Pillar A/B must report **100%** or the commit cannot merge.
- Determinism: no timers/network/RNG in tests; clocks injected.

## 14.3 On-device E2E harness

`scripts/device_e2e.ps1` drives a real device over `adb`:

- **9 triage scenarios** spanning age groups and outcomes (adult normal,
  toddler Peds-NEWS2 with capillary refill, newborn PEWS feeding review,
  sepsis qSOFA 1→P2, modifier bump Age>65→P4, Tier 2 adult-normal with
  MedGemma, and more) — each asserts the on-screen tier, reasons, and nav.
- **Vitals smokes:** `vitalsHRSmoke` + `vitalsBRSmoke` (permissions pre-granted;
  tolerant/non-gating — a quiet room yields an honest insufficient-signal,
  which is the expected terminal state).
- Harness hardening: `-ViewableOnly` node resolution, degenerate-bounds tap
  guards, `Not measured <unit>` fallback so off-screen steppers are skipped
  safely.

## 14.4 Test inventory (current)

- **383 automated tests pass**; `flutter analyze` clean.
- Breakdown highlights: scoring/boundary sweeps against the published
  reference tables; multi-scale engine tests; sepsis regression (`F1+F2 Yes`
  reaches the engine); Tier 2 parser merge invariant suite; token-budget unit
  tests; reasoning-trace detection tests; vitals DSP synthetic-waveform tests
  (clean → expected BPM/RR; noisy/insufficient → no estimate; silence-then-
  breath NaN regression); spectral denoise FFT round-trip and calibration
  tests; monitor-store round-trips; drug-interaction dataset/engine/store/
  screen tests (25).
- **Vignette suite** (`/test/fixtures/vignettes/`) and `results_history.csv`
  under-triage tracking are backlog items.

## 14.5 Test inventory by module (current, 383 passing)

| Area | What is asserted |
|---|---|
| Red-flag scorer | All 6 individual flags + composite `anyFire`, isolation per flag |
| News2 thresholds | All 8 component scorers + aggregate bands + risk tiers; boundary sweep |
| GCS | Eye/verbal/motor, total, tier map (incl. head-injury escalation) |
| Burn | TBSA adult (9.9/10/19.9/20/25) + pediatric (4.9/5/9.9/10) edges; critical-location substrings; case-insensitivity |
| Multi-scale engine | 23 engine tests: band edges across NEWS2 / Peds-NEWS2 / PEWS, missing-vitals P3 floor + substitution, modifier bumps, escalation |
| Multi-scale flow (widget) | 6 flow tests: walkthrough adaptivity, dynamic step list, node identity |
| Sepsis | qSOFA from answered rows only; `F1+F2 Yes` regression; fail-closed null=No |
| Tier 2 parser + merge | Strict-JSON shape; multi-brace scan; reasoning-block masking; fail-closed on unparsable; `max()` invariant suite |
| Token budgets | `InferenceBudget` floors/caps/clamps, retry-once logic, compaction threshold |
| Reasoning trace | Draft/Critique/Revise detection, extraction from last Revise, loop cancellation |
| Vitals DSP (HR) | Synthetic PPG → expected BPM; 42/210 edges; noisy/insufficient → no estimate; silence-then-signal NaN regression |
| Vitals DSP (RR) | One- vs two-burst envelopes; 3 cpm drift rejected; reflections of band edges; 8/45 cpm edge cases; integer-ratio + subharmonic rules |
| Spectral denoise | FFT round-trip; tonereduction preserves uncalibrated tone; output-length preservation; calibration service learn/fail |
| Monitor store | Round-trip, cap 50, tolerance for corrupt/legacy state |
| Engine regression guard | Sensor-filled answers == manual-value answers (source-blind scoring) |
| Interactions (25) | Dataset normalisation/symmetry; real-asset parse; engine dedupe/sort/blocking/unknowns; store round-trip/cap/corrupt; screen flows + blocking dialog + AI hint |
| Widget/nav | Shell nav indexes (Monitor/Drugs tabs), top-left Settings route, walkthrough smokes |

## 14.6 Tier 2 on-device failure matrix (why ADRs 015/019 exist)

| Observed failure | Root cause | Resolution |
|---|---|---|
| Empty replies | fllama chat `done` carried final cumulative output we dropped | Capture to `done`; report `(fullOutput, elapsed, reason)` |
| No JSON in reply | Fixed 512 cap truncated the thinking stanza | Dynamic completion budgets (ADR-015) |
| Wrong "first object" won | Parser stopped at first brace-balanced block | Multi-brace scan + reasoning masking |
| Mid-sentence truncation | Unbounded prompt growth evicted context | Compaction + `finish_reason` handling + retry-once/cap |
| Looping Draft/Critique/Revise | MedGemma self-critique never terminates | `ReasoningTrace` + cancel-on-second-Draft + stricter prompt |
| Flicker of raw reasoning | Trace streamed visibly | Hide trace; extract from last Revise |
| Intermittent parse / full-chat | fllama `n_parallel=4` → ¼ context | `requestedContext = usable×4`; device-aware profile (ADR-019) |
| OOM on low-RAM phones | Fixed 4096/3072 context | RAM-gated profile; Tier 2 off below 4 GB |

---

# 15. Deployment & Build

| Target | Command | Artifact |
|---|---|---|
| Android (primary) | `flutter build apk --debug` (or `--release`) | `build/app/outputs/flutter-apk/app-debug.apk` |
| Windows (dev/demo) | `flutter build windows --release` | `build/windows/x64/runner/Release/healthguardian.exe` |

- **Device-verified:** Android 10+ Vivo V2061 (7.5 GB RAM, SDK 31); package
  `com.healthguardian.healthguardian`.
- **Windows prerequisite:** Visual Studio 2026 "Desktop development with C++"
  workload; Developer Mode ON (dev symlinks).
- **Kotlin incremental off** in `gradle.properties` (ADR-006) — the project
  lives on a path containing spaces (`D:\PROJECTS ALL(Programming)\…`), which
  breaks Gradle's Kotlin incremental cache on Windows; builds are slower but
  reliable and reproducible.
- **Model files (optional, Tier 2):** push the GGUF to the device models dir,
  press Refresh in Settings → AI models. Fastest: `adb push <file>.gguf
  "/storage/emulated/0/Android/data/com.healthguardian.healthguardian/files/
  models/"`. Auto-download from Hugging Face supported.
- **App icon pipeline:** source SVG → headless-Chrome raster → PNGs →
  `flutter_launcher_icons` (Android adaptive, inset 0%) + Windows ico (256 px).

---

# 16. Safety & Clinical Governance

- **Deterministic safety layer first.** Tier 1 never depends on the AI, the
  network, sensors, or operator expertise.
- **Fail-closed defaults.** Missing/invalid/ambiguous input → more conservative
  tier; unparsable AI → AI ignored; rejected sensor reading → manual entry.
- **Escalation-only architecture** (`max()`). The cardinal error (under-triage)
  is structurally impossible to introduce via the AI path.
- **Source-cited thresholds.** Every threshold in `clinical_thresholds.dart`
  cites its source (`docs/CLINICAL_SOURCES.md`); deviations are recorded ADRs
  (notably ADR-009 AVPU gradient, ADR-010 conservative NEWS2 tier map,
  ADR-008 missing-vitals policy, ADR-013 optional paediatric BP). Any threshold
  change requires a DECISIONS entry; git history on the config file is an
  audit trail.
- **Human verification in the schema.** Every Tier 2 object must set
  `requires_human_verification: true`; enforcement is in the parser.
- **"Decision support — clinician decides"** banner on every output; a
  clinician **override** button captures manual overrides with a reason.
- **Prompt-policy lock:** no diagnosis certainty; no medicine/dose names from
  the AI; emergency non-medication first aid is the only treatment-class
  content allowed, and it never becomes a prescription.
- **Pre-launch gates:** multi-device vitals calibration/pilot; vignette suite
  with zero under-triage; clinical review of the missing-vitals substitution
  granularity (spec §21.11 open items).

## 16.1 Security & threat model

The app is **client-only**: no credentials, no accounts, no server, no sync.
The residual threat surface is local and its worst case is small.

| Threat | Posture |
|---|---|
| Interception of patient data in transit | N/A — zero network in the safety path; no PII is transmitted |
| Recording/storage of clinical data | Encrypted local record store; minimal persisted sensor tuple `{kind, value, confidence, time}`; no raw frames/audio stored |
| AI transcript exfiltration | Transcripts are ephemeral, never persisted (ADR-014) |
| Model-file tampering on device | GGUF downloaded w/ size checks; adb-push is the operator-controlled path; the model is advisory only |
| Prompt injection via user text | Model is constrained by system prompt; LLM output is advisory-only and can never lower a tier; drug explain can never authorise a combination |
| Miscalibrated clinical data | Fabrication proof: every threshold cites a source; git history on `clinical_thresholds.dart` is an audit trail; threshold changes require a DECISIONS entry |
| Untrusted data sources | Fixed license-gate policy (§10.6); reproducible pipeline; raw downloads git-ignored, authored files tracked |

Uptime posture: nothing in the app depends on a server, a rate limit, or a
third-party API (NLM's RxNav DDI API was permanently discontinued in Jan 2024 —
the app ships its own static dataset and never calls any live drug-interaction
API).

---

# 17. Architecture Decision Records (Summary)

Full text in `docs/DECISIONS.md`. (ADR-002 — the original skin-classifier
decision — was removed with ADR-020.)

| ADR | Decision |
|---|---|
| 001 | fllama as on-device LLM runtime (over llama.cpp direct / tflite LLM / MediaPipe LLM) |
| 003 | Text-only MedGemma in production (mmproj evaluated and dropped) |
| 004 | BLoC for state management (explicit, testable state transitions) |
| 005 | `max()` merge rule — Tier 2 can only escalate Tier 1; invariant-tested |
| 006 | Disable Kotlin incremental compilation for reliable Windows/Android builds |
| 007 | Cross-platform with Android primary |
| 008 | Missing SpO₂/temp — hybrid partial-score + conservative substitution; P3 floor |
| 009 | AVPU gradient A=0/V=2/P,U=3 (documented deviation from NEWS2) |
| 010 | Adult NEWS2 tier map — conservative reading ("any param = 3 → P1") |
| 011 | Tier 1 engine as pure synchronous Dart; vanilla state in current walkthrough |
| 012 | Multi-scale vitals engine (NEWS2 / Peds-NEWS2 / PEWS), complaint probes, GCS, sepsis |
| 013 | Systolic BP optional for pediatric/neonatal scales (scored if provided) |
| 014 | Strict-JSON prompt + tolerant fail-closed parser (no GBNF); both-flags display; record v2.1 |
| 015 | Dynamic token budgets, truncation control, parser hardening, markdown-lite |
| 016 | Patient-first walkthrough, engine complaint aggregation, sepsis fail-closed, shell restructure |
| 017 | Vitals sensing module — camera PPG HR + mic RR; never-block confidence policy |
| 018 | Offline drug-interaction checker — public-domain dataset + on-device explain |
| 019 | Device-aware context window, fllama `n_parallel=4` correction, reasoning-trace handling, emergency first-aid prompt |
| 020 | Drop the on-device vision / skin-classifier path entirely |

---

# 18. Project Status & Roadmap

## Shipped milestones

- **v0.1.0 — Engine validation:** fllama + MedGemma streaming; model
  management UI; Tier 1 rule engine; GCS + multi-scale NEWS2; burn guided UI.
- **v0.2.0 — Tier 1 complete:** decision table P1–P5 per scale; hard red-flag
  layer; cited threshold config; boundary-value tests.
- **v0.3.0 — Tier 2 integration:** strict-JSON prompt engineering; fail-closed
  parser; `max()` merge invariant; both-flags result; post-triage chat + Ask AI
  (ephemeral, dynamic budgets); record v2.1.
- **v0.4.0 — Vitals sensing:** camera PPG HR + mic RR pipelines; Monitor tab;
  confidence gate + manual fallback; spectral denoising + background
  calibration; on-device calibration/pilot tuning recorded in ADR-017.
- **v0.5.0 — Drug Interaction Checker:** public-domain pipeline; bundled
  assets; Drugs tab + blocking dialog + saved checks; optional MedGemma
  explanations.

## Release gate for v1.0.0

- [ ] Vignette suite + under-triage tracking (backlog)
- [ ] Multi-device vitals calibration/pilot (3–5 phones)
- [ ] Urdu copy pass (locale-aware shell done; copy backlog)
- [ ] Performance validation on low-spec target hardware
- [ ] CI for Tier 1 unit tests (fllama warning cleanup adjacent)
- [ ] Full openFDA severity enrichment resume (partial, resumable)

## Deferred / out of scope (see `docs/ROADMAP.md`)

- Eye, throat/oral, and anaemia vision classifiers (research done; not shipped,
  per ADR-020).
- Pill recognition / adherence tracking.
- Live server-side integration (permanently excluded — offline-first).
- Voice STT/TTS; accelerometer RR "precision mode"; camera SpO₂.

## 18.1 Technical debt & open items (tracked)

| Item | Status / note |
|---|---|
| BLoC for the triage flow | ADR-011 debt: walkthrough ships vanilla state; `TriageAnswers` is the single state object |
| Session persistence across app kill | Open (in-memory during a session) |
| Vignette suite + under-triage tracking | Backlog; the release blocker metric |
| Multi-device vitals calibration/pilot | Pre-launch gate (3–5 phones) |
| Urdu copy pass | Locale-aware shell shipped; copy backlog |
| Low-spec performance validation | Backlog (budget §13.8) |
| CI for Tier 1 unit tests | Backlog; cleanse fllama C-warnings adjacent |
| openFDA full severity pass | Partial, resumable; currently 2,295 re-graded + 869 discovered |
| RR Welch-PSD + harmonic-fundamental estimator | Fixes remaining 30 bpm two-burst synthetic artifact (ADR-017 12i) |
| fllama `n_parallel=1` / unified KV fork | ~10× tokens/GiB, deferred (ADR-019) |
| Session "Use latest reading" in triage | Open roadmap checkbox (v0.4.0) |

The pattern is deliberate: every open item is *documented and gated*, none is an
unrecorded gap, and none affects the safety-critical Tier 1 path's completeness.

---

# 19. Presentation Key Numbers

| Number | What it is |
|---|---|
| **2 tiers** | Deterministic rule engine + optional on-device LLM advisory |
| **≤ 3 min / ≤ 35 taps** | Complete triage walkthrough budget |
| **< 1 s** | Tier 1 compute budget on any device |
| **0 network** | Safety-critical path is fully offline |
| **5 clinical scales** | NEWS2, Peds-NEWS2, PEWS, GCS/AVPU, qSOFA/pedSIRS |
| **6** | Hard red-flag gates forcing P1 |
| **18** | Chief-complaint chips |
| **P1–P5** | Risk-band output (Emergency → Minor) with a locked colour palette |
| **383** | Passing automated tests (`flutter analyze` clean) |
| **9** | On-device e2e triage scenarios (adb harness) |
| **~4,200 tokens/GiB** | fllama KV-cache economy with `n_parallel=4`; corrected in Dart |
| **30 s / 45 s** | HR / RR measurement sessions (early finish when high confidence) |
| **0.7 bpm mean error** | HR pilot vs pulse oximeter (clean readings) |
| **±1–2 cpm** | RR pilot vs manual breath count (post-subharmonic fix) |
| **16,593** | Bundled drug-interaction pairs |
| **1,193** | Recognised generic drug names |
| **4 severities** | contraindicated > severe > moderate > reported |
| **869** | openFDA newly-discovered (lower-confidence) pairs |
| **~2.32 GiB** | MedGemma-1.5-4B Q4_K_M GGUF |
| **3 languages** | Urdu (default, RTL), English, Roman Urdu (roadmap platform) |

---

# 20. Presentation Narrative (Talk-Track & Demo Flow)

This appendix turns the specification into a presentation script. It assumes a
~15–20 minute talk with the app demoed live (or recorded) on the Android
device. Suggested slide count: ~20.

## Act I — The problem (slides 1–4)

1. **Hook (slide: photo of a village scene, phone in hand).** "Who computes
   NEWS2 in a village? Nobody — yet that number decides whether a sick mother
   travels two hours to hospital or waits at home. In rural Pakistan, the
   family is the triage nurse."
2. **The gap.** Assessment today = gut feeling. Clinicians use *validated,
   published* scores (NEWS2, GCS, qSOFA). Families have no access to any of
   them, no way to combine them, and no reference for "normal" for a child or
   an elder.
3. **The constraints that shape a real answer.** No reliable network. No pulse
   oximeter in the drawer. Low-to-mid-range Android phone. Caregiver under
   stress, low tech-literacy, possibly elderly, possibly reading Urdu RTL.
4. **Our thesis.** "The phone already in the family's hand can walk them
   through the published scores, *sense* HR and breathing from its own camera
   and microphone, and explain the result in plain language — fully offline."
   *→ name: Sehat Nigraan — صحت نگران — "Health Guardian".*

## Act II — The system (slides 5–10)

5. **Architecture: two tiers + two companion modules.** Slide the big diagram:
   Tier 1 (deterministic, always runs, < 1 s, offline) → capability gate →
   Tier 2 (MedGemma LLM, optional, text-only, *can only escalate*); alongside:
   vitals sensing and the drug interaction checker. Emphasise the one-liner:
   **"Tier 1 is a complete, safe product on its own; everything else is
   enhancement."**
6. **Tier 1 is not 'a calculator' — it is a safety structure.** Gates first
   (6 red-flag conditions force P1 instantly). Then age-appropriate scales:
   NEWS2 / Peds-NEWS2 / PEWS, GCS/AVPU. Then complaint-driven scored probes,
   sepsis, burn, modifiers. Mention the max() merge and the missing-vitals
   policy (never invent a number; floor P3; sepsis mandatory when both SpO₂ and
   temp missing). *Key phrase: **fail-closed**.*
7. **Tier 2 respects the safety contract.** Strict-JSON prompt; a parser that
   *never guesses an escalation*; unparsable output → AI ignored; the model may
   only agree or raise. Both flags shown on screen so every number's provenance
   is visible. Verbatim prompt snippet on the slide (the "escalation-only"
   rule bolded).
8. **The engineering reality of a 4B model on a phone.** The KV-cache story:
   fllama's `n_parallel=4` gave conversations only ¼ of their context — we
   diagnosed it in llama.cpp source and corrected it in Dart (`usable × 4`),
   found the RAM-to-context map, tuned completion budgets so a reply always
   fits, and catch the model's Draft/Critique/Revise loop with a reasoning-trace
   canceller. *Point: this is where 'AI on-device' stops being a demo and
   becomes a product.*
9. **Vitals sensing: the device as a sensor kit.** Camera → PPG → HR (30 s);
   microphone + 6 s background-noise calibration + spectral subtraction → RR
   (45 s). Confidence-gated, never-blocking. Show the calibration photo-op:
   labelled clean vs chaotic readings, mean |err| ≈ 0.7 bpm on HR; ±1–2 cpm on
   RR. *Point: we calibrated this against a real pulse oximeter, not a
   spreadsheet.*
10. **Drug interactions: offline and license-clean.** Public-domain only
    (NDF-RT + ONC + openFDA), 16,593 pairs, severity model, blocking dialog only
    for severe/contraindicated, AI explanations on-device. *Point: no NLM API
    (permanently discontinued Jan 2024) — a static, commercial-clean dataset is
    the architecturally correct answer.*

## Act III — Demo (slides 11–14)

11. **Walkthrough:** cold start → Start Triage → patient info → vitals
    (measure HR with phone; enter temp; "Not available" for SpO₂ → yellow
    banner) → complaint → probes → sepsis (auto-engaged) → result: tier banner,
    reason chips, review banner, **Generate AI summary** → both flags →
    **Ask about this result** (chat). Keep the demo to ~4 minutes; narrate only
    the *safety* moments (missing-vitals handling, escalation note).
12. **Monitor tab + Drug tab:** quick HR reading; add two medicines →
    blocking dialog for a severe pair → **Ask AI about these medicines**.
13. **Offline prove-out:** toggle airplane mode before the demo and do the whole
    walkthrough again — it visibly changes nothing. *This is the strongest
    single moment in the talk.*
14. **Windows demo (optional):** run the same app on the desktop release
    (`healthguardian.exe`) to show cross-platform reality.

## Act IV — Trust & rigour (slides 15–18)

15. **Safety story.** "Decision support — clinician decides" is on every screen;
    `requires_human_verification: true` is enforced at the schema level; no
    diagnosis, no prescribing (even the AI prompt can't name a medicine or
    dose); the only treatment-class content it may give is safe, non-medication
    first aid. A clinician override exists and is recorded.
16. **Testing.** 383 automated tests, clean analyze; boundary sweeps at every
    clinical threshold; the `max()` invariant is CI-blocking; an adb harness
    runs 9 scenarios against a physical device; the cardinal metric —
    **under-triage rate** — is tracked and any vignette miss is a release
    blocker.
17. **Evidence of rigour.** Kitchen-sink slide: ADRs (020 decisions recorded),
    cited clinical sources, calibrated vitals constants gated by DECISIONS
    entries, git audit trail on thresholds, license-checked datasets.
18. **Honest limitations.** Low model headroom (4B); LLM is advisory by design;
    sensors are triage-aids, not diagnostics; multi-device pilot still a
    pre-launch gate; Urdu copy largely present but polishing backlog; vision
    classifiers deferred. *Frame as deliberate scope, not omission.*

## Act V — Close (slides 19–20)

19. **The one-line ask.** "Every family should be able to answer two questions
    offline: *Is this urgent, and what do I do now?* Sehat Nigraan answers
    them the same way a triage nurse would — with published scores, a calm
    interface, and zero dependence on the network."
20. **Acknowledgements & roadmap.** Datasets (VA/ONC/openFDA), MedGemma
    (Google/unsloth), fllama, Flutter. Roadmap: vignette suite, multi-device
    pilot, Urdu copy, voice-first, CI, performance on low-spec targets.

---

# 21. Glossary

| Term | Meaning |
|---|---|
| **Tier 1** | Deterministic, offline, sub-second rule engine; always runs; authoritative |
| **Tier 2** | MedGemma-1.5-4B advisories; optional; can only escalate Tier 1 |
| **NEWS2** | National Early Warning Score 2 (RCP 2017), used for adults ≥ 16 y |
| **Peds-NEWS2** | Pediatric NEWS2 variant for 1–15 y, per age bracket |
| **PEWS** | Pediatric Early Warning Score, adapted for neonates (< 1 month) |
| **GCS / AVPU** | Glasgow Coma Scale / Alert-Voice-Pain-Unresponsive consciousness |
| **qSOFA / pedSIRS** | Quick sepsis-related organ failure (adults) / pediatric SIRS criteria |
| **TBSA** | Total Body Surface Area (% burn), palm method for estimation |
| **MUAC / CFS** | Mid-upper arm circumference / Clinical Frailty Scale (modifiers) |
| **PPG** | Photoplethysmography — camera-based heart-rate measurement |
| **DDI** | Drug-drug interaction |
| **NDF-RT / ONC / openFDA** | Public-domain data sources for the interaction dataset |
| **GGUF** | llama.cpp model format (Q4_K_M = 4-bit k-quant, medium) |
| **fllama** | Flutter plugin wrapping llama.cpp for on-device inference |
| **AD-ADR** | Architecture Decision Record — a dated, reasoned design decision |
| **Fail-closed** | Missing/ambiguous input resolves to the more conservative tier |
| **max() merge** | Final tier = the most urgent of all sub-scores; AI may only raise |
| **ReviewBanner** | Yellow, non-dismissible flag when vitals were incomplete |
| **vitalReviewRequired** | Record flag forcing clinician review of incomplete-data cases |

---

*End of specification. Reference files remain authoritative for the exact
thresholds, prompts, and constants: `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`,
`docs/PROMPTS.md`, `docs/CLINICAL_SOURCES.md`, `docs/tier-1-complete-spec.md`,
`docs/VITALS_SENSING.md`, `docs/DRUG_INTERACTIONS.md`, `docs/ui-ux-plan.md`,
`docs/ROADMAP.md`, `docs/tier1-engine-algorithm.md`, `docs/MODEL_CARDS/`.*