# Sehat Nigraan — Complete Tier 1 Triage System Specification

**Version:** 2.0  
**Date:** 2026-09-05  
**Status:** Draft for Clinical Review  
**Companion to:** `docs/final-scope-skin-vision.md`, `docs/ARCHITECTURE.md`

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [System Architecture](#2-system-architecture)
3. [Age Stratification](#3-age-stratification)
4. [Section A — Emergency Danger Signs (Gates)](#4-section-a--emergency-danger-signs-gates)
5. [Section B — Vital Signs](#5-section-b--vital-signs)
   - 5.1 [Adult: NEWS2](#51-adult-news2)
   - 5.2 [Pediatric: Peds-NEWS2 (1–16 years)](#52-pediatric-peds-news2-116-years)
   - 5.3 [Neonatal: Adapted PEWS (&lt;1 month)](#53-neonatal-adapted-pews-1-month)
6. [Section C — Consciousness Assessment](#6-section-c--consciousness-assessment)
7. [Section D — Chief Complaint & History](#7-section-d--chief-complaint--history)
8. [Section E — Complaint-Driven Probes & Scoring](#8-section-e--complaint-driven-probes--scoring)
9. [Section F — Sepsis Screen](#9-section-f--sepsis-screen)
10. [Section G — Skin Classifier (Optional)](#10-section-g--skin-classifier-optional)
11. [Section H — Burn Module](#11-section-h--burn-module)
12. [Section I — Modifiers](#12-section-i--modifiers)
13. [Merge Logic: Cross-Scale Integration](#13-merge-logic-cross-scale-integration)
14. [Tier Mapping & Response Targets](#14-tier-mapping--response-targets)
15. [Output Specification](#15-output-specification)
16. [Tier 2 Payload](#16-tier-2-payload)
17. [Validation & Calibration](#17-validation--calibration)
18. [Safety Architecture](#18-safety-architecture)
19. [Implementation Phases](#19-implementation-phases)
20. [Appendices](#20-appendices)
21. [Missing Vital Signs Policy](#21-missing-vital-signs-policy-spo--temperature--hybrid-approach)

---

## 1. Design Principles

| # | Principle | Rationale |
|---|-----------|-----------|
| 1 | **Gate-first, always.** Binary emergency gates short-circuit all scoring. A patient with stridor never waits for NEWS2 arithmetic. | Prevents computation delay for time-critical conditions |
| 2 | **Max() merge, escalate-only.** Final tier = highest (most urgent) among all sub-scores. Tier 2 may raise, never lower. | Guarantees conservative triage |
| 3 | **Age-appropriate scales.** Adults use NEWS2; children use Peds-NEWS2; neonates use adapted PEWS. Never apply adult thresholds to children. | Prevents dangerous mis-triage from scale mismatch |
| 4 | **Nearly-free inputs.** Every collected field feeds at least one score. No orphaned questions. | Minimizes user burden |
| 5 | **Fail-closed.** Any missing, invalid, or ambiguous input defaults to more conservative tier. | Prevents unsafe operation under uncertainty |
| 6 | **Auditability.** Every tier decision stores contributing sub-scores and triggering items with full provenance. | Enables clinician review and quality improvement |
| 7 | **Low-resource realism.** Works without labs; palm-method TBSA; AVPU fallback where GCS is impractical; minimal free text. | Enables deployment in resource-limited settings |

---

## 2. System Architecture

```
Questionnaire (Sections A–I)
      │
      ├─ A Danger-sign gates ─────────────────────────► P1 override (any YES)
      ├─ B Vitals ─────────────────────────────────► NEWS2 (adult) / Peds-NEWS2 (child) / PEWS (neonate)
      ├─ C Consciousness (GCS/AVPU) ───────────────► GCS score + AVPU tier
      ├─ D Chief complaint ────────────────────────► Branch selector for E
      ├─ E Complaint-driven probes + scoring ──────► Complaint tier + Tier 2 payload
      ├─ F Sepsis screen ──────────────────────────► Sepsis tier (NEW)
      ├─ G Skin classifier (optional) ─────────────► Skin tier
      ├─ H Burn module ────────────────────────────► Burn rule tier
      ├─ I Modifiers ──────────────────────────────► Bump rules
      │
      ▼
   Per-scale band → tier map (Tables 10, 11, 12)
      │
      ▼
   max() merge + bump application
      │
      ▼
   Final tier P1–P5 + reason string + all contributing scores
      │
      ▼
   MedGemma Tier 2 prompt (escalation-only)
```

### Table 1 — Sub-scores and Their Inputs

| Sub-score | Inputs Needed | Sections | Age Range |
|-----------|--------------|----------|-----------|
| NEWS2 | RR, SpO₂, SBP, HR, Temp, on-O₂, AVPU | B | ≥16 years |
| Peds-NEWS2 | RR, SpO₂, SBP, HR, Temp, on-O₂, AVPU, capillary refill | B | 1–15 years |
| Neonatal PEWS | RR, HR, SpO₂, Temp, BP, consciousness, feeding | B | 0–30 days |
| GCS | Eye, Verbal, Motor | C | All ages |
| AVPU | A/V/P/U | B/C | All ages (fallback) |
| Complaint-driven | D1 + E-branch answers | D, E | All ages |
| Sepsis screen | Infection suspicion + qSOFA/pedSIRS | F | All ages |
| Burn rule | Mechanism, TBSA, depth, airway, location, circumferential | H | All ages |
| Skin tier | Classifier output | G | All ages |
| Modifiers | Age, pregnancy, immunocompromise, MUAC, CFS | I | All ages |

---

## 3. Age Stratification

The system **must** determine the correct age bracket before any vital sign scoring:

| Bracket | Age | Scale Used | Consciousness |
|---------|-----|-----------|---------------|
| Neonate | 0–30 days | Adapted PEWS | AVPU only (GCS not validated) |
| Infant | 1–11 months | Peds-NEWS2 | AVPU preferred, GCS if head injury |
| Toddler/Preschool | 1–4 years | Peds-NEWS2 | AVPU preferred, GCS if cooperative |
| School-age | 5–11 years | Peds-NEWS2 | GCS if cooperative, AVPU fallback |
| Adolescent | 12–15 years | Peds-NEWS2 | GCS standard |
| Adult | ≥16 years | NEWS2 | GCS standard |

**Implementation:** Age is collected in Section I (H1) but **must** be asked first or auto-populated from profile. All subsequent vital sign pickers adjust their ranges and thresholds based on this bracket.

---

## 4. Section A — Emergency Danger Signs (Gates)

> **"Does the patient have ANY of the following right now?"**

Any **YES** → **Immediate P1**, bypass all scoring. Complete B/C for Tier 2 payload.

| ID | Item | Age Modification | Source |
|----|------|-----------------|--------|
| A1 | Not responding normally / very drowsy / unconscious | None | WHO IMCI |
| A2 | Convulsing now, or convulsed during this illness | None | WHO IMCI |
| A3 | Cannot drink/breastfeed, or vomiting everything | **Breastfeed** if <2 years | WHO IMCI |
| A4 | Noisy breathing / stridor when calm | Stridor only if calm | WHO IMCI |
| A5 | Severe breathing difficulty; cannot speak full sentences | **Cannot feed/cries weakly** if <2 years | WHO IMCI |
| A6 | Swelling of lips/tongue/face or hives WITH breathing difficulty | None | Anaphylaxis guideline |
| A7 | Bleeding that won't stop with pressure after 10 minutes | None | First aid standard |
| A8 | Severe chest pain with sweating or breathlessness | **None** — if child, consider chest pain atypical | ESC/ACS |
| A9 | Fever with stiff neck or non-blanching rash | Non-blanching = glass test | NICE NG143 |
| A10 | Suspected poisoning or overdose | Include medication errors | ToxBase |
| A11 | Severe abdominal pain, rigid or swollen belly | None | RCR/RCS |
| A12 | Unable to stand/walk, or unusually weak on one side | **Not moving limb normally** if pre-verbal | FAST-ED |
| A13 | Severe injury (head, spine, chest, abdomen, multiple fractures) | None | ATLS |
| A14 | Severe dehydration: sunken eyes, no urine ≥12h, lethargic | **No tears, dry mouth, fontanelle sunken** if <5y | WHO IMCI |
| A15 | Suspected sepsis: fever or hypothermia + altered mental status | See Section F | Sepsis Trust |

**Gate output:** `P1 + reason: "Danger gate: [ID]"`. If multiple gates trigger, all are recorded.

---

## 5. Section B — Vital Signs

### 5.1 Adult: NEWS2 (≥16 years)

**Input fields:**

| ID | Parameter | Input Type | Range | Source |
|----|-----------|-----------|-------|--------|
| B1 | Respiratory rate (breaths/min) | Stepper | 4–60 | Manual entry |
| B2 | SpO₂ (%) | Stepper | 50–100 | Pulse oximeter |
| B3 | Systolic BP (mmHg) | Stepper | 60–260 | Manual/automated |
| B4 | Heart rate (bpm) | Stepper | 20–220 | Manual/automated |
| B5 | Temperature (°C) | Picker | 34.0–43.0 | Thermometer |
| B6 | On supplemental oxygen? | Toggle | Y/N | Observation |
| B7 | Consciousness | AVPU | A/V/P/U | Clinical |
| B8 | **Scale 2 indicator:** COPD/CO₂ retention known? | Toggle | Y/N | History |

#### NEWS2 Scoring Table (Adult)

| Parameter | 3 points | 2 points | 1 point | 0 points | 1 point | 2 points | 3 points |
|-----------|----------|----------|---------|----------|---------|----------|----------|
| **Respiration rate** | ≤8 | — | 9–11 | 12–20 | — | 21–24 | ≥25 |
| **SpO₂ Scale 1** | ≤91 | 92–93 | 94–95 | ≥96 | — | — | — |
| **SpO₂ Scale 2** (COPD) | ≤83 | 84–85 | 86–87 | 88–92 | 93–94 | 95–96 | ≥97 |
| **Systolic BP** | ≤90 | 91–100 | 101–110 | 111–219 | — | — | ≥220 |
| **Heart rate** | ≤40 | — | 41–50 | 51–90 | 91–110 | 111–130 | ≥131 |
| **Temperature** | ≤35.0 | — | 35.1–36.0 | 36.1–38.0 | 38.1–39.0 | ≥39.1 | — |
| **Consciousness** | — | — | — | A | — | V | P or U |

**NEWS2 total:** 0–20 (consciousness maxes at 3 regardless of AVPU; SpO₂ scale selected by B8)

#### NEWS2 Tier Mapping (Adult)

| NEWS2 | Tier | Response Time | Rationale |
|-------|------|---------------|-----------|
| ≥7 or any parameter = 3 | **P1** | Immediate | RCP escalation threshold + 2025 EMJ validation |
| 5–6 | **P2** | ≤10 min | High risk, clinician within 10 min |
| 3–4 | **P3** | ≤30–60 min | Moderate risk, frequent reassessment |
| 1–2 | **P4** | ≤2 h | Low risk, routine assessment |
| 0 | **P5** | ≤4 h | Minimal risk |

**Single-parameter escalation rule:** Any parameter scoring 3 → minimum P2, and if consciousness = 3 or SpO₂ Scale 1 ≤91/Scale 2 ≤83 → P1.

---

### 5.2 Pediatric: Peds-NEWS2 (1–15 years)

**Critical:** NEWS2 is **not validated** for children. We adapt the UK Royal College of Paediatrics and Child Health (RCPCH) PEWS-compatible thresholds, aligned with [Geanacopoulos et al. 2024](https://doi.org/10.1542/hpeds.2024-008063) pediatric ED validation.

#### Age-Specific Normal Ranges & Scoring

**Respiratory Rate (breaths/min)**

| Age | Normal Range | Score 3 | Score 2 | Score 1 | Score 0 | Score 1 | Score 2 | Score 3 |
|-----|-----------|---------|---------|---------|---------|---------|---------|---------|
| 1–11 months | 25–40 | ≤20 | — | 21–24 | 25–40 | 41–50 | 51–60 | ≥61 |
| 1–2 years | 20–30 | ≤15 | — | 16–19 | 20–30 | 31–40 | 41–50 | ≥51 |
| 3–4 years | 20–25 | ≤15 | — | 16–19 | 20–25 | 26–35 | 36–45 | ≥46 |
| 5–7 years | 16–22 | ≤12 | — | 13–15 | 16–22 | 23–30 | 31–40 | ≥41 |
| 8–11 years | 14–20 | ≤10 | — | 11–13 | 14–20 | 21–28 | 29–38 | ≥39 |
| 12–15 years | 12–20 | ≤8 | — | 9–11 | 12–20 | 21–28 | 29–38 | ≥39 |

**Heart Rate (bpm)**

| Age | Normal Range | Score 3 | Score 2 | Score 1 | Score 0 | Score 1 | Score 2 | Score 3 |
|-----|-----------|---------|---------|---------|---------|---------|---------|---------|
| 1–11 months | 100–160 | ≤80 | 81–90 | 91–100 | 100–160 | 161–170 | 171–180 | ≥181 |
| 1–2 years | 90–150 | ≤70 | 71–80 | 81–90 | 90–150 | 151–160 | 161–170 | ≥171 |
| 3–4 years | 80–140 | ≤60 | 61–70 | 71–80 | 80–140 | 141–150 | 151–160 | ≥161 |
| 5–7 years | 70–120 | ≤50 | 51–60 | 61–70 | 70–120 | 121–130 | 131–140 | ≥141 |
| 8–11 years | 65–110 | ≤45 | 46–55 | 56–65 | 65–110 | 111–120 | 121–130 | ≥131 |
| 12–15 years | 60–100 | ≤40 | 41–50 | 51–60 | 60–100 | 101–110 | 111–120 | ≥121 |

**Systolic BP (mmHg)**

| Age | Normal Range (5th–95th percentile) | Score 3 | Score 2 | Score 1 | Score 0 | Score 1 | Score 2 | Score 3 |
|-----|-----------------------------------|---------|---------|---------|---------|---------|---------|---------|
| 1–11 months | 70–95 | ≤55 | 56–60 | 61–70 | 70–95 | 96–105 | 106–115 | ≥116 |
| 1–2 years | 75–100 | ≤60 | 61–65 | 66–75 | 75–100 | 101–110 | 111–120 | ≥121 |
| 3–4 years | 80–105 | ≤65 | 66–70 | 71–80 | 80–105 | 106–115 | 116–125 | ≥126 |
| 5–7 years | 85–110 | ≤70 | 71–75 | 76–85 | 85–110 | 111–120 | 121–130 | ≥131 |
| 8–11 years | 90–120 | ≤75 | 76–80 | 81–90 | 90–120 | 121–130 | 131–140 | ≥141 |
| 12–15 years | 95–130 | ≤80 | 81–85 | 86–95 | 95–130 | 131–140 | 141–150 | ≥151 |

**SpO₂ (%)**

| Age | Score 3 | Score 2 | Score 1 | Score 0 |
|-----|---------|---------|---------|---------|
| All pediatric | ≤90 | 91–93 | 94–95 | ≥96 |

**Temperature (°C)**

| Age | Score 3 | Score 2 | Score 1 | Score 0 | Score 1 | Score 2 | Score 3 |
|-----|---------|---------|---------|---------|---------|---------|---------|
| All pediatric | ≤35.0 | — | 35.1–36.0 | 36.1–38.0 | 38.1–39.0 | ≥39.1 | — |

**Consciousness (AVPU)**

| Response | Score |
|----------|-------|
| Alert | 0 |
| Voice | 2 |
| Pain | 3 |
| Unresponsive | 3 |

**Capillary Refill (NEW — pediatric addition)**

| Time | Score |
|------|-------|
| <2 seconds | 0 |
| 2–3 seconds | 1 |
| >3 seconds | 3 |

#### Peds-NEWS2 Tier Mapping

| Peds-NEWS2 | Tier | Response Time |
|------------|------|---------------|
| ≥7 or any parameter = 3 | **P1** | Immediate |
| 5–6 | **P2** | ≤10 min |
| 3–4 | **P3** | ≤30–60 min |
| 1–2 | **P4** | ≤2 h |
| 0 | **P5** | ≤4 h |

**Pediatric-specific escalation:** Capillary refill >3 seconds → minimum P2 (shock indicator).

---

### 5.3 Neonatal: Adapted PEWS (0–30 days)

Neonates require special handling. GCS is not validated; AVPU is used with feeding assessment.

| Parameter | Normal Range | Score 2 | Score 1 | Score 0 | Score 1 | Score 2 |
|-----------|-----------|---------|---------|---------|---------|---------|
| Respiratory rate | 30–60 | ≤25 | 26–29 | 30–60 | 61–70 | ≥71 |
| Heart rate | 120–160 | ≤100 | 101–119 | 120–160 | 161–180 | ≥181 |
| Systolic BP | 60–90 | ≤45 | 46–59 | 60–90 | 91–100 | ≥101 |
| SpO₂ | ≥95% | ≤85 | 86–90 | 91–94 | 95–100 | — |
| Temperature | 36.5–37.5 | ≤35.5 | 35.6–36.4 | 36.5–37.5 | 37.6–38.5 | ≥38.6 |
| Consciousness | Alert, feeding | — | Drowsy, poor feeding | Alert, feeding well | — | Unresponsive, not feeding |

**Neonatal tier mapping:** Any score ≥4 → P1; 2–3 → P2; 1 → P3; 0 → P4 (minimum, given age).

---

## 6. Section C — Consciousness Assessment

### Full GCS (when indicated)

Show full GCS pickers if:
- A1 = YES (not responding normally)
- B7/AVPU ≠ A (anything other than alert)
- Chief complaint = head injury, seizure, decreased consciousness
- Age ≥5 years and cooperative

| Component | Range | Score |
|-----------|-------|-------|
| Eye opening | 1–4 | Spontaneous(4), To sound(3), To pressure(2), None(1) |
| Verbal | 1–5 | Oriented(5), Confused(4), Words(3), Sounds(2), None(1) |
| Motor | 1–6 | Obeys(6), Localises(5), Withdraws(4), Flexion(3), Extension(2), None(1) |

**Total GCS:** 3–15

### AVPU Fallback

| Response | Interpretation | Tier Hook |
|----------|---------------|-----------|
| A — Alert | Normal | No action |
| V — Voice | Responds to voice | NEWS2/CNS = 2 |
| P — Pain | Responds to pain only | NEWS2/CNS = 3; minimum P2 |
| U — Unresponsive | No response | NEWS2/CNS = 3; minimum P1 |

### GCS Tier Mapping

| GCS | Tier | Context Override |
|-----|------|----------------|
| 3–8 | **P1** | — |
| 9–12 | **P2** | Head injury → P1 regardless |
| 13 | **P3** | With neuro deficit → P2 |
| 14 | **P4** | Head injury → P2 |
| 15 | **P5** | Head injury → P4 minimum |

---

## 7. Section D — Chief Complaint & History

| ID | Item | Input | Branching |
|----|------|-------|-----------|
| D1 | Main problem | Chip grid (18 options) | Determines Section E |
| D2 | Onset | <1h / 1–6h / 6–24h / 1–3d / >3d | Time sensitivity |
| D3 | Trend | Getting worse / Same / Getting better | Trajectory |
| D4 | Similar before? | Y/N | Risk factor |
| D5 | Current medications | Multi-select + other | Drug interactions |
| D6 | Allergies | Multi-select + other | Anaphylaxis risk |

### D1 Chip Grid Options

| # | Complaint | E-Section | Special Handling |
|---|-----------|-----------|----------------|
| 1 | Fever | E-Fever | Include sepsis screen |
| 2 | Breathing difficulty | E-Breath | Peak flow if asthma known |
| 3 | Chest pain | E-Chest | Cardiac risk stratification |
| 4 | Abdominal pain | E-Abdo | Ectopic pregnancy if F 12–55y |
| 5 | Vomiting/diarrhoea | E-GI | Dehydration assessment |
| 6 | Sore throat | E-Airway | Epiglottitis screen |
| 7 | Ear pain | E-ENT | — |
| 8 | Eye problem | E-Eye | Chemical exposure → P1 |
| 9 | Skin/rash | E-Skin | Urticaria + airway → P1 |
| 10 | Wound/burn | H-Burn | Burn module |
| 11 | Headache | E-Neuro | Thunderclap → P1; meningism → P1 |
| 12 | Weakness/numbness | E-Neuro | FAST screen |
| 13 | Urinary problem | E-GU | Sepsis if fever + UTI symptoms |
| 14 | Pregnancy-related | E-OB | Ectopic, pre-eclampsia screens |
| 15 | Injury/trauma | E-Trauma | Mechanism, head injury |
| 16 | Poisoning/overdose | E-Tox | Toxidrome recognition |
| 17 | Mental health crisis | E-Psych | Suicide risk, self-harm |
| 18 | Other | E-Generic | Minimal probe set |

---

## 8. Section E — Complaint-Driven Probes & Scoring

Each branch has 2–6 targeted questions with **scored outputs** that map to tier hints.

### E-Chest Pain (Adult)

| ID | Question | Input | Score Impact |
|----|----------|-------|--------------|
| E-C1 | Radiation to arm, jaw, or back? | Y/N | Y = +2 |
| E-C2 | Worse with exertion? | Y/N | Y = +1 |
| E-C3 | Associated sweating, nausea, or vomiting? | Y/N | Y = +1 |
| E-C4 | Tearing pain to back? | Y/N | Y = +3 (aortic dissection) |
| E-C5 | Known CAD or risk factors (smoking, diabetes, HTN)? | Multi | Each = +1 |

**Chest Pain Tier Map:**

| Score | Tier | Trigger |
|-------|------|---------|
| ≥4 | **P2** | "High-risk chest pain" |
| ≥6 | **P1** | "Suspected ACS or aortic dissection" |
| With E-C4 = Y | **P1** | Regardless of other score |

### E-Breathing Difficulty

| ID | Question | Input | Score Impact |
|----|----------|-------|--------------|
| E-B1 | Cannot speak full sentences? | Y/N | Y = +3 |
| E-B2 | History of asthma/COPD? | Y/N | Y = +0 (context only) |
| E-B3 | Using accessory muscles / tripod position? | Y/N | Y = +3 |
| E-B4 | New confusion with breathlessness? | Y/N | Y = +2 (hypercapnia) |
| E-B5 | Chest pain with breathing? | Y/N | Y = +1 |

**Breathing Tier Map:**

| Score | Tier | Trigger |
|-------|------|---------|
| ≥3 | **P2** | "Severe respiratory distress" |
| ≥6 | **P1** | "Life-threatening asthma/COPD" |

### E-Fever

| ID | Question | Input | Score Impact |
|----|----------|-------|--------------|
| E-F1 | Temp ≥39°C measured? | Y/N | Y = +1 |
| E-F2 | Rash that doesn't fade with glass press? | Y/N | Y = +3 (meningococcaemia) |
| E-F3 | Stiff neck or photophobia? | Y/N | Y = +3 (meningitis) |
| E-F4 | Recent travel to malaria/dengue area? | Y/N | Y = +1 |
| E-F5 | Immunocompromised? | Y/N | Y = +2 |

**Fever Tier Map:**

| Score | Tier | Trigger |
|-------|------|---------|
| ≥3 | **P2** | "Fever with concerning features" |
| ≥5 | **P1** | "Suspected meningitis or meningococcaemia" |

### E-Headache

| ID | Question | Input | Score Impact |
|----|----------|-------|--------------|
| E-H1 | Sudden onset ("thunderclap")? | Y/N | Y = +3 (SAH) |
| E-H2 | Worst headache ever? | Y/N | Y = +2 |
| E-H3 | With fever and stiff neck? | Y/N | Y = +3 (meningitis) |
| E-H4 | With weakness, numbness, or vision change? | Y/N | Y = +2 |
| E-H5 | During pregnancy or postpartum? | Y/N | Y = +2 (pre-eclampsia, CVT) |
| E-H6 | On anticoagulants or bleeding disorder? | Y/N | Y = +2 |

**Headache Tier Map:**

| Score | Tier | Trigger |
|-------|------|---------|
| ≥3 | **P2** | "Thunderclap or focal neurology" |
| ≥5 | **P1** | "Suspected SAH or CNS infection" |

### E-Abdominal Pain

| ID | Question | Input | Score Impact |
|----|----------|-------|--------------|
| E-A1 | Rigid or guarded abdomen? | Y/N | Y = +3 (peritonitis) |
| E-A2 | Vomiting with no flatus/stool? | Y/N | Y = +2 (obstruction) |
| E-A3 | Blood in vomit or black stool? | Y/N | Y = +2 (GI bleed) |
| E-A4 | Pregnant? (if F 12–55y) | Y/N + weeks | Y = +3 if ectopic risk |
| E-A5 | Severe testicular pain? | Y/N | Y = +2 (torsion) |

**Abdo Tier Map:**

| Score | Tier | Trigger |
|-------|------|---------|
| ≥3 | **P2** | "Surgical abdomen suspected" |
| ≥5 | **P1** | "Peritonitis or ectopic pregnancy" |

### E-Psychiatric Crisis

| ID | Question | Input | Score Impact |
|----|----------|-------|--------------|
| E-P1 | Active suicidal thoughts with plan? | Y/N | Y = +3 |
| E-P2 | Self-harm in last 24 hours? | Y/N | Y = +3 |
| E-P3 | Psychosis with danger to others? | Y/N | Y = +3 |
| E-P4 | Severe agitation requiring restraint? | Y/N | Y = +2 |

**Psych Tier Map:**

| Score | Tier | Trigger |
|-------|------|---------|
| ≥3 | **P2** | "Mental health crisis — safety priority" |
| ≥6 | **P1** | "Immediate safety risk" |

---

## 9. Section F — Sepsis Screen (NEW)

All patients with fever, suspected infection, or immunocompromise **must** complete.

| ID | Item | Input | Hook |
|----|------|-------|------|
| F1 | Suspected or confirmed infection? | Y/N | Gate to rest of screen |
| F2 | Altered mental status (confused, drowsy, not normal)? | Y/N | qSOFA/pedSIRS |
| F3 | Respiratory rate ≥22/min (adult) or age-adjusted high? | Y/N | qSOFA/pedSIRS |
| F4 | Systolic BP ≤100 mmHg (adult) or age-adjusted low? | Y/N | qSOFA/pedSIRS |
| F5 | Age ≥65 years? | Y/N | Risk factor |
| F6 | Immunocompromised? | Y/N | Risk factor |
| F7 | Temperature <36°C or >38.5°C? | Y/N | SIRS criterion |

### qSOFA (Adult ≥16 years)

| Criterion | Points |
|-----------|--------|
| Altered mental status | 1 |
| RR ≥22/min | 1 |
| SBP ≤100 mmHg | 1 |

**qSOFA Tier Map:**

| qSOFA | Tier | Action |
|-------|------|--------|
| ≥2 | **P1** | "Suspected sepsis — immediate antibiotics" |
| 1 | **P2** | "Possible sepsis — reassess in 15 min" |

### pedSIRS (1–15 years)

| Criterion | Points |
|-----------|--------|
| Temp >38.5°C or <36°C | 1 |
| HR > age 95th percentile | 1 |
| RR > age 95th percentile | 1 |
| WBC not available (skip) | — |

**pedSIRS Tier Map:**

| pedSIRS | Tier | Action |
|---------|------|--------|
| ≥2 + suspected infection | **P1** | "Pediatric sepsis — immediate" |
| 1 + suspected infection | **P2** | "Possible sepsis — close observation" |

---

## 10. Section G — Skin Classifier (Optional)

| ID | Item | Input | Output |
|----|------|-------|--------|
| G1 | Take photo of skin problem? | Camera/gallery | — |
| G2 | Classifier output | Auto | Class + confidence |

### Skin Tier Map

| Class | Confidence | Tier | Action |
|-------|-----------|------|--------|
| Normal/benign | ≥90% | P5 | Reassure |
| Benign, monitor | ≥90% | P4 | Watch |
| Suspicious | Any | P3 | Review |
| Urgent (cellulitis, abscess) | ≥70% | P2 | Treat |
| Emergency (nec fasc, meningococcaemia) | ≥50% | **P1** | Immediate |

**Fail-closed:** Classifier unavailable, low confidence, or error → **ignore classifier**, proceed with questionnaire only.

---

## 11. Section H — Burn Module

Branch if D1 = wound/burn or user opts in.

| ID | Item | Input | Rule Hook |
|----|------|-------|-----------|
| H1 | Cause | Flame/Scald/Chemical/Electrical/Contact/Other | P1 if chemical/electrical |
| H2 | Time since injury | <1h / 1–6h / 6–24h / >24h | Freshness |
| H3 | Body areas (multi-tap) | Body map | Face/airway flag; hands/feet/genitals flag |
| H4 | TBSA estimate | Palm method: entire opened hand including fingers = 1% | Stepper 0–40% |
| H5 | Deepest appearance | Red-blanching / Blistered / White-leathery / Black / Unsure | Depth |
| H6 | Airway signs: hoarseness, soot, singed hairs | Y/N each | P1 if any YES |
| H7 | Circumferential? | Y/N | P1 if full-thickness |
| H8 | Electrical/chemical to eyes or mouth? | Y/N | P1 if YES |

### Burn Tier Rules

| Condition | Tier | Reason |
|-----------|------|--------|
| Any airway sign (H6) | **P1** | Inhalation injury |
| Electrical or chemical cause (H1) | **P1** | Internal injury risk |
| Electrical/chemical to eyes/mouth (H8) | **P1** | Critical structure |
| Circumferential full-thickness (H7 + H5=white/black) | **P1** | Compartment risk |
| >10% TBSA (child <16y) | **P2** | Fluid resuscitation threshold |
| >20% TBSA (adult ≥16y) | **P2** | Fluid resuscitation threshold |
| Full-thickness >1% any location | **P2** | Burn center |
| Face, hands, feet, genitals, major joints | **P2** | Functional/cosmetic risk |
| Any burn + age <5 or >60 | **P2** (bump from P3/P4) | Vulnerable population |
| <5% TBSA, partial thickness, no risk areas | **P4** | Outpatient possible |
| Superficial only, <1% | **P5** | Self-care |

---

## 12. Section I — Modifiers

| ID | Item | Input | Bump? | Condition |
|----|------|-------|-------|-----------|
| I1 | Age | Stepper (years; <1 in months) | Y | <5y or >65y |
| I2 | Sex | M/F | — | — |
| I3 | Pregnant? (if F 12–55y) | Y/N/unsure + weeks | Y | Any pregnancy; 2nd/3rd trimester; any complication |
| I4 | Immunocompromised? | Y/N/unsure | Y | HIV/AIDS, chemo, steroids >20mg prednisolone, transplant |
| I5 | MUAC (if <5y) | Tape measure | Y | <11.5 cm (severe malnutrition) |
| I6 | CFS (if ≥65y) | 1–7 pictorial | Y | ≥5 (moderately frail+) |
| I7 | COPD/CO₂ retention? | Y/N | — | Drives NEWS2 Scale 2 |

### Modifier Bump Rules

- One tier bump per qualifying modifier
- Maximum bump: to P1 (cannot exceed P1)
- Multiple modifiers: single bump only (do not stack)
- Bump applied **after** max() merge

| Modifier | Bump To | Cap |
|----------|---------|-----|
| Age <5 or >65 | +1 tier | P1 |
| Pregnancy (any) | +1 tier | P1 |
| Immunocompromised | +1 tier | P1 |
| MUAC <11.5 cm | +1 tier | P1 |
| CFS ≥5 | +1 tier | P1 |

---

## 13. Merge Logic: Cross-Scale Integration

### Pseudocode (Dart)

```dart
enum Tier implements Comparable<Tier> {
  p1(1, "Emergency", "Immediate", 0xFFD32F2F),
  p2(2, "Very Urgent", "≤10 min", 0xFFF57C00),
  p3(3, "Urgent", "≤30–60 min", 0xFFFBC02D),
  p4(4, "Standard", "≤2 h", 0xFF388E3C),
  p5(5, "Minor", "≤4 h", 0xFF1976D2);

  final int urgency;      // Lower = more urgent
  final String label;
  final String responseTime;
  final int color;

  const Tier(this.urgency, this.label, this.responseTime, this.color);

  @override
  int compareTo(Tier other) => urgency.compareTo(other.urgency);

  bool isMoreUrgentThan(Tier other) => urgency < other.urgency;
  Tier bump() => Tier.values.firstWhere(
    (t) => t.urgency == (urgency - 1).clamp(1, 5),
    orElse: () => this,
  );
}

class TriageResult {
  final Tier tier;
  final List<String> reasons;
  final Map<String, dynamic> allScores;
  final DateTime timestamp;
  final bool vitalReviewRequired;

  TriageResult({
    required this.tier,
    required this.reasons,
    required this.allScores,
    required this.timestamp,
    this.vitalReviewRequired = false,
  });
}

TriageResult computeTier1(TriageInput t) {
  final reasons = <String>[];
  
  // === 1. EMERGENCY GATES ===
  if (t.dangerSigns.anyYes) {
    final triggered = t.dangerSigns.triggeringItems;
    return TriageResult(
      tier: Tier.p1,
      reasons: ["Danger gate: ${triggered.join(', ')}"],
      allScores: {'gate': triggered},
      timestamp: DateTime.now(),
    );
  }

  // === 2. AGE BRANCHING ===
  final ScaleType scale = t.ageBracket.scale;
  
  // === 3. VITAL SIGNS SCORE ===
  final ScoredTier vitalTier = switch (scale) {
    ScaleType.news2 => news2Band(t.vitals, t.hasCopd),
    ScaleType.pedsNews2 => pedsNews2Band(t.vitals, t.ageMonths),
    ScaleType.neonatalPews => neonatalPewsBand(t.vitals),
  };
  reasons.add("Vitals: ${vitalTier.score} → ${vitalTier.tier.label}");

  // === 4. CONSCIOUSNESS SCORE ===
  final ScoredTier gcsTier = gcsBand(t.gcs, context: t.chiefComplaint);
  reasons.add("GCS: ${gcsTier.score} → ${gcsTier.tier.label}");

  // === 5. COMPLAINT-DRIVEN SCORE ===
  final ScoredTier complaintTier = complaintDrivenTier(t.chiefComplaint, t.probeAnswers);
  if (complaintTier.tier != Tier.p5) {
    reasons.add("Complaint: ${t.chiefComplaint} → ${complaintTier.tier.label}");
  }

  // === 6. SEPSIS SCREEN ===
  final ScoredTier sepsisTier = sepsisScreen(t.sepsisAnswers, t.ageBracket);
  if (sepsisTier.tier.isMoreUrgentThan(Tier.p5)) {
    reasons.add("Sepsis screen: ${sepsisTier.score} → ${sepsisTier.tier.label}");
  }

  // === 7. BURN MODULE ===
  final ScoredTier burnTier = t.isBurn ? burnRule(t.burn!) : ScoredTier(Tier.p5, null, "N/A");
  if (burnTier.tier.isMoreUrgentThan(Tier.p5)) {
    reasons.add("Burn: ${burnTier.reason}");
  }

  // === 8. SKIN CLASSIFIER ===
  final ScoredTier skinTier = t.skinResult ?? ScoredTier(Tier.p5, null, "No image");
  
  // === 9. MAX() MERGE ===
  final candidates = [vitalTier, gcsTier, complaintTier, sepsisTier, burnTier, skinTier];
  var merged = candidates.reduce((a, b) => a.tier.isMoreUrgentThan(b.tier) ? a : b);
  
  // === 10. MODIFIER BUMP ===
  if (t.modifiers.requiresBump && merged.tier != Tier.p1) {
    final preBump = merged.tier;
    merged = ScoredTier(merged.tier.bump(), merged.score, merged.reason);
    reasons.add("Modifier bump: $preBump → ${merged.tier} (${t.modifiers.active.join(', ')})");
  }

  // === 11. SAFETY CHECKS ===
  bool vitalReview = false;
  if (t.vitals.hasPhysiologicallyImpossibleValue) {
    vitalReview = true;
    reasons.add("WARNING: Physiologically impossible vital — clinician review required");
  }
  if (t.vitals.anyMissing && merged.tier.isMoreUrgentThan(Tier.p3)) {
    vitalReview = true;
    reasons.add("WARNING: Missing vitals with high tier — review required");
  }

  return TriageResult(
    tier: merged.tier,
    reasons: reasons,
    allScores: {
      'vital': vitalTier.toJson(),
      'gcs': gcsTier.toJson(),
      'complaint': complaintTier.toJson(),
      'sepsis': sepsisTier.toJson(),
      'burn': burnTier.toJson(),
      'skin': skinTier.toJson(),
      'merged': merged.tier.urgency,
      'modifiers': t.modifiers.toJson(),
    },
    timestamp: DateTime.now(),
    vitalReviewRequired: vitalReview,
  );
}
```

---

## 14. Tier Mapping & Response Targets

### Final Tier Definitions

| Tier | Label | Response Time | Clinical Meaning | Color |
|------|-------|---------------|------------------|-------|
| **P1** | Emergency | Immediate | Life-threatening; resuscitation bay | 🔴 Red |
| **P2** | Very Urgent | ≤10 min | Serious illness/injury; monitored area | 🟠 Orange |
| **P3** | Urgent | ≤30–60 min | Significant problem; semi-urgent area | 🟡 Yellow |
| **P4** | Standard | ≤2 h | Non-urgent; routine waiting area | 🟢 Green |
| **P5** | Minor | ≤4 h | Self-limiting; minor area or advice | 🔵 Blue |

### Cross-Scale Tier Mapping Summary

| Scale/Module | P1 Threshold | P2 Threshold | P3 Threshold | P4 Threshold | P5 |
|-------------|--------------|--------------|--------------|--------------|-----|
| NEWS2 (adult) | ≥7 or any=3 | 5–6 | 3–4 | 1–2 | 0 |
| Peds-NEWS2 | ≥7 or any=3 | 5–6 | 3–4 | 1–2 | 0 |
| Neonatal PEWS | ≥4 | 2–3 | 1 | 0 | — |
| GCS | 3–8 | 9–12 | 13+deficit | 14 | 15 |
| Complaint-driven | Branch-specific | Branch-specific | Branch-specific | — | Default |
| Sepsis (qSOFA) | ≥2 | 1 | — | — | 0 |
| Sepsis (pedSIRS) | ≥2+infection | 1+infection | — | — | 0 |
| Burn | See H rules | See H rules | — | Minor burns | Superficial only |
| Skin | Emergency class | Urgent class | Suspicious | Benign | Normal |

---

## 15. Output Specification

### Screen Display

```
┌─────────────────────────────────────┐
│  [TIER BANNER: color + label]       │
│  P2 — Very Urgent (≤10 min)         │
├─────────────────────────────────────┤
│  Reason chips:                      │
│  • Vitals: 6 → P2                   │
│  • Complaint: Chest pain → P2         │
│  • Modifier bump: P2 → P1 (Age >65)   │
├─────────────────────────────────────┤
│  [Response time hint]               │
│  Expected: Within 10 minutes        │
├─────────────────────────────────────┤
│  [All scores expand/collapse]       │
│  NEWS2: 6 | GCS: 15 | qSOFA: 1     │
├─────────────────────────────────────┤
│  ⚠️ DECISION SUPPORT ONLY           │
│  Final clinical decision by         │
│  qualified healthcare professional  │
├─────────────────────────────────────┤
│  [Generate Tier 2 Summary]          │  ← Active if device capable
│  [Edit Responses] [Start Over]      │
└─────────────────────────────────────┘
```

### Stored Record (JSON)

```json
{
  "triageId": "uuid",
  "timestamp": "2026-09-05T14:30:00Z",
  "version": "2.0",
  "finalTier": {"tier": "P1", "urgency": 1, "label": "Emergency"},
  "contributingScores": {
    "news2": {"score": 6, "tier": "P2", "components": {"rr": 2, "spo2": 0, "sbp": 1, "hr": 2, "temp": 0, "avpu": 1}},
    "gcs": {"score": 15, "tier": "P5", "assumed": false},
    "complaint": {"branch": "chest_pain", "score": 4, "tier": "P2"},
    "sepsis": {"qsofa": 1, "tier": "P2"},
    "burn": null,
    "skin": null
  },
  "modifiers": {"age": 72, "cfs": 6, "bumpApplied": true},
  "mergeReasons": [
    "Vitals: 6 → P2",
    "Complaint: Chest pain → P2",
    "Modifier bump: P2 → P1 (Age >65, CFS 6)"
  ],
  "gates": {"passed": false, "triggered": []},
  "safetyFlags": ["vitalReviewRequired": false],
  "inputs": { /* full input record */ }
}
```

---

## 16. Tier 2 Payload

Structured JSON sent to MedGemma:

```json
{
  "triageContext": {
    "tier1Result": "P1",
    "tier1Reasons": ["..."],
    "allScores": { /* as above */ }
  },
  "patientSummary": {
    "age": 72, "sex": "M", "pregnant": false,
    "chiefComplaint": "Chest pain",
    "onset": "1h", "trend": "worsening"
  },
  "vitals": {"rr": 24, "spo2": 94, "sbp": 105, "hr": 115, "temp": 37.2, "avpu": "A"},
  "consciousness": {"gcs": 15, "avpu": "A"},
  "probeAnswers": {"chest_radiation": true, "chest_sweating": true, "cad_history": true},
  "sepsisScreen": {"suspectedInfection": false, "qsofa": 1},
  "modifiers": ["age>65", "cfs>=5"],
  "instruction": "Provide SOAP narrative. ESCALATION ONLY: you may raise tier, never lower. If you disagree with P1, state why but maintain P1. Include differential diagnosis and recommended immediate actions."
}
```

---

## 17. Validation & Calibration

### Vignette Battery (Phase 5)

| Category | Count | Purpose |
|----------|-------|---------|
| Gate triggers | 15 | Each danger sign A1–A15 |
| NEWS2 boundaries | 10 | Score 0,1,2,3,4,5,6,7,10,15 |
| Peds-NEWS2 boundaries | 10 | Per age bracket |
| GCS boundaries | 8 | 3,5,8,9,12,13,14,15 |
| Complaint branches | 18 | One per D1 option |
| Sepsis variants | 6 | qSOFA 0,1,2,3; pedSIRS variants |
| Burn scenarios | 8 | Airway, chemical, electrical, TBSA thresholds |
| Modifier interactions | 10 | Each modifier + boundary cases |
| Merge edge cases | 10 | Tie-breaking, multiple P1s, bump caps |
| Negative cases | 10 | Normal findings, should be P5 |

**Total: 105 vignettes minimum**

### Clinician Review Process

1. 2+ independent clinicians label expected tier per vignette
2. App output compared: match = pass; app more conservative = pass with note; app less conservative = **fail**
3. Target: ≥95% safe triage (app tier ≥ clinician tier)
4. Target undertriage rate: <5% (vs MTS gold standard)

### Retrospective Validation

If local ED dataset available:
- Compare app tier vs actual disposition, mortality, ICU admission
- Calculate AUROC for each outcome
- Benchmark against NEWS2-only, REMS-only baselines

---

## 18. Safety Architecture

### Fail-Closed States

| Component | Failure | Safe State |
|-----------|---------|------------|
| Skin classifier | Not loaded / confidence <50% | Ignore; text-only triage |
| GCS incomplete | <3 components entered | Use AVPU; if AVPU unclear, assume P |
| Vitals missing | Any of B1–B7 missing | Cannot compute NEWS2; use danger gates + complaint only; **minimum P3** |
| Age missing | Not entered | Assume adult thresholds (most conservative for vitals) |
| MedGemma unavailable | Timeout / OOM | Tier 1 result stands; show "offline mode" |
| Calculation overflow | Impossible vitals entered | Flag "VITAL_REVIEW_REQUIRED"; tier from available data |

### Guardrails

1. **"Decision support — clinician decides"** banner on every output
2. **No medication dosing** in Tier 1
3. **No diagnosis** — only triage urgency + differentials for Tier 2
4. **Time stamp** all decisions; auto-reassess prompt at 15 min for P2, 30 min for P3
5. **Override button** for clinician: any tier can be manually overridden with reason capture

---

## 19. Implementation Phases

| Phase | Work | Exit Criterion | Regulatory |
|-------|------|---------------|------------|
| 1 | Data models + all scoring fns (NEWS2, Peds-NEWS2, PEWS, GCS, complaint, sepsis, burn) as pure Dart; unit tests | All unit tests pass; 100% branch coverage for scoring | IEC 62304 software plan; Class B designation |
| 2 | Questionnaire UI (Sections A–I); age-aware branching; offline-first; local encrypted store | Complete walkthrough on Windows; time-to-complete ≤3 min; tap count ≤35 | Usability test (n≥5) |
| 3 | Burn + modifier rules; merge engine; reason chips; safety flags | 105-vignette edge case table; all pass | Risk management file (ISO 14971) |
| 4 | Tier 2 prompt wiring; escalation-only enforcement; MedGemma integration | Demo for 20 vignettes; zero downgrades | Clinical Evaluation Plan (MDCG 2020-1) |
| 5 | Calibration: clinician review of vignette set; threshold tuning; prospective pilot | Signed-off thresholds; inter-rater κ ≥0.7 | Clinical validation report |
| 6 | Android build; field-usability; RAM/latency test | APK debug build; ≤1s Tier 1 latency; ≤4GB RAM for Tier 2 | Post-market surveillance plan |
| 7 | Regulatory submission prep; technical documentation; cybersecurity review | CE marking readiness; IEC 62304 audit pass | Notified Body engagement |

---

## 20. Appendices

### Appendix A: NEWS2 Reference

- Royal College of Physicians. National Early Warning Score (NEWS) 2. 2017.
- Goodacre et al. Accuracy of NEWS2 in predicting time-critical treatment. *EMJ* 2025. DOI: 10.1136/emermed-2024-214562

### Appendix B: Pediatric Vital Signs

- Royal College of Paediatrics and Child Health. PEWS standards. 2021.
- Geanacopoulos et al. Pediatric triage accuracy. *Hosp Pediatr* 2024. DOI: 10.1542/hpeds.2024-008063

### Appendix C: Sepsis

- UK Sepsis Trust. Adult and Paediatric Sepsis Screening and Action Tools. 2023.
- Singer et al. The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). *JAMA* 2016;315(8):801-810.

### Appendix D: Burn Care

- American Burn Association. Advanced Burn Life Support (ABLS) Course Provider Manual. 2022.
- NSW Health. Major Burns Clinical Practice Standard. 2025.

### Appendix E: Regulatory

- EU MDR 2017/745, Annex VIII Rule 11
- MDCG 2019-11 Rev.1: Guidance on Qualification and Classification of Software
- IEC 62304:2006+A1:2015 Medical device software — Software life cycle processes
- ISO 14971:2019 Medical devices — Application of risk management

---

*Document owner: Clinical Safety Lead*  
*Review cycle: Every 6 months or after any threshold change*  
*Approval: Clinical Director + Software Safety Engineer*

---

## 21. Missing Vital Signs Policy (SpO₂ / Temperature — Hybrid Approach)

**Date:** 2026-09-05  
**Status:** Draft for Clinical Review — see §21.11 for open items  
**Supersedes/extends:** §18 Fail-Closed "Vitals missing" row and §13 pseudocode `anyMissing` handling  
**Decision record:** `docs/DECISIONS.md` → ADR-008

### 21.1 Problem Statement

In rural and low-resource settings, a **pulse oximeter (SpO₂)** or **thermometer** may be unavailable even when other vitals (RR, HR, BP, AVPU) are measurable. The current fail-closed row in §18 treats *any* missing vital as "cannot compute NEWS2 → gates + complaint only → minimum P3". This is conservative but has two defects:

1. **Data waste / under-triage risk.** A partial NEWS2 computed from RR/HR/BP/AVPU that are grossly abnormal is discarded entirely. A patient with measured RR 28, HR 130, BP 90 but no oximeter could be scored P3 (from incomplete-data floor) instead of P1 (from present abnormal parameters).
2. **No per-parameter nuance.** Missing SpO₂ and missing temperature create *different* unanswerable questions (hypoxia vs fever/hypothermia) and demand *different* compensating rules. The spec currently treats them identically.

### 21.2 Design Principles (in addition to §1)

| # | Principle | Rationale |
|---|-----------|-----------|
| 8 | **Partial scoring, not all-or-nothing.** Score NEWS2 from all *present* parameters; never discard measured abnormal values because one parameter is missing. | Prevents under-triage from data waste |
| 9 | **Missing ≠ normal.** A missing parameter is never scored as 0 (normal); it is either *not scored (flagged)* or *substituted conservatively* when there is contextual concern. | Prevents silent normal-assumption |
| 10 | **Context-assisted substitution.** When clinical context suggests the missing parameter would be abnormal, substitute a conservative abnormal score. | Recovers signal lost to the missing measurement |
| 11 | **Incomplete data never yields the lowest tiers.** Any missing vital forces a tier floor and a mandatory clinician-review flag. | Preserves §1 principle 5 (fail-closed) |

### 21.3 Definitions

| Term | Meaning |
|------|---------|
| **Complete data** | All of B1–B7 entered and valid |
| **Partial data** | ≥1 of B1–B7 missing/invalid |
| **Missing parameter** | Not entered, or marked "unavailable" by the user |
| **Invalid parameter** | Entered outside the physiological range (§18 overflow row) — treated as missing AND flagged `VITAL_REVIEW_REQUIRED` |
| **Substitution score** | A synthetic NEWS2 score applied to a missing parameter *only when a concerning context exists* (§21.4/§21.5) |
| **Concerning context** | Complaint/probe/modifier signals that make the missing parameter likely abnormal (§21.4/§21.5 lists) |

### 21.4 General Rules (applies to any missing vitals parameter)

1. **Danger gates (§4) bypass everything.** A triggered gate is P1 regardless of vital completeness.
2. **Compute partial NEWS2** from all present parameters using the normal scoring tables (§5). Each present parameter that scores 3 still fires the **single-parameter escalation** (§5.1) — a present RR 28 alone forces P1 and is *not* diluted by a missing SpO₂.
3. **Record provenance.** Stored record gains `missingParams[]`, `substitutionApplied{}`, and `vitalReviewRequired: true` whenever ≥1 parameter is missing (see §21.8).
4. **Tier floor.** When ≥1 vital is missing, the vital tier can never be lower (less urgent) than **P3**, regardless of partial score. Rationale: a partial score cannot prove a patient is low-risk.
   - Neonatal floor (§5.3, minimum P4 by age) is overridden upward by this floor: neonate + missing vitals → P3.
5. **`vitalReviewRequired` flag** is always set when any vital is missing — the output banner must show "Incomplete vitals — clinical review required" even when other scores are reassuring.
6. **Substitution only ever raises, never lowers**, the partial score.
7. **Interaction with §13 merge.** Substitution scores feed the vital tier *before* the max() merge. The §13 safety check `anyMissing && merged > P3 → review` is relaxed to simply **always** set `vitalReviewRequired` on `anyMissing` (the P3 floor is now enforced in the vital tier itself).

### 21.5 SpO₂-Specific Handling (B2)

#### 21.5.1 Concern list (triggers substitution)

A "respiratory concern context" exists if **any** of the following is true:

| Trigger | Source |
|---------|--------|
| Chief complaint = breathing difficulty (D1 #2) | D |
| Respiratory rate present and scores ≥2 (RR ≤11 or ≥21 adult; age-adjusted equivalent pediatric) | B1 |
| E-B1 "cannot speak full sentences" = YES | E-Breath |
| E-B3 "accessory muscles / tripod" = YES | E-Breath |
| Danger sign A4 (stridor) or A5 (severe breathing difficulty) = YES | A |
| On supplemental oxygen (B6 = YES) or home O₂/COPD history (B8/I7) | B, I |
| Cyanosis observed (to be added as E-B probes if confirmed in review) | E-Breath (proposed) |

#### 21.5.2 Substitution rule

| Scenario | Substituted SpO₂ score | Effect |
|----------|------------------------|--------|
| SpO₂ missing + respiratory concern present | **3** (worst band, ≤91%) | May trigger single-parameter escalation → P1 (via §5.1) |
| SpO₂ missing + no respiratory concern | **not scored** | Excluded from aggregate; flagged; P3 floor still applies |

> Note: an explicit "SpO₂ measured?" question precedes all of this. Only *confirmed-unavailable* SpO₂ enters the substitution path.

### 21.6 Temperature-Specific Handling (B5)

#### 21.6.1 Concern list (triggers substitution)

A "temperature concern context" exists if **any** of the following is true:

| Trigger | Source |
|---------|--------|
| Chief complaint = fever (D1 #1) or chills/rigors reported | D, E-Fever |
| Sepsis screen engaged: F1 suspected infection = YES | F |
| Immunocompromised modifier (I4 = YES) | I |
| Extremes of age: <1 year or ≥65 years | I |
| E-F1 "measured temp ≥39°C" answered YES despite missing field | E-Fever |
| Exposure concern: hypothermia risk (elderly, cold exposure, submersion) — recorded manually | E-Generic |

#### 21.6.2 Substitution rule

| Scenario | Substituted temp score | Effect |
|----------|------------------------|--------|
| Temp missing + concern present | **3** (conservative worst-case) | May trigger single-parameter escalation → P1 |
| Temp missing + no concern | **not scored** | Excluded; flagged; P3 floor applies |

> Asymmetry note: in NEWS2, hyperthermia ≥39.1°C scores only 2, while hypothermia ≤35.0°C scores 3. The substitution score of 3 is deliberately the *most conservative* across both directions. Clinical review (§21.11) may refine to 2 when the specific concern is hyperthermia/fever only.

### 21.7 Combined Missing SpO₂ + Temperature

If both parameters are missing, both substitution rules apply independently and **sum** into the partial score (up to +6 theoretical). Because this scenario also disables the two most sepsis-critical red flags, the **sepsis screen (§9) is mandatory** (not optional) when both B2 and B5 are missing, and `vitalReviewRequired` is set with the reason `"SpO₂ and temperature unavailable — cannot exclude hypoxia or fever"`.

### 21.8 Implementation (extended pseudocode)

```dart
/// Extends §13 computeTier1 — replaces the vitals scoring step (step 3).

enum MissingVitalStatus { present, missing, invalid }

const Tier kMissingVitalsFloor = Tier.p3; // §21.4 rule 4

class _VitalPolicyInput {
  final TriageInput t;
  final Vitals v;
}

({int score, Map<String, int> present, List<String> missing,
  Map<String, int> substituted, bool substituteApplied}) scoreVitals(TriageInput t) {
  final present = <String, int>{};
  final missing = <String>[];
  final substituted = <String, int>{};
  var score = 0;

  // --- present parameters scored normally (NEWS2 / Peds-NEWS2 / PEWS) ---
  void add(String name, int s) { present[name] = s; score += s; }

  // (per age bracket scoring from §5, unchanged)
  if (t.vitals.rr != null) add('rr', rrScore(t));
  if (t.vitals.sbp != null) add('sbp', sbpScore(t));
  if (t.vitals.hr != null) add('hr', hrScore(t));

  // --- missing-handling for the two critical parameters ---
  final spo2Missing = t.vitals.spo2 == null;
  final tempMissing = t.vitals.temp == null;
  if (spo2Missing) {
    final sub = hasRespiratoryConcern(t) ? 3 : null; // §21.5.2
    if (sub != null) { substituted['spo2'] = sub; score += sub; }
    missing.add('spo2');
  } else {
    add('spo2', spo2Score(t));
  }
  if (tempMissing) {
    final sub = hasTemperatureConcern(t) ? 3 : null; // §21.6.2
    if (sub != null) { substituted['temp'] = sub; score += sub; }
    missing.add('temp');
  } else {
    add('temp', tempScore(t));
  }

  // (AVPU / consciousness continues on its own branch per §13 step 4)
  return (score: score, present: present, missing: missing,
          substituted: substituted, substituteApplied: substituted.isNotEmpty);
}

/// Wraps the per-scale band with the missing-vitals floor (replaces §13 step 3).
ScoredTier vitalTierWithMissingPolicy(TriageInput t) {
  final r = scoreVitals(t);

  // Single-parameter escalation first (a present/substituted score of 3).
  var tier = anyParameterScoredThree(r.present, r.substituted)
      ? tierForSingleParamThree(t.complaint.api)
      : bandFromScore(r.score, t.ageBracket.scale); // §5 tier maps

  // Fail-closed floor: never below P3 when vitals are incomplete.
  if (r.missing.isNotEmpty) {
    tier = tier.isMoreUrgentThan(kMissingVitalsFloor) ? tier : kMissingVitalsFloor;
  }

  return ScoredTier(tier, r.score, 'Vitals ${r.score} → ${tier.label}'
      '${r.missing.isNotEmpty ? ' (missing: ${r.missing.join(', ')})' : ''}');
}

bool hasRespiratoryConcern(TriageInput t) => /* §21.5.1 list */;
bool hasTemperatureConcern(TriageInput t) => /* §21.6.1 list */;
```

Safety-check update (§13 step 11):

```dart
vitalReview = t.vitals.hasPhysiologicallyImpossibleValue ||
              t.vitals.anyMissing; // any incomplete data → review, per §21.4 rule 5
```

### 21.9 Stored Record Addition

```json
{
  "contributingScores": {
    "news2": {
      "score": 5,
      "tier": "P3",
      "components": {"rr": 2, "spo2": 3, "sbp": 1, "hr": 2, "temp": null, "avpu": 0},
      "missingParams": ["temp"],
      "substitutionApplied": {"spo2": 3},
      "vitalReviewRequired": true
    }
  },
  "safetyFlags": ["vitalReviewRequired", "incompleteVitalsP3Floor"]
}
```

### 21.10 Validation Additions (extends §17)

| Category | Count | Purpose |
|----------|-------|---------|
| Missing SpO₂ — respiratory concern triggers substitution | 6 | Concern list hits each fire the P1 escalation |
| Missing SpO₂ — no concern stays partial + P3 floor | 4 | Confirm no premature escalation without context |
| Missing temp — fever concern substitution | 4 | Fever/sepsis/immunocompromise paths |
| Missing temp — no concern stays partial + P3 floor | 4 | Confirm floor, no escalation |
| Both missing — sepsis screen mandatory | 3 | Scored behaviour and record flags |
| Neonatal + missing vitals → P3 override | 2 | Cross-scale floor override |
| Invalid (out-of-range) treated as missing+review | 3 | Overflow path |

**Adds ~26 vignettes to the §17 battery (105 → ~131 total).** Criteria unchanged: app tier must be ≥ clinician tier; any under-triage with missing vitals is a release blocker.

### 21.11 Open Items for Clinical Review

1. Confirm the SpO₂ substitution score of 3 vs the concern list granularity — may want 3 for stridor/accessory-muscle/cyanosis, but 2 for "RR mildly elevated" only.
2. Confirm temp substitution default of 3 vs 2 for fever-only concerns (NEWS2 asymmetry noted in §21.6.2).
3. Ratify the **P3 floor** for all missing-vitals cases vs a P4 floor for low-risk complaints. The P3 default matches §18 today; a P4 variant would reduce unnecessary urgent escalation at the cost of fail-closed conservatism.
4. Add cyanosis / chills-rigors to the questionnaire as explicit E-B/E-F probes (currently proposed, not specced).
5. Verify source citations (§21.12) against local tele-triage/remote-monitoring guidelines.

### 21.12 Sources

- Royal College of Physicians. *National Early Warning Score (NEWS) 2.* 2017 — scoring tables and single-parameter escalation that partial scoring relies on.
- Royal College of Physicians. *NEWS2 implementation guidance.* — direction that escalation should still occur from available parameters.
- UK Sepsis Trust. *Adult and Paediatric Sepsis Screening and Action Tools.* 2023 — sepsis screen remains the safety net when SpO₂/temp are unavailable (§21.7).
- Informing the missing-parameter conventions (partial score + floor + context-assisted substitution): remote/tele-triage and CDSS documentation on handling unavailable oximetry/thermometry — **citations to be verified against the relevant guidelines during clinical review (open item 5).**

*Version note: This section is appended as a clinical-review draft. It does not change any published scoring thresholds; it defines how missing SpO₂/temperature inputs are treated.*