# Vitals Sensing Module — On-Device HR & Breathing Rate

**Status:** In progress (planned, not yet implemented)
**Scope:** On-device Heart Rate (HR) and Respiratory Rate (RR) estimation using
only phone sensors — rear camera + flash (HR, PPG) and microphone (RR). No
external hardware, no cloud, offline-first.
**Related:** ADR-014 (Tier 2) · ADR-016 (feature batch) · ADR-017 (this module's
decisions) · `lib/vitals/` (target tree) · `docs/ui-ux-plan.md` §5.1 / §7.4.

---

## 1. Purpose & Clinical Framing

This is a *triage / emergency assessment* aid, **not** a diagnostic device.
Every measurement:

- is presented with a **confidence indicator** (low / medium / high),
- is labelled with a standing disclaimer
  ("Screening estimate only — not a substitute for clinical assessment"),
- **never blocks** the triage flow on a low-confidence reading — manual entry
  and a graceful "unable to get a reliable reading" path are always available
  (see §6 Confidence Policy).

The sensor value feeds the same `TriageAnswers` fields the manual steppers
already drive (`heartRate`, `respiratoryRate`), so **the Tier 1 engine is
untouched** — scoring, thresholds, and records continue to work identically.

---

## 2. Product Placement & Navigation

The app currently has a shell (`lib/ui/screens/root_shell.dart`) with an
`IndexedStack` and bottom `NavigationBar`: **Start · History · Settings ·
Ask AI**. This module restructures both entry points:

1. **Standalone Monitor tab (new, bottom nav).** A fifth screen becomes the
   fourth nav destination:
   **Start · History · Monitor · Ask AI**. The Monitor tab lists measurement
   cards (**Heart rate**, **Breathing rate**) that each launch the shared
   measurement session, plus a "recent readings" list.
2. **Settings moves to a top-left icon.** Settings is no longer a nav
   destination. A shared top-left gear action appears on each tab (owning
   AppBars get a `leading`; Start gets its own minimal AppBar/SafeArea row)
   and pushes `SettingsScreen` as a normal route (full screen + back) so the
   pin appears everywhere but never advertises model management.
3. **In-triage measure option.** On the `hr` and `rr` vital steps of the
   walkthrough (`lib/ui/screens/triage/vitals_steps.dart`) the UI offers
   **"Measure with phone"** beside the existing stepper, and — when a recent
   monitoring reading exists — **"Use latest reading"** as a one-tap fill.

Rationale in ADR-017: family users should never be one tap away from model
management; vitals monitoring is a primary action, so it earns a tab.

---

## 3. Module Architecture

Two isolated sub-modules plus shared session machinery, mirroring the
"reuse before rebuild; UI decoupled from sensor internals" goal:

```
lib/vitals/
  models.dart                        VitalReading, VitalKind, Confidence, SessionStatus
  measurement_session.dart           Pure-Dart state machine (ChangeNotifier) — testable headless
  measurement_session_view.dart      Shared full-screen session UI (countdown, waveform, gauge)
  permissions.dart                   permission_handler wrapper (CAMERA / RECORD_AUDIO)
  dsp/                               Shared pure-Dart signal utilities (no Flutter deps)
    biquad.dart                      Band-pass/low-pass biquad filter
    rms.dart                         Root-mean-square energy / envelope
    movavg.dart                      Moving-average (detrend + smoothing)
    peak_detect.dart                 Peak detection with refractory window + regularity
    window.dart                      Rolling window helpers
  heart_rate/
    ppg_capture.dart                 camera lifecycle → mean red-channel intensity stream
    ppg_pipeline.dart                detrend → bandpass → peaks → BPM + quality index
    heart_rate_service.dart          Stream<VitalReading> over capture + pipeline
  breathing_rate/
    breath_capture.dart              record package → PCM chunks
    breath_pipeline.dart             envelope → bandpass → cycle detection → RR + quality
    breathing_rate_service.dart      Stream<VitalReading>
  monitor/
    monitor_screen.dart              The new nav tab
    monitor_store.dart               Persist value + confidence + timestamp only
```

Each service exposes `Stream<VitalReading>` with fields
`value`, `unit`, `confidence`, `status`
(`measuring | success | failed | insufficient-signal`), so the UI never touches
sensor/processing internals and the backend (package/algorithm) can be swapped
without touching the walkthrough or Monitor tab.

---

## 4. Heart Rate — Camera Photoplethysmography (PPG)

### 4.1 Method

Fingertip over the rear camera with flash on. Blood-volume changes modulate
light absorption, producing periodic brightness changes in captured frames,
strongest in the **red channel** under flash illumination.

### 4.2 Package & pipeline

**Decision (ADR-017): custom pipeline on the official `camera` plugin — no
`heart_rate` widget package.** The `heart_rate` prototype path in the original
research was dropped to avoid churn; we need raw frame access and our own
confidence scoring anyway.

1. **Capture** (`ppg_capture.dart`): initialise rear camera, enable flash,
   **lock exposure / focus / white balance** once finger contact is confirmed
   (prevents auto-exposure "breathing" that mimics a pulse), sample
   **mean red-channel intensity per frame (~30 fps)**.
2. **Detrend** (`movavg.dart`): subtract a long moving average to remove slow
   drift / illumination wander.
3. **Band-pass** (`biquad.dart`): isolate ~0.7–3.5 Hz → 42–210 BPM.
4. **Peak detection** (`peak_detect.dart`): peaks with a refractory window →
   inter-beat intervals (IBI).
5. **BPM** : smoothed (EMA) rate over a rolling window. Minimum window **10–15 s**
   for stability; session can accept early when stable.
6. **Quality index**: peak regularity + signal SNR → low/medium/high. Surface
   it; only medium/high auto-accept (§6).

### 4.3 Risks
- **Motion artifact** — frame-to-frame variance detects it; prompt "hold still".
- **Poor perfusion** (cold fingers, shock, hypotension) — the most relevant
  triage population may have the weakest signal → graceful
  insufficient-signal state, never a forced number.
- **Cross-device variability** — flash intensity/sensor response differ; filter
  cutoffs and quality thresholds are **tunable constants**, and pilot testing
  on target devices (§9) is required before reliance.

---

## 5. Breathing Rate — Microphone-First

### 5.1 Why microphone-first (ADR-017)
- Lower effort: port from existing Dart/Flutter references
  (`shiihaa-breath-detection`, `BreathState` GSoC) instead of porting
  research-grade processing from another language.
- More passive UX: phone sits on a table/bed near the patient — better for a
  distressed/incapacitated patient than placing it on the chest.
- Screening-level accuracy is sufficient for triage (normal vs bradypnea /
  tachypnea flags).

Accelerometer/gyroscope chest-placement is deferred as **v2 "precision mode"**
(`sensors_plus`; Zephyr/AutoRR-style filtering) — only if microphone accuracy
proves insufficient in practice.

### 5.2 Capture & pipeline
1. **Capture** (`breath_capture.dart`): `record` at **16 kHz** (plenty for
   breath sounds), mono, PCM16.
2. **Noise-floor check** before measuring: if ambient RMS is above threshold
   (talking, alarms), prompt "please ensure quiet surroundings" rather than
   starting blind.
3. **Envelope** (`rms.dart`): short-time energy over ~30 ms frames — breath
   sounds appear as periodic energy bursts.
4. **Band-pass** (`biquad.dart`): ~100–1000 Hz, suppressing higher-frequency
   noise/speech.
5. **Cycle detection** (`peak_detect.dart`): identify inhale/exhale cycles.
6. **RR**: count cycles over a rolling window — **minimum 30–60 s** (RR is
   slower than HR; rest range ~12–20/min).
7. **Confidence**: same low/med/high scheme; low when ambient noise is high or
   periodicity is unclear.

### 5.3 Risks
- Ambient noise swamps breath sounds — noise-floor gate + quiet prompt.
- Shallow/irregular breathing in distressed patients lowers amplitude —
  insufficient-signal fallback (same as HR).

---

## 6. Confidence Policy (ADR-017)

> **Never block; allow explicit confirmation for low confidence.**

- **Medium / high** confidence → accepted, shown with an indicator.
- **Low** confidence → value shown with amber/red badge and an explicit
  **"Accept anyway"** button; the walkthrough still records it but the record
  input carries `confidence: low` for later clinician review.
- **Insufficient signal / failed** → "unable to get a reliable reading" card;
  the stepper (manual entry) is always reachable from the same step. No tier
  score is silently influenced by a rejected sensor value.

---

## 7. Data Model & Record Integration

### 7.1 `TriageAnswers` metadata (additive, engine-neutral)
Values land in the existing fields so scoring is unchanged, while new metadata
records provenance:

- `Map<String, VitalMeasurement>` `measurementMeta` keyed by `'hr'` / `'rr'`,
  where `VitalMeasurement{ source: manual|sensor, confidence, measuredAt }`.
- Sensor fill: `answers.heartRate = reading.value` (+ `measurementMeta['hr']`),
  `answers.respiratoryRate = ...` (+ `measurementMeta['rr']`).

### 7.2 Record
`TriageEngine._inputsSnapshot` adds the meta fields under `vitals`
(`hrSource`, `hrConfidence`, `rrSource`, `rrConfidence`). Record `inputs` is an
open map — **additive only, no record-version bump**. History detail can render
"HR 78 bpm · sensor · medium confidence". `buildRecordContext` includes the
source/confidence hints so Ask-AI can reason about the reading.

### 7.3 Monitor store
`MonitorStore` persists only `{kind, value, confidence, timestamp}` (no raw
frames, no audio) — a compact JSON file in the app directory, consistent with
the existing offline-first, privacy-preserving posture. It powers the recent
readings list and the in-triage "use latest reading" offer.

---

## 8. Android Permissions & Dependencies

### 8.1 Manifest (`android/app/src/main/AndroidManifest.xml`)
```
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.flash" android:required="false" />
```
Runtime requests centralised in `lib/vitals/permissions.dart`
(`permission_handler`). The e2e harness pre-grants via
`adb shell pm grant com.healthguardian.healthguardian android.permission.CAMERA`
(and `RECORD_AUDIO`) so on-device scenarios don't stall on dialogs.

### 8.2 Dependencies (`pubspec.yaml`)
- `camera` — official plugin, raw-frame access + flash/exposure lock.
- `record` — microphone capture.
- `permission_handler` — unified CAMERA/RECORD_AUDIO runtime flow.
- **Not added:** `heart_rate` (custom pipeline chosen), `sensors_plus`
  (deferred to v2 precision mode).

Flutter 3.47 / Dart 3.13 baseline; minSdk verified against the target device
(budget Vivo V2061, Android 10+) during the build step — only bump if a plugin
demands it.

---

## 9. Testing & Calibration

### 9.1 Automated
- **DSP unit tests (pure Dart, headless):** synthetic PPG / breath waveforms →
  assert expected BPM / RR; tunable-filter boundary checks (42/210 BPM edges).
- **Session widget tests (fake service):** accept / retry / cancel→manual,
  low-confidence "Accept anyway" gate, permission-denied + insufficient-signal
  fallback, no crash on service error.
- **Monitor store round-trip:** save → load → tolerance for legacy/empty state.
- **Engine regression guard:** answers with sensor metadata produce identical
  tier to the same values entered manually (nothing depends on source).
- **Shell nav smoke:** 4-destination bar + top-left Settings route; widget_test
  updates where nav indexes are asserted.
- Full suite stays green (`flutter test`) + `flutter analyze` clean.

### 9.2 On-device e2e (`scripts/device_e2e.ps1`)
- New best-effort scenario `monitorVitalsSmoke`: pre-grant permissions via adb,
  open Monitor tab, launch HR session, confirm the session renders and the
  **manual/skip path** is reachable, cancel cleanly. Kept tolerant/non-gating:
  real signal quality on the harness phone cannot be a release gate.
- Existing 9 triage scenarios unchanged (sensor is optional there).

### 9.3 Calibration / pilot protocol (pre-launch gate)
Validate both modules against reference devices across **3–5 target phones**:
- HR vs a reference **pulse oximeter** (e.g. ±5 bpm within ±2 σ over two trials).
- RR vs a **manual 60 s breath count** (e.g. ±2 breaths/min).
- Worst-case checks: low ambient light / flashlight-off indoor, poor perfusion
  imitation, talking/alarm noise for RR, motion during HR.
- Metrics logged to a CSV as the vignette/under-triage practice does for the
  engine; a DECISIONS entry is required to change any filter/quality constant.

---

## 10. Build Order (implementation)

1. **Scaffold:** deps, manifest permissions, `lib/vitals/models.dart` +
   `measurement_session.dart` + `measurement_session_view.dart` + `permissions.dart`;
   shell restructure (Monitor tab, top-left Settings icon, StartScreen AppBar);
   Monitor tab placeholder.
2. **HR module:** `ppg_capture` + `dsp` + `ppg_pipeline` + `heart_rate_service`;
   wire into `hr` vital step + Monitor card; confidence gate.
3. **RR module:** `breath_capture` + `breath_pipeline` + `breathing_rate_service`;
   noise-floor prompt; wire into `rr` step + Monitor card.
4. **Monitor store + in-triage "use latest reading"**; recent-readings UI.
5. **Docs & calibration pass:** finalise pilot protocol, run `flutter test` +
   `analyze` + e2e smoke; record findings in an ADR if constants change.

---

## 11. Deferred / Out of Scope
- Accelerometer/gyroscope RR "precision mode" (`sensors_plus`).
- SpO₂ from the camera (not reliable via on-phone sensors only) — requires a
  pulse oximeter, already a manual field today.
- Raw sensor streaming to any remote service — permanently excluded
  (offline-first, privacy).