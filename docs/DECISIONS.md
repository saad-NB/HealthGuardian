# Architecture Decision Records

Each significant design choice is recorded here with date, context, alternatives considered, and rationale.

---

## ADR-001: fllama as on-device LLM runtime

**Date:** 2026-08-30
**Status:** Accepted

**Context:** We need an on-device LLM runtime that integrates with Flutter for MedGemma-1.5-4B inference. Requirements: streaming output, background isolate (no UI blocking), vision/mmproj support, cross-platform.

**Alternatives considered:**
1. **llama.cpp directly** -- Would require custom FFI bindings, no Flutter integration out of the box. More control but significant engineering overhead.
2. **tflite LLM** -- TFLite is mature for vision models but lacks mature LLM support for large models (4B+). No streaming API.
3. **MediaPipe LLM** -- Google's solution; limited to specific model formats, no GGUF support, poor cross-platform story.

**Decision:** Use `fllama` (Telosnex/fllama on GitHub), which wraps llama.cpp with a Flutter-friendly OpenAI-style chat API, runs on background isolate, supports streaming, and handles GGUF loading.

**Consequences:**
- Direct dependency on a third-party package (fllama) that wraps llama.cpp
- GGUF format is required for model files
- First build is slow (~10 min) due to native compilation of llama.cpp
- Hundreds of benign compiler warnings from llama.cpp C code

---

## ADR-002: MobileNetV3-Large for skin classifier

**Date:** 2026-08-31
**Status:** Accepted

**Context:** We need a lightweight on-device vision classifier for skin conditions. Must run on low-to-mid-range Android devices with <50ms inference time. TFLite INT8 quantization required.

**Alternatives considered:**
1. **MobileNetV3-Small** -- Smaller (~2MB), faster, but lower accuracy. Baseline doc originally proposed this.
2. **EfficientNet-Lite** -- Good accuracy/speed tradeoff, but larger model size and slower on CPU.
3. **MedGemma native vision (mmproj)** -- Evaluated and dropped due to upstream reliability issues in llama.cpp Gemma ecosystem.

**Decision:** MobileNetV3-Large with TFLite INT8 quantization (~5.5MB). Balances accuracy and speed for the skin classification task. Multi-label output for ~11 classes + residual-Normal.

**Consequences:**
- ~5.5MB model size, acceptable for on-device
- INT8 quantization reduces accuracy slightly but enables CPU inference
- Requires TFLite Flutter plugin (`tflite_flutter`)
- Separate training pipeline (Python) before TFLite conversion

---

## ADR-003: Text-only MedGemma in production

**Date:** 2026-08-30
**Status:** Accepted

**Context:** MedGemma-1.5-4B supports both text and vision (via mmproj-F16.gguf). We evaluated the vision pathway for clinical image analysis.

**Decision:** Production use is text-only. The mmproj vision pathway is evaluated but dropped due to:
- Unresolved upstream mmproj/multimodal reliability issues in the current llama.cpp Gemma ecosystem
- Memory pressure: loading both LLM and mmproj GGUF files simultaneously strains low-RAM devices
- Skin classification handled by dedicated MobileNetV3 model instead

**Consequences:**
- mmproj files still shipped for development/testing
- Skin classifier is the sole vision component
- Eye/throat vision classifiers deferred to roadmap

---

## ADR-004: BLoC for state management

**Date:** 2026-09-01
**Status:** Accepted

**Context:** This is a safety-critical medical app. State transitions must be explicit, traceable, and testable. Every triage-relevant state change should be traceable to a specific event.

**Alternatives considered:**
1. **Provider/Riverpod** -- Simpler, but implicit state changes. Harder to trace what triggered a triage state transition.
2. **GetX** -- Opinionated, less testable, magic dependencies.
3. **Vanilla setState** -- Used in validation project. Fine for prototypes, not for safety-critical logic.

**Decision:** BLoC (flutter_bloc). Explicit unidirectional data flow: Event -> Bloc -> State. Every state change is a traceable, testable transition.

**Consequences:**
- More boilerplate code
- Stronger testability for safety-critical paths
- Explicit audit trail of state transitions

---

## ADR-005: Max() merge rule for Tier 1 + Tier 2

**Date:** 2026-08-30
**Status:** Accepted

**Context:** Tier 2 (MedGemma) may produce a different triage level than Tier 1 (rule-based). How do we combine them?

**Decision:** `triage_level_final = max(triage_level_base, tier2_suggestion)`. Tier 2 can only ESCALATE, never DOWNGRADE Tier 1.

**Rationale:**
- Tier 1 is deterministic, tested, and based on validated clinical scores
- Tier 2 is probabilistic and may miss edge cases
- Safety principle: when in doubt, escalate
- This is a hard architectural guarantee, enforced in code, not just convention

**Consequences:**
- Tier 2 output is advisory; Tier 1 is authoritative
- Under-triage rate is the single most important metric to track
- Requires invariant tests that `triage_level_final >= triage_level_base` on every build

---

## ADR-006: Disable Kotlin incremental compilation for Android builds

**Date:** 2026-09-04
**Status:** Accepted

**Context:** Android debug build (`flutter build apk --debug`) failed with:
```
Could not close incremental caches in <project>\build\<plugin>\kotlin\compileDebugKotlin\cacheable\caches-jvm\jvm\kotlin
```
affecting `device_info_plus` and `image_picker_android`. Persisted across `flutter clean`.

**Root cause (diagnosed):** This is a known Windows/Gradle issue where Kotlin's incremental compilation cache cannot close its file handles when the project lives on a path containing **spaces** (`D:\PROJECTS ALL(Programming)\uraan techathon\HealthGuardian`). The backtick-escaped path breaks the KOIN/FilePageCache storage close.

**Alternatives considered:**
1. Move the project to a space-free path -- rejected (would require relocating the whole project off the established directory).
2. Manual cache deletion each build -- workaround but fragile and repeated.
3. Disable incremental compilation -- chosen.

**Decision:** In `android/gradle.properties`:
```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
org.gradle.daemon=false
```

**Consequences:**
- Android builds are slightly slower (no Kotlin incremental caching).
- Build is now reliable and reproducible on this machine.
- If the project is ever moved to a space-free path, these flags may be reverted for faster builds.

---

## ADR-007: Cross-platform with Android primary

**Date:** 2026-09-01
**Status:** Accepted

**Context:** Target audience is elderly patients and families in Pakistan. Primary device: low-to-mid-range Android phones. Secondary: iOS, Windows desktop for development/demo.

**Decision:** Flutter cross-platform. Android is primary development target. iOS and Windows are secondary.

**Consequences:**
- Android build must be validated first on every change
- Windows desktop used for rapid dev iteration (faster builds)
- iOS deferred until Android baseline confirmed
- Model download/adb push workflow optimized for Android

---

## ADR-008: Missing SpO₂ / temperature — hybrid partial-score + context-substitution policy

**Date:** 2026-09-05
**Status:** Accepted (clinical review pending — see tier-1 spec §21.11)

**Context:** In rural / low-resource settings, a pulse oximeter or thermometer may be unavailable while RR/HR/BP/AVPU are measurable. The Tier 1 spec §18 originally said any missing vital → "cannot compute NEWS2; gates + complaint only; minimum P3" (all-or-nothing). Two defects: (1) it discards grossly abnormal present parameters and risks under-triage; (2) it treats missing SpO₂ and missing temperature as the same problem when they have different compensating logic.

**Alternatives considered:**
1. **Strict all-or-nothing (current spec text)** — simplest and fully conservative, but data-waste under-triage risk. Rejected.
2. **Treat unrecordable as abnormal always** — maximum safety but over-triages nearly every child/elder without a thermometer. Rejected as default.
3. **Partial score + context-driven substitution (chosen)** — hybrid of Options A + C.

**Decision (spec §21):**
- Compute NEWS2 from all *present* parameters; never discard measured abnormal values.
- A missing parameter is either *not scored (flagged)* or, when a defined "concerning context" exists, *substituted conservatively* (SpO₂ concern → score 3; temperature concern → score 3 by default, review pending for 2 in fever-only cases).
- Any missing vital → tier floor of **P3** and mandatory `vitalReviewRequired` flag.
- Danger gates and single-parameter escalation (from present parameters) always take precedence.
- Missing SpO₂ AND temperature together → sepsis screen becomes mandatory.

**Consequences:**
- Partial scores carry a P3 floor so incomplete data can never produce the lowest tiers.
- Requires ~26 additional vignettes (§21.10) — under-triage with missing vitals remains a release blocker.
- Replaces/augments the §13 `anyMissing` safety check (review flag now always set on missing data).
- Clinical review open items tracked in spec §21.11 (substitution granularity, P3 vs P4 floor, cyanosis/chills probes).

---

## ADR-009: Project AVPU consciousness score deviates from standard NEWS2 ("V" = 2)

**Date:** 2026-09-05
**Status:** Accepted (project spec is source of truth; standard NEWS2 cited)

**Context:** Standard NEWS2 scores any non-alert AVPU state as 3 (RCP 2017). Our Tier 1 spec §5.1/§5.2 defines a gradient: Alert = 0, Voice = 2, Pain/Unresponsive = 3, shared with the pediatric scales. The engine and the new `News2Thresholds.avpuConsciousnessScore` implement the spec gradient.

**Decision:** Implement `avpuConsciousnessScore` per spec (`A`=0, `V`=2, `P`/`U`=3, unknown fails closed to 3). The original bool `consciousnessScore` (A vs non-A = 3) is retained for standard-NEWS2 contexts and existing tests.

**Consequences:**
- The adult engine is consistent with the (also spec'd) pediatric AVPU gradient.
- This is a documented, intentional deviation from published NEWS2 and is isolated to the engine; any clinical re-review can flip a single function without touching thresholds.
- Flagged for clinical safety lead review alongside ADR-008.

---

## ADR-010: Adult NEWS2 → tier mapping interpretation

**Date:** 2026-09-05
**Status:** Accepted

**Context:** Spec §5.1 defines the adult mapping: `≥7 or any parameter = 3 → P1; 5–6 → P2; 3–4 → P3; 1–2 → P4; 0 → P5`. The 2025 note's "any parameter = 3 → minimum P2" is looser than the table's "→ P1".

**Decision:** Implement the **more conservative table reading**: any single parameter scoring 3 **or** aggregate ≥ 7 → P1. This is fail-closed relative to the P2 minimum.

**Consequences:**
- A lone score-3 parameter (e.g., temp ≤ 35.0, RR ≥ 25, pulse ≥ 131) alone yields P1, matching spec table and the escalate-only principle.
- Encoded and tested in `TriageEngine._tierFromNews2`.



## ADR-011: Tier 1 engine as pure synchronous Dart + vanilla state in UI

**Date:** 2026-09-05
**Status:** Accepted

**Context:** ADR-004 chose BLoC for production state. The initial triage walkthrough UI ships with plain `setState` in a local flow controller, and the decision engine is a pure synchronous class (`TriageEngine`) with no Flutter dependencies.

**Decision:** Ship the increment with vanilla state; migrate the triage flow to BLoC in a follow-up before the flow grows complex. `TriageEngine` stays framework-free so Pillars A–D tests run headless.

**Consequences:**
- Faster iteration on UI grounding; less boilerplate during greenfield screens.
- The explicit-audit-trial goal of ADR-004 is preserved because `TriageAnswers` is the single state object and every mutation flows through typed setter-like UI callbacks.
- Outstanding debt: BLoC for triage flow, session persistence, Tier 2 result merge (ADR-005).

## ADR-012: Multi-scale Tier 1 vitals engine (�5.2/�5.3) with complaint probes (�7/�8), GCS (�6), and sepsis screen (�9)

**Date:** 2026-09-06
**Status:** Accepted

**Context:** The initial engine only scored adult NEWS2. Spec �5.2 (Peds-NEWS2, 6 age brackets), �5.3 (neonatal PEWS), �6 (GCS tier mapping), �7/�8 (chief complaint + scored probes), and �9 (sepsis screen) were unimplemented. Age brackets were restructured into 9 groups (ADR from spec �3) mapping to three vital scales.

**Decision:**
- **Scales:** AgeGroup.scale selects NEWS2 (16+), Peds-NEWS2 (1-15y, per-bracket thresholds), or PEWS (neonates). Each scale produces its own aggregate + tier.
- **Vitals flow** is field-based (VitalsStep(field: ...)) and scale-aware: adults collect rr/spo2/sbp/hr/temp/onOxygen/copd/avpu; children collect rr/spo2/hr/temp/capRefill/onOxygen/avpu; neonates collect rr/spo2/hr/temp/feeding/onOxygen. Copd is adult-only; capillary refill and feeding are pediatric/neonatal-only.
- **Dynamic step list:** The flow node list is rebuilt from answers, so GCS appears only when indicated (AVPU!alert, head-injury complaint, or headache danger), and the sepsis screen appears only when engaged (fever complaint, or unmeasured temp/SpO2, or F1 answered Yes).
- **Complaint probes (�7/�8):** 18 chief-complaint chips; 6 branches carry scored probes. Branch tier maps: chest >=6 P1 / >=4 P2; breathing >=6 P1 / >=3 P2; fever/headache/abdo >=5 P1 / >=3 P2; psych >=6 P1 / >=3 P2. E-C4 (tearing back pain) forces P1 regardless. E-B1 ("speak in full sentences") is inverted -- No = concern (+3).
- **GCS (�6):** three component steps (eye/verbal/motor), stored as three ints so a partial assessment never counts. Tier via GcsThresholds.tierFromGcs; head-injury context escalates 9-12 to P1 and 14+ to a P4 floor.
- **Sepsis (�9):** adult qSOFA (F2+F3+F4; >=2 P1, ==1 P2); child pedSIRS from measured vitals (temp/RR/HR age-adjusted 95th percentiles, F-screen as fallback); neonates get no F-screen sepsis tier (clinical judgement via danger gates). F1 gates escalation.
- **Missing-vitals (�21)** still applies to every scale: partial scoring, context substitution (adult temp/spo2 substitute 3, peds temp substitutes 2 -- peds max param), P3 floor, vitalReviewRequired. TriageResult.scale records which scale produced the aggregate.

**Alternatives considered:**
1. Separate standalone scoring classes per scale -- rejected: engine stays a single pure class dispatching by scale.
2. Wizard divergence per age at the age gate -- rejected: current screen-first flow with adaptive step list keeps one linear UI.

**Consequences:**
- One linear walkthrough adapts to age; total taps grow with detail (spec-compliant for the populations served).
- AgeGroup.child replaced by 6 explicit pediatric brackets + neonate; existing tests updated.
- GCS stored as gcsEye/gcsVerbal/gcsMotor on TriageAnswers (partial-safe); the GcsScores record class removed.
- Engine, thresholds, probes are pure Dart (Pillars A-D headless) and covered by multi_scale_engine_test.dart (23 tests) and multi_scale_flow_widget_test.dart (6 tests).

## ADR-013: Blood pressure is an optional (scored-if-provided) vital for pediatric and neonatal scales

**Date:** 2026-09-06
**Status:** Accepted

**Context:** The pediatric (Peds-NEWS2) and neonatal (PEWS) walkthroughs deliberately never collect systolic BP -- in the rural low-resource target setting a pediatric/neonate BP cuff is often unavailable, and BP is not part of the app's collectable set for those ages. But the engine's per-scale "missing vitals" list included `sbp == null`, so every child and neonate triaged through the app always showed the missing-vitals review banner and floored to P3 even with all collectable vitals normal. This contradicted the intended measurement set (ADR-012: children/neonates collect rr/spo2/hr/temp/+, not BP) and made the walkthrough useless for its primary audience.

**Decision:**
- SBP is **optional** for `VitalScale.pedsNews2` and `VitalScale.pews`: it is removed from those scales' `missing` list, so its absence never sets `vitalReviewRequired` and never triggers the §21 P3 floor.
- SBP is still **scored if provided**: if a caregiver does have a reading, the peds/neonatal SBP tables apply and a score-3 parameter still fires single-parameter P1 escalation.
- When SBP is not measured, the result screen shows an **informational** reason ("Blood pressure not measured (optional for this age group).") -- satisfying §21 rule 9 ("missing ≠ silent-normal") without escalating.
- Adult `VitalScale.news2` is unchanged: SBP remains a required vital (the adult UI always collects it; missing → review + P3 floor).

**Rationale:** Failing closed on a parameter the app was never designed to collect under-triages-by-flag the entire pediatric population. Shock risk for children/neonates remains covered by the collected set (capillary refill, feeding/consciousness, RR/HR extremes, sepsis screen for fever). This is an intentional measurement-set reduction for the low-resource field context, not an accidental omission.

**Alternatives considered:**
1. Add a BP step to the pediatric/neonatal walkthrough -- rejected: requires cuffs the target users often lack and contradicts the app's low-resource design.
2. Keep BP required but context-guard the P3 floor (floor only when a shock context exists) -- deferred: adds subjective rules; revisit if capillary-refill or feeding signals prove insufficient.

**Consequences:**
- Fully-measured (per collectable set) healthy child now maps to P5; healthy neonate to the P4 age floor (spec §5.3), with no review banner.
- Genuinely-missing required params (HR, RR, consciousness, temperature, SpO2, refill/feeding) still floor to P3 review -- fail-closed preserved.
- Windows e2e harness scenarios `toddlerPedsNews2CapRefill` and `newbornPewsFeedingReview` updated to assert the corrected tiers.

---

## ADR-014: Tier 2 structured output via prompt-constrained JSON (no GBNF in fllama) + both-flags result display

**Date:** 2026-09-08
**Status:** Accepted

**Context:** Tier 2 (MedGemma-1.5-4B) must return a triage grade + a 4–6 line summary. Roadmap v0.4.0 planned GBNF grammar-constrained JSON. Inspection of fllama's API (`OpenAiRequest` in `fllama-.../lib/misc/openai.dart`) shows **no grammar/GBNF parameter exists**, so grammar-constrained output is impossible without forking fllama. Separately, ADR-005 defines escalation-only `max()` merging; the product decision is to keep **both flags visible** on the result screen (Tier 1 flag first, then the AI flag + description) so provenance is transparent.

**Decision:**
1. **Structured output = strict-JSON system prompt + tolerant parser + fail-closed fallback.** The model is told to reply with a single JSON object only (`triage_level` P1–P5, `summary` 4–6 lines, `requires_human_verification`). `Tier2Parser` extracts the first brace-balanced object, decodes leniently, validates the tier, and **fails closed**: unparsable/off-schema output → `suggestion: null`, Tier 1 result stands untouched (ADR-005 invariant preserved). The parser never guesses an escalation.
2. **Both-flags display (ADR-005 stays the merge rule).** The result screen shows the Tier 1 banner (flag + description) first, then an "AI analysis" card with the AI flag + description + summary. If the AI flags a higher tier, a one-line merge note renders `Tier 1: P2 · AI: P1 → final P1`. Record `finalTier` remains the authoritative Tier 1; the tier 2 block is advisory.
3. **Chat transcripts are ephemeral.** Post-triage context chat and the main "Ask AI" tab attach a read-only patient context block (post-triage only) and are never persisted. Only the triage summary (Tier 2 suggestion + summary text) is stored in the record.
4. **Record schema v2.1 (additive).** `TriageRecord` gains an optional `tier2` block `{suggestion, summary, escalated, latencyMs}`. `fromJson` is tolerant (absent → null) so legacy v2.0 records load unchanged. The record's content fingerprint strips the `tier2` block so the tier-1 save and the post-tier-2 upsert dedupe to one entry (keyed by `triageId`).

**Alternatives considered:**
1. **Fork fllama to add GBNF grammar** -- rejected: heavy fork maintenance for an MVP; prompt+parse gives equivalent guarantees with fail-closed safety.
2. **Tool/function calling** -- rejected: `ToolChoice`/`tools` exist in fllama's API but chat-template/tool support for Gemma is unverified and lossy for free-text summaries.
3. **Replace the Tier 1 banner with the merged tier** -- rejected: hides provenance and the user's earlier requirement to show Tier 1 first, then the AI flag/description.

**Consequences:**
- Tier 2 output is advisory-by-default; escalation requires a parsed, validated P1–P5.
- Strict prompts + `Tier2Parser` + merge invariant are unit-tested headless (Pillars A–D).
- Roadmap item "GBNF grammar-constrained JSON output" is superseded by prompt-constrained JSON (documented above); revisit only if fllama adds grammar support.
- Record version bumped to `2.1`; History shows an "AI ↑" indicator when the AI escalated.

---

## ADR-015: Tier 2 token budgets, truncation control, parser hardening, and markdown-lite rendering

**Date:** 2026-09-10
**Status:** Accepted

**Context:** On-device verification of the MedGemma Tier 2 path surfaced four
failure modes: (1) `fllama`'s `chat` callback only surfaced content deltas while
`done == false`, and reported the **final cumulative response at `done`**, which
we were dropping — replies could be silently empty; (2) a fixed `maxTokens` of
512 truncated MedGemma's leading `thought | …` stanza before it ever emitted the
JSON object → empty or partial replies, especially on cold start; (3) the
tolerant parser stopped at the *first* brace-balanced object, so a visible
reasoning block upstream of the real summary could win; (4) long multi-turn chat
grew the prompt unboundedly until llama.cpp evicted context, cutting replies
mid-sentence (`finish_reason: "length"`) with no user-facing signal.

**Decision:**
1. **Dynamic completion budgets (token estimate = `ceil(chars / 3.5)`).**
   - Chat: fixed `contextSize` **3072**; `completion = clamp(3072 − promptEst − 192, 512, 1536)`; `chatPromptCap = 2368`.
   - Summary: fixed `contextSize` **4096**; `completion = clamp(4096 − promptEst − 384, 1024, 1536)`.
   All decisions live in `InferenceBudget` (single source of truth, unit-tested).
2. **`finish_reason` parsed from fllama's OpenAI-style chunk JSON.** `LlmService.parseFinishedReason` reads `choices[0].finish_reason`; `onFinished` now reports `(fullOutput, elapsedMs, reason)`. Only a real `"length"` is treated as truncation.
3. **Truncation behavior.** Chat: a "Reply reached its length limit" note is appended. Summary: the call **retries once at the max budget (1536)** when the reply is `length`-truncated, and also once on cold-start error/empty reply (a warm second attempt usually succeeds). Two failed attempts fail closed (ADR-014).
4. **Chat history compaction (ephemeral, ADR-014).** Only the system prompt + attached triage context + the newest Q/A turns survive: while `promptTokens(system + history) + current prompt > chatPromptCap`, the *oldest* turns are dropped. Never the medical context.
5. **Parser hardening.** Multi-brace scan — every brace-balanced block is tried in document order; a decodable block carrying a triage/summary key wins over reasoning-only (`{"thought": ...}`) blocks. Regex fallback uses the **last** key match and masks leading reasoning objects so thinking-stanza text can't steer the tier.
6. **"Start new chat"** resets the ephemeral transcript/history in the chat UI.
7. **Markdown-lite rendering (`MarkdownLite`).** Summary card + chat bubbles render real bullets (`- ` / `* ` / `1.` → `• `) and `**bold**` / `*italic*` / `` `code` `` without a markdown dependency; share/copy uses `stripMarkdown` so SMS text stays plain.

**Alternatives considered:**
1. **Static 1024 token cap.** Rejected: reasoning-heavy replies truncated; wasted the 4096 summary context.
2. **Set `n_predict` to fill the context every turn.** Rejected: long-user prompts still got evicted; no signal to the user.
3. **Full markdown package.** Rejected: unnecessary dependency for two block styles; lite renderer keeps the ~2.3 GB model footprint lean.

**Consequences:**
- Repeated **3× cold-start on-device Tier 2 scenario passes** (`adultNormalMedGemmaTier2`) and the full 9-scenario E2E harness is green with the model present.
- Full headless suite (243 tests) green + `flutter analyze` clean.
- `/storage/emulated/0/Android/data/com.healthguardian.healthguardian/files/models/medgemma-1.5-4b-it-Q4_K_M.gguf` (2,489,894,976 bytes) is the verified model paired with these prompts.

---

## ADR-016: Patient-first walkthrough, engine complaint aggregation, sepsis fail-closed, and the Settings/History/Ask-AI shell

**Date:** 2026-09-11
**Status:** Accepted

**Context:** On-device e2e (via the adb harness) surfaced UX and correctness gaps after Tier 2 hardening: (1) the walkthrough started on complaint selection and asked age/sex later in the modifiers step, so vulnerable-age modifier bumps (e.g. `Age >65`) were easy to miss; (2) only the single chief complaint branch fed scored probes, so additional complaints were invisible to the engine; (3) the sepsis F-screen was effectively broken on device — rows passed uppercase field ids (`F1`…) into a switch with lowercase cases (`f1`…), so every tap was a silent no-op and qSOFA could never trigger; (4) flow navigation was index-based, which let a chip tap auto-advance and skip nodes; (5) the Models tab dominated the bottom navigation for family users.

**Decisions:**
1. **Patient info first.** Age (stepper with typed values) and sex are collected at the start of the walkthrough. The modifiers step (`I1` age / `I2` sex) renders only when a field was **not** answered at the start (`ModifierAnswers.ageAnswered` / `sexAnswered`), so the vulnerable-age bump is presented instead of re-asked. The age-bracket chip no longer auto-advances; the flow advances on an explicit Continue via **identity-based** `_next()` (type + field match on `_shownNode`/`_sameNode`), which fixed skipped/clipped nodes (e.g. the toddler age chip reporting `@ 0,0`).
2. **Engine complaint aggregation (primary + additional).** `chiefComplaint` stays the primary (engine-payload/branch compat); `additionalComplaints` and `activeComplaint` drive the probe screens and the "More problems?" round-robin loop. The engine escalates from **every** answered complaint — most-urgent branch tier wins and its label is recorded — and unanswered probes never escalate.
3. **Sepsis fail-closed.** The F-screen no longer pre-fills answers; every row starts un-answered and the engine treats `null` as **"No"**. qSOFA is computed only from the answered rows (`F2`+`F3`+`F4`). Fixed the silent no-op bug (uppercase switch cases + regression test `sepsis F1+F2 Yes answers reach the engine`).
4. **Widget cleanup.** Removed stepper quick-value rows; unified stepper tile semantics so a value-less stepper labels itself (`Not measured <unit>`, e.g. the age stepper → `Not measured y`); Yes/No segmented control contrast improved (selected teal on selected fill vs dark unselected) — verified by pixel-sampling in e2e.
5. **Settings tab replaces Models.** Bottom navigation is now **Start / History / Settings** plus the **Ask AI** session carried by the shell; model management (`FilesScreen`) moved under Settings so family users never land on it accidentally.
6. **Richer History + Ask AI handoff.** History detail card shows vitals chips, complaints, escalation reasons, missing params, the AI summary + `AI ↑` indicator, and an **Ask AI** button that opens a per-record context chat (ephemeral, ADR-014).
7. **e2e harness hardening.** `Find-Node -ViewableOnly` resolution, degenerate-bounds tap guards, and a `Not measured <unit>` fallback so off-screen/missing-value steppers are skipped or typed safely.

**Consequences:**
- All 9 on-device scenarios pass; the sepsis qSOFA path (`qSOFA 1 → P2`), modifier bump (`Age >65` → P4), and Tier 2 (`adultNormalMedGemmaTier2`) are regression-verified against the device.
- Full suite is now **244 tests** green + `flutter analyze` clean.
- `extraComplaintNotes` free text flows only to the Tier 2 payload/context block — never the deterministic engine.

---

## ADR-017: Vitals Sensing Module — on-device HR (camera PPG) + RR (microphone)

**Date:** 2026-09-11
**Status:** Accepted (implemented — pipes + confidence gate + `MonitorStore` +
shell; on-device smokes green; calibration/pilot still a pre-launch gate) — see
`docs/VITALS_SENSING.md`

**Context:** The triage walkthrough collects HR/RR by manual entry only
(`vitals_steps.dart` steppers → `TriageAnswers.heartRate/respiratoryRate`). We
want screening-level measurements from phone sensors for speed and for
caregivers without a pulse oximeter/thermometer — offline, zero extra hardware.

**Decisions:**
1. **Custom camera pipeline for HR (no `heart_rate` prototype).** Use the
   official `camera` plugin for raw frames (flash + exposure/focus/WB lock) and
   a tunable pure-Dart DSP chain (detrend → band-pass 0.7–3.5 Hz → peak
   detection → BPM + quality index). Rationale: we need confidence scoring and
   filter control anyway; a throwaway prototype adds churn for a feature that
   will be reworked regardless.
2. **Microphone-first RR** with `record` at 16 kHz (energy envelope →
   band-pass ~100–1000 Hz → cycle detection → RR + quality, with a noise-floor
   gate). Accelerometer/gyroscope chest-placement is deferred to v2
   ("precision mode", `sensors_plus`) until mic accuracy is measured in
   practice.
3. **Engine-neutral integration.** Sensor values fill the existing
   `heartRate` / `respiratoryRate` doubles; provenance lives in additive
   `measurementMeta` on `TriageAnswers` and in record `inputs`
   (`hrSource`/`rrConfidence`/…). No engine or record-version change.
4. **Never-block confidence policy.** Medium/high auto-accept with an
   indicator; low requires an explicit "Accept anyway"; insufficient-signal and
   manual entry are always available. No tier score is silently driven by a
   rejected reading.
5. **Product placement.** A new **Monitor** bottom-nav tab (Start · History ·
   Monitor · Ask AI); **Settings moves to a top-left icon** pushed as a route —
   model management is never advertised in the nav. In-triage, the `hr`/`rr`
   steps gain "Measure with phone" plus a "Use latest reading" shortcut fed by
   `MonitorStore`.
6. **Privacy posture.** Only `{kind, value, confidence, timestamp}` are
   persisted; raw frames/audio never leave the device (consistent with
   ADR-014 ephemeral transcripts).

**Consequences:**
- `docs/VITALS_SENSING.md` is the design/implementation reference (pipeline
  details, permissions, test + calibration protocol); build order is tracked as
  a milestone in `docs/ROADMAP.md`.
- Calibration/pilot (3–5 devices vs a pulse oximeter and manual breath count)
  is a pre-launch gate; any filter/quality-constant change requires a DECISIONS
  entry.

**Implementation notes (2026-09-12, per `docs/VITALS_SENSING.md §5.2`):** RR
pipeline constants were tuned against synthetic benches and the target device.
Changes recorded here in lieu of a separate ADR: lags below the 550 Hz
band-pass's settle-in transient excluded from period detection (`settled window`,
`detrendSeconds`); an `envelopeSubBandDominant` guard (sub-band RMS vs band RMS)
to reject 3 cpm envelope drift; a relative `minPeakRatio` echo guard for the
double-counted 8 cpm near-cutoff ringing; and the **integer-ratio rule** at the
estimate step — cadence that is an integer *multiple* of the dominant period is
the rate, cadence that is an integer *divisor* of it is the echo, so the
dominant (~half) period is the rate. All are tunable constants (`§9.3`);
synthetic benches must stay green and require a DECISIONS entry to change after pilot.

**Implementation notes (2026-09-12b, HR pilot feedback — `VITALS_SENSING §4.2`):**
on-device pilot showed the estimate converges with time (±3 bpm by ~18 s vs a
pulse oximeter) but sessions were ending too early/medium. Tuning recorded here
in lieu of a separate ADR: HR session lengthened **20 s → 30 s**; beat
regularity now uses a **trailing 12-IBI window** (placement transients no longer
drag the whole-session score); early-finish is allowed **only when confidence is
already high** (medium signals run the full window to converge, then auto-accept
as medium); the debug panel exposes `reg / corr / amp` so `quality` is auditable
in the field. A **live camera preview is now shown during the positioning phase**
(`PpgSampleSource.previewListenable`) so the finger can be verified before the
timer starts.

**Implementation notes (2026-09-12c, HR pilot tuning):** pilot showed quality
≈0.62 (medium) with an accurate reading (±3 bpm) still refused as "not enough
signal" — the failing gate was `dominantPeriod()==null` (band autocorrelation
< 0.5), i.e. `periodicity()==0` dragged the score and nulled `estimate()`.
Fit: score reweighted to `0.5·regularity + 0.3·periodicity + 0.2·peakSNR`
(SNR matters more), and a **weak-autocorrelation fallback** accepts the peak
cadence when regularity ≥ 0.7 AND quality ≥ medium — a strongly regular beat
train is its own rhythm evidence, while noise and sub-band signal still fall
below both bars. New benches: fallback registers a clean train, does NOT rescue
a noisy one.

**Implementation notes (2026-09-12d, HR supervised calibration — device
ee783d64):** labeled 3 clean (oximeter 78/82/79) + 3 chaotic (movement)
readings captured via `tools/hr_log.dart`. Final-instant (30 s) values:

| label | bpm (oxi) | reg | corr | drift | q | result |
|---|---|---|---|---|---|---|
| clean | 78.4 (78) | 0.98 | — | 0.3 | 0.56 | ok medium |
| clean | 80.5 (82) | 0.95 | — | 0.7 | 0.55 | ok medium |
| clean | 78.7 (79) | 0.97 | — | 2.6 | 0.55 | ok medium |
| chaotic | 81 (81) | 0.51 | — | 4.8 | 0.31 | insufficient |
| chaotic | 110    | 0.52 | — | 9.2 | 0.32 | insufficient |
| chaotic | 77     | 0.67 | — | 7.9 | 0.39 | insufficient |

Clean mean |err| = 0.7 bpm. Before tuning the clean sessions cleared
medium=0.55 by only 0-0.01; autocorrelation stays below 0.5 on this device
(corr − always), so clean quality sits at the regularity+SNR floor.
Changes (all synthetic benches stay green — clean 100 bpm still high, noisy
still low/null): **qualityMedium 0.55 → 0.45**; new **`maxAcceptableDriftBpm`
4.0** gate in `confidence()` and in the weak-autocorrelation fallback (drift
0.3-2.6 clean vs 4.8-9.2 chaotic at the acceptance instant); `tools/hr_log.dart`
constants mirrored. Result: clean accepted with cushion, 3/3 chaotic rejected.

**Tuning note (2026-09-12e): qualityMedium 0.45 → 0.50.** On-device live
rechecks showed chaotic readings spike to ~0.48 just before collapsing, while
a proper reading never drops below 0.50 during the session — so 0.50 rejects
the spike without touching real readings (clean final-second q 0.55-0.56
clears it with margin). Kept `maxAcceptableDriftBpm > 4` gate unchanged.

**Implementation notes (2026-09-12f, RR on-device diagnosis — `VITALS_SENSING
§5.2/§5.3`):** every real breathing-rate session returned `insufficient`
(`peaks=0`, `breaths=false`) despite clear breath energy in the audio. Replaying
captured PCM through the pipeline offline isolated three defects, all now fixed:

1. **NaN poisoning of the envelope IIR cascade (the show-stopper).** Real
   captures begin with silent/zero frames: `env=0` and the detrend mean `det=0`,
   so `env/det = 0/0 = NaN`. A single NaN never leaves a recursive filter's
   delay line, so the band-passed envelope stayed `NaN` for the whole session and
   `PeakDetector` (whose confirm test is `value <= peak*(1-fallRatio)`) confirmed
   nothing — 0 peaks regardless of signal quality. Fix: skip frames while
   `det <= 1e-9`, and `Biquad.process` now sanitizes non-finite input and resets
   its state if it ever goes non-finite. The synthetic benches missed this
   because they start with signal, not silence; a silence-then-breath regression
   test now covers it.
2. **Startup transient.** Leading silence dragged the running-mean denominator
   toward zero, inflating the first real frame into a huge crest that raised the
   echo floor and rejected every real breath after it. Fix: seed the running
   mean at the first nonzero level, and make the echo floor an EMA rather than a
   monotonic max.
3. **Rate picked the wrong period.** The estimate let the envelope
   autocorrelation's global maximum override the peak cadence; slow envelope
   drift (a ~14 s wander completing ~2 cycles in the 30 s window) read as a
   strong 4 cpm period (one session logged **4.26 cpm**). The old integer-ratio
   rule is superseded: the rate now comes from the **peak train** (drift-free)
   via `peakTrainPeriodMs()` (median interval, or the pair sum when intervals
   alternate short/long from filter echoes), the autocorrelation search is capped
   to periods completing ≥ `minDominantCycles` (3) cycles, and `breathPeriodMs()`
   doubles the burst period to the breath cycle when the envelope's
   autocorrelation at 2× the burst period is nearly as strong as at the burst
   period.

**Double-burst calibration (2026-09-12g):** five supervised sessions (counted
10/11/15/16/18 breaths/min) all read ~1.9× high — phone-at-mouth breathing yields
an **inhale and an exhale energy burst per breath**, so the raw peak cadence is
the burst rate, not the breath rate. After the subharmonic fix the same captures
read 10.4/9.3/13.9/14.9/18.5 (mean |err| ≈ 1 cpm); three further on-device
sessions agreed within ±2 bpm. This is now the operating assumption for the
mouth/nose placement the UI instructs. `singleBurstCorrFloor` /
`subharmonicEnergyRatio` are the tunable constants; a two-burst synthetic bench
locks it in.

**Implementation notes (2026-09-12h, RR background calibration + denoising —
`VITALS_SENSING §5.2`):** to reduce per-device tuning, the RR flow records a
**6 s background-only profile in a separate pre-step** and applies **spectral
subtraction** using it to the measurement audio, ahead of the existing
band-pass/envelope/peak chain. New pure-Dart `fft.dart` (radix-2),
`spectral_denoise.dart` (512-pt Hann STFT, 50% overlap, COLA-exact overlap-add;
per-bin `|X| - α|N|` with α = 2, β = 0.05), `BreathingCalibrationService`, and an
in-memory `NoiseProfileStore`. The RR page shows **"Measure background noise"**
above **"Measure with phone"**; measuring without a profile prompts and
redirects through the background step, then proceeds to the normal countdown.
The first attempt ran calibration *inside* the measurement session, which
briefly showed the 45 s countdown before the noise window — moving it to an
explicit pre-step fixes that. Output length is preserved so the pipeline's
per-chunk timing is unchanged, and the denoised signal feeds the existing
ambient-noise gate. `BreathingRateServiceConfig` gains `denoise`. Benches: FFT
round-trip; denoiser suppresses a calibrated tone while preserving an
uncalibrated one and preserves chunk length; calibration service learns a
profile / fails cleanly; service applies a stored profile without disturbing
detection.

**Tuning note (2026-09-12i, high-rate halving):** synthetic two-burst scans
showed fast rates being halved (45 → 22.5) because `peakTrainPeriodMs()`'s
pair-sum branch triggered on ~2% interval jitter. It now requires a substantial
short/long swing (`minPairSwing = 0.12`) before summing; 45 now reads 45.5 and
the real captured sessions are byte-identical. Lowering the peak refractory to
the burst ceiling was tried and **reverted** — it destabilised the low-rate
doubling decision (v2 22.5 → 11.5). The remaining synthetic artifact is 30 bpm
two-burst (refractory-edge aliasing); the planned Welch-PSD + harmonic-fundamental
estimator is the intended fix.

**Implementation notes (2026-09-12j, RR high-rate halving on device — octave
disambiguation):** on-device, rates up to ~21 bpm were correct but 30+ read
**13-14** (roughly half). Cause: at high rates the inhale/exhale bursts fall
inside the peak refractory (~1 s), so the peak detector resolves **one crest per
breath** and the peak train already *is* the breath period; the old doubling
condition (`corrDouble >= corrBurst - 0.2`) then doubled a correct period. A
peak cadence of 30/min is fundamentally ambiguous — 30 breaths/min with one
burst per breath, or 15 breaths/min with two — and only the envelope's
subharmonic content can tell them apart. `breathPeriodMs()` now keeps the
pristine-rhythm guard (`corrBurst >= singleBurstCorrFloor` → never double) and
otherwise doubles only when a Hann-windowed **Goertzel** test finds a genuine
envelope fundamental at half the cadence: `subharmonicRatio()` = envelope energy
at f/2 ÷ (energy at f/2 + energy at f) ≥ `subharmonicEnergyRatio` (0.08).
Measured on synthetics, one burst/breath gives ≈0.000 and a true two-burst
envelope ≈0.14+, a clean separation. `doubleBurstCorrMargin` is removed;
`sub_e` is added to the HG_RR diagnostic line for on-device validation.


