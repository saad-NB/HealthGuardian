# Project Handoff — MedGemma Validation (Flutter)

This doc captures the state of the project so it can be continued in a new
session (and possibly copied to another folder/machine). Written after the
Windows desktop baseline was confirmed working.

## 1. Project identity

- App / package name: `medgemma_validation`
- Current root (machine D: drive):
  `D:\PROJECTS ALL(Programming)\uraan techathon\medgemma test`
- What it is: a Flutter app that validates **MedGemma 1.5-4B** on-device via
  the `fllama` plugin (OpenAI-style chat API over GGUF). Also the future home
  of a low-resource medical triage assistant (vision classifiers + rule-based
  triage + MedGemma text reasoning).

## 2. Goal / vision (agreed scope)

The long-term design is a 2-tier triage system. This session only validated
the baseline platform (MedGemma + fllama + Flutter on Windows desktop).

- **Tier 1 (rule-based, no LLM, no vision):** GCS + NEWS2 + burn questions (UI)
  + hard red-flag overrides + skin classifier's risk-tier output feeding the
  same decision table extension. Fully demo-able by itself.
- **Skin classifier (sole vision component):** MobileNetV3-Large, TFLite INT8
  (~5.5 MB), multi-label ~11 classes + residual-Normal, trained on
  SCIN + AZH; outputs risk tiers feeding Tier 1 thresholds and the Tier 2
  prompt.
- **Tier 2 (MedGemma text-only):** takes free-text history + vitals + skin
  findings + burn answers and produces SOAP narrative. Reasons qualitatively
  about described symptoms (sore throat, eye redness, fatigue) from text; no
  eye/throat classifiers.
- Rule: MedGemma can escalate, never downgrade Tier 1 (`max()` merge).
- Eye/Throat vision classifiers are **deferred to roadmap**, not part of the
  current build.

Full detail: `docs/final-scope-skin-vision.md`.

## 3. Environment / tools (already installed on this machine)

Storage rule used during setup: anything big (>~5 GB) goes on a non-C: drive
(VS and Flutter SDK are on D:).

| Tool | Version / detail | Location |
| --- | --- | --- |
| Flutter SDK | 3.47.2 (stable) | `D:\flutter\src\flutter` |
| Dart | 3.13.x (bundled) | `D:\flutter\src\flutter\bin` |
| Visual Studio | Community 2026 (VS 17.x / MSVC 14.44, 14.50) | `D:\visual studio tools` |
| CMake | 4.2.3 (bundled by VS) | via VS |
| Windows SDK | 10.0.22621 | `C:\Program Files (x86)\Windows Kits\10` |
| Android SDK | present | `C:\Users\M-Saad\AppData\Local\Android\Sdk` |
| Java | OpenJDK 20.0.2 | via Android Studio |

Windows prerequisites that were needed to build desktop:

- **Windows Developer Mode ON** (registry
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense = 1`) — needed to create/parse developer symlinks used by the Flutter toolchain.
- **VS C++ workload** "Desktop development with C++" (`NativeDesktop`)
  installed via VS Installer GUI. vswhere reports `NativeDesktop` registered;
  `VCTools` may still report 0, but Flutter build works regardless.

Disk free at handoff: C: ~147 GB, D: ~303 GB, E: ~394 GB.

## 4. Build & run (Windows)

From the project root:

```powershell
flutter build windows --debug      # or --release
flutter run -d windows             # hot-reload dev loop
```

Debug output: `build\windows\x64\runner\Debug\medgemma_validation.exe`
(~1.1 MB exe; remaining files are debug assets).

Verified: **debug build succeeds and the app window launches** (process
`medgemma_validation`, ~390 MB RAM while idle).

Gotchas:

- First build is slow (~10 min) because `fllama` compiles llama.cpp/MTMD
  natively; hundreds of `[fllama]` warnings (C4267/C4305/C4244) are benign.
- Android scaffolding exists (`android/`) but was NOT built this session;
  baseline was done on Windows desktop.
- Clean up with `flutter clean` if you copy the folder and caching fights you.

fllama-related caches (machine C:):
`C:\Users\M-Saad\AppData\Local\Pub\Cache\git\fllama-<hash>\` and
`C:\Users\M-Saad\AppData\Local\fllama\Cache\<hash>\llama.cpp\`.

## 5. App structure

```
lib/
  main.dart                       App shell, 3-tab NavigationBar + AppState
  models/medgemma_files.dart      GGUF metadata (filenames, sizes, HF URLs)
  screens/
    chat_screen.dart              Chat UI vs MedGemma (incl. image picker)
    benchmark_screen.dart         Benchmark UI (prompts, timing, tokens)
    files_screen.dart             Model-file download/verify UI
  services/
    llm_service.dart              fllama OpenAI-style chat wrapper, streaming
    benchmark_service.dart        Benchmark logic
    download_service.dart         Resumable model download w/ size checks
  state/app_state.dart            Shared state (model paths, logs)
assets/samples/                   burn_wound.jpg, skin_lesion.jpg
```

pubspec dependencies: `fllama` (git `https://github.com/Telosnex/fllama.git`,
ref `main`), `path_provider`, `http`, `image_picker`, `device_info_plus`,
`cupertino_icons`; lints: `flutter_lints`.

## 6. Model files the app expects

Source repo (public, ungated): `https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF`

- `medgemma-1.5-4b-it-Q4_K_M.gguf` — ~2.32 GiB (2,489,894,976 B) language model
- `mmproj-F16.gguf` — ~0.79 GiB (851,252,224 B) vision projector

`llm_service.dart` attaches a base64 `<img>` tag and sets `mmprojPath` for
vision; runs inference on fllama's background isolate.

## 7. Docs in this folder (single source of truth for the machine-learning side)

- `docs/final-scope-skin-vision.md` — FINAL agreed architecture: Tier 1 /
  skin classifier / Tier 2, risk-tier thresholds, open items, 2-week action
  plan. **Start here.**
- `docs/dataset-merge-plan.md` — dataset inventory + label schema + mixing
  plan for skin/eye/throat/anaemia. Key decisions logged: CODE dropped
  (16 GB), SMART-OM added (throat+oral), conjunctivitis collapsed to a single
  class (no viral/bacterial), MobileNetV3-Large for classifiers.
- `docs/taxonomy-approaches.md` — earlier taxonomy/approach exploration
  (superseded by final-scope).

### Dataset research highlights (verified in session)

- **SMART-OM** (oral/throat): Figshare 31341790, 959.3 MB zip (MD5
  `27db67d29be86f4f18ec155b4f0159fe`, file id 61924579), 2,469 RGB images,
  331 subjects, 4 classes (healthy, variations-from-normal, OPMD, OC),
  JSON polygon annotations + clinical metadata (age/sex/tobacco/alcohol/areca).
- **PGUPharyngitis**: Figshare 28163513, 742 patients, 20-symptom + age/gender
  vector; symptom vector kept for Tier 2, images not used for classification
  (baseline AUC 0.554).
- **Mendeley Eye v2** (`n9zp473wfw.2`): 5 classes (Normal, Uveitis,
  Conjunctivitis, Cataract, Eyelid Drooping; 649 each = 3,245).
- **AZH**: 6 classes verified. **SCIN**: used for skin. **Oral Images**
  (165 benign + 158 malignant), **CP-AnemiC** (Ghana children),
  **Severe Pharyngitis** (339), **Conjunctivitis Recognition** (CC BY 4.0).
- Licensing: SCIN research-terms, AZH no explicit license (caveat), others
  CC BY 4.0. Kaggle disk (~20 GB) limit applies for training.

## 8. Open items / next steps

- Convert skin dataset merge + MobileNetV3-Large training (TFLite INT8) per
  `final-scope-skin-vision.md` action plan; confirm final skin class list (~11).
- Optionally add PAD-UFES-20 to skin set.
- Implement Tier 1 rule engine + decision table in Flutter.
- Build MedGemma-only Tier 2 prompt (text symptoms, vitals, skin tier, burn).
- Android build test (`flutter build apk --debug`) — not yet attempted.
- Move eye/throat classifier research to roadmap doc.

## 9. What this session accomplished

- Researched/verified all candidate datasets and wrote the merge plan.
- Agreed the final architecture (Tier 1 + skin-only vision + MedGemma Tier 2).
- Set up full Windows desktop build environment (VS C++ workload, Developer
  Mode) with all big tools on D:.
- Scaffolded `windows/`, built the MedGemma validation app for Windows,
  confirmed it launches — **baseline confirmed**.