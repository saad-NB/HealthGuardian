# Clinical Sources

Every threshold and scoring rule used in Sehat Nigraan must be traceable to a published source. This file is the single source of truth for clinical references.

---

## 1. National Early Warning Score 2 (NEWS2)

**Source:** Royal College of Physicians. *National Early Warning Score (NEWS) 2: Standardising the assessment of acute-illness severity in the NHS.* London: RCP, 2017.

**ISBN:** 978-1-86016-572-6

### Scoring Table (NEWS2 Scale 1 for adults)

| Physiological Parameter | 3 | 2 | 1 | 0 | 1 | 2 | 3 |
|---|---|---|---|---|---|---|---|
| SpO2 Scale 1 (%) | <=91 | 92-93 | 94-95 | >=96 | - | - | - |
| Air or oxygen | - | Oxygen | - | Air | - | - | - |
| Systolic BP (mmHg) | <=90 | 91-100 | 101-110 | 111-219 | - | - | >=220 |
| Heart rate (bpm) | <=40 | - | 41-50 | 51-90 | 91-110 | 111-130 | >=131 |
| Temperature (C) | <=35.0 | - | 35.1-36.0 | 36.1-38.0 | 38.1-39.0 | >=39.1 | - |
| Respiratory rate | <=8 | - | 9-11 | 12-20 | 21-24 | - | >=25 |
| Consciousness | - | - | - | Alert | - | - | Voice/Pain/Unresponsive |

### Clinical Risk Bands

| Aggregate Score | Clinical Risk |
|---|---|
| 0 | Low |
| 1-4 | Low |
| 3 in any single parameter | Low-Medium (trigger response) |
| 5-6 | Medium |
| >=7 | High |

**Implementation:** `lib/config/clinical_thresholds.dart` - `News2Thresholds` class.

---

## 2. Glasgow Coma Scale (GCS)

**Source:** Teasdale, G. & Jennett, B. "Assessment of coma and impaired consciousness: A practical scale." *Lancet*, 304(7872), 81-84, 1974.

**Additional:** Royal College of Surgeons of England. *Guidelines for the Management of Acute Head Injury.* 1984.

### Scoring

| Component | Score | Description |
|---|---|---|
| Eye Opening | 4 | Spontaneous |
| | 3 | To voice |
| | 2 | To pain |
| | 1 | None |
| Verbal Response | 5 | Oriented |
| | 4 | Confused |
| | 3 | Inappropriate words |
| | 2 | Incomprehensible sounds |
| | 1 | None |
| Motor Response | 6 | Obeys commands |
| | 5 | Localizes pain |
| | 4 | Flexion (withdrawal) |
| | 3 | Abnormal flexion |
| | 2 | Extension |
| | 1 | None |

**Total:** 3-15 (3 = deep coma, 15 = fully alert)

### Triage Thresholds

| GCS | Severity | Triage Level |
|---|---|---|
| <=8 | Severe (unable to protect airway) | Emergency |
| 9-13 | Moderate | Urgent |
| 14-15 | Mild | Routine |

**Implementation:** `lib/config/clinical_thresholds.dart` - `GcsThresholds` class.

---

## 3. Burn Injury Assessment

### TBSA (Total Body Surface Area)

**Primary Source:** Wallace, A.B. "The exposure treatment of burns." *Lancet*, 267(6803):501-504, 1951.

**Rule of Nines (adults):**
- Head: 9%
- Each arm: 9%
- Front torso: 18%
- Back torso: 18%
- Each leg: 18%
- Groin: 1%

### ABA Referral Criteria

**Source:** American Burn Association. *Burn Referral Criteria.* (Latest edition.)

| TBSA (adult) | TBSA (pediatric) | Action |
|---|---|---|
| >=20% | >=10% | Emergency transfer to burn center |
| 10-19% | 5-9% | Urgent evaluation |
| <10% | <5% | Routine (with monitoring) |

**Critical locations** (automatic Urgent regardless of TBSA):
- Face, hands, feet, genitalia/perineum
- Circumferential burns
- Burns over major joints

**Implementation:** `lib/config/clinical_thresholds.dart` - `BurnThresholds` class.

---

## 4. Skin Classifier Risk Tiers

**Source:** Internal calibration from MobileNetV3-Large training on SCIN + AZH datasets.

| Risk Tier | Probability Threshold | Triage Level |
|---|---|---|
| Normal | <0.4 | Routine |
| Suspicious | 0.4-0.7 | Urgent |
| High | >0.7 | Emergency |

**Note:** These thresholds require validation against clinical data before deployment. See `docs/MODEL_CARDS/skin_classifier.md`.

**Implementation:** `lib/config/clinical_thresholds.dart` - `SkinClassifierThresholds` class.

---

## 5. Hard Red-Flag Overrides

These are absolute safety nets derived from emergency medicine first-principles. If ANY flag fires, triage is forced to Emergency regardless of aggregate scores.

| Flag | Threshold | Source |
|---|---|---|
| Severe impairment (GCS) | GCS <= 8 | RCS Trauma guidelines |
| Hypotension | SBP <= 90 mmHg | ATLS (Advanced Trauma Life Support) |
| Severe hypoxia | SpO2 <= 91% on room air | BTS Emergency Guidelines |
| Critical respiratory rate | RR <= 8 or >= 25 | RCP NEWS2 |
| Critical heart rate | HR <= 40 or >= 131 | RCP NEWS2 |
| Critical temperature | Temp <= 35.0 or >= 39.1 | RCP NEWS2 |

**Implementation:** `lib/config/clinical_thresholds.dart` - `RedFlags` class.
