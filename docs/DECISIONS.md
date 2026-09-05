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
