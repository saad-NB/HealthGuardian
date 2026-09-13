# Drug Interaction Data Sources

Provenance and licensing for the **Drug Interaction Checker** dataset. This
document is the authoritative record of every data source used to build the
bundled interaction table, its license, and its attribution requirements.

> **Hard rule:** only **commercial-clean** sources (public domain, CC0, or
> license-free) may enter the pipeline. No `NonCommercial` (NC) source —
> DDInter, full DrugBank, SIDER, TWOSIDES, KEGG, or any DrugBank-derived graph —
> is permitted. See [Excluded sources](#excluded-sources).

## License policy

| Allowed | Not allowed |
|---|---|
| U.S. Government public domain | `CC BY-NC*` (NonCommercial) |
| `CC0` | Research-only / academic-only |
| `CC BY` / `CC BY-SA` (with attribution) | Proprietary / per-request license |
| NLM license-free releases | Anything derived from a disallowed source |

## Source catalog

### 1. NDF-RT — National Drug File – Reference Terminology (base severity table)

- **Provider:** U.S. Department of Veterans Affairs (VHA), distributed via NCI EVS.
- **Provides:** drug–drug interaction pairs coded to **RxNorm RxCUI** /
  NDF-RT VUID. (The public extraction carries **no severity** — see below.)
- **License:** U.S. Government work — **public domain**, commercial use permitted.
- **Format:** RRF / OWL / XML releases; an extracted CSV
  (`drug_interaction_id, drug_1_vuid, drug_2_vuid, severity, drug_1_rxcui, drug_2_rxcui`)
  is mirrored in the `dbmi-pitt/public-PDDI-analysis` repository.
- **Status:** Retired in 2018; the 2018 release is used as a **frozen** base.
- **URL:** `https://evs.nci.nih.gov/ftp1/NDF-RT/`
- **✅ Acquired (2026-09-12):** `datasets/ndf-rt/NDF-RT-interactions.csv`
  (269,527 rows; 35,178 with RxCUI on **both** sides). Schema:
  `ID, IN1-VUID, IN2-VUID, SEVERITY, IN1-RXCUI, IN2-RXCUI`.
- **⚠️ Severity is blank in every row** of the public extraction — the public
  NDF-RT data provides the **pairs but not a severity grade**. Severity is
  therefore sourced from ONC (`contraindicated`) and openFDA label text; NDF-RT
  pairs default to a "reported interaction" grade.
- **Used for:** broad DDI pair list with RxCUI coding.

### 2. MED-RT — Medication Reference Terminology (successor; class-based layer)

- **Provider:** NCI Enterprise Vocabulary Services (EVS); evolutionary successor
  to VHA NDF-RT, released monthly, integrated into UMLS.
- **Provides:** medication terminology, pharmacologic classes, and asserted
  relationships. Used by FDA/NLM to normalize drug classes in DDI extraction
  (TAC 2019).
- **License:** U.S. Government work — **public domain**, commercial use permitted.
- **URL:** `https://evs.nci.nih.gov/ftp1/MED-RT/`
- **✅ Verification gate — result (2026-09-12):** the MED-RT release
  (`Core_MEDRT_Accessory_Files.zip`, release 2026.09.08) contains **only**
  NDFRT↔MeSH and NDFRT↔RxNorm **crosswalk** files. The DTS ontology has **no
  `severity`** and no `has_DDI` pair table. **MED-RT does not carry DDI pairs
  with severity** — it is a terminology/class resource only. The plan therefore
  uses the **frozen 2018 NDF-RT** for pairs, and MED-RT only for class
  normalization.
- **Used for:** drug classes (class-based ONC pairs); **not** the pair table.

### 3. ONC high-priority DDI list (contraindicated overlay)

- **Source:** Phansalkar S, et al. "High-priority drug–drug interactions for use
  in electronic health records." *JAMIA* 2012;19(5):735–743. PMC3422823.
  Commissioned by the ONC (U.S. HHS).
- **Provides:** **15 expert-consensus contraindicated pairs** (drug–drug,
  drug–class, and class–class). Full table in `datasets/onc/onc_high_priority.json`.
- **License:** U.S. Government work — **public domain**.
- **Used for:** escalating matching pairs to **`contraindicated`** and driving the
  hard warning popup. Class entries are expanded to member generic names.

### 4. RxNorm — "Current Prescribable Content" (drug names)

- **Provider:** U.S. National Library of Medicine (NLM).
- **Provides:** normalized drug names and identifiers. We extract **generic**
  ingredient names (`TTY` IN/PIN) and the RxCUI map for autocomplete/matching.
- **License:** the **Current Prescribable Content** download
  (`RxNorm_full_prescribe_*.zip`) is **license-free**. (The full RxNorm release
  requires a free UMLS license and is **not** used here.)
- **Format:** pipe-delimited RRF (`RXNCONSO.RRF`).
- **URL:** `https://www.nlm.nih.gov/research/umls/rxnorm/docs/rxnormfiles.html`
- **Used for:** RxCUI → generic-name mapping and the autocomplete dictionary.

### 5. openFDA drug/label — static bulk export (severity enrichment)

- **Provider:** U.S. FDA (openFDA), sourced from DailyMed SPL.
- **Provides:** Structured Product Labeling (SPL) documents including the
  `drug_interactions` / `contraindications` sections as narrative text.
- **License:** U.S. Government work — **public domain**; the openFDA server code
  is open source (`github.com/FDA/openfda`).
- **Access (static, no API rate limits):** the **bulk JSON export**, not the
  live query API. **14 zipped parts, ~1.8 GB, 262,842 records**, export
  `2026-09-11`. The API is used **only** to read the file list
  (`https://api.fda.gov/download.json`); the data comes from
  `https://download.open.fda.gov/drug/label/drug-label-000N-of-0014.json.zip`.
  Manifest snapshot: `datasets/intermediate/openfda_manifest.json`.
- **⚠️ No `openfda.rxcui` in the bulk export** — labels are matched to our
  ingredients by normalized `generic_name` / `substance_name`.
- **Used for (two passes):**
  1. **Enrichment** — re-grade existing NDF-RT pairs. For each pair, if one drug
     is named in the other's label, the ±250-char context window is classified
     `severe` / `moderate`. Never overrides `contraindicated`, never downgrades.
  2. **New-pair discovery** — pairs named in a label that NDF-RT lacks. This is
     **lower-confidence** and uses a strict rule: **single-ingredient labels
     only**, the **interaction/contraindication sections only** (not `warnings`),
     **both drug names in the same sentence**, and an explicit severity phrase
     (bare "interaction" is excluded). Only `severe`/`moderate` discoveries are
     bundled; all others are discarded. Combination-product labels are skipped
     because a warning cannot be attributed to one ingredient.
- **Result (2026-09-11 export):** enrichment re-graded 2,295 pairs; discovery
  contributed **869** new pairs (243 `severe`, 626 `moderate`). Discovered pairs
  are a **screening aid** and may contain false positives.

### 6. DrugCentral (metadata only — NOT a DDI source)

- **Provider:** University of New Mexico / IDG.
- **License:** `CC BY-SA 4.0` (commercial use with attribution + share-alike).
- **Verified:** the DrugCentral DRS API exposes **no DDI data** (0 hits for
  `ddi`/`interaction`/`severity` across 141 endpoints); its only "interaction"
  file is drug–**target**. **Not used for interactions.**
- **Possible use:** drug names/classes/targets metadata only.

## Excluded sources

| Source | License | Why excluded |
|---|---|---|
| DDInter 1.0 / 2.0 | `CC BY-NC-SA 4.0` | NonCommercial + ShareAlike |
| DrugBank (full) | `CC BY-NC 4.0` | NonCommercial |
| DrugBank Open Data | `CC0` | **No DDI** (vocabulary/structures only) |
| SIDER | `CC BY-NC-SA` | NonCommercial |
| TWOSIDES | Research/NC | NonCommercial, statistical noise |
| KEGG DRUG | Restricted | Commercial use restricted |
| PrimeKG / BioSNAP / merged PDDI | DrugBank-derived | Inherits NC |

## Normalization and matching

- **Name normalization:** lowercase; trim; strip salt/ester/hydrate forms,
  strengths, and dosage-form tokens; collapse whitespace. Generics only (no
  brand names) per product decision.
- **Matching:** normalized exact match → prefix → fuzzy (Levenshtein) fallback.
  Regex is retained only as a fallback validator — it is insufficient for salts,
  strengths, and spelling variants.
- **Severity model (app):** `contraindicated > severe > moderate > reported`.
  Merge rule: the **highest** severity across sources wins; ONC always forces
  `contraindicated`; openFDA only upgrades `reported` pairs.
- **Absence ≠ safety:** a non-match is reported as "no known interaction", never
  as "safe".

## Attribution

Public-domain sources require no attribution but should be cited for
transparency. DrugCentral (if ever used for metadata) is `CC BY-SA 4.0` and
requires attribution. This project will include a sources/credits section in
`docs/DRUG_INTERACTIONS.md` and the app's about screen.

## Reproduction

See `datasets/README.md` for the script order. Record the **release version and
download date** of each source in `datasets/intermediate/provenance.json` when
building so the bundled dataset is reproducible.

## Phase 0 verification findings (2026-09-12)

- **MED-RT has no DDI pairs/severity** — its accessory bundle is crosswalks
  only and its DTS ontology has no `severity`/`has_DDI`. Gate result: use the
  **frozen 2018 NDF-RT** for the pair table.
- **NDF-RT public CSV has no severity** (blank in all 269,527 rows) — pairs
  only; 35,178 have RxCUI on both sides.
- **ONC mapped list** `datasets/onc/ONC_High_Priority_Mapped.csv` — 1,929
  class-expanded contraindicated pairs (`$`-delimited; DrugBank IDs present but
  ignored; names used).
- **NDFRT→RxNorm name map** `datasets/ndf-rt/NDFRT_RxNorm_mapping.csv`
  (20,281 rows, `;`-delimited `rxcui;nui;drugname`) — enough to name pairs, so a
  full RxNorm download may not be needed.

## Open items

- [x] MED-RT DDI verification gate — **done: MED-RT has no DDI pairs/severity.**
- [x] Merge pipeline built — `datasets/scripts/build_ddi.ps1` →
      `intermediate/ddi.csv` (15,724 pairs) + `drug_names.csv` (1,193 names).
- [x] openFDA switched to the **static bulk export** (no API rate limits):
      `fetch_openfda_bulk.ps1` (14 parts) + `mine_openfda.py`. Full run complete
      (262,842 labels scanned, 56,494 kept).
- [x] Enrichment **merged**: 2,295 pairs re-graded (`severe` +845, `moderate`
      +1,450). New-pair discovery added **869** pairs (243 `severe`, 626
      `moderate`) under the strict rule. `assets/data/ddi.json` = 555,324 bytes.
- [x] Default grade decided: ungraded NDF-RT pairs are shown as
      **"reported interaction"** (distinct from graded pairs, never "safe").
- [ ] Discovered pairs are regex-mined and **lower-confidence** (~15% likely
      false positives). Future work: manual review, or a tighter NLP/curation
      pass, to raise precision.
- [ ] Optional curated brand→generic map (deferred; generics-only for now).
