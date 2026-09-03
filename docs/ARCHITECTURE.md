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
- Inputs: vitals (SpO2, BP, HR, temp, RR), GCS assessment, burn questions, skin image
- Outputs: `triage_level_base` (Emergency / Urgent / Routine), risk factors, red flags
- Latency target: < 1 second on any device
- No network dependency

### Tier 2 (MedGemma LLM, Optional Enhancement)
- Only runs if device has sufficient RAM (~4 GB free)
- Inputs: free-text patient history + all Tier 1 structured findings
- Outputs: SOAP-formatted narrative, can only ESCALATE Tier 1, never downgrade
- Architectural guarantee: `triage_level_final = max(triage_level_base, tier2_suggestion)`

## Key Design Decisions

See `docs/DECISIONS.md` for full ADRs. Summary:
1. **fllama** over alternatives (llama.cpp direct, tflite LLM) -- best Flutter integration, streaming support, background isolate
2. **MobileNetV3-Large** for skin classifier -- balance of accuracy and on-device speed
3. **Text-only MedGemma** in production -- mmproj pathway evaluated and dropped due to upstream reliability issues
4. **BLoC** for state management -- explicit, testable state transitions for safety-critical logic

## File Structure

```
lib/
  main.dart                          App shell, NavigationBar + AppState
  config/
    clinical_thresholds.dart         All thresholds with inline citations
  models/
    medgemma_files.dart              GGUF metadata (filenames, sizes, HF URLs)
  screens/
    chat_screen.dart                 Chat UI vs MedGemma
    files_screen.dart                Model-file download/verify UI
  services/
    llm_service.dart                 fllama OpenAI-style chat wrapper, streaming
    download_service.dart            Resumable model download w/ size checks
  state/
    app_state.dart                   Shared state (model paths, logs)
docs/
  ARCHITECTURE.md                    This file
  CLINICAL_SOURCES.md                Every scale/threshold with citation
  DECISIONS.md                       Architecture decision records
  ROADMAP.md                         Out-of-scope items
  MODEL_CARDS/                       Per-model training data and validation
assets/
  samples/                           Sample clinical images for testing
```
