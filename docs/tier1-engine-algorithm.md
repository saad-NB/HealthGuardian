# Tier 1 Engine — Implemented Algorithm (reference document)

**Applies to:** `lib/triage/engine.dart` (v2.0 `TriageRecord`)
**Date:** 2026-09-08
**Spec reference:** `docs/tier-1-complete-spec.md` (§4–§22), ADR-008/ADR-009/ADR-013
**Decision record:** `docs/DECISIONS.md`

This document describes the **implemented** algorithm of the Tier 1 triage engine at
`lib/triage/engine.dart` and validates it against the governing spec. It is the
authoritative implementation reference and the place to check before changing any
scoring rule.

---

## 1. Pipeline Overview

`TriageEngine.compute(a)` / `computeRecord(a)` both funnel through the single pure,
synchronous `_evaluate(a)`. No side effects, no I/O — trivially unit-testable and
within the 1 s compute budget.

Evaluation order (matches spec §13 pseudocode):

1. **Age gate** — `ageGroup` must be set, otherwise fail-closed P3 + `vitalReviewRequired`.
2. **Danger gates (§4)** — any of A1–A15 → immediate **P1**, short-circuit everything.
3. **Vital-sign scoring (§5)** — scale selected by age bracket.
4. **Consciousness / GCS (§6)** — full GCS tier only when all 3 components present.
5. **Chief complaint + probes (§7/§8)** — branch-specific scored tier.
6. **Sepsis screen (§9)** — qSOFA (adult) / pedSIRS (1–15y).
7. **Burn module (§11/§22)** — 19-rule decision table.
8. **Modifier bump after merge (§12/§13 step 10)** — single +1 bump, capped at P1.

Merge principle (PRINCIPLE 2): the final tier is the **most urgent** of
{vitals, GCS, complaint, sepsis, burn} via `TriageTier.atMostUrgent`. Escalate-only;
never down-tier. Fail-closed (PRINCIPLE 5) applies to every module.

```
age gate ─► danger gates (P1 short-circuit)
            ─► vitals  ─┐
            ─► GCS     ─┤
            ─► complaint─┼─► atMostUrgent(max) ─► modifier bump ─► tier + record
            ─► sepsis  ─┤
            ─► burn    ─┘
```

---

## 2. Age Gate & Scale Selection

- `AgeGroup` (9 brackets: neonate…olderAdult) carries its own `VitalScale`
  (`news2` / `pedsNews2` / `pews`). See `models.dart`.
- **No age selected** → can never score; returns P3 with reason `"Age was not
  selected."` and `vitalReviewRequired: true`. This is stricter than the spec's
  "assume adult thresholds" (§18) — the implementation instead refuses to guess.
- Pediatric (Peds-NEWS2) brackets map to a `pedsBracket` key consuming the
  age-exact scoring rows in `PedsNews2Thresholds`.

Helper predicates used across modules:

| Predicate | Meaning |
|-----------|---------|
| `usesNews2` / `isPediatric` | Adult NEWS2 vs Peds-NEWS2 |
| `isUnderOneYear` | neonate/infant — temp-concern list |
| `isUnderFive` | neonate…preschool — modifier vulnerability + burn bump |
| `isOlderAdult` | ≥65 — temp-concern list |

---

## 3. Danger Gates (§4) — P1 short-circuit

`_applyDangerGates` is the very first scoring step. If `dangerSigns` is non-empty,
the engine returns **P1** at once (`_evaluate` line 82), recording every triggered
gate ID in order A1→A15 (`_dangerSignOrder`) as reasons. No vital/complaint/sepsis/
burn scoring runs; a `gates: {'passed': false, 'triggered': [...]}` block is stored.

The record for a gate-triggered result is built by `_dangerRecord` (a slimmed record
with `contributingScores.gate`). Note: danger gates do **not** wait for GCS; a P1
gate result bypasses B/C scoring for the result object (Tier 2 collects them later).

---

## 4. Vital-Sign Scoring (§5)

### 4.1 Data validation & physiological bounds

`_valueOf(a, field)` returns the entered value only if it is **physiologically
possible**:

| Field | Valid range | Invalid → treated as missing |
|-------|-------------|------------------------------|
| rr  | 4–60 | y |
| spo2| 50–100 | y |
| sbp | 60–260 | y |
| hr  | 20–220 | y |
| temp| 34.0–43.0 | y |

An out-of-range value is treated as **missing** for scoring (and thus contributes to
`vitalReviewRequired`), per §21.3 "Invalid parameter".

### 4.2 Missing SpO₂ / temperature (§21.5/§21.6 — hybrid substitution)

- `_isMissingSpo2` = `spo2Missing` flag OR no valid value.
- `_isMissingTemp`  = `tempMissing` flag OR no valid value.
- **Substitution only when a concerning context exists:**

`_respiratoryConcern(a, age)` — true if ANY of:
- chief complaint = breathing difficulty
- on supplemental oxygen
- COPD/CO₂ retention (Scale 2)
- danger sign A4 (stridor) or A5 (severe breathing difficulty)
- E-B1 answered No ("cannot speak full sentences")
- E-B3 accessory muscles/tripod = Yes
- present RR scores ≥2 (`_rrScore`)

→ missing SpO₂ substitutes **3** (worst band).

`_temperatureConcern(a, age)` — true if ANY of:
- chief complaint = fever
- age <1y or ≥65y
- F1 suspected infection = Yes
- F6 immunocompromised = Yes
- E-F1 measured temp ≥39°C = Yes

→ missing temperature substitutes **3** (adult/NEWS2) or **2** (Peds-NEWS2).

- Substitution **only raises**, never lowers, and is recorded in `substituted`.
- Missing vitals that are **not** contextually concerning are simply **not scored**
  and excluded from the aggregate, but still force the P3 floor + review flag.

### 4.3 Common tier map (`_tierFromNews2`) — used by NEWS2 and Peds-NEWS2

```
aggregate >= 7 || any single parameter == 3  → P1
aggregate >= 5                                → P2
aggregate >= 3                                → P3
aggregate >= 1                                → P4
else                                          → P5
```

`anyParamThree` treats any present **or substituted** parameter scoring 3 as a P1
single-parameter escalation.

### 4.4 Adult NEWS2 (`_scoreNews2`)

Components: RR, SpO₂ (Scale 1 by default, Scale 2 if `copdCo2Retention`), SBP, HR,
Temp, supplemental O₂ (on-O2 adds 2), AVPU consciousness.

- AVPU mapping (`avpuConsciousnessScore`): A=0, V=2, P=3, U=3, unknown→3.
  **Deviates** from standard NEWS2 ('V'=3) per ADR-009 (shared pediatric gradient).
- Missing-vitals **P3 floor** (`_missingVitalsFloor`) applies when any
  RR/SBP/HR/AVPU/SpO₂/Temp is missing; `review = hasMissingVitals`.
- Out-of-range vitals count as missing → review.

### 4.5 Peds-NEWS2 (`_scorePeds`)

Components: RR/HR/SBP via `pedsBracket` rows, SpO₂, Temp, AVPU, **capillary refill**.

- SBP is **optional** per ADR-013 — when absent it is informational-only and
  **never** contributes to `missing`/review (low-resource no-cuff scenario).
- Capillary refill score (`CapillaryRefill`): under2=0, twoTo3=1, over3=3.
- A `refill == 3` (`over3`) contributes to `anyParamThree` → **P1**.
- Same P3 floor + review logic as adult.

### 4.6 Neonatal PEWS (`_scorePews`)

Components: RR, HR, SBP (optional per ADR-013), SpO₂, Temp,
`neonatalConsciousness` (feeding-well=0 / drowsy-poor=1 / unresponsive-no-feed=2).

- Tier map (`NeonatalPewsThresholds.tierUrgency`):
  score ≥4 → P1, 2–3 → P2, 1 → P3, 0 → P4 (age minimum).
- Missing vitals override P4-by-age upward to **P3** (§21.4 rule 4):
  `tier = tier.atMostUrgent(P3)`; `review = true`.

---

## 5. Consciousness / GCS (§6)

`_gcsTotal` returns `eye + verbal + motor` only when **all three** components are
present (else null — never guesses a partial GCS).

`GcsThresholds.tierFromGcs(gcs, headInjury:)`:

| GCS | Tier | Head-injury override |
|-----|------|----------------------|
| ≤8  | P1   | — |
| 9–12| P2   | → P1 |
| 13  | P3   | — |
| 14  | P4   | → P2 |
| 15  | P5   | → P4 (floor) |

`headInjury` comes from `chiefComplaint.suggestsHeadInjury` (injury or headache).
`atMostUrgent` merges GCS into the running tier.

**Note:** §6 "13 with neuro deficit → P2" is not implemented — the engine has no
input for a neuro-deficit flag, so 13 stays P3.

---

## 6. Chief Complaint & Probes (§7/§8)

`_complaintTier` runs only when the branch has a scored probe list
(`probeQuestions(branch)`). Unanswered probes contribute **0** (missing never
escalates). Score = Σ of `score` for each "concerned" answer.

- Inverted question handling (`_probeConcerns`): E-B1 ("Can the patient speak in
  full sentences?") — a **No** answer is the concern (score 3).
- E-C4 tearing back pain → forced **P1** regardless of total score (aortic dissection).

Per-branch tier map:

| Branch | P2 at | P1 at |
|--------|-------|-------|
| chest | ≥4 | ≥6 (or E-C4) |
| breathing | ≥3 | ≥6 |
| fever | ≥3 | ≥5 |
| headache | ≥3 | ≥5 |
| abdo | ≥3 | ≥5 |
| psych | ≥3 | ≥6 |

Only the six detailed branches (`chest, breathing, fever, headache, abdo, psych`)
have probes in this increment; other complaints have `branch == null` → no score, no
tier contribution (E-Generic note).

---

## 7. Sepsis Screen (§9)

`_sepsisTier` is age-branched by `VitalScale`.

**Adult (NEWS2) — qSOFA** (`SepsisAnswers.qsofa` = f2+f3+f4):
- qSOFA ≥2 → **P1** ("immediate care")
- qSOFA 1 → **P2** ("possible sepsis")
- qSOFA 0 → no contribution

**Pediatric (Peds-NEWS2) — pedSIRS:** counts temp / RR / HR abnormalities.
**Measured vitals win over the F-screen answers** when both present:
- Temp abnormal if `temp < 36.0 || > 38.5` (else uses f7)
- RR abnormal if `rr > age 95th` (else uses f3)
- HR abnormal if `hr > age 95th` (HR has no F-pair, always measured)
- q ≥2 → **P1**; q == 1 → **P2**; q == 0 → none.

**Neonates:** no sepsis screen in this increment (handled by danger gates).

---

## 8. Burn Module (§11 H1–H8 / §22 decision table)

Single decision-table function `_burnTier`. Engagement gate (see ADR note):

```
engaged ⇔ cause != null || areas.isNotEmpty || tbsaPercent > 0 ||
          airwaySigns || circumferential || depth != null
return null ⇔ !engaged || (areas.isEmpty && tbsaPercent <= 0)
```

The module engages on **TBSA alone** even with no critical `BurnArea` (e.g. a shaded
upper-arm segment), per the tap-shade design.

Depth fail-closed mappings:
- `unsure` → **deep-partial** (`isDeepOrDeeper`)
- `isFullThickness` (full or unsure) for the full-thickness rules

### 8.1 Rule order (first match wins)

The engine evaluates rules in a fixed order matching §22.9 priority. Order in code:

| # | Condition | Tier | Reason |
|---|-----------|------|--------|
| 1 | any airway sign | P1 | inhalation |
| 2 | chemical/electrical cause | P1 | hidden internal injury |
| 3 | full-thickness on critical area (face/hand/foot/genitals/joint) | P1 | functional/cosmetic |
| 4 | circumferential full-thickness | P1 | compartment |
| 18 | circumferential full-thickness + cap-refill >3s | P1 | surgical emergency |
| 19 | face/genitals + airway signs | P1 | inhalation spread |
| 5 | TBSA ≥20% adult / ≥10% child | P2 | fluid threshold |
| 6 | full-thickness >1% any location | P2 | burn center |
| 7 | critical area, any depth | P2 | functional risk |
| 8 | deep-partial >5% | P2 | excision threshold |
| 9 | circumferential non-full | P2 | compartment surveillance |
| 10 | chemical/electrical to eye/mouth/perineum | P2 | critical structure |
| 15 | contaminated wound | P3 | infection risk |
| 16 | immunocompromised | P3 | infection risk |
| 11 | partial, TBSA 6–9% (child) / 11–19% (adult) | P3 | moderate burn |
| 12 | partial, TBSA <6% child / <11% adult, no risk areas | P4 | outpatient |
| 13 | deep-partial/full ≤1%, no risk areas | P4 | outpatient possible |
| 14 | superficial ≤1%, no risk areas | P5 | self-care |
| — | default (engaged but unclassified) | P3 | clinical review |

Note the ordering places **rules 15/16 before rules 11–14**, per §22.9 priority
(1–10 > 11–16), so a contaminated or immunocompromised small burn lands at P3 rather
than P4/P5.

`hasCriticalArea` = any of face/hand/foot/genitals/joint in `BurnAnswers.areas`.

---

## 9. Modifiers & Bump-after-Merge (§12/§13 step 10)

`_vulnerableAge(a)` — true only when `modifiers.ageYears` is **explicitly** <5 or
>65. It is never inferred from the age bracket (ADR-013: brackets already encode
age-appropriate scales). Returns false when `ageYears` is null.

`_activeModifiers(a, vulnerableAge)` collects the bumped flags:
- Age <5 or >65 (when `vulnerableAge`)
- Pregnant
- Immunocompromised
- MUAC <11.5 cm
- CFS ≥5

Bump rule (`_evaluate` step 8): if any active modifier **and** tier != P1 →
`tier = tier.bumpOnce()` — a **single** +1 escalation capped at P1 (P1 stays P1).
Applied **after** the max-merge. Multiple modifiers do **not** stack.

---

## 10. Stored Record (`computeRecord`)

`_evaluate` builds a `TriageRecord` (`record.dart`) capturing
`contributingScores { vital, gcs, complaint, sepsis, burn, skin:null }`,
`mergeReasons`, `missingParams`, `substitutionApplied`, `safetyFlags
(+vitalReviewRequired)`, `modifiers`, `gates`, and a `_inputsSnapshot` (raw inputs
incl. burn `shaded` pairs) for reproducible offline reconstruction. Version `2.0`.

---

## 11. Recheck of Engine vs Spec — Required / Noted Modifications

The implementation is validated against `tier-1-complete-spec.md`. Findings, ordered
by severity:

### Deviations currently present (all fail-safe except where noted)

| # | Finding | Spec | Engine | Impact |
|---|---------|------|--------|--------|
| D1 | **Pediatric cap-refill escalation** | §5.2: cap refill >3s → **minimum P2** | `refill==3` feeds `anyParamThree` → **P1** | More conservative (safe); acceptable but document |
| D2 | **Modifier vulnerable-age threshold** | §12 I1: <5y or >65y | matches (<5 or >65) | ✅ consistent |
| D3 | **Burn §22.10 extra vulnerable bump (>60y, +1 before merge)** | §22.10: age <5 or **>60** with any burn → +1 (pre-merge, capped so it can't upstage P1/P2) | **Not implemented** — only the global §12 >65 bump-after-merge exists | **Gap**: a 61–65y adult with a moderate burn does not receive §22.10's burn-specific bump. Release-relevant. |
| D4 | **Burn rule 12 "single region" clause** | §22.9 rule 12: partial <6% child/<11% adult, **single region**, no risk areas → P4 | Engine checks only `tbsa < partialLow && !hasCriticalArea`, **omits single-region** | Possible mild **under-triage** (P4 for multi-region). Should add region-count check. |
| D5 | **QSOFA / pedSIRS infection gate** | §9 F1 is "gate to rest of screen"; pedSIRS tier map requires "+ suspected infection" | Engine does **not** check `f1` before returning qSOFA/pedSIRS tiers | qSOFA/pedSIRS can fire on vitals with F1 unanswered. Conservative when vitals abnormal, but diverges from the gated design. |
| D6 | **GCS 13 + neuro deficit → P2** | §6: 13 w/ neuro deficit → P2 | Not implemented (no deficit input) | GCS 13 stays P3; no input field. |
| D7 | **Burn rule 11 "scald/flame" qualifier** | §22.9 rule 11: scald/flame, partial… | Engine's rule 11 is any `partial` regardless of cause | Slightly conservative (any partial in band → P3). |
| D8 | **Burn rule 10 tier** | §11 H8 says eye/mouth chemical/electrical → P1; §22.9 rule 10 says → P2 (operative §22 supersedes) | P2 | Consistent with operative §22. ✅ |

### Behavior confirmed correct / aligned

- Danger-gate P1 short-circuit + ordered reasons. ✅
- Max-merge escalate-only via `atMostUrgent`. ✅
- Missing-vitals P3 floor + `vitalReviewRequired` + partial scoring + context
  substitution (SpO₂=3, temp=3 adult/2 peds). ✅
- Peds-NEWS2 age-exact rows; neonatal PEWS P4-by-age overridden to P3 on missing
  vitals. ✅
- Single modifier bump after merge, capped at P1, non-stacking. ✅
- Burn rule order 1–10 > 11–16, 18/19 override. ✅
- GCS head-injury overrides. ✅
- E-C4 forced P1. ✅

### Recommended action (in priority order)

1. **D3 — implement §22.10 burn-specific vulnerable bump** (age <5 or >60 with any
   burn → +1 before merge, only when burn tier is P3/P4 and never upstaging P1/P2).
   This is the only finding that can cause an **undertriage gap** the spec
   explicitly calls out (61–65y moderate burn).
2. **D4 — enforce the "single region" clause** in burn rule 12 (use the shaded-region
   count or `areas` size) to avoid over-granting P4 to multi-region partial burns.
3. **D5 — gate qSOFA/pedSIRS on F1** suspected/confirmed infection (per §9), or
   document the intentional always-score behaviour.
4. **D1 — align pediatric cap-refill to §5.2 minimum P2** (or keep P1 and record an
   ADR).
5. **D6 — add an optional neuro-deficit flag** for GCS 13→P2, or document as a scope
   limitation.

None of the above changes scoring thresholds in §4–§9; all are within the already
implemented rule structures. Any change must land alongside a unit-test in
`test/multi_scale_engine_test.dart` and be logged in `docs/DECISIONS.md`.
