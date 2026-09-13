# Architecture

## System Overview

Sehat Nigraan is a two-tier, offline-first medical triage application built with Flutter for cross-platform deployment (Android primary, iOS, Windows desktop).

```
Input Layer (Flutter, on-device)
   |
   v
Tier 1 -- Core Engine (deterministic, always runs, <1s, offline)
   +-- GCS scorer
   +-- NEWS2 scorer
   +-- Burn TBSA/degree (guided UI questions, no CV)
   +-- Skin classifier (MobileNetV3-Large, TFLite INT8) [PLANNED]
   +-- Hard red-flag override layer
   +-- Decision table -> triage_level_base
   |
   v
Device capability check (RAM / GPU delegate availability)
   |
   +-- capable --> Tier 2 -- MedGemma-1.5-4B (Q4_K_M GGUF, via fllama, text-only)
   |                   +-- triage_level_final = max(triage_level_base, triage_level_from_MedGemma)
   |
   +-- not capable / declined --> Tier 1 result stands alone
   |
   v
Output Layer -- triage result, SOAP-style summary, red flags, recommended action
```

## Tier Responsibilities

### Tier 1 (Deterministic, Rule-Based)
- **Always runs** -- the app is fully functional with Tier 1 alone
- Inputs: patient info (age/sex), vitals (SpO2, BP [adult optional for children], HR, temp, RR, cap refill, feeding), GCS assessment, chief complaint + additional complaints with scored probes, sepsis screen, burn questions, modifier answers
- Scales by age: NEWS2 (16+), Peds-NEWS2 (per age bracket), PEWS (neonates); engine aggregates probe escalation across **all** answered complaints (ADR-016)
- Outputs: `triage_level_base` (P1–P5), risk factors, red flags, escalation reasons
- Latency target: < 1 second on any device
- No network dependency

### Tier 2 (MedGemma LLM, Optional Enhancement)
- Only runs if device has sufficient RAM (~4 GB free) and the GGUF is present (Settings → AI models / adb)
- Inputs: structured Tier 1 payload (spec §16) — patient summary, vitals, GCS, complaint probes, sepsis screen, modifiers, Tier 1 result
- Outputs: AI triage grade + 4–6 line summary (strict-JSON prompted; `Tier2Parser` fails closed on unparsable output)
- Can only ESCALATE Tier 1, never downgrade: `triage_level_final = max(triage_level_base, tier2_suggestion)`
- Result screen shows **both flags**: Tier 1 banner first, then the AI flag + description (ADR-014); record stores Tier 2 as an advisory `tier2` block (record v2.1)
- Token budgets are dynamic (`InferenceBudget`): chat 3072 context / summary 4096 context; completion clamped per call; `finish_reason` truncation detected and handled (chat note, summary retry-once at cap); chat history is compacted (oldest turns dropped; ADR-015)
- Post-triage "Ask about this result" chat and the main "Ask AI" tab attach a read-only context block (post-triage only); chat transcripts are ephemeral
- Summary card + chat bubbles render via `MarkdownLite` (real bullets, `**bold**`, `*italic*`, `` `code` ``); share/copy strips markdown (ADR-015)

## Drug Interaction Checker (Offline, Public-Domain Data)

Independent of triage: a bundled, on-device DDI screening aid (ADR-018,
`docs/DRUG_INTERACTIONS.md`).
- Data: public-domain only — VA NDF-RT pairs + ONC high-priority list + openFDA
  label text, named via an NDFRT->RxNorm map. MED-RT is classes only (it carries
  no DDI severity).
- Severity: `contraindicated` > `severe`/`moderate` > `reported` (ungraded);
  severe/contraindicated pairs raise a blocking dialog.
- Runtime: `InteractionDataset` loads `assets/data/*.json` once; a pure-Dart
  `InteractionEngine` checks pairs locally. No network.
- MedGemma optionally explains a detected interaction on-device
  (`Tier2Service.explainInteraction`); the model never decides whether an
  interaction exists. "Ask AI about these medicines" hands the combination and
  screening result to the Ask AI chat as read-only attached context.
- Saved checks store only generic names, matched severities, and timestamps.

## Key Design Decisions

See `docs/DECISIONS.md` for full ADRs. Summary:
1. **fllama** over alternatives (llama.cpp direct, tflite LLM) -- best Flutter integration, streaming support, background isolate
2. **MobileNetV3-Large** for skin classifier -- balance of accuracy and on-device speed
3. **Text-only MedGemma** in production -- mmproj pathway evaluated and dropped due to upstream reliability issues
4. **BLoC** for state management -- explicit, testable state transitions for safety-critical logic

## File Structure

```
lib/
  main.dart                          App entry; wires RootShell + AppState
  config/clinical_thresholds.dart    Scale thresholds with inline citations
  models/medgemma_files.dart         GGUF metadata (filenames, sizes, HF URLs)
  prompts/
    tier2_prompts.dart               Tier 2 system/user prompt templates
    interaction_prompts.dart         Drug-interaction explain prompt (ADR-018)
  screens/files_screen.dart          Model-file download/verify UI (hosted by Settings)
  services/
    llm_service.dart                 fllama OpenAI-style chat wrapper, streaming
    download_service.dart            Resumable model download w/ size checks
    device_capabilities.dart         RAM -> usable context profile (ADR-019)
    tier2_service.dart               Tier 2 orchestrator (prompt -> LLM -> parser -> merge)
                                     + interaction explain (ADR-018)
  state/app_state.dart               Shared state (model paths, logs)
  triage/
    engine.dart                      Pure synchronous multi-scale Tier 1 engine
    models.dart                      TriageAnswers, AgeGroup, scales, thresholds, records' inputs
    probes.dart / danger_signs.dart / burn_profile.dart  Probe/question/burn definitions
    record.dart / record_store.dart  TriageRecord (v2.1) + encrypted local store
    tier2.dart / tier2_parser.dart   Tier 2 assessment types + tolerant fail-closed parser
    reasoning_trace.dart             Draft/Critique/Revise detection + answer extraction (ADR-019)
    inference_budget.dart            Token-budget single source of truth (ADR-015/019)
  ui/
    screens/
      root_shell.dart                Bottom nav: Start / History / Monitor /
                                     Drugs / Ask AI + top-left Settings route
                                     (ADR-016/017/018)
      start_screen.dart              New triage entry
      history_screen.dart            Record list + detail card + Ask AI handoff
      settings_screen.dart           Settings (top-left gear route); hosts FilesScreen
      chat_screen.dart               Chat UI vs MedGemma (Ask AI session)
      triage/                        Walkthrough steps (flow, complaints, probes, GCS,
                                     vitals, danger, sepsis, burn, modifiers, result)
    text/markdown_lite.dart          Bullet/bold/italic/code renderer (ADR-015)
    theme/                           App theme + design tokens
    widgets/                         Stepper tiles, segmented Yes/No, chips, banners, etc.
  vitals/                            On-device sensing (ADR-017, docs/VITALS_SENSING.md)
    measurement_session.*            Shared session state machine + view (HR/RR)
    dsp/                             Pure-Dart filters (biquad, envelope, peaks, windows)
    heart_rate/                      Camera PPG: capture + pipeline + service
    breathing_rate/                  Microphone: capture + pipeline + service
    monitor/                         Monitor tab UI + compact store (value/confidence/time)
  interactions/                      Drug interaction checker (ADR-018)
    models.dart / dataset.dart / engine.dart  Types, bundled data, lookup engine
    drug_check_screen.dart           Drugs tab UI + blocking dialog + AI explain
    drug_check_store.dart            Saved checks (names/severities/timestamp)
    severity_style.dart              Severity -> tier colour/icon
scripts/device_e2e.ps1               adb harness: 9 triage scenarios + monitor smoke (ADR-016/017)
docs/
  ARCHITECTURE.md                    This file
  PROMPTS.md                         Final shipped prompts (verbatim) + rationale
  CLINICAL_SOURCES.md                Every scale/threshold with citation
  DECISIONS.md                       Architecture decision records
  ROADMAP.md                         Scope/deferred + milestone status
  MODEL_CARDS/                       Per-model training data and validation
assets/
  samples/                           Sample clinical images for testing
  data/                              Bundled DDI assets (ddi.json, drug_names.json)
```
