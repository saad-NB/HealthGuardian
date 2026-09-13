# Datasets — Drug Interaction Checker

This folder holds the **raw source data** and the **build-time scripts** used to
produce the small, bundled interaction dataset shipped inside the app. Nothing
here is loaded at app runtime; only the compact output under `assets/data/` is.

## Layout

```
datasets/
  ndf-rt/         VHA National Drug File - Reference Terminology (DDI pairs; public severity is blank)
  med-rt/         Medication Reference Terminology (successor; verified 2026-09-12: no DDI pairs/severity)
  onc/            ONC high-priority contraindicated DDI list (public domain)
  rxnorm/         RxNorm "Current Prescribable Content" (drug names; license-free)
  openfda/        openFDA / DailyMed SPL label interaction text (public domain) + cache/
  scripts/        Download + normalize/merge tooling (checked in)
  intermediate/   Normalized merged output (checked in: ddi.csv, drug_names.csv, provenance.json)
```

Raw downloads (`*.zip`, `*.rrf`, `*.xml`, `*.csv` from upstream) are **not**
committed — see `.gitignore`. Reproduce them with the scripts in `scripts/`.

## Pipeline

1. `scripts/verify_medrt_ddi.ps1` — hard gate: confirm MED-RT still carries
   DDI pair relations. **Result (2026-09-12): it does not** (crosswalks only),
   so the pipeline uses the frozen 2018 NDF-RT for pairs and MED-RT for classes.
2. Acquire inputs into `ndf-rt/`, `onc/` (see `docs/DRUG_INTERACTION_DATA_SOURCES.md`
   for URLs).
3. `scripts/fetch_openfda_bulk.ps1` — download the **static** openFDA drug/label
   bulk export (14 parts, ~1.8 GB, gitignored) and snapshot the manifest to
   `intermediate/openfda_manifest.json`. Resumable; no API rate limits.
4. `scripts/mine_openfda.py` — Python 3: parse the bulk export one part at a time,
   keep labels for our ingredients, then emit:
   - `intermediate/ddi_openfda.csv` — re-grade existing pairs from a context window;
   - `intermediate/ddi_openfda_new.csv` — new pairs discovered under a strict rule
     (single-ingredient labels, interaction sections, both names in one sentence,
     explicit severity phrase); only severe/moderate are kept.
5. `scripts/build_ddi.ps1` — merge NDF-RT pairs + ONC contraindicated list +
   NDFRT→RxNorm names, apply the openFDA enrichment overlay (max severity; never
   downgrades `contraindicated`), then append the discovered new pairs →
   `intermediate/ddi.csv`, `drug_names.csv`. Pass `-SkipEnrich` to omit openFDA.
6. `scripts/emit_assets.ps1` — convert `intermediate/` into the bundled
   `assets/data/ddi.json` + `drug_names.json`.

## Licensing (summary)

| Source | License | Commercial |
|---|---|---|
| NDF-RT / MED-RT (US VA / NCI) | U.S. Government public domain | Yes |
| ONC high-priority DDI list | U.S. Government public domain | Yes |
| RxNorm Current Prescribable Content | License-free (NLM) | Yes |
| openFDA / DailyMed SPL | U.S. Government public domain | Yes |

Full provenance, versions, URLs, and attribution requirements are documented in
`docs/DRUG_INTERACTION_DATA_SOURCES.md`. **Do not add any NC-licensed source**
(DDInter, full DrugBank, SIDER, TWOSIDES, etc.) to this pipeline.
