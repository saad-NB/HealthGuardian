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
  prompts/tier2_prompts.dart         Tier 2 system/user prompt templates
  screens/files_screen.dart          Model-file download/verify UI (hosted by Settings)
  services/
    llm_service.dart                 fllama OpenAI-style chat wrapper, streaming
    download_service.dart            Resumable model download w/ size checks
    tier2_service.dart               Tier 2 orchestrator (prompt → LLM → parser → merge)
  state/app_state.dart               Shared state (model paths, logs)
  triage/
    engine.dart                      Pure synchronous multi-scale Tier 1 engine
    models.dart                      TriageAnswers, AgeGroup, scales, thresholds, records' inputs
    probes.dart / danger_signs.dart / burn_profile.dart  Probe/question/burn definitions
    record.dart / record_store.dart  TriageRecord (v2.1) + encrypted local store
    tier2.dart / tier2_parser.dart   Tier 2 assessment types + tolerant fail-closed parser
    inference_budget.dart            Token-budget single source of truth (ADR-015)
  ui/
    screens/
      root_shell.dart                Bottom nav: Start / History / Settings + Ask AI session
      start_screen.dart              New triage entry
      history_screen.dart            Record list + detail card + Ask AI handoff
      settings_screen.dart           Settings tab; hosts FilesScreen (model mgmt)
      chat_screen.dart               Chat UI vs MedGemma (Ask AI session)
      triage/                        Walkthrough steps (flow, complaints, probes, GCS,
                                     vitals, danger, sepsis, burn, modifiers, result)
    text/markdown_lite.dart          Bullet/bold/italic/code renderer (ADR-015)
    theme/                           App theme + design tokens
    widgets/                         Stepper tiles, segmented Yes/No, chips, banners, etc.
scripts/device_e2e.ps1               adb harness: 9 on-device e2e scenarios (ADR-016)
docs/
  ARCHITECTURE.md                    This file
  CLINICAL_SOURCES.md                Every scale/threshold with citation
  DECISIONS.md                       Architecture decision records
  ROADMAP.md                         Scope/deferred + milestone status
  MODEL_CARDS/                       Per-model training data and validation
assets/
  samples/                           Sample clinical images for testing
```
