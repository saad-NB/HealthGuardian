# Sehat Nigraan (Health Guardian)

**Offline-first, two-tier AI patient triage app for elderly and rural populations.**

Sehat Nigraan takes patient vitals, consciousness status (GCS), symptoms, medical history, and an optional skin photo, and produces a risk-banded triage category — Emergency / Urgent / Routine — along with a plain-language clinical summary for the patient, caregiver, or first responder. Built for low-to-mid-range Android devices with unreliable connectivity: the safety-critical path runs fully offline, with zero server dependency.

Named in Urdu (*Sehat* = health, *Nigraan* = guardian/overseer) to reflect its primary audience — elderly patients and their families in Pakistan — with "Health Guardian" used as the English-language project identity for broader technical audiences.

---

## 1. Scope

**In scope (MVP):**
- Two-tier triage engine:
  - **Tier 1** — deterministic, rule-based, offline, sub-second: GCS, NEWS2, burn TBSA/degree (via guided UI, not image classification), a skin-condition classifier, and a hard red-flag override layer.
  - **Tier 2** — MedGemma-1.5-4B (text-only), synthesizing free-text history and structured Tier 1 findings into a SOAP-formatted narrative summary. Can only escalate the Tier 1 result, never downgrade it.
- Single custom vision model: on-device skin-condition classifier (MobileNetV3-Small, TFLite), replacing MedGemma's native vision path (dropped due to unresolved upstream mmproj/multimodal reliability issues in the current llama.cpp Gemma ecosystem).
- Voice-first interaction for accessibility (STT/TTS), multilingual roadmap.

**Explicitly out of scope for MVP (see `docs/ROADMAP.md`):**
- Eye and throat vision classifiers (dataset research completed, not shipped this cycle).
- Full pill recognition / medication adherence tracking module.
- Drug interaction / adverse-effect checking.
- Live server-side drug interaction API integration (note: NLM's RxNav Drug-Drug Interaction API was permanently discontinued Jan 2024 — any future implementation of this must use a static, locally-shipped, curated dataset, not a live third-party API).

**Explicit non-goal:** this app does not diagnose, and does not replace professional medical judgment. Every Tier 2 output includes a `requires_human_verification: true` field enforced at the schema level, not just in UI copy.

---

## 2. Core Architecture

```
Input Layer (Flutter, on-device)
   │
   ▼
Tier 1 — Core Engine (deterministic, always runs, <1s, offline)
   ├─ GCS scorer
   ├─ NEWS2 scorer
   ├─ Burn TBSA/degree (guided UI questions, no CV)
   ├─ Skin classifier (MobileNetV3-Small, TFLite INT8)
   ├─ Hard red-flag override layer
   └─ Decision table → triage_level_base
   │
   ▼
Device capability check (RAM / GPU delegate availability)
   │
   ├── capable ──▶ Tier 2 — MedGemma-1.5-4B (Q4_K_M GGUF, via fllama, text-only)
   │                   └─ triage_level_final = max(triage_level_base, triage_level_from_MedGemma)
   │
   └── not capable / declined ──▶ Tier 1 result stands alone
   │
   ▼
Output Layer — triage result, SOAP-style summary, red flags, recommended action
```

Tier 1 is a **complete, safe, standalone product**. Tier 2 is progressive enhancement — the app must be fully functional and demoable with Tier 2 disabled.

---

## 3. Technical Stack

| Layer | Choice | Notes |
|---|---|---|
| App framework | **Flutter** | Single codebase, target Android first (low-to-mid-range devices as the baseline hardware assumption) |
| State management | **BLoC** (`flutter_bloc`) | Chosen for explicit, unidirectional state transitions and strong testability — critical given this app's safety requirements (see §5); every triage-relevant state change should be traceable to a specific, testable event → state transition, not implicit widget state |
| On-device CV inference | **`tflite_flutter`** | Skin classifier (MobileNetV3-Small, INT8 quantized) |
| On-device LLM inference | **`fllama`** | Wraps llama.cpp; loads MedGemma GGUF via `initContext`, manages context lifecycle (`stopCompletion`, `releaseContext`) |
| LLM model | **MedGemma-1.5-4B-IT, Q4_K_M GGUF quantization** | Text-only pathway in production use (vision/mmproj pathway evaluated and dropped — see `docs/DECISIONS.md`) |
| Structured LLM output | Grammar-constrained decoding (GBNF) | Enforces valid JSON against the defined output schema at the decoding level, not via prompt-following alone |
| Local storage | SQLite | Patient session history, no cloud dependency by default |
| OCR / voice (where applicable) | ML Kit / Vosk | On-device, offline-capable |

---

## 4. Repository & Documentation Plan

Given this app makes triage-relevant decisions, **every rule, threshold, and hardcoded flag must be traceable to a documented source and a specific commit**, not embedded silently in application logic. Documentation structure:

```
/docs
  ARCHITECTURE.md       — system diagram, tier responsibilities, data flow (source of truth, kept in sync with code)
  CLINICAL_SOURCES.md   — every scale/threshold used (GCS, NEWS2, Rule of Nines, burn depth criteria) with citation
                           to its original published source; any deviation from the published standard must be
                           justified here, not just in a code comment
  DECISIONS.md          — architecture decision records (ADRs). One entry per significant design choice
                           (e.g., "why text-only MedGemma," "why skin-only vision model," "why fllama over
                           alternative runtimes") — dated, with the alternatives considered and why rejected
  ROADMAP.md            — explicitly out-of-scope items (eye/throat models, pill recognition, interaction
                           checking), so scope decisions are visible and intentional, not accidental omissions
  MODEL_CARDS/          — one file per trained model (skin classifier, MedGemma config): training data, license,
                           known limitations, validation metrics (confusion matrix, AUC, per-class breakdown)
```

**Hardcoded flags and thresholds specifically** (the highest-scrutiny part of this codebase):
- All thresholds (NEWS2 bands, GCS bands, burn %BSA/degree cutoffs, skin-classifier risk-tier thresholds `t_susp`/`t_high`) live in a single versioned config file (`lib/config/clinical_thresholds.dart` or equivalent JSON), **never scattered as magic numbers in business logic**.
- Every value in that config file carries an inline comment citing its source (e.g., NHS NEWS2 documentation, Rule of Nines) and links to the corresponding entry in `CLINICAL_SOURCES.md`.
- Any change to a threshold requires a corresponding entry in `DECISIONS.md` explaining why — this is a deliberate process cost, intentional given the consequence of a miscalibrated safety threshold.
- Git history on this config file should be treated as an audit trail — avoid squashing commits that touch it.

---

## 5. Testing Strategy

Testing is tiered to match the architecture, since a rule-based safety layer and an LLM output layer need fundamentally different validation approaches.

### 5.1 Tier 1 — Unit & boundary tests (deterministic, must be exhaustive)
- Unit tests against **published worked examples** for GCS and NEWS2 — confirm exact score output matches documented reference cases, not just "looks reasonable."
- **Boundary-value tests** at every threshold edge (e.g., SpO2 exactly 92%, GCS exactly 13, burn exactly 10% BSA) — off-by-one errors at a clinical threshold are the highest-consequence class of bug in this app.
- **Hard red-flag coverage test**: one synthetic patient case per defined hard flag, asserting it fires regardless of what other scores say.
- **Decision table completeness test**: enumerate all defined input combinations in `clinical_thresholds.dart`/decision config and assert every combination maps to a defined `triage_level_base` — no silent fallthrough.
- Target: **100% branch coverage on the Tier 1 decision logic specifically** — this is non-negotiable given it's the safety-critical path; coverage targets elsewhere in the app can be more conventional.

### 5.2 Skin classifier — standard ML validation, run standalone before integration
- Confusion matrix, per-class precision/recall/F1, macro-averaged one-vs-rest AUC, balanced accuracy.
- Explicit test-condition breakdown (lighting, blur, occlusion) rather than a single aggregate number.
- Residual-Normal / open-set handling explicitly tested: confirm a clear, unambiguous real finding is never masked by an over-confident Normal prediction, and confirm out-of-distribution inputs (non-skin photos) don't produce a false confident class.

### 5.3 Tier 2 (MedGemma) — output-contract and invariant tests
- **JSON schema validity rate** across a fixed set of N test prompts — track this as a regression metric across model/prompt changes.
- **`max()` invariant test**: deterministic pass/fail — construct cases and assert `triage_level_final` never falls below `triage_level_base`, across the full test suite, on every build. This is a hard architectural guarantee and should be a CI-blocking test, not a manual spot-check.
- **Human-rated narrative sample review**: smaller-N, documented as qualitative (not automated) — a fixed rubric (factual consistency with input data, no unsupported claims introduced) applied by the team to a sample each time the prompt template changes materially.

### 5.4 End-to-end / integration
- A maintained **vignette test set** (`/test/fixtures/vignettes/`) — synthetic patient cases spanning severity bands, weighted toward boundary/ambiguous cases, each with an expected `triage_level_final`. Re-run this suite on every change to thresholds, prompts, or model versions, and track results over time (`/test/results_history.csv` or similar) so threshold-tuning changes are visible as a before/after comparison, not lost.
- **Under-triage rate** on this vignette set is the single most important tracked metric in the project — report it in every model/threshold update, and treat any non-zero result as a release blocker given the `max()` architecture's stated guarantee.
- Latency benchmarking on real low-spec target hardware (not just dev machines), tracked per Tier, reported as a distribution (min/median/max), not a single number.

### 5.5 CI expectations
- Tier 1 unit/boundary tests + the `max()` invariant test run on every commit.
- Full vignette suite + classifier validation run at minimum before every release tag, with results archived (not just printed to a CI log) so historical comparisons are possible.

---

## 6. Getting Started

*(Fill in once initial setup is finalized — Flutter version, model download/setup instructions for the MedGemma GGUF and skin-classifier TFLite files, and environment setup for training the skin classifier separately in Python before conversion.)*

---

## 7. Contributing / Safety Note for Contributors

Any pull request touching `lib/config/clinical_thresholds.dart`, the Tier 1 decision table, or the Tier 2 output schema requires:
1. A corresponding `DECISIONS.md` entry.
2. Passing boundary and invariant tests (§5.1, §5.3).
3. At least one reviewer explicitly checking the change against `CLINICAL_SOURCES.md`.

This is a deliberately higher bar than the rest of the codebase, given what this app is used for.
