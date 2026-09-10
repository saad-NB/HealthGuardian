# Sehat Nigraan (Health Guardian)

Offline-first, two-tier AI patient triage app for elderly and rural populations.

Sehat Nigraan takes patient vitals, consciousness status (GCS), symptoms, medical history, and an optional skin photo, and produces a risk-banded triage category — Emergency / Urgent / Routine — along with a plain-language clinical summary. Built for low-to-mid-range Android devices with unreliable connectivity: the safety-critical path runs fully offline, with zero server dependency.

**See:** `blueprints/` for project baseline and design docs, `docs/` for architecture, clinical sources, decisions, and roadmap.

## Current Status

- [x] Flutter project scaffolded (Android / iOS / Windows)
- [x] fllama engine integrated for on-device MedGemma-1.5-4B inference
- [x] Model file download/management UI (under Settings)
- [x] Chat UI with streaming LLM output ("Ask AI" + post-triage result chat)
- [x] Clinical thresholds config with cited sources
- [x] Unit + widget tests for every scale and flow (244 pass, `flutter analyze` clean)
- [x] Tier 1 rule engine — multi-scale vitals (NEWS2 / Peds-NEWS2 / PEWS), complaint probes, GCS, sepsis qSOFA/pedSIRS, burn TBSA, danger gates, modifier bumps
- [x] Tier 2 integration — MedGemma triage grade + summary, escalation-only merge (ADR-005), both-flags result display, Ask AI chat with dynamic token budgets
- [x] Walkthrough UX — patient info first, multi-complaint loop, round-trip/edge-case verified on device (`adb` e2e harness, 9 on-device scenarios)

## Getting Started

### Prerequisites

- Flutter 3.47+ (`D:\flutter\src\flutter`)
- Visual Studio 2026 with "Desktop development with C++" workload (Windows builds)
- Windows Developer Mode ON (required for Windows desktop dev symlinks)

### Build & Run

```powershell
flutter build windows --debug   # or --release
flutter run -d windows          # hot-reload dev loop
```

### Model Files

The app expects the MedGemma GGUF files on device:

- `medgemma-1.5-4b-it-Q4_K_M.gguf` (~2.32 GiB) — language model
- `mmproj-F16.gguf` (~0.79 GiB) — vision projector (dev/testing)

Source: `https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF`

Fastest path (Android): `adb push <file>.gguf "<model_dir>/"` then press Refresh in the Models tab. Auto-download from Hugging Face is also supported.

## Safety Note

This app does not diagnose and does not replace professional medical judgment. Every Tier 2 output includes `requires_human_verification: true` enforced at the schema level. Clinical thresholds are safety-critical — see `docs/CLINICAL_SOURCES.md` and the contributing policy in `docs/DECISIONS.md`.
