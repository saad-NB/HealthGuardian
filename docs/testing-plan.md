# Sehat Nigraan — Testing Plan (Red Flags & Grading Correctness)

**Version:** 1.0  
**Date:** 2026-09-05  
**Status:** Draft  
**Companion to:** `docs/tier-1-complete-spec.md` (§17 Validation, §21 Missing Vitals), `lib/config/clinical_thresholds.dart`, `test/`

---

## Table of Contents

1. [Objectives](#1-objectives)
2. [Scope](#2-scope)
3. [Test Pyramid & Environment](#3-test-pyramid--environment)
4. [Pillar A — Red-Flag Coverage Tests](#4-pillar-a--red-flag-coverage-tests)
5. [Pillar B — Grading-Correctness Tests](#5-pillar-b--grading-correctness-tests)
6. [Pillar C — Merge & Bump Integrity](#6-pillar-c--merge--bump-integrity)
7. [Pillar D — Missing-Vitals Policy Tests](#7-pillar-d--missing-vitals-policy-tests)
8. [Test Fixtures & Reference Tables](#8-test-fixtures--reference-tables)
9. [Boundary-Value Cheat Sheet](#9-boundary-value-cheat-sheet)
10. [Code Coverage Targets](#10-code-coverage-targets)
11. [CI Integration & Gate Rules](#11-ci-integration--gate-rules)
12. [Reporting & Failure Triage](#12-reporting--failure-triage)
13. [Risk Register for the Testing Effort](#13-risk-register-for-the-testing-effort)
14. [Reference Test Files to Create](#14-reference-test-files-to-create)

---

## 1. Objectives

Two hard test objectives, stated as a single **guarantee** each:

### O1 — No red flag is ever skipped
> For **every** defined red flag, there exists a test case where **only that flag** is abnormal, all other inputs are "textbook normal", and the system **must** fire that flag (and therefore force Emergency). A flag that fails to fire in its own isolation test is a **release blocker**.

Rationale: red flags are OR-ed (`RedFlags.anyFire`). An OR-chain is only as good as every leaf it contains — a typo, wrong threshold, or swapped operator in one leaf silently renders that flag dead while all other tests still pass.

### O2 — The grading system matches the prespecified reference
> Every scale score is verified **exactly** against a prespecified reference table (the published NEWS2/GCS/burn tables in `docs/CLINICAL_SOURCES.md`), including **every boundary value** (the exact cutoff, one below, one above). Any deviation from the reference is a bug — not a "reasonable" result.

---

## 2. Scope

| In scope | Out of scope (this doc) |
|---|---|
| `RedFlags` (all 6 individual + composite `anyFire`) | MedGemma / Tier 2 output contract tests |
| `News2Thresholds` (all 8 component scorers + aggregate + risk bands) | End-to-end UI walkthrough tests |
| `GcsThresholds` (eye/verbal/motor, total, tier map) | Performance/latency benchmarks |
| `BurnThresholds` (TBSA adult/pediatric, critical locations) | Usability tests (`docs/ui-ux-plan.md` §14) |
| **To-be-built:** `PedsNews2Thresholds`, `NeonatalPewsThresholds`, complaint probes, sepsis (qSOFA/pedSIRS), decision table, `max()` merge, modifier bumps | — |
| Missing-vitals policy (spec §21) | — |

---

## 3. Test Pyramid & Environment

```
        ┌──────────────┐
        │    Vignette   │  12. Vignette suite (fixtures, release-gated)
        │    E2E/logic  │
        │  (small, slow)│
        ├──────────────┤
        │ Merge/bump    │  3. Cross-scale integrity tests
        │  integration  │
        ├──────────────┤
        │ Grading       │  2. Reference-table + boundary tests  ← O2
        │  correctness  │
        ├──────────────┤
        │ Red flags     │  1. Isolation per-flag tests           ← O1
        │  coverage     │
        └──────────────┘
```

**Environment:**
- Framework: `flutter test` (Dart VM), pure-Dart test targets with **no plugin/IO** in the unit tier (the engine in `lib/config/` and future `lib/triage/` is synchronous — testable instantly).
- Coverage: `flutter test --coverage` + `genhtml` report; coverage published per commit (see §10).
- Determinism: no timers, no network, no RNG in tests. All clock use (e.g., `timestamp`) injected.
- CI: every commit runs Pillars A + B + C + a fast slice of D (see §11).

---

## 4. Pillar A — Red-Flag Coverage Tests

*Aim: prove **O1** — nothing in the flag set is dead code.*

### 4.1 The isolation matrix (one case per flag)

Each flag gets **exactly one test case** where every *other* input is inside a healthy band, so the flag under test is the *only* possible reason a "fire" could happen.

| Flag (method) | Healthy background inputs | Trigger input | Expect |
|---|---|---|---|
| `severeImpairment` | gcs = 15, sbp = 120, spo2 = 98, hr = 70, rr = 16, temp = 37.0 | gcs = **8** | true |
| `hypotension` | gcs = 15, spo2 = 98, hr = 70, rr = 16, temp = 37.0 | sbp = **90** | true |
| `severeHypoxia` | gcs = 15, sbp = 120, hr = 70, rr = 16, temp = 37.0, **room air** | spo2 = **91** | true |
| `criticalRespiratoryRate` (low) | gcs = 15, sbp = 120, spo2 = 98, hr = 70, temp = 37.0 | rr = **8** | true |
| `criticalRespiratoryRate` (high) | gcs = 15, sbp = 120, spo2 = 98, hr = 70, temp = 37.0 | rr = **25** | true |
| `criticalHeartRate` (low) | gcs = 15, sbp = 120, spo2 = 98, rr = 16, temp = 37.0 | hr = **40** | true |
| `criticalHeartRate` (high) | gcs = 15, sbp = 120, spo2 = 98, rr = 16, temp = 37.0 | hr = **131** | true |
| `criticalTemperature` (low) | gcs = 15, sbp = 120, spo2 = 98, hr = 70, rr = 16 | temp = **35.0** | true |
| `criticalTemperature` (high) | gcs = 15, sbp = 120, spo2 = 98, hr = 70, rr = 16 | temp = **39.1** | true |

**Companion "negative" cases** (assert the *same* callers do **not** falsely fire):
| Case | Expect |
|---|---|
| gcs = 9 | `severeImpairment` false |
| sbp = 91 | `hypotension` false |
| spo2 = 91 **on oxygen** | `severeHypoxia` false (O₂ makes it non-red-flag) |
| rr = 25 with... exactly one flag (must still fire only the RR flag — see 4.3) | true |
| hr = 70, rr = 16, temp = 37.0, gcs = 15, sbp = 120, spo2 = 98 | `anyFire` false |

### 4.2 Composite `anyFire` truth table

`anyFire` must be the **OR of every leaf** with no short-circuit shadowing a leaf that is *also* true. Enumerate the full 2^6 truth table by construction:

- **All-16-on**: single cases where *only one* leaf is true (from §4.1) → `anyFire == true` for all 9 trigger rows.
- **None-on**: healthy case → `anyFire == false`.
- **Combined**: two leaves simultaneously true → still `true` (trivially OR, covered by the "two-flag firing" case below).

### 4.3 No-shadowing guarantee (the heart of O1)

The most common red-flag bug is **one flag masked by another**. Two explicit assertions:

1. **Single-flag firing proof:** for each flag in isolation, assert `_countFiringFlags(case) == 1` **and** `anyFire == true`. This proves the flag fired *because of its own threshold*, not because a sibling also happened to be abnormal.
2. **Edit-distance proof:** take each isolation case and move the trigger input to the *healthy* side of its boundary (gcs 9, sbp 91, spo2 92, rr 24 then 9, hr 111, temp 38.5 for high pings...). Assert `anyFire == false`. This proves the flag is **tight** — it fires only on its own side of the boundary, never bleeding across.

> This pair — "fires when it should, alone" + "silent when its sibling is the only abnormality" — is the formal check that **no flag is skipped and no flag bleeds**.

### 4.4 Structured test sketch

```dart
test("hypotension fires as the only abnormality", () {
  final flags = <String>[];
  // healthy: gcs 15, sbp 120, spo2 98, hr 70, rr 16, temp 37.0, room air
  if (RedFlags.hypotension(90)) flags.add("hypotension");
  expect(flags, ["hypotension"]);       // exactly one flag
  expect(RedFlags.anyFire(gcs:15, sbp:90, spo2:98, hr:70, rr:16, temp:37.0), isTrue);
});
```

**Table-driven version** reads a fixture row `(name, inputs, onlyExpectedFlag)` from `test/fixtures/red_flags.json` — see §8.

---

## 5. Pillar B — Grading-Correctness Tests

*Aim: prove **O2** — scores match the prespecified reference exactly, including boundaries.*

### 5.1 NEWS2 component scorers — exhaustive per-table

For **every** band of **every** component, test:
| Band edge | Expect |
|---|---|
| One BELOW the band (inclusive lower) | lower band's score |
| The boundary value itself | this band's score |
| One ABOVE the band (inclusive upper) | this or next band's score per table |

Table-driven from the reference (`docs/CLINICAL_SOURCES.md` §1, `News2Thresholds`):

| Scorer | Boundary rows (must test ALL) |
|---|---|
| `spO2Score` | 91, 92, 93, 94, 95, 96 |
| `airOrOxygenScore` | onO₂ true/false |
| `systolicBpScore` | 90, 91, 100, 101, 110, 111, 219, 220 |
| `heartRateScore` | 40, 41, 50, 51, 90, 91, 110, 111, 130, 131 |
| `temperatureScore` | 35.0, 35.1, 36.0, 36.1, 38.0, 38.1, 39.0, 39.1 |
| `respiratoryRateScore` | 8, 9, 11, 12, 20, 21, 24, 25 |
| `consciousnessScore` | A → 0, V/P/U → 3 |

### 5.2 NEWS2 aggregate + risk bands

- Valid aggregate range **0–20**; sum-of-parts identity test: `aggregate(...) == sum(components)` for a sweep of random-but-complete instantiations (seeded RNG for reproducibility).
- Tier bands: aggregate 0 / 1 / 2 / 3 / 4 → routine ≥3-rule; 5 / 6 → urgent; **7 → emergency**. Boundary rows: 0, 3 (any-single-3 rule), 5, 6, 7.
- **Any single parameter = 3 → urgent minimum** (spec §5.1 row): construct one-component-3-with-total-3 cases and assert the escalation, not just the aggregate.

### 5.3 GCS

- Full component tables (eye 1–4, verbal 1–5, motor 1–6) with every valid string mapping to its exact score.
- `total` identity: `total == eye + verbal + motor`.
- Tier map boundaries: gcs **8/9**, **13/14**, 15; worst case 3.
- Invalid/empty string handling → defaults to lowest score (spec fail-closed), asserted explicitly.

### 5.4 Burn

- Adult TBSA bounds: 9.9 / **10 / 19.9 / 20** / 25 → routine/urgent/emergency (i.e., `10→urgent`, `20→emergency` per code).
- Pediatric bounds: 4.9 / **5 / 9.9 / 10** → routine/urgent/emergency.
- `hasCriticalLocation` coverage: each critical substring ("face", "hands", "feet", "genitalia", "joint", "perineum", "circumferential") → true; a benign location ("thigh") → false; case-insensitive match asserted.

### 5.5 (Removed — skin classifier)

> Former skin-classifier tier-mapping tests (e.g., `triageLevel("high")→emergency`)
> were deleted with the classifier itself (ADR-020). P5 default stays covered
> through the merge and vignette pillars.

### 5.6 Future scales (documented, tests to be added with implementation)

Peds-NEWS2 (per age bracket bands), Neonatal PEWS, qSOFA, pedSIRS, complaint probes, decision table (see §11 gate: **the decision table completeness test is the release gate** — every input combination maps to a defined tier, no silent fallthrough).

### 5.7 Serving as "abnormality detection"

The boundary sweep in §5.1–5.4 doubles as the **anomaly detector**: any off-by-one in a threshold turns into a red test at exact edges. A continuous fuzz sweep (seed fixed, band indices `±1`) guards against accidentally shifted bands that unit tests written by hand tend to miss.

---

## 6. Pillar C — Merge & Bump Integrity

Once the merge engine exists (`max()` + modifier bumps):

- **max() invariant (CI-blocking):** `triage_level_final >= triage_level_base` for every input combination in the vignette suite. Spec §5.3 — a hard architectural guarantee.
- **Decision-table completeness:** enumerate all defined input combos; assert every combo maps to a defined tier (no fallthrough to default).
- **Bump cap:** bump from P2 → P1 can never exceed P1; P1 bump is a no-op.
- **Single-bump:** multiple qualifying modifiers produce exactly one bump (spec §12).

---

## 7. Pillar D — Missing-Vitals Policy Tests

Implements spec §21. Test cases (from spec §21.10):

| Case | Input | Assert |
|---|---|---|
| SpO₂ missing + respiratory concern (RR ≥2) | substitution applies | sub score 3; may escalate to P1 via single-param |
| SpO₂ missing + no concern | not scored | partial; **P3 floor**; `vitalReviewRequired` true |
| Temp missing + fever concern | substitution applies | sub score 3; escalated |
| Temp missing + no concern | not scored | partial; P3 floor; flag true |
| Both missing | sepsis screen mandatory | mandatorySepsis boolean; review reason set |
| Neonatal + missing vitals | PEWS itself floors P4 | **P3 override** asserted |
| Invalid (out-of-range) input | e.g. SpO₂ 140 | treated as missing + review flag, never graded as if valid |

**Key assertion:** any missing vital ⟹ `vitalReviewRequired == true` and **never** produces P4/P5 from incomplete data.

---

## 8. Test Fixtures & Reference Tables

Directory layout (to create):

```
test/
  red_flags_test.dart          # Pillar A
  grading_reference_test.dart  # Pillar B
  merge_bump_test.dart         # Pillar C (as implemented)
  missing_vitals_test.dart     # Pillar D
  fixtures/
    red_flags.json             # Table-driven isolation rows (§4.1)
    news2_reference.json       # Full published table as data (§5.1)
    gcs_reference.json
    burn_reference.json
    vignettes/
      *.json                   # Vignette battery (spec §17 + §21.10)
  results_history.csv          # Tracked over time (spec §5.4)
```

- `*_reference.json` is **prespecified** — copied from the published tables, reviewed once by the clinical safety lead, then treated as immutable ground truth by tests. Changing a reference row requires a DECISIONS entry per project policy.
- **The reference files are the source of truth for grading tests**, not the implementation — so a wrong constant in code is caught, not copied.

---

## 9. Boundary-Value Cheat Sheet

The exact numbers that MUST appear in tests (implement or fail — this is the anomaly-sensitive set):

| Scale | Boundaries |
|---|---|
| NEWS2 SpO₂ | 91 / 92 / 93 / 94 / 95 / 96 |
| NEWS2 SBP | 90 / 91 / 100 / 101 / 110 / 111 / 219 / 220 |
| NEWS2 HR | 40 / 41 / 50 / 51 / 90 / 91 / 110 / 111 / 130 / 131 |
| NEWS2 Temp | 35.0 / 35.1 / 36.0 / 36.1 / 38.0 / 38.1 / 39.0 / 39.1 |
| NEWS2 RR | 8 / 9 / 11 / 12 / 20 / 21 / 24 / 25 |
| NEWS2 AVPU | A=0, V/P/U=3 |
| GCS tier | 8 / 9 / 12 / 13 / 14 / 15 |
| Burn adult | 10 / 19.9 / 20 |
| Burn pediatric | 5 / 9.9 / 10 |
| Red flags | gcs 8/9 · sbp 90/91 · spo2 91 (O₂ vs air) · rr 8/9·24/25 · hr 40/41·130/131 · temp 35.0/35.1·39.1 |

**Room-air rule is critical:** spo2 91 on O₂ must NOT fire `severeHypoxia` (spec: red-flag hypoxia is on room air).

---

## 10. Code Coverage Targets

| Component | Target |
|---|---|
| `RedFlags` (all leaves + `anyFire`) | **100%** — mandatory (Pillar A proves it) |
| `News2Thresholds` / `GcsThresholds` / `BurnThresholds` | **100%** branch on every scorer (target; any gap is flagged) |
| Tier 1 decision logic (future merge/engine) | **100% branch** — non-negotiable per spec §5.1 |
| Rest of app | Conventional (≥ 80% line) |

Coverage gate on CI: Pillar A/B must report **100%** or the commit cannot merge.

---

## 11. CI Integration & Gate Rules

| Event | Runs | Gate |
|---|---|---|
| Every commit/PR | `flutter analyze` clean + Pillars A, B, C + fast slice of D | Merge **blocked** on any failure or <100% coverage on A/B |
| Every release tag | Full suite: all pillars + vignette battery + classifier validation; results **archived** to `test/results_history.csv` | **Under-triage rate must be 0%** in vignettes-with-missing-vitals; no release otherwise (spec §5.4) |
| Any change to `clinical_thresholds.dart` | Full A–D + vignettes + a DECISIONS entry (project policy) | Reviewer cross-check against `CLINICAL_SOURCES.md` |

CI command baseline:

```powershell
flutter analyze
flutter test                       # Pillars A-D + fixtures
flutter test --coverage            # coverage report + gate check
```

---

## 12. Reporting & Failure Triage

- Every failure outputs the exact **input row** + **expected** vs **actual** (table-driven tests make this trivial: include the fixture id in the failure message).
- Failure taxonomy maps to action:
  | Symptom | Likely cause | Action |
  |---|---|---|
  | Flag A fires when only B abnormal | OR-chain/shadowing | Fix RedFlags + rerun edit-distance proof |
  | Boundary off-by-one (e.g., 92→3 instead of 2) | Threshold constant drift | Diff vs `*_reference.json`; DECISIONS entry |
  | `anyFire` passes but isolation count != 1 | Two flags share a trigger properly — recheck healthy inputs are truly benign | Correct fixture background |
  | Missing-vitals returns P4/P5 | Floor missing | Fix `kMissingVitalsFloor` |
  | Reference file changed unseen | Human-edited ground truth | Re-review by clinical safety lead before re-committing |
- `results_history.csv` append on every release-suite run (spec §5.4): under-triage rate, coverage, pass/fail count, date, commit hash.

---

## 13. Risk Register for the Testing Effort

| Risk | Mitigation |
|---|---|
| Tests pass but a flag is still dead | Isolation matrix + edit-distance proof (§4.3) makes this near-impossible; the 100% coverage gate catches unexercised leaves |
| Reference tables drift from published guidelines | `*_reference.json` versioned + clinically reviewed; any change = DECISIONS entry |
| Boundary tests duplicate implementation bugs (copying the bug) | Fixtures sourced from published tables, not from code; a different person/process writes them |
| Peds/neonatal scales unimplemented yet tested | Tests document expected behavior now; CI gates implementation (tests fail = unfinished feature is visible) |
| Fuzz sweep flakes | Seeded RNG, no timers, pure functions only |

---

## 14. Reference Test Files to Create

| File | Pillar | First draft content |
|---|---|---|
| `test/red_flags_test.dart` | A | 9 isolation + 8 negative + composite truth table (table-driven) |
| `test/grading_reference_test.dart` | B | NEWS2 (all 7 scorers, boundaries), GCS, Burn, Skin mapping |
| `test/missing_vitals_test.dart` | D | spec §21 rows, incl. P3 floor + both-missing sepsis |
| `test/fixtures/red_flags.json` | A | Isolation rows per §4.1 |
| `test/fixtures/news2_reference.json` | B | Full NEWS2 table as data |
| `test/fixtures/gcs_reference.json` | B | GCS components + tier map |
| `test/fixtures/burn_reference.json` | B | Adult/ped TBSA + locations |
| `test/fixtures/vignettes/*.json` | C/D | spec §17 battery + §21.10 additions |
| `test/results_history.csv` | report | header + append log |

---

*Document owner: Software Safety Engineer*  
*Review cycle: Every 6 months or after any threshold/decision change*  
*Approval: Software Safety Engineer + Clinical Safety Lead*