# Roadmap

Items explicitly out of scope for the current MVP. These are intentionally visible so scope decisions are documented and not accidental omissions.

---

## Deferred to Future Releases

### Eye Vision Classifier
- **Status:** Dataset research completed (Mendeley Eye v2, 5 classes, 3,245 images). Not shipped this cycle.
- **Reason:** Scope constraint. Skin classifier is the only vision component for MVP.
- **Datasets:** Mendeley Eye v2 (n9zp473wfw.2), Conjunctivitis Recognition (CC BY 4.0).
- **See:** `docs/DECISIONS.md` ADR-003.

### Throat/Oral Vision Classifier
- **Status:** Dataset research completed (SMART-OM, 2,469 images, 4 classes). Not shipped this cycle.
- **Reason:** Scope constraint. Requires additional training pipeline work.
- **Datasets:** SMART-OM (Figshare 31341790), PGUPharyngitis (symptom vector only, images not for classification).

### Full Pill Recognition / Medication Adherence Tracking
- **Status:** Not started.
- **Reason:** Significant separate ML pipeline. Requires pill image dataset curation.

### Drug Interaction / Adverse Effect Checking
- **Status:** Not started.
- **Note:** NLM's RxNav Drug-Drug Interaction API was permanently discontinued Jan 2024. Any future implementation must use a static, locally-shipped, curated dataset, not a live third-party API.

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
- [x] Model file download/management
- [ ] Tier 1 rule engine implementation
- [ ] GCS + NEWS2 scoring in Flutter
- [ ] Burn TBSA guided UI

### v0.2.0 - Tier 1 Complete
- [ ] Decision table implementation
- [ ] Hard red-flag override layer
- [ ] Clinical threshold config with citations
- [ ] Boundary-value unit tests (100% branch coverage)
- [ ] Vignette test suite

### v0.3.0 - Skin Classifier
- [ ] MobileNetV3-Large training pipeline
- [ ] TFLite INT8 conversion
- [ ] Skin classifier integration
- [ ] Risk-tier threshold calibration

### v0.4.0 - Tier 2 Integration
- [x] MedGemma Tier 2 prompt engineering (strict JSON schema, escalation-only)
- [x] Structured JSON output via prompt + tolerant parser (fail-closed; GBNF **not** available in fllama — see ADR-014)
- [x] Max() merge rule implementation (escalation-only, enforced in `Tier2Assessment.merge`)
- [x] Invariant tests
- [x] Result screen: both-flags display (Tier 1 first, then AI flag + description) + AI summary card
- [x] Post-triage context chat + main "Ask AI" tab
- [x] Record v2.1 additive `tier2` block (tolerant `fromJson`, legacy v2.0 loads)

### v1.0.0 - MVP Release
- [ ] Voice input/output (STT/TTS)
- [ ] Multilingual support (Urdu primary)
- [ ] Patient session history (SQLite)
- [ ] Full test suite passing
- [ ] Performance validated on target hardware
