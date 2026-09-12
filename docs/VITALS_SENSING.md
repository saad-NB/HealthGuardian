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
   - **Torch reliability:** the torch is enabled *after* the image stream is
     running (a flash command issued before CameraX is streaming is silently
     dropped on budget devices), is verified against `controller.value.flashMode`
     and retried; each attempt awaits the previous attempt's full disposal
     before reopening the camera, so "Try again" never races an in-flight
     close. The torch is explicitly switched off during teardown. No torch ⇒
     poor signal, never a crash.
   - **Frame format:** both I420 (3-plane) and NV21 (2-plane interleaved)
     YUV layouts are handled for the red-channel (BT.601) mean over the central
     ROI, with a luma-mean fallback if no chroma plane is usable — a 2-plane
     assumption here silently zeroed or errored the pulse reading on some
     devices.
- **Live preview + diagnostics:** the measuring screen shows the live camera
      feed (`CameraPreview`) so the operator can verify fingertip coverage, and a
      collapsible "Sensor diagnostics" panel surfaces live `torch / bpm /
      peak_amp / band_rms / period_ms / corr / usable` values while measuring and
      a "why it failed" summary on insufficient/failed — for field tuning without
      changing the confidence policy.
   - **Log-based calibration:** every measuring second is `debugPrint`ed to
      logcat (tag `HG_HR`) as one JSON line `{v, type: p|f, sec, bpm, reg,
      corr, amp, drift, q, usable, sub, outcome, conf}`; `tools/hr_log.dart`
      collects these (`collect` clears logcat, prompts for measuring, pulls and
      analyzes) or analyzes a saved dump, and reports each session's
      quality-factor means plus any **gate anomaly** — a session scoring ≥
      medium that still ended insufficient. `drift` is the bpm range over the
      last ~15 per-beat estimates (a real pulse converges and holds).
   - **Supervised calibration protocol:** run **3-4 clean readings** (verified
      against a pulse oximeter) then **2-3 deliberately noisy readings**
      (movement / partial coverage). `tools/hr_log.dart ... --label` then takes
      a `clean <bpm>` / `noisy` label per session and prints per-group factor
      distributions, a threshold search that best separates the groups
      (0/5 misclassifications = well-separated), FP/FN counts at the current
      medium threshold, and a suggested `qualityMedium` = midpoint of the
clean/noisy gap — each change gated by a DECISIONS entry after
       confirmations.
   - **Breathing-rate diagnostics:** `BreathingRateService` mirrors this with
      `HG_RR` JSON lines (fields `cpm, reg, corr, amp, q, usable, ibis, lag,
      breath, noisy, sub, env_sub`) and a final line carrying the
      insufficient `reason` — `noisy` / `sub` / `env_sub` / `no-validate`
      (breaths found but cadence↔period agreement failed) / `no-breath` /
      `short` — so `tools/hr_log.dart analyze --label --tag HG_RR` pinpoints
      which gate kills a real device reading (DECISIONS 2026-09-12f).
- **Position-then-start (HR):** the session parks in a `positioning` phase
      once the camera is live — the user places the fingertip and taps
      **Start measuring**, and only then does the 30 s countdown begin. Reliable
      usable coverage is no longer spent placing the sensor, which is what kept
      causing `usableSeconds < minUsableSeconds` (false "Not enough signal")
      on otherwise good readings.
2. **Detrend** (`movavg.dart`): subtract a long moving average to remove slow
   drift / illumination wander.
3. **Band-pass** (`biquad.dart`): isolate ~0.7–3.5 Hz → 42–210 BPM.
4. **Peak detection** (`peak_detect.dart`): peaks with a refractory window →
   inter-beat intervals (IBI).
5. **BPM** : smoothed (EMA) rate over a rolling window. Minimum window **10–15 s**
   for stability; session can accept early when stable.
6. **Quality index** (`qualityScore`): `0.5·regularity + 0.3·periodicity +
   0.2·peakSNR` (peak SNR weighted up after pilot — strong distinct beats must
   reward the score)
   - **Regularity** = `1 − CV(MAD/median IBI)` over a **trailing window of the
     last 12 beats** — a missed/garbled beat during fingertip placement no
     longer drags the score for the whole session (error shrinks as the
     session proceeds, ±3 bpm by ~18 s in pilot).
   - **Periodicity** = dominant-period autocorrelation; **peakSNR** = mean peak
     amplitude vs. band RMS.
   - Confidence cutoffs: **high ≥ 0.75, medium ≥ 0.50**, low below — medium was
     **calibrated from labeled on-device data** (DECISIONS 2026-09-12d) then
     raised to 0.50 after follow-up observations: during chaotic readings the
     quality score spiked to ~0.48 before collapsing, while a proper reading
     never dipped below 0.50.
   - **Settled estimate gate:** no reading is confident while per-beat BPM
     drift over the recent window is **> 4.0 bpm** (calibrated: clean final
     drift 0.3-2.6 bpm, chaotic 4.8-9.2 bpm) — a wandering estimate never
     presents as a reading.
   - **Weak-autocorrelation fallback:** if the band autocorrelation cannot
     confirm a rhythm period, the estimate is still accepted when the beat
     train is strongly regular (regularity ≥ 0.7) AND quality is at least
     medium AND drift is settled — a beating fingertip that scores 0 on
     periodicity must not die as "not enough signal". Noisy and sub-band
     signals stay below the bars (calibration: chaotic ended with reg 0.51-0.67,
     drift 4.8-9.2, q 0.31-0.39 → all rejected).
   - Session is a full **30 s**; the session reduces itself early ONLY when
     confidence is already **high** (`earlyFinishUsableSeconds` passed) —
     a merely medium-quality signal runs the full window, where the estimate
     keeps converging, then auto-accepts as medium (§6 — medium/high
     auto-accept).

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
1. **Capture** (`breath_capture.dart`): `record` at **16 kHz**, mono, PCM16,
   with `autoGain / echoCancel / noiseSuppress` all off so the energy envelope
   we measure is the room's, not the on-device DSP's.
2. **Audio band-pass** (`biquad.dart`): ~100–1000 Hz (550 Hz center, Q 0.6) —
   suppresses speech high-frequencies, mains hum, and rumble.
3. **Envelope** (`rms.dart`): short-time RMS over **30 ms** frames of the band
   signal; normalised by a moving detrend so gain offsets don't dominate (a
   running mean bridges the detrend's warm-up so the first seconds count). The
   running mean is seeded at the first nonzero level and frames with a
   zero/near-zero denominator are skipped — a real capture starts with silent
   frames, and `0/0` would inject a NaN that permanently poisons the recursive
   envelope filters (`biquad.dart` also self-heals on non-finite state).
4. **Envelope band-pass** ~0.07–1 Hz: two cascaded low-pass subtractions cut
   the sub-band drift that otherwise masquerades as slow breathing (the 3 bpm
   guard), then an LP at 1 Hz kills ripple. Envelope values captured before the
   detrend window fills are the cascade's settle-in transient and are excluded
   from period detection.
5. **Cycle detection** (`peak_detect.dart`): a hard refractory (= 60 bpm
   ceiling), a deep **fall ratio (0.35)** so rounded envelope crests and
   inhale/exhale splits don't double-count, and an **echo guard** that drops
   peaks below ~12% of the recent-accepted amplitude (an EMA, so one startup
   transient can't reject every later breath). Median inter-breath interval
   (IBI) → RR.
6. **Rate from the peak train** (drift-free): `peakTrainPeriodMs()` uses the
   median IBI, or the pair sum when the intervals alternate short/long from
   filter echoes. The envelope autocorrelation's global maximum is *not* used to
   override this — slow envelope drift (~14 s, only ~2 cycles in the window)
   otherwise masquerades as a strong 4 cpm period; the correlation search is
   capped to periods completing ≥3 cycles. `breathPeriodMs()` then doubles the
   burst period to the breath cycle when the autocorrelation at **2× the burst
   period** is nearly as strong as at the burst period: phone-at-mouth breathing
   produces an **inhale + exhale burst per breath**, so the raw peak cadence is
   the burst rate (~2× the breath rate).
7. **Confidence**: low/med/high from peak regularity + periodicity + amplitude.
   Always **insufficient** (never a forced number) when ambient noise is high,
   the audio energy sits outside the band, or the envelope's dominant variation
   is sub-band. Minimum **30 s** usable for a reading; session is 45 s with a
   28 s early finish for high-quality signals.

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
readings list (newest first, capped at 50) and the in-triage "use latest
reading" offer.

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
- Scenarios `vitalsHRSmoke` and `vitalsBRSmoke`: pre-grant permissions via adb
  (`pm grant` CAMERA + RECORD_AUDIO), open the Monitor tab, tap the HR / RR
  **Measure** card, assert the session renders (instruction + countdown), let
  it run to its terminal state, then reach the **manual/skip path** and return
  to the Monitor list. Kept tolerant/non-gating: real signal quality on the
  harness phone is not a release gate (a quiet room yields an honest
  insufficient-signal, which is the expected terminal state).
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