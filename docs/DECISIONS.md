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
