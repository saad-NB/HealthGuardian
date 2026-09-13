# Sehat Nigraan (Health Guardian)

**Offline-first, two-tier AI patient triage for elderly and rural populations — Android & Windows.**

Sehat Nigraan (Urdu: "health guardian") walks a caregiver through a structured
clinical assessment and produces a risk-banded triage category
(**Emergency / Very urgent / Urgent / Routine / Non-urgent**) with a
plain-language summary — **fully offline, with zero server dependency**.

The safety-critical Tier 1 path is a deterministic rules engine built on
published clinical scales (NEWS2, Peds-NEWS2, PEWS, GCS/AVPU, qSOFA/pedSIRS,
burn TBSA + Parkland) with every threshold cited to a source. Tier 2
optionally layers an on-device **MedGemma-1.5-4B** advisory that can confirm or
escalate the Tier 1 grade — never downgrade it.

Read the full story in **[`docs/SPECIFICATION.md`](docs/SPECIFICATION.md)**.
Watch the live demo video here: https://www.youtube.com/watch?v=6bVY9SXXEl0

## Features

- **Tier 1 deterministic triage** — multi-scale vitals scoring, question
  probes per complaint, consciousness (GCS/AVPU), sepsis screen, burn module,
  hard red-flag gates, modifier bumps with transparent reasons.
- **Tier 2 on-device AI** (optional model) — MedGemma triage summary, grade
  confirmation, and post-triage chat via fllama; escalation-only merge
  (ADR-005); every AI output flagged `requires_human_verification`.
- **On-device vitals sensing** — heart rate from the phone's **camera**
  (fingertip PPG) and breathing rate from the **microphone**, with a Monitor
  tab and a never-blocking confidence policy.
- **Drug interaction checker** — 16.5k+ static pairs (commercial-clean VA
  NDF-RT + ONC + openFDA), blocking dialog for severe/contraindicated pairs,
  plain-language AI explanation.
- **Privacy-first** — no accounts, no server, no sync, no network calls in the
  safety path; records stored encrypted on device.
- **Accessible & localization-ready** — large tap targets, Urdu shell
  strings, screen-reader support, missing-data UX that fails visible.
- **Runs Android (7.0+, `minSdk 24`) and Windows (10/11 64-bit).**

## Download & Install

### Android 📱

1. Grab the prebuilt APK: **`SehatNigraan-android.apk`** from the [GitHub Releases](../../releases/latest) page (or build it yourself — see below).
   > The APK is **~85 MB**, a release/sideload build (not Play-signed, not on
   > the Play Store yet). It's git-ignored — binaries live in GitHub Releases.
   > A `flutter build apk --debug` build is also fine for testing but is
   > slower and ~3× larger; use the release APK for everyday installs.
2. Copy it to the phone, open it, and allow **"Install unknown apps"** for your
   file manager or browser when prompted.
3. Tap **Install** → open **Sehat Nigraan**.

Tier 1, vitals sensing, and Drug Check work with **zero model files**. To enable
**Ask AI / Tier 2**, add the MedGemma model inside
**Settings → Model Files** (see [Model files](#model-files) below).

### Windows 💻

1. Download and extract **`SehatNigraan-windows-release.zip`** from the
   [GitHub Releases](../../releases/latest) page.
   > Use the **zip** — it contains the complete runnable build. A bare
   > `healthguardian.exe` will not run by itself: it needs sibling files
   > (`data/`, `flutter_windows.dll`, …) in the same folder, which the zip provides.
2. Run `healthguardian.exe`.

Tier 1, Drug Check, and chat work on Windows. Camera-PPG / microphone vitals
sensing is tuned for Android phones and may be limited on desktop.

## Run From Source 🧑‍💻

### Prerequisites

- **Flutter** — install the SDK used by this project
  (`pubspec.yaml` requires Dart `^3.13.2`; this repo is developed on
  **Flutter 3.47 / Dart 3.13**).
- **Android** — Android Studio + Android SDK cmdline tools + a device/emulator
  (`adb`).
- **Windows** — Visual Studio 2022+ with the **"Desktop development with C++"**
  workload, and **Developer Mode** enabled (required for Windows desktop tool
  symlinks).

### First run

```bash
git clone <your-fork-url> healthguardian
cd healthguardian
flutter pub get
```

> **Note:** the first Gradle build downloads Android Gradle Plugin, Kotlin and
> plugin artifacts — expect a few minutes. The `fllama` engine comes straight
> from `https://github.com/Telosnex/fllama.git` per `pubspec.yaml`; a
> transient "Nuget.exe not found… cached version" message during Windows
> builds is benign.

### Run

```bash
flutter devices                          # list targets
flutter run -d <device-id>               # Android phone/emulator
flutter run -d windows                   # Windows desktop
```

### Build

```bash
# Android
flutter build apk --debug              # sideloadable .apk (used for the release above)
flutter build apk --release            # signed with your keystore configure under android/

# Windows
flutter build windows --debug          # dev build
flutter build windows --release        # output in build/windows/x64/runner/Release/
```

### Tests & checks

```bash
flutter analyze                         # lints (clean)
flutter test                            # 383 unit/widget tests
```

On-device end-to-end harness (Android): `scripts/device_e2e.ps1` — runs 9
triage scenarios + vitals/Monitor smokes over `adb`.
Vitals calibration collector: `tools/hr_log.dart` (supervised
HR/RR sessions; see `docs/VITALS_SENSING.md` §9.4).

## Model Files (Tier 2 / Ask AI)

MedGemma is **optional** — everything else works without it. The app downloads
from Hugging Face, or you can push via `adb`:

| File | Size | Purpose |
|---|---|---|
| `medgemma-1.5-4b-it-Q4_K_M.gguf` | ~2.32 GiB | Language model (required) |
| `mmproj-F16.gguf` | ~0.79 GiB | Vision projector (dev/testing only) |

Source: [`huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF`](https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF)

Android fastest path:

```bash
adb push medgemma-1.5-4b-it-Q4_K_M.gguf "/data/data/com.healthguardian.healthguardian/files/models/"
# then tap Refresh in Settings → Model Files. In-app auto-download also works.
```

Tier 2 is memory-gated: it stays disabled on devices with < 4 GB RAM; on ~7.5 GB
devices it uses a 3072-token context (≈12288 requested context) with device-aware
token budgets (see ADR-019 and `docs/SPECIFICATION.md` §8.6–§8.11).

## Repository Layout

```
lib/        Dart source (triage engine, vitals sensing, drug check, LLM, UI)
docs/       Design + spec docs (SPECIFICATION is the master); ADRs in DECISIONS.md
blueprints/ Engineering baseline & hand-off notes
datasets/   Commercial-clean DDI data pipeline + authored assets (assets/data/)
tools/      Calibration/analysis tooling
scripts/    adb on-device e2e harness
```

## Documentation

| Document | What it covers |
|---|---|
| [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md) | **Master spec** — architecture, engine, LLM, vitals, drug check, privacy, UI/UX, testing, safety, ADR summary, presentation narrative |
| [`docs/tier-1-complete-spec.md`](docs/tier-1-complete-spec.md) | Full Tier 1 rules, scoring tables, records, payload |
| [`docs/CLINICAL_SOURCES.md`](docs/CLINICAL_SOURCES.md) | Cited clinical sources for every threshold |
| [`docs/VITALS_SENSING.md`](docs/VITALS_SENSING.md) | HR/RR sensing design, pipelines, calibration |
| [`docs/DRUG_INTERACTIONS.md`](docs/DRUG_INTERACTIONS.md) | DDI severity model, data pipeline, licensing |
| [`docs/PROMPTS.md`](docs/PROMPTS.md) + [`docs/MODEL_CARDS/`](docs/MODEL_CARDS/) | Prompt engineering + MedGemma model card |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | All 20+ architecture decision records (ADRs) |
| [`docs/ui-ux-plan.md`](docs/ui-ux-plan.md), [`docs/testing-plan.md`](docs/testing-plan.md) | UI/UX + QA plans |
| [`blueprints/`](blueprints/) | Baseline, design iterations, session hand-offs |

## Data & Licensing

- **Code:** licensed under **GNU AGPL-3.0** — see [`LICENSE`](LICENSE). Use,
  modify, and share freely, but derivatives stay open.
- **Clinical thresholds:** every constant is cited to a published source
  (see `docs/CLINICAL_SOURCES.md`); changing a safety-critical threshold
  requires an ADR entry in `docs/DECISIONS.md`.
- **Drug interaction data:** static, commercial-clean dataset
  (VA NDF-RT 2018.02.05 + ONC + openFDA bulk; pipeline in `datasets/scripts/`).
  The app **never** calls a live DDI API.
- **Model weights:** MedGemma / Gemma weights are covered by their own
  upstream terms on Hugging Face — they are not covered by this repo's license.
- **Icon/art:** original.

## Contributing

Pull requests are welcome. Please:

1. Read the ADRs in `docs/DECISIONS.md` and the master spec first.
2. Keep the safety invariants (ADR-005: AI can only escalate, never downgrade;
   no diagnosis). When touching `lib/config/clinical_thresholds.dart`, include
   the citation + an ADR note.
3. Keep `flutter analyze` clean and `flutter test` green before submitting.

## Disclaimer

**Not a medical device. Not a diagnosis.** Sehat Nigraan is decision support
for caregivers — it does not replace professional medical judgment. In an
emergency, always contact your local emergency number (e.g. **1122** in
Pakistan) or a hospital immediately. The application is provided under AGPL-3.0
**without warranty of any kind**.
