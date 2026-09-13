# Drug Interaction Checker

Offline, on-device drug-drug interaction (DDI) screening for generic medicine
names. Implemented in the **Drugs** tab (ADR-018). This document is the design
reference; `docs/DRUG_INTERACTION_DATA_SOURCES.md` is the data provenance and
licensing record.

---

## 1. What it does

1. The user adds medicines by **generic name** (autocomplete over the bundled
   reference set).
2. "Check interactions" evaluates every unordered pair locally.
3. Results are listed most-urgent first, coloured by the locked tier palette.
   **Moderate** pairs are shown as an inline warning; only **severe** /
   **contraindicated** pairs raise the non-dismissible blocking dialog.
4. Each result can be explained in plain language by **MedGemma on-device**
   (optional; requires the GGUF from Settings).
5. **"Ask AI about these medicines"** opens the Ask AI chat with the entered
   medicines and the screening result attached as read-only context.
6. Checks are saved locally (names, matched severities, timestamp) and listed
   under "Recent checks".

Everything works with no network.

---

## 2. Severity model

| Severity | Source | Meaning | Blocks |
|---|---|---|---|
| `contraindicated` | ONC high-priority list | Do not use together | Yes |
| `severe` | openFDA/DailyMed label context | Serious interaction | Yes |
| `moderate` | openFDA/DailyMed label context | Monitor / may need adjustment | No |
| `reported` | NDF-RT pair (ungraded) | Interaction on record, severity not graded | No |

`reported` is deliberately kept below `moderate` and is **never** presented as
"safe". Absence of any result is explicitly not proof of safety.

The enum lives in `lib/interactions/models.dart`; each value carries a `label`,
`headline`, `advice`, and `blocks` flag.

---

## 3. Bundled data

| Asset | Size | Contents |
|---|---|---|
| `assets/data/ddi.json` | ~555 KB | 16,593 pairs as `[nameA, nameB, severityIndex]` |
| `assets/data/drug_names.json` | ~30 KB | 1,193 generic names + RxCUI |

`severityIndex` indexes `["reported","moderate","severe","contraindicated"]`
(declared in the asset's `severity` array).

Both assets are declared under `assets/data/` in `pubspec.yaml` and loaded once
via `rootBundle`.

---

## 4. Code map

```
lib/interactions/
  models.dart             InteractionSeverity, Drug, DrugInteraction
  dataset.dart            normalizeDrugName(), InteractionDataset (load/fromJson/search)
  engine.dart             InteractionEngine (check / unknownDrugs / hasBlocking)
  severity_style.dart     severity -> colour/icon (tier palette)
  drug_check_store.dart   SavedDrugCheck + DrugCheckStore (local JSON, cap 20)
  drug_check_screen.dart  Drugs tab UI + blocking dialog + AI explain sheet
lib/prompts/interaction_prompts.dart   MedGemma explain system/user prompt
lib/services/tier2_service.dart        explainInteraction() streaming call
```

- **`InteractionDataset`** is plain data: a normalized pair -> severity map and
  a name list. `load()` reads the assets; `fromJson()` lets tests run headless.
- **`InteractionEngine`** is pure and synchronous: dedupes by normalized name,
  evaluates all unordered pairs, sorts most-urgent first, and reports unknown
  names.
- **`DrugCheckScreen`** takes injectable `dataset`, `store`, and `tier2Service`
  for widget tests.

---

## 5. Data pipeline

Reproduce the assets from public-domain sources:

```powershell
pwsh -File datasets/scripts/verify_medrt_ddi.ps1    # gate: MED-RT has no DDI pairs/severity
pwsh -File datasets/scripts/fetch_openfda_bulk.ps1  # static bulk export (14 parts, ~1.8 GB, gitignored)
python datasets/scripts/mine_openfda.py             # bulk -> intermediate/ddi_openfda.csv
pwsh -File datasets/scripts/build_ddi.ps1           # NDF-RT + ONC + names + openFDA overlay
pwsh -File datasets/scripts/emit_assets.ps1         # intermediate/ -> assets/data/
```

The openFDA step is a **static bulk download** (the API is used only to read the
file list), so it is reproducible without rate limits. `mine_openfda.py` produces
two files: `ddi_openfda.csv` (re-grade existing pairs) and `ddi_openfda_new.csv`
(strictly-discovered new pairs). `build_ddi.ps1 -SkipEnrich` omits openFDA. Raw
upstream downloads are git-ignored; authored/derived files are tracked. See
`datasets/README.md` and `docs/DRUG_INTERACTION_DATA_SOURCES.md`.

---

## 6. Safety and limitations

- This is **decision support, not a prescription**. It never replaces a doctor
  or pharmacist.
- The reference set is ingredient-level and finite; unlisted medicines are
  flagged as "not recognised" and are not checked.
- The public data carries **no graded severity** for most NDF-RT pairs; those
  appear as `reported`. openFDA re-grades some pairs and adds a small set of
  discovered pairs.
- openFDA-**discovered** pairs are regex-mined and **lower-confidence** (~15%
  likely false positives); they are a screening aid, not a curated table.
- No dosage, indication, or interaction-timing advice is given.
- Only generic names, matched severities, and timestamps are stored locally.

---

## 7. Tests

`test/interactions/` (25 tests):

- `dataset_test.dart` - normalization, symmetric lookup, unknown pairs,
  autocomplete ordering/limits, and an integration test parsing the real
  bundled assets.
- `engine_test.dart` - dedupe, severity sort, blocking logic, unknown names.
- `drug_check_store_test.dart` - round-trip, dedupe, corrupt tolerance, cap.
- `drug_check_screen_test.dart` - add/check/results, blocking dialog, no-result
  message, unknown-medicine note, and the AI download hint.
