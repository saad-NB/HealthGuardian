# Roadmap

Items explicitly out of scope for the current MVP. These are intentionally visible so scope decisions are documented and not accidental omissions.

---

## Deferred to Future Releases

### Eye Vision Classifier
- **Status:** Dataset research completed (Mendeley Eye v2, 5 classes, 3,245 images). Not shipped this cycle.
- **Reason:** Scope constraint. Vision input is out of scope for MVP (ADR-020).
- **Datasets:** Mendeley Eye v2 (n9zp473wfw.2), Conjunctivitis Recognition (CC BY 4.0).
- **See:** `docs/DECISIONS.md` ADR-003, ADR-020.

### Throat/Oral Vision Classifier
- **Status:** Dataset research completed (SMART-OM, 2,469 images, 4 classes). Not shipped this cycle.
- **Reason:** Scope constraint. Requires additional training pipeline work.
- **Datasets:** SMART-OM (Figshare 31341790), PGUPharyngitis (symptom vector only, images not for classification).

### Full Pill Recognition / Medication Adherence Tracking
- **Status:** Not started.
- **Reason:** Significant separate ML pipeline. Requires pill image dataset curation.

### Drug Interaction / Adverse Effect Checking
- **Status:** Shipped. See `docs/DRUG_INTERACTIONS.md`, ADR-018.
- **Note:** Uses a static, locally-shipped, public-domain dataset (NDF-RT + ONC + openFDA) — never a live third-party API (NLM's RxNav DDI API was permanently discontinued Jan 2024).

### Live Server-Side API Integration
- **Status:** Explicitly excluded.
- **Reason:** Offline-first architecture. Zero server dependency by design. The app must work without connectivity.

### Anaemia Detection (Conjunctival)
- **Status:** Dataset research partially completed (CP-AnemiC, Ghana children dataset).
- **Reason:** Requires dedicated conjunctival image classifier, separate from eye/throat.

---

## Technical Debt / Improvements

- [ ] Clean up fllama compiler warnings (C4267/C4305/C4244) in build pipeline
- [ ] Add automated CI for Tier 1 unit tests
- [ ] Set up vignette test suite (`/test/fixtures/vignettes/`)
- [ ] Create `results_history.csv` for tracking under-triage rate over time
- [ ] Android build validation on low-spec target hardware
- [ ] Performance benchmarking on real devices (not just dev machines)

---

## Version Milestones

### v0.1.0 - Engine Validation (Current)
- [x] fllama integration working
- [x] MedGemma model loading and streaming
- [x] Basic chat UI
- [x] Model file download/management (Settings → AI models)
- [x] Tier 1 rule engine implementation
- [x] GCS + NEWS2 scoring in Flutter (multi-scale: NEWS2 / Peds-NEWS2 / PEWS)
- [x] Burn TBSA guided UI

### v0.2.0 - Tier 1 Complete
- [x] Decision table implementation (P1–P5 mapping, per-scale)
- [x] Hard red-flag override layer (danger gates + single-parameter escalation)
- [x] Clinical threshold config with citations
- [x] Boundary-value unit tests (reference-table driven, 244-test suite)
- [ ] Vignette test suite (`/test/fixtures/vignettes/`) — backlog

### v0.3.0 - Tier 2 Integration
- [x] MedGemma Tier 2 prompt engineering (strict JSON schema, escalation-only)
- [x] Structured JSON output via prompt + tolerant parser (fail-closed; GBNF **not** available in fllama — see ADR-014)
- [x] Max() merge rule implementation (escalation-only, enforced in `Tier2Assessment.merge`)
- [x] Invariant tests
- [x] Result screen: both-flags display (Tier 1 first, then AI flag + description) + AI summary card
- [x] Post-triage context chat + Ask AI session (ephemeral; dynamic token budgets — ADR-015)
- [x] Record v2.1 additive `tier2` block (tolerant `fromJson`, legacy v2.0 loads)

### v0.4.0 - Vitals Sensing (In Progress)
Design/approach: `docs/VITALS_SENSING.md` · Decisions: ADR-017.
- [x] Scaffold: `camera`/`record`/`permission_handler` deps, CAMERA + RECORD_AUDIO manifest, `lib/vitals/models.dart` + shared `MeasurementSession` (controller + view) + `permissions.dart`
- [x] Shell restructure: 4-tab nav (Start · History · Monitor · Ask AI), Settings moved to a top-left icon route, Monitor tab placeholder
- [x] Custom HR pipeline (camera PPG): raw frames → red-mean → detrend → band-pass (0.7–3.5 Hz) → peak detection → BPM + quality index
- [x] HR integration: "Measure with phone" + confidence gate on the `hr` vital step + Monitor card
- [x] Microphone RR pipeline: 16 kHz capture → energy envelope → band-pass (~100–1000 Hz) → cycle detection → RR + quality; noise-floor gate
- [x] RR integration: "Measure with phone" on the `rr` vital step + Monitor card
- [x] `MonitorStore` (value/confidence/timestamp only) + recent-readings list
- [x] Tests: pure-Dart DSP (synthetic waveforms → expected BPM/RR), session widget tests w/ fake service, monitor-store round-trip, engine regression guard, nav smoke updates — **309 tests green**
- [x] e2e: `vitalsHRSmoke` + `vitalsBRSmoke` scenarios w/ adb permission pre-grant (passed on Vivo V2061); full suite + `flutter analyze` green
- [ ] In-triage "Use latest reading" (pull a stored Monitor reading into the vital step)
- [ ] Calibration/pilot protocol vs reference (pulse oximeter / manual RR count) on 3–5 devices — pre-launch gate

### v0.5.0 - Drug Interaction Checker
Design: `docs/DRUG_INTERACTIONS.md` · Decisions: ADR-018.
- [x] Public-domain dataset pipeline (NDF-RT + ONC + openFDA + NDFRT->RxNorm names)
- [x] Bundled assets (`assets/data/ddi.json`, `drug_names.json`) + pubspec
- [x] Pure-Dart `InteractionDataset` + `InteractionEngine` + 25 tests
- [x] Drugs tab: autocomplete, chip list, results, blocking dialog, saved checks
- [x] Optional on-device MedGemma explanation (`Tier2Service.explainInteraction`)
- [ ] Full openFDA severity enrichment pass (resumable, rate-limited)
- [ ] Pilot vs a reference interaction database (pre-launch gate)

### v1.0.0 - MVP Release
- [ ] Voice input/output (STT/TTS)
- [x] Multilingual structure ready (locale-aware shell); Urdu copy — backlog
- [x] Patient session history (detail card + Ask AI handoff; encrypted local store, not SQLite)
- [x] Full test suite passing (244 tests + `flutter analyze` clean)
- [x] Device-tested on Android (Vivo V2061, 9-scenario adb e2e harness)
- [ ] Performance validated on low-spec target hardware — backlog
