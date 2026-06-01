#!/usr/bin/env python3
"""Extract verifiable claims from text and emit them as JSON grouped by type.

Usage:
    cat text.txt | python3 extract-claims.py
    python3 extract-claims.py path/to/file.txt

Output: JSON object with keys: statistical, attribution, causal, temporal, comparative.
Each key maps to a list of matched claim strings.

This is a deterministic regex pre-pass for the fact-checker agent. It surfaces
candidate claims cheaply before the agent performs live web verification.
False positives are expected and acceptable — the agent filters by judgment.
"""
import json
import re
import sys


PATTERNS = {
    "statistical": [
        r"\b\d+(?:\.\d+)?%(?:\s+of\s+[\w\s]{1,40})?",
        r"\$[\d,]+(?:\.\d+)?(?:\s*(?:million|billion|trillion|thousand|M|B|K)\b)?",
        r"\b\d+(?:,\d{3})+(?:\s+[\w\s]{1,30})?",
        r"\b(?:increased?|decreased?|grew?|fell?|dropped?|rose?|jumped?)\s+by\s+\d+(?:\.\d+)?%",
        r"\b\d+(?:\.\d+)?\s*(?:million|billion|trillion|thousand)\s+[\w\s]{1,30}",
        r"\b(?:over|more than|fewer than|at least|nearly|approximately|about)\s+\d[\d,]*(?:\s+[\w\s]{1,20})?",
    ],
    "attribution": [
        r"according\s+to\s+[\w\s,]{1,60}(?=,|\.|said|reported)",
        r"[\w\s]{1,40}(?:said|says|stated|claimed|argued|reported|found|concluded|announced)\s+that\b",
        r"(?:per|citing)\s+[\w\s]{1,40}(?=,|\.|:)",
        r"[\w\s]{1,40}(?:published|released|announced)\s+(?:a\s+)?(?:study|report|survey|analysis|data)",
    ],
    "causal": [
        r"\b[\w\s]{1,40}(?:causes?|leads?\s+to|results?\s+in|is\s+responsible\s+for|contributes?\s+to)\s+[\w\s]{1,60}",
        r"\bbecause\s+of\s+[\w\s]{1,60}",
        r"\bdue\s+to\s+[\w\s]{1,60}",
        r"\b(?:therefore|thus|consequently|as\s+a\s+result)\b.{0,80}",
    ],
    "temporal": [
        r"\bin\s+(?:19|20)\d{2}\b.{0,40}",
        r"\b(?:since|as\s+of|by|before|after)\s+(?:19|20)\d{2}\b",
        r"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+(?:19|20)\d{2}\b",
        r"\bversion\s+\d+(?:\.\d+){1,3}\b",
        r"\bv\d+(?:\.\d+){1,3}\b",
        r"\b(?:last|this|next)\s+(?:year|month|quarter|decade)\b.{0,40}",
        r"\b(?:recently|currently|now|today|yesterday)\b.{0,40}",
    ],
    "comparative": [
        r"\b(?:the\s+)?(?:largest?|smallest?|fastest?|slowest?|biggest?|best|worst|most|least|highest?|lowest?)\s+[\w\s]{1,40}",
        r"\b(?:more|less|greater|fewer|higher|lower)\s+than\s+[\w\s]{1,40}",
        r"\b#\s*1\b.{0,40}",
        r"\b(?:leading|top|premier|dominant|number[\s-]one)\s+[\w\s]{1,30}",
        r"\b[\w\s]{1,30}(?:outperforms?|surpasses?|exceeds?|beats?)\s+[\w\s]{1,40}",
    ],
}


def extract_claims(text: str) -> dict[str, list[str]]:
    results: dict[str, list[str]] = {k: [] for k in PATTERNS}
    seen: set[str] = set()

    for claim_type, pats in PATTERNS.items():
        for pat in pats:
            for match in re.finditer(pat, text, re.IGNORECASE):
                raw = match.group(0).strip()
                # extend context: grab the full sentence containing the match
                start = max(0, match.start() - 60)
                end = min(len(text), match.end() + 60)
                context = text[start:end].strip()
                # normalise whitespace
                context = re.sub(r"\s+", " ", context)
                key = (claim_type, context.lower())
                if key not in seen and len(context) >= len(raw):
                    seen.add(key)
                    results[claim_type].append(context)

    return results


def main() -> None:
    if len(sys.argv) > 1:
        path = sys.argv[1]
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            print(f"Error reading file: {exc}", file=sys.stderr)
            sys.exit(1)
    else:
        text = sys.stdin.read()

    if not text.strip():
        print(json.dumps({k: [] for k in PATTERNS}, indent=2))
        return

    claims = extract_claims(text)
    total = sum(len(v) for v in claims.values())
    output = {"total_candidates": total, "claims": claims}
    print(json.dumps(output, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
