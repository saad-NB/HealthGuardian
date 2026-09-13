#!/usr/bin/env python3
"""Mine the static openFDA drug/label bulk export for DDI severity enrichment.

Replaces the old API-based mine_openfda.ps1. The bulk export (14 zipped JSON
parts, ~1.8 GB, 262,842 records) has NO openfda.rxcui field, so labels are
matched to our ingredients by normalized generic_name / substance_name.

For every "reported" NDF-RT pair, if one drug's name appears in the other
drug's label text, the pair is re-graded from the local context window:
  severe  (contraindicated / do not use / fatal ...)
  moderate (caution / monitor / may increase ...)
  reported (documented, but no severity keyword)

Also reports (but does NOT bundle) how many candidate new pairs openFDA would
add beyond the NDF-RT set.

Outputs:
  datasets/openfda/labels.jsonl           kept labels (gitignored)
  datasets/intermediate/ddi_openfda.csv   name_a,name_b,severity,sources

Usage:
  python datasets/scripts/mine_openfda.py
  python datasets/scripts/mine_openfda.py --limit-parts 1
"""

import argparse
import csv
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INTER = ROOT / "intermediate"
BULK = ROOT / "openfda" / "bulk"
LABELS_OUT = ROOT / "openfda" / "labels.jsonl"
ENRICH_OUT = INTER / "ddi_openfda.csv"
NEW_OUT = INTER / "ddi_openfda_new.csv"
DDI_CSV = INTER / "ddi.csv"
NAMES_CSV = INTER / "drug_names.csv"

TEXT_FIELDS = [
    "drug_interactions",
    "contraindications",
    "warnings",
    "drug_and_or_laboratory_test_interactions",
    "food_drug_interactions",
]

# Discovery only reads the explicit interaction/contraindication sections
# (not `warnings`, which is where most generic boilerplate lives).
INTERACTION_FIELDS = [
    "drug_interactions",
    "contraindications",
    "drug_and_or_laboratory_test_interactions",
    "food_drug_interactions",
]

SEVERE = [
    "contraindicat", "do not use", "should not be used", "must not be",
    "not recommended", "fatal", "life-threatening", "life threatening", "death",
]
MODERATE = [
    "caution", "monitor", "closely", "may increase", "may decrease",
    "may enhance", "may reduce", "interaction", "adjust", "serious",
]

RANK = {"reported": 0, "moderate": 1, "severe": 2}
WORD_RE = re.compile(r"[A-Za-z0-9]+")

# Discovery (new pairs) uses a stricter, sentence-scoped rule than enrichment:
# the sentence around the mentioned drug must carry an explicit severity signal.
# Bare "interaction"/"serious"/"adjust" are excluded — they appear in almost
# every label and produced ~65% false-positive candidates.
DISCOVERY_SEVERE = [
    "contraindicat", "do not use", "should not be used", "must not be",
    "not recommended", "avoid", "fatal", "life-threatening", "life threatening",
    "death", "should be avoided",
]
DISCOVERY_MODERATE = [
    "caution", "monitor", "closely", "may increase", "may decrease",
    "may enhance", "may reduce", "dose adjustment", "adjust the dose",
]
SENTENCE_BOUNDARY = ".;\n"


def sentence_around(text: str, pos: int, limit: int = 400) -> str:
    start = 0
    for boundary in SENTENCE_BOUNDARY:
        start = max(start, text.rfind(boundary, 0, pos) + 1)
    end = len(text)
    for boundary in SENTENCE_BOUNDARY:
        found = text.find(boundary, pos)
        if found != -1:
            end = min(end, found)
    sentence = text[start:end].strip()
    return sentence[:limit]


def discovery_severity(text: str, pos: int) -> str:
    sentence = sentence_around(text, pos).lower()
    if not sentence:
        return "reported"
    for keyword in DISCOVERY_SEVERE:
        if keyword in sentence:
            return "severe"
    for keyword in DISCOVERY_MODERATE:
        if keyword in sentence:
            return "moderate"
    return "reported"


def norm(value: str) -> str:
    if not value:
        return ""
    value = re.sub(r"\[[^\]]*\]", " ", value)
    value = value.upper()
    value = re.sub(r"[^A-Z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def pair_key(a: str, b: str) -> str:
    return f"{a}|{b}" if a <= b else f"{b}|{a}"


def load_names() -> dict:
    names = {}
    with open(NAMES_CSV, encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            name = (row.get("name") or "").strip()
            if name:
                names[norm(name)] = name
    return names


def extract_text(record: dict) -> str:
    parts = []
    for field in TEXT_FIELDS:
        value = record.get(field)
        if value:
            parts.append("\n".join(map(str, value)) if isinstance(value, list) else str(value))
    return "\n".join(parts)


def extract_interaction_text(record: dict) -> str:
    parts = []
    for field in INTERACTION_FIELDS:
        value = record.get(field)
        if value:
            parts.append("\n".join(map(str, value)) if isinstance(value, list) else str(value))
    return "\n".join(parts)


def openfda_values(record: dict, key: str) -> list:
    value = (record.get("openfda") or {}).get(key)
    if value is None:
        return []
    return [str(v) for v in value] if isinstance(value, list) else [str(value)]


def find_name_spans(text: str, names: dict, max_words: int) -> dict:
    """Map each known ingredient name in text to its first (start, end) span."""
    matches = list(WORD_RE.finditer(text))
    words = [m.group(0).upper() for m in matches]
    spans = {}
    for i in range(len(words)):
        for n in range(1, max_words + 1):
            if i + n > len(words):
                break
            key = " ".join(words[i:i + n])
            if key in names and key not in spans:
                spans[key] = (matches[i].start(), matches[i + n - 1].end())
    return spans


def find_names(text: str, names: dict, max_words: int) -> set:
    return set(find_name_spans(text, names, max_words))


def classify(text: str) -> str:
    lowered = text.lower()
    for keyword in SEVERE:
        if keyword in lowered:
            return "severe"
    for keyword in MODERATE:
        if keyword in lowered:
            return "moderate"
    return "reported"


def context_severity(texts: list, needle: str) -> str | None:
    if not needle or not texts:
        return None
    pattern = re.compile(
        r"(?<![A-Za-z0-9])" + re.escape(needle) + r"(?![A-Za-z0-9])",
        re.IGNORECASE,
    )
    for text in texts:
        match = pattern.search(text)
        if match:
            start = max(0, match.start() - 250)
            return classify(text[start:start + 500])
    return None


def mine(limit_parts: int) -> int:
    names = load_names()
    if not names:
        print("no drug names loaded", file=sys.stderr)
        return 1
    max_words = max(len(k.split()) for k in names)
    print(f"ingredients: {len(names)} (max {max_words} words)")

    zips = sorted(BULK.glob("drug-label-*.json.zip"))
    if limit_parts:
        zips = zips[:limit_parts]
    if not zips:
        print(f"no bulk zips in {BULK}; run fetch_openfda_bulk.ps1 first", file=sys.stderr)
        return 1

    kept = 0
    scanned = 0
    with open(LABELS_OUT, "w", encoding="utf-8") as out:
        for zp in zips:
            with zipfile.ZipFile(zp) as archive:
                for member in [n for n in archive.namelist() if n.endswith(".json")]:
                    with archive.open(member) as fh:
                        data = json.load(fh)
                    results = data.get("results") or []
                    part_kept = 0
                    for record in results:
                        scanned += 1
                        own_text = " ".join(
                            openfda_values(record, "generic_name")
                            + openfda_values(record, "substance_name")
                        )
                        own = find_names(own_text, names, max_words)
                        if not own:
                            continue
                        text = extract_text(record)
                        if not text.strip():
                            continue
                        out.write(json.dumps({
                            "own": sorted(own),
                            "generic": openfda_values(record, "generic_name"),
                            "text": text,
                            "itext": extract_interaction_text(record),
                        }, ensure_ascii=False) + "\n")
                        kept += 1
                        part_kept += 1
                    print(f"  {zp.name}/{member}: {len(results)} records, kept {part_kept}")
                    del data
    print(f"scanned {scanned} labels, kept {kept} -> {LABELS_OUT}")

    # ---- cross-reference NDF-RT pairs ----
    text_by_name: dict = {}
    for line in open(LABELS_OUT, encoding="utf-8"):
        record = json.loads(line)
        for name in record["own"]:
            text_by_name.setdefault(name, []).append(record["text"])

    ddi_rows = list(csv.DictReader(open(DDI_CSV, encoding="utf-8-sig")))
    ddi_pairs = set()
    for row in ddi_rows:
        ddi_pairs.add(pair_key(norm(row["name_a"]), norm(row["name_b"])))

    enriched = []
    for row in ddi_rows:
        na, nb = norm(row["name_a"]), norm(row["name_b"])
        severity = context_severity(text_by_name.get(nb, []), na)
        hit = "a_in_b_label" if severity else None
        if not hit:
            severity = context_severity(text_by_name.get(na, []), nb)
            hit = "b_in_a_label" if severity else None
        if hit:
            enriched.append({
                "name_a": row["name_a"],
                "name_b": row["name_b"],
                "severity": severity,
                "sources": f"ndf-rt+openfda({hit})",
            })

    with open(ENRICH_OUT, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["name_a", "name_b", "severity", "sources"])
        writer.writeheader()
        writer.writerows(enriched)

    counts = {}
    for row in enriched:
        counts[row["severity"]] = counts.get(row["severity"], 0) + 1
    summary = ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
    print(f"enriched pairs: {len(enriched)} ({summary}) -> {ENRICH_OUT}")

    # ---- discover candidate new pairs; bundle only severe/moderate grades ----
    # Strict: only the interaction/contraindication sections, only a sentence
    # that names BOTH the label's drug and the candidate, and only an explicit
    # severity phrase (bare "interaction" is excluded).
    all_candidates = set()
    graded = {}  # pair_key -> (a, b, severity)
    for line in open(LABELS_OUT, encoding="utf-8"):
        record = json.loads(line)
        own = set(record["own"])
        # Only single-ingredient labels: in a combination product we cannot tell
        # which ingredient a warning sentence refers to.
        if len(own) != 1:
            continue
        text = record.get("itext") or ""
        if not text:
            continue
        spans = find_name_spans(text, names, max_words)
        for b, (start, _) in spans.items():
            if b in own:
                continue
            sentence = sentence_around(text, start)
            severity = discovery_severity(sentence, 0)
            if severity == "reported":
                continue
            sentence_names = find_names(sentence, names, max_words)
            for a in own:
                if a not in sentence_names:
                    continue
                key = pair_key(a, b)
                all_candidates.add(key)
                current = graded.get(key)
                if current is None or RANK[severity] > RANK[current[2]]:
                    graded[key] = (a, b, severity)

    novel = {k: v for k, v in graded.items() if k not in ddi_pairs}
    with open(NEW_OUT, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["name_a", "name_b", "severity", "sources"])
        for key in sorted(novel):
            a, b, severity = novel[key]
            writer.writerow([names[a], names[b], severity, "openfda(new)"])

    new_counts = {}
    for _, _, severity in novel.values():
        new_counts[severity] = new_counts.get(severity, 0) + 1
    new_summary = ", ".join(f"{k}={v}" for k, v in sorted(new_counts.items()))
    print(f"candidate new pairs: {len(all_candidates)}; "
          f"graded severe/moderate: {len(graded)}; "
          f"novel bundled: {len(novel)} ({new_summary}) -> {NEW_OUT}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit-parts", type=int, default=0,
                        help="process only the first N bulk parts (smoke test)")
    args = parser.parse_args()
    return mine(args.limit_parts)


if __name__ == "__main__":
    raise SystemExit(main())
