# Sehat Nigraan — UI/UX Plan

**Version:** 1.0  
**Date:** 2026-09-05  
**Status:** Draft for review  
**Companion to:** `docs/tier-1-complete-spec.md`, `docs/ARCHITECTURE.md`, `docs/final-scope-skin-vision.md`

---

## Table of Contents

1. [Design Vision](#1-design-vision)
2. [UX Principles](#2-ux-principles)
3. [Design Theme & Visual Identity](#3-design-theme--visual-identity)
4. [Accessibility Baseline](#4-accessibility-baseline)
5. [Information Architecture](#5-information-architecture)
6. [Core Flow: Triage Walkthrough](#6-core-flow-triage-walkthrough)
7. [Screen-by-Screen Design](#7-screen-by-screen-design)
8. [Component Library](#8-component-library)
9. [Tier Result & Emergency States](#9-tier-result--emergency-states)
10. [Missing Data & Fail-Closed UX](#10-missing-data--fail-closed-ux)
11. [Voice-First & Localization](#11-voice-first--localization)
12. [Global States (Offline, Interruption)](#12-global-states-offline-interruption)
13. [Performance Budget & Device Strategy](#13-performance-budget--device-strategy)
14. [Usability Validation](#14-usability-validation)
15. [Open Questions](#15-open-questions)

---

## 1. Design Vision

**One clear sentence:** *"A calm, giant-button questionnaire that tells a family exactly what to do next — in their own language, with or without network, and with or without a clinician in the room."*

The person holding the phone in an emergency is **not a clinician**. They are:
- A daughter checking on her mother in a village.
- A first responder with first-aid training.
- An elderly person themselves who may have poor eyesight, tremor, or low tech-literacy.

Every design decision below optimizes for that user **under stress**: reduce decisions, enlarge targets, keep one path, never force recall, and make the app the *calmest* thing in the room.

### Primary UX contrast with consumer apps

| Typical app goal | Sehat Nigraan goal |
|---|---|
| Maximize engagement/time in-app | Minimize time-to-decision (≤3 min) |
| Discover features | Hide everything except the next step |
| Personalize with account/login | Zero required setup; runs from cold start |
| Beautiful density/richness | Giant, sparse, high-contrast, foolproof |

---

## 2. UX Principles

| # | Principle | Application |
|---|-----------|-------------|
| 1 | **One task per screen.** No scrolling questionnaires with mixed questions. | Each question = one screen or one focused card group |
| 2 | **Never ask users to type.** | Number entry via large steppers/chips; free text only in Tier 2 notes and optional |
| 3 | **Every answer is revisitable.** | A persistent "Back"/"Change" affordance; answers stored per-field, not per-page |
| 4 | **Idempotent and undoable.** | "Start over" and "undo last" always available; no destructive default |
| 5 | **Progress is visible and calming.** | Steady progress bar "Question 4 of 9"; never a countdown/alarm tone |
| 6 | **The machine is humble.** | "Support tool" framing on every result screen; clinician overrides loud |
| 7 | **Fail-visible, not fail-silent.** | Missing vitals shown as a yellow banner, never hidden |
| 8 | **Offline == invisible.** | No network indicators in the main path; offline is the expected state |
| 9 | **Voice-first where it helps.** | STT for free text, TTS for instructions and result reading (roadmap) |
| 10 | **Trust through transparency.** | Every tier result shows the exact reasons that produced it |

---

## 3. Design Theme & Visual Identity

### 3.1 Name & Identity
- App title: **Sehat Nigraan — صحت نگران** ("Health Guardian")
- Tagline in-app: *"Pehle janch, phir aaram"* (Check first, then rest) — calm, non-alarming.
- Icon concept: a shield enclosing a heart waveform + a hand; minimal, high-contrast, no fine detail (legible at 48px).

### 3.2 Color System

**Brand palette (authored for both wet-ink legibility and color-vision safety):**

| Role | Token | Value | Usage |
|---|---|---|---|
| Primary | `--teal-700` | `#0D7377` seed | Actions, active state, progress |
| Primary dark | `--teal-800` | `#0A5A5E` | Pressed states, headers |
| Background | `--bg` | `#F7F9FA` (light) / `#121416` (dark) | App surface |
| Surface | `--surface` | White / `#1D2125` | Cards |
| Text primary | `--text` | `#1A1A1A` / `#ECF0F2` | Body |
| Text subdued | `--text-sub` | `#5A646A` / `#9AA6AD` | Hints, captions |

**Tier palette (from spec §14 — LOCKED, non-negotiable):**

| Tier | Label | Color | Dark-on-light text | Icon |
|---|---|---|---|---|
| P1 | Emergency | `#D32F2F` red | White | ⛑ square |
| P2 | Very Urgent | `#F57C00` orange | White | ⏱ circle |
| P3 | Urgent | `#FBC02D` yellow | Black | ⚠ triangle |
| P4 | Standard | `#388E3C` green | White | ✓ diamond |
| P5 | Minor | `#1976D2` blue | White | ▪ pentagon |

**Color-vision safety rule:** tier is communicated by **shape + label text + color** together, never color alone. (Danger: red/green deutan color blindness — elderly population prevalence is high.)

### 3.3 Typography

| Role | Spec | Notes |
|---|---|---|
| Display/Result | 40–48 sp, w800 | Tier label, result banner |
| Headings | 24–28 sp, w700 | Section titles |
| Question | 22–26 sp, w600 | The question being asked |
| Answer options | 20 sp+ | Button labels (≥ 18 sp minimum) |
| Body/captions | 16 sp | Supporting text |
| Scale sensitivity | **Text scaling up to 200% must not clip** | Obey `MediaQuery.textScaler` |

- Fonts: **Noto Sans** (Latin) + **Noto Nastaliq Urdu** (Urdu) bundled for offline. Nastaliq rendering validated on low-end Android (test phase).
- `letterSpacing` disabled for Urdu; direction switches to RTL automatically when Urdu active.

### 3.4 Spacing, Targets & Touch

| Element | Minimum |
|---|---|
| Touch target | **56×56 dp** (spec floor; norm for elderly)
| Primary action button | **Full-width, ≥64 dp tall** |
| Gap between tappable elements | ≥ 12 dp |
| Screen side margins | ≥ 20 dp |
| Stepper tap zones | Full tile, not just the +/- icon |

---

## 4. Accessibility Baseline

Beyond WCAG 2.1 AA, this product adds **emergency-specific** requirements.

### 4.1 Vision
- All text ≥ 18 sp default; results banner ≥ 40 sp.
- Contrast ≥ 4.5:1 for text, ≥ 3:1 for UI/tier shapes.
- **Text scaling to 200%** tested no-clip on all screens.
- Non-reliance on color (shape+label rule above).

### 4.2 Motor / dexterity
- Tremor-friendly: no drag-and-drop, no swipe-to-answer, no double-tap required.
- Steppers accept hold-to-repeat (press-and-hold increment) for large ranges.
- "Large" toggle switch size (48×32 dp minimum).

### 4.3 Hearing
- TTS is a *companion* to reading, never the only channel.
- All emergency-result actions also communicated as persistent on-screen text (user may be deaf).

### 4.4 Cognition / literacy
- ≤ 3 answer choices per question unless clinically required.
- Every question has an optional one-tap "Explain" (təghreq-u: plain-language expansion, audio + text).
- No medical jargon; terms mapped to plain Urdu/English phrases.
- Icons carry text labels always (never icon-only).

### 4.5 Screen readers / AT
- Full **TalkBack / VoiceOver** support: semantic labels on every control; question number announced; tier result announced with `liveRegion`.
- The triage questionnaire is a logical focus order (no focus traps).
- Haptic co-signals: gentle short vibration on question advance, distinct long pattern on P1 result.

### 4.6 Reduced motion
- Respect `disableAnimations`/`accessibleNavigation`: fade/opacity transitions replace slide/traverse animations when reduced motion is set.
- Progress bar animates as "grow", not "slide".

---

## 5. Information Architecture

### 5.1 Top-level structure (3 tabs)

> **Implementation note (ADR-016):** shipped shell is **Start / History / Settings**; the old Models tab moved under Settings, and **Ask AI** is a session carried by the shell (opened from the result screen or from a History record) rather than a nav destination.

```
┌──────────────────────────────────────────────┐
│  Sehat Nigraan                               │
├──────────────┬──────────────┬────────────────┤
│  START       │  HISTORY      │  SETTINGS      │
│  (triage)    │  (records)    │  (models/app)  │
└──────────────┴──────────────┴────────────────┘
```

- **[Start]** — the default, only screen needed in an emergency. One big "Start Triage / جنچ شروع کریں" button.
- **[History]** — past sessions, exportable/shareable summary for the clinic. Read-only by default; detail card includes vital chips, complaints, AI summary and an "Ask AI" handoff.
- **[Settings]** — developer/advanced: model files, download state, app info. Model management is tucked under Settings because a family user must never land there accidentally.

### 5.2 Core flow map (triage walkthrough)

```
 Home/Start
   │
 ┌─▼────────────────────────────┐
 │ Who is this for? (Age gate)  │ ← single screen, 4 big chips
 └─┬────────────────────────────┘
   │
 ┌─▼────────────────────────────┐
 │ Danger signs — "Does the     │ ← A1–A15 as ONE card list, each
 │ patient have ANY of these    │   with giant Yes / No; ANY Yes
 │ right now?"                  │   → results immediately (P1)
 └─┬────────────────────────────┘
   │  (P1 gate fired → jump to Result; still capture best-effort vitals)
   │
 ┌─▼────────────────────────────┐
 │ Vitals (B) — one screen per  │ ← B1–B7; "Not available" option
 │ parameter, stepper/AVPU      │   on SpO2 & temperature
 └─┬────────────────────────────┘
   │
 ┌─▼────────────────────────────┐
 │ Consciousness (C)            │ ← GCS or AVPU pickers
 └─┬────────────────────────────┘
   │
 ┌─▼────────────────────────────┐
 │ Chief complaint (D1)         │ ← 18-option chip grid (2 screens max)
 └─┬────────────────────────────┘
   │  branch
 ┌─▼────────────────────────────┐
 │ Probes (E, from branch)      │ ← 2–6 questions, one per screen
 └─┬────────────────────────────┘
   │
 ┌─▼────────────────────────────┐
 │ Sepsis screen (F) if engaged │
 └─┬────────────────────────────┘
   │  optional
 ┌─▼────────────────────────────┐
 │ Skin photo (G) — optional    │ ← camera/gallery, skippable 3×
 └─┬────────────────────────────┘
   │  optional
 ┌─▼────────────────────────────┐
 │ Burn module (H) if selected  │
 └─┬────────────────────────────┘
   │
 ┌─▼────────────────────────────┐
 │ Modifiers (I)                │ ← age/sex/pregnancy/immunocompromise
 └─┬────────────────────────────┘
   │
 ┌─▼────────────────────────────┐
 │ RESULT — tier banner +       │
 │ reasons + next steps         │
 │  [Generate Tier 2 summary]   │ ← only if device capable
 │  [Edit]   [Start over]       │
 └──────────────────────────────┘
```

### 5.3 Navigation rules
- **Forward-only, linear** within the triage flow (one next-step at a time).
- **Back** goes to the previous *question* (not previous *screen type*) and re-enables editing that answer.
- **Undo/Start-over** lives in a persistent top-bar "menu" (…) with two items: *Undo last*, *Start over*.
- **No tab switching** while a triage session is in progress — the walkthrough is modal over the 3-tab shell.

---

## 6. Core Flow: Triage Walkthrough

### 6.1 Session entry (cold start → first tap)
1. App opens to Start tab. **No onboarding, no login, no permission prompt blocking.**
2. One primary button: **"Start Triage"** (Urdu + English on the button).
3. Camera/photo permission is requested *only when* the user taps into Section G (skin photo) — not at launch.

### 6.2 One-question-per-card pattern
Each questionnaire card shares an invariant skeleton to reduce cognitive load:

```
┌──────────────────────────────────────────┐
│  ● 4/9               Sehat Nigraan  ⠇    │  ← progress + overflow menu
├──────────────────────────────────────────┤
│                                          │
│  QUESTION                                │
│  (one sentence, ≤ 14 words)              │
│                                          │
│  [ (i) Plain-language explain ]          │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  BIG ANSWER OPTION A               │  │
│  ├────────────────────────────────────┤  │
│  │  BIG ANSWER OPTION B               │  │
│  ├────────────────────────────────────┤  │
│  │  BIG ANSWER OPTION C               │  │
│  └────────────────────────────────────┘  │
│                                          │
│  [ BACK ]                    [ NEXT skip]│
└──────────────────────────────────────────┘
```

- The question card **auto-advances** on a selected answer (stress: fewer taps) but *always* allows Back to change it.
- Tapping the question card reads it aloud (TTS) and speaks option labels.

### 6.3 Stepper-based numeric vitals
Used for RR, SpO₂, SBP, HR, Temp:

```
  Respiratory rate   [ (i) ]
   ┌───────────────┐
   │  −   [ 24 ]  +  │   ← giant − / + tiles; hold to repeat
   └───────────────┘
   Common: 12 • 16 • 20 • 24     ← quick-chips for common values
   [Not available]               ← UNSAFE-to-guess escape for SpO₂/Temp
   [Continue]
```

**Critical detail (spec §21):** For **SpO₂ and temperature only**, an explicit **"Not available"** button appears. Tapping it silently maps to the missing-vitals policy (no numeric value invented) and shows a one-line note: *"Removed without guessing — we'll still give a careful recommendation."*

### 6.4 AVPU instead of GCS unless indicated
- Default consciousness question: **AVPU with 4 giant tiles**.
- Full GCS appears only when the spec requires it (§6): danger sign A1, AVPU ≠ Alert, or relevant complaint/age.

### 6.5 Steady-state pacing
- Target **≤ 35 taps** and **≤ 3 min** for a complete walkthrough (spec Phase 2 exit criteria — see §14).

---

## 7. Screen-by-Screen Design

### 7.0 App shell
- 3-tab `NavigationBar` (M3), labels always visible under icons.
- Current tab text in Urdu when locale = ur.
- Tab bar height ≥ 80 dp, tap-safe.

### 7.1 Home / Start
| Element | Design |
|---|---|
| Hero | Shield+wave mark, 120 dp, tinted teal |
| Heading | "Sehat Nigraan" in Urdu + English sub-line "صحیح انتخاب، جلد فیصلہ" |
| Primary CTA | Full-width **Start Triage** button (64 dp+) |
| Secondary | "View past records", "App models/settings" small links |
| Ambient | No news, no promotions, no network prompt |

### 7.2 Who is this for? (age gate)
- 4 chips: **Infant (<1 m) · Child (1–15 y) · Adult (16+) · Older adult (65+)** — tap-selectable tiles with icons.
- Selecting auto-branches to the right scale (PEWS / Peds-NEWS2 / NEWS2) and modifier defaults.
- Green checkmark fills selected chip; tap again to unselect is NOT offered (choose + continue).

### 7.3 Danger signs
- Card list of A1–A15 in plain language. Each row: icon + short phrase + **Yes / No** segmented control.
- List order = clinical priority (A1 at top). Auto-scroll as answered.
- "Any Yes" sets persistent sticky bar: **"⚠ A danger sign detected"** so the user knows the gate fired even if they continue.
- Gate fires → **immediate result jump** with clear text "We're getting help for you now — quick questions continue only if you can."

### 7.4 Vitals (7 screens or grouped sections)
- One parameter per screen (stepper or AVPU tiles).
- Each shows a realistic range label ("Typical: 12–20") but **never implies normality determines anything**.
- Vitals summary screen before continuing: a compact recap table with each value + "Change".

### 7.5 Chief complaint
- 18-option chip grid (responsive 3-col). Selecting → branch probes.
- Chip shows icon + word; tabs fully; selection highlighted.
- "Sores / rash" and "Burn" chips route to Skin/Burn modules.

### 7.6 Complaint probes (E-branch)
- Reuses the one-question-per-card skeleton. 2–6 questions, ≤ 3 options.
- Probe answers echo into the Tier 2 payload and the reasons string.

### 7.7 Skin photo (G, optional)
- One screen: "Add a photo if you have one — it helps."
- Buttons: **Camera**, **Gallery**, **Skip (recommend without)**.
- "Skip" is a real choice, visually equal; three skips in a row sum to "no photo" with no guilt.
- While classifier runs: spinner + "Checking…" (offline NN). On failure: fail-closed — proceed silently with text-only triage (spec §10).

### 7.8 Burn module (H)
- Mechanism chips → time chips → body map (tap regions) → TBSA stepper → depth appearance chips → airway/circumferential toggles.
- Body map is a simple front/back figure; tap toggles regions (hands/face/genitalia highlight in red when flagged).

### 7.9 Modifiers (I)
- Compact single card: age (auto from gate, editable), sex, pregnant?, immunocompromised?, MUAC (if <5), CFS (≥65).
- Any active modifier gets a live "will bump the result" badge.

### 7.10 Result
Covered in §9.

---

## 8. Component Library

| Component | Rules |
|---|---|
| **BigButton** | Full-width, ≥64 dp, label 20 sp+, ripple visible, no icons-only |
| **AnswerChip** | ≥56 dp, icon+text, selected = filled brand color with check |
| **StepperTiles** | `−` / value / `+` each ≥56 dp; hold-to-repeat; optional quick-chips |
| **SegmentedYesNo** | Two giant segments; selected = filled, contrast-safe states |
| **OptionalSkip** | Visually equals primary options; never a "pass" in grey |
| **ExplainSheet** | Bottom sheet with plain-language expansion + speaker icon |
| **ProgressDots** | "4 of 9" text label (not only dots); bar grows, never slides when reduced motion |
| **TierBanner** | Full-bleed tinted block: shape + label + response time + read-aloud button |
| **ReasonChip** | Small chips composing the "why", tapping one expands its contribution |
| **ReviewBanner** | Yellow `#FBC02D`-tinted card: "Some readings missing — clinician review recommended" |
| **OverflowMenu** | Top-right ⋯: Undo last, Start over, About |

All components ship in `lib/ui/widgets/` with a single `theme.dart` tokens file.

---

## 9. Tier Result & Emergency States

### 9.1 Result screen anatomy

```
┌──────────────────────────────────────────────┐
│  ██████ P1 — EMERGENCY (IMMEDIATE) ██████   │  ← full-bleed banner
│  [▶ Read aloud]  [Share with hospital]      │
├──────────────────────────────────────────────┤
│  Why:                                       │
│  • Vitals: 7 → P1 (RR 28, SpO₂ 88)          │  ← reason chips
│  • Danger gate: convulsing (A2)             │
│  • Modifier bump applied: age >65           │
├──────────────────────────────────────────────┤
│  Next steps (plain language):               │
│  1. Call 112 / go to nearest hospital NOW    │
│  2. Keep patient awake, stop giving food     │
│  3. Show this screen to the ambulance team   │
├──────────────────────────────────────────────┤
│  All scores [expand]  │  [Edit]  [Restart]  │
├──────────────────────────────────────────────┤
│  ⚖ DECISION SUPPORT — a clinician decides   │
│  [Generate Tier 2 summary] (if capable)     │
└──────────────────────────────────────────────┘
```

### 9.2 Emergency-tier specifics
- **P1 banner is persistent and non-dismissible** until user edits answers or starts over.
- Optional loud **haptic + TTS** pattern announced at result (user opt-out in Settings).
- **Share** button composes a cold message (SMS/WhatsApp) with the tier, reasons, vitals, and timestamp — **no app-installed data sent online**, it just opens the system share sheet offline-safe.
- Auto-suggested reassessment timer: P2 → 10 min, P3 → 30 min (spec §18 guardrail 4). As a calm card: "Recheck in 10 min" with a silence-first countdown — **no alarm sound**, gentle tone + vibration at due time.

### 9.3 Non-emergency tier specifics
- P4/P5 result framed as "self-care + when to recheck", not "nothing wrong".
- Provides literal fallback language: "If any of these appear, start triage again or go to hospital."

### 9.4 Result state machine
```
computing → result_ready → (edit answers → recompute → result_ready)
         → review_required (missing vitals) → result with banner
tier2_available → generating (progress dots, no blocking)
DRAFT guard: result_ready cannot be reached while a danger gate OR
physiologically-impossible value exists without review_required overlay.
```

---

## 10. Missing Data & Fail-Closed UX

Directly implements Tier 1 spec §21 (ADR-008).

### 10.1 Behavior
- SpO₂ / temperature: explicit **"Not available"** capture point (§6.3).
- The system **never presumes a value**; it flags review.
- The result screen shows a **yellow ReviewBanner** (§8) whenever vitals were incomplete — always, even if the tier is high for other reasons.

### 10.2 Copy examples (Urdu/EN bilingual)
| Case | Message |
|---|---|
| SpO₂ missing, no concern | "Oxygen level not measured — no concern was otherwise obvious." |
| SpO₂ missing + breathing problem | "Oxygen level not measured, and breathing is a concern — treated as serious." |
| Temp missing + fever complaint | "Temperature not measured — fever symptoms noted, treated as serious." |
| Both missing | "Oxygen and temperature missing — cannot rule out serious infection. Sepsis check included." |

### 10.3 Visual treatment
- Missing-value markers shown as **"— (not measured)"** never as 0 or blank.
- The vital recap shows the missing cell as a dashed outline + "Not measured".
- ReviewBanner is not dismissible on the result screen; it be recorded in the stored record (§21.9 spec).

---

## 11. Voice-First & Localization

### 11.1 Voice
| Capability | Status | UX |
|---|---|---|
| STT → free text (Tier 2 summary input) | Roadmap | Mic button beside text field; Urdu/English/Roman Urdu |
| TTS → read questions/options aloud | Roadmap | Speaker button on every question card + result banner |
| Full hands-free flow | Roadmap | "Start speaking" mode with confirmation tones and "Next" by voice |
- All voice input is **offline** (Vosk / on-device) — never requires network.

### 11.2 Languages
- **Urdu (default, RTL)** and **English**, plus **Roman Urdu** as an accessibility variant for users who read Urdu script poorly but do not read English.
- Language chosen once, stored locally; quickly switchable in the overflow menu (not buried in settings).
- All strings in one `arb` set (`app_en.arb`, `app_ur.arb`, `app_roman_ur.arb`); **pseudo-locale tested for text growth**.

### 11.3 Numerals & units
- Numerals render in **Western Arabic digits** even in Urdu locale (universally recognized in practice) — to be validated with users (open question Q2).
- Units always spelled once: "mmHg", "breaths per minute" never abbreviated.

---

## 12. Global States (Offline, Interruption)

### 12.1 Offline
- The triage path uses **zero network calls in Tier 1**. No spinners, no "you're offline" errors.
- Tier 2 generation (MedGemma) is local and offline too.
- Any cloud/upload step is explicitly post-hoc and user-confirmed.

### 12.2 Interruption / death of app
- State is persisted **per answered question** to local encrypted store (spec §19 roadmap).
- On relaunch after interruption: "Continue where you left off?" → resumes the current session; "Start over" resets.
- Battery/dark-mode/pip not used in the triage path (full-screen, keep-screen-on during active session).

### 12.3 Clinician override
- On the result screen, a **"Clinician override"** affordance (developer/clinical profile) records a manual tier change with reason; this is stored and visibly marked as overridden — not presented as the algorithmic tier.

---

## 13. Performance Budget & Device Strategy

**Target device baseline:** Android 9+, 2 GB RAM, arm64, 2019-class SoC (spec architecture).

| Metric | Budget |
|---|---|
| Cold start to Start button | ≤ 2 s |
| First tap → first question | ≤ 500 ms |
| Tier 1 compute | ≤ 1 s (spec §19) |
| Question advance | ≤ 200 ms perceived |
| Skin classify | ≤ 3 s (INT8 MobileNetV3-Large) |
| Tier 2 total | Device-dependent; async, non-blocking |
| Complete walkthrough | ≤ 3 min, ≤ 35 taps (spec Phase 2) |

**Techniques:** no network in Tier 1, singleton scoring engine in pure Dart (no async), `RepaintBoundary` on banner, `const` widget trees, image decode only when gallery picked, thread jank guard on question cards.

---

## 14. Usability Validation

From spec Phase 2 + 7 (exit criteria and tests). Converts these into concrete UX tests:

| Test | Measure | Target |
|---|---|---|
| Cold-start walkthrough n=5 (mixed literacy, ≥60y) | time-to-triage | ≤ 3 min |
| Tap count for full path | taps | ≤ 35 |
| First-time users find Tier result | correct tap in 10 s | 100% |
| Danger-gate path | correct skip to result | 100% |
| Missing-vitals path (SpO₂ not available) | no invented value; banner shown | 100% |
| Text scale 200% | no clipped text, all actions reachable | pass |
| TalkBack walkthrough | every control labelled & ordered | pass |
| Color-blind simulation (both deutan types) | tier still distinguishable | pass |
| Urdu + Roman Urdu rendering | no tofu/overflow | pass |
| Interrupt/kill mid-session | resume correctly | pass |

Field-test checklist (village clinic / home, sunlight): screen dimming, touch with wet hands, single-hand use.

---

## 15. Open Questions

1. **Numerals in Urdu UI** — Western digits (proposed) vs Urdu numerals: validate with the actual audience before locking.
2. **Iconography for low-literacy users** — are clinical icons (breathing, burning) safely recognizable, or should a **photo-based option set** replace icons for A-gates?
3. **Tier colors muting for anxiety** — red full-bleed P1 banner is intentional; confirm the *non-emergency* color saturation so a green P4 doesn't read as "safe — ignore".
4. **Reassessment timer alarms** — "no audible alert" default vs family request for sound: make it a Settings toggle or keep silence-first always?
5. **CFS (frailty) pictorial scales** — how to render the 1–7 pictorial scale simply without clinical jargon.
6. **Voice-First scope cut-in** — STT/TTS are roadmap; confirm whether the MVP needs a "read this aloud" toggle *now* given the elderly audience.

---

*Document owner: Product/UX owner*  
*Review cycle: Every 6 months or after any threshold/flow change*  
*Approval: Product + Clinical Safety Lead*