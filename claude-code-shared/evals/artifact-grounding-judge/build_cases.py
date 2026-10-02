#!/usr/bin/env python3
"""build_cases.py — build the artifact-grounding-judge eval case set.

Sources base records from learnings/unified-learnings.jsonl, pins each cited
artifact to a git blob (repo + sha:path), materializes those blobs under
fixtures/<base>/ (gitignored: the source is private code), then derives
labeled variants (exact / fabricated / paraphrase / whitespace / missing
file / absence) and asserts every label against the frozen file contents.

Usage:
  build_cases.py            # build cases.jsonl + fixtures.lock.json + fixtures/
  build_cases.py --fixtures # re-materialize fixtures/ from fixtures.lock.json only
  build_cases.py --notes    # write case_notes.jsonl (plain-English per-case notes)
"""
import hashlib
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
LEARNINGS = HERE.parent.parent / "learnings" / "unified-learnings.jsonl"
REPOS = {
    "quaestor-web": pathlib.Path.home() / "Documents/dev/Quaestor-Web",
    "dotfiles": pathlib.Path.home() / ".dotfiles",
}
STRIP = {"schema_version", "id", "timestamp", "status"}

# Base records: learnings line number -> evidence indices to keep (resolvable ones).
BASES = {
    0: [0, 2, 3], 4: [0, 1, 3], 11: [2, 3, 4], 15: [0, 1], 19: [0, 1], 20: [1, 2],
    30: [0, 1], 52: [0, 1], 76: [1, 2], 87: [0, 1, 2, 3], 116: [0, 1, 2], 131: [1, 2],
}


def norm(s):
    return " ".join(s.split())


def git_show(repo, spec):
    r = subprocess.run(["git", "-C", str(REPOS[repo]), "show", spec], capture_output=True, text=True, errors="ignore")
    return r.stdout if r.returncode == 0 else None


def pin(ref, quotes):
    """Return (repo, rel, spec) for the newest blob of ref containing every quote."""
    for name, root in REPOS.items():
        rel = ref
        if ref.startswith("/"):
            if not ref.startswith(str(root) + "/"):
                continue
            rel = ref[len(str(root)) + 1:]
        shas = subprocess.run(["git", "-C", str(root), "log", "--all", "--format=%H", "-n", "40", "--", rel],
                              capture_output=True, text=True).stdout.split()
        for spec in [f"HEAD:{rel}"] + [s for sha in shas for s in (f"{sha}:{rel}", f"{sha}^:{rel}")]:
            t = git_show(name, spec)
            if t is not None and all(q in t for q in quotes):
                if spec.startswith("HEAD:"):
                    head = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
                    spec = f"{head}:{rel}"
                return name, rel, spec
        # Untracked file (e.g. an uncommitted docs/tasks file): pin by content hash.
        p = root / rel
        if p.is_file() and all(q in p.read_text(errors="ignore") for q in quotes):
            return name, rel, "worktree:sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()
    raise SystemExit(f"cannot pin {ref!r}")


def materialize(lock):
    for base, files in lock.items():
        for f in files:
            dest = HERE / "fixtures" / base / f["rel"]
            dest.parent.mkdir(parents=True, exist_ok=True)
            if f["spec"].startswith("worktree:"):
                src = REPOS[f["repo"]] / f["rel"]
                want = f["spec"].rsplit(":", 1)[1]
                if src.is_file() and hashlib.sha256(src.read_bytes()).hexdigest() == want:
                    text = src.read_text()
                elif dest.is_file() and hashlib.sha256(dest.read_bytes()).hexdigest() == want:
                    continue  # already materialized
                else:
                    raise SystemExit(f"worktree file changed or gone, cannot materialize {f}")
            else:
                text = git_show(f["repo"], f["spec"])
            if text is None:
                raise SystemExit(f"cannot materialize {f}")
            dest.write_text(text)


def build_bases():
    lines = LEARNINGS.read_text().splitlines()
    bases, lock = {}, {}
    for ln, keep in BASES.items():
        r = json.loads(lines[ln])
        rec = {k: v for k, v in r.items() if k not in STRIP}
        ev, files = [], {}
        kept = [r["evidence"][i] for i in keep]
        for e in kept:
            repo, rel, spec = pin(e["ref"], [x["quote"] for x in kept if x["ref"] == e["ref"]])
            files[rel] = {"rel": rel, "repo": repo, "spec": spec}
            ev.append({"source": "artifact", "ref": rel, "quote": e["quote"]})
        rec["evidence"] = ev
        key = f"b{ln:03d}"
        bases[key] = rec
        lock[key] = sorted(files.values(), key=lambda f: f["rel"])
    return bases, lock


def ftext(base, rel):
    p = HERE / "fixtures" / base / rel
    return p.read_text() if p.exists() else None


# Variant specs. Each: (kind, base, op, args, expected_verdict, expected_confidence or None=unchanged)
#   op "exact"   : no change
#   op "replace" : evidence[i].quote = new            (assert per kind)
#   op "reref"   : evidence[i].ref = new_ref          (cite quote against another/missing file)
#   op "add"     : append {"source":"artifact","ref":ref,"quote":quote}
#   op "multi"   : list of ops
SPECS = [
    # --- fabricated: one token changed (subtle) ---
    ("fabricated", "b004", "replace", (1, '"test": "jest --run",'), "rejected", None),
    ("fabricated", "b011", "replace", (1, "const { cadence, startDate, endDate } = useMetricsUrlParams({ fiscalYearEnd })"), "rejected", None),
    ("fabricated", "b015", "replace", (1, '"status": "cancelled"'), "rejected", None),
    ("fabricated", "b019", "replace", (1, None), "rejected", None),  # filled below: "Revenue 2" -> "Revenue (2)"
    ("fabricated", "b030", "replace", (0, "# Ascending age is the smallest age first, i.e. the oldest `flagged_at`\n        # first, so the sort direction is inverted relative to the timestamp."), "rejected", None),
    ("fabricated", "b052", "replace", (1, "body: { value: value.replace(/,/g, '') ?? null, currency }"), "rejected", None),
    ("fabricated", "b087", "replace", (1, "formikContext?.setFieldValue(`${fieldName}.updatedAt`, new Date().toISOString())"), "rejected", None),
    ("fabricated", "b131", "replace", (1, "const ALLOWED_DATE_FORMATS = ['MM/dd/yy', 'yyyy-MM-dd', 'MM/dd/yyyy', 'MM-dd-yyyy']"), "rejected", None),
    # --- fabricated: real quote cited against the wrong file ---
    ("wrong_file", "b000", "reref", (2, "docs/seeds/20260605-1358-retro-attribution-learning.json"), "rejected", None),
    ("wrong_file", "b011", "reref", (2, "client/src/modules/portfolio-company/metrics/components/FYEChangeBanner.tsx"), "rejected", None),
    ("wrong_file", "b076", "reref", (0, None), "rejected", None),  # filled below: swap to the other file
    ("wrong_file", "b116", "reref", (2, "clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.tsx"), "rejected", None),
    # --- paraphrase: same meaning, not verbatim -> pass, demote to candidate ---
    ("paraphrase", "b000", "replace", (0, "Merge the three learning forks (the existing skill-learning, the planned agent-learning, and retroactive attribution) into a single system with one v2 superset schema and one append-only log. The per-skill-file layout goes away and live skill-learning is rewired to the unified log. Doing it now costs almost nothing since there is no data yet; later it would be a migration project."), "pass", "candidate"),
    ("paraphrase", "b000", "replace", (1, "Unifying means the live skill-learning system has to be migrated: 24 tail blocks, the capture-learning agent, log-learning.py, learning-schema.json and the learnings/ directory. It is cheap while there is no data and gets expensive once data and the agent-learning fork build up."), "pass", "candidate"),
    ("paraphrase", "b011", "replace", (0, "Takes fiscalYearEnd and reportingCurrency so it can derive reasonable date and currency defaults when the URL has no params. Callers should pass values from useCompanyDetails() and useGetCurrencyForCompany()."), "pass", "candidate"),
    ("paraphrase", "b015", "replace", (0, '"Both CurrencyContext.Provider (with preferredCurrency) and an InvestmentsProvider with an empty value are present in the wrapper tree"'), "pass", "candidate"),
    ("paraphrase", "b020", "replace", (1, "Green run: all 18 tests passed in 0.08 seconds"), "pass", "candidate"),
    ("paraphrase", "b030", "replace", (0, "# Sorting by ascending age puts the newest flagged_at first, which means the sort order is the reverse of the timestamp order."), "pass", "candidate"),
    # --- near-verbatim: whitespace/punctuation only -> pass, confidence unchanged ---
    ("whitespace", "b011", "replace", (0, None), "pass", None),
    ("whitespace", "b019", "replace", (0, None), "pass", None),  # filled below: collapse whitespace
    ("whitespace", "b087", "replace", (2, None), "pass", None),
    ("whitespace", "b131", "replace", (0, None), "pass", None),
    # --- missing file -> pass, candidate ---
    ("missing_file", "b004", "reref", (0, "client/biome-check.sh"), "pass", "candidate"),
    ("missing_file", "b019", "reref", (0, "app/firm_exports/dashboard_v2.py"), "pass", "candidate"),
    ("missing_file", "b052", "reref", (0, "clients/web/src/pages/portfolio-company/EditableMetricsV2.tsx"), "pass", "candidate"),
    ("missing_file", "b116", "reref", (2, "clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.spec.tsx"), "pass", "candidate"),
    # --- missing file + fabricated elsewhere -> fabrication wins ---
    ("missing_plus_fab", "b019", "multi", [("reref", (0, "app/firm_exports/dashboard_v2.py")), ("replace", (1, None))], "rejected", None),
    ("missing_plus_fab", "b052", "multi", [("reref", (0, "clients/web/src/pages/portfolio-company/EditableMetricsV2.tsx")), ("replace", (1, "body: { value: value.replace(/,/g, '') ?? null, currency }"))], "rejected", None),
    # --- absence anchors: true -> pass, false -> rejected ---
    ("absence_true", "b015", "add", ("docs/tasks/20260722-0955-key-1935-portco-cutover-scaffolding.json", 'The identifier "useInvestmentsQuery" does not appear anywhere in this file.'), "pass", None),
    ("absence_true", "b000", "add", ("docs/tasks/20260605-1501-retro-attribution-learning.json", 'No task in this file mentions "migrate-learnings.py".'), "pass", None),
    ("absence_true", "b020", "add", ("docs/tasks/.logs/20260814-1236-investigation-egress-architecture/T-0076.md", 'The word "flaky" does not appear in this log.'), "pass", None),
    ("absence_false", "b131", "add", ("clients/web/src/components/DateInput/date-utils.ts", "The format 'yyyy-MM-dd' is missing from this file."), "rejected", None),
    ("absence_false", "b030", "add", ("client/src/modules/data-checks/DataChecksInboxPanel.tsx", 'No "Oldest first" sort option appears in this file.'), "rejected", None),
    ("absence_false", "b087", "add", ("clients/web/src/pages/reports/hooks/useCreateOrUpdateMetric/index.jsdom.test.ts", "The test never stubs the 'metric.updatedAt' path."), "rejected", None),
]

# Absence probes: the literal phrase the builder checks for (present/absent) per absence spec.
ABSENCE_PROBE = {
    ("b015", "absence_true"): "useInvestmentsQuery",
    ("b000", "absence_true"): "migrate-learnings.py",
    ("b020", "absence_true"): "flaky",
    ("b131", "absence_false"): "'yyyy-MM-dd'",
    ("b030", "absence_false"): "Oldest first",
    ("b087", "absence_false"): "metric.updatedAt",
}


def apply(rec, op, args, base, bases):
    ev = rec["evidence"]
    if op == "multi":
        for sub_op, sub_args in args:
            apply(rec, sub_op, sub_args, base, bases)
        return
    if op == "replace":
        i, new = args
        q = ev[i]["quote"]
        if new is None:
            if base == "b019" and i == 1:
                new = q.replace("Revenue 2", "Revenue (2)")
            else:  # whitespace collapse
                new = norm(q)
        ev[i]["quote"] = new
    elif op == "reref":
        i, new_ref = args
        if new_ref is None:  # swap to the other file in the record
            new_ref = next(e["ref"] for e in ev if e["ref"] != ev[i]["ref"])
        ev[i]["ref"] = new_ref
    elif op == "add":
        ref, quote = args
        ev.append({"source": "artifact", "ref": ref, "quote": quote})


def check(case, base, orig):
    """Assert the label holds against the frozen fixture files."""
    kind = case["tags"][0]
    for e in case["record"]["evidence"]:
        t = ftext(base, e["ref"])
        o = next((x for x in orig["evidence"] if x["ref"] == e["ref"] and x["quote"] == e["quote"]), None)
        if (base, kind) in ABSENCE_PROBE and e is case["record"]["evidence"][-1]:
            present = ABSENCE_PROBE[(base, kind)] in t
            assert present == (kind == "absence_false"), (case["id"], "absence probe")
            continue
        if t is None:
            assert kind in ("missing_file", "missing_plus_fab"), (case["id"], e["ref"], "unexpected missing")
            continue
        if o is not None:
            assert e["quote"] in t, (case["id"], "exact quote not in file")
        elif kind in ("fabricated", "wrong_file", "missing_plus_fab", "paraphrase"):
            assert e["quote"] not in t and norm(e["quote"]) not in norm(t), (case["id"], kind, "mutation still matches")
        elif kind == "whitespace":
            assert e["quote"] not in t and norm(e["quote"]) in norm(t), (case["id"], "whitespace variant mismatch")


KIND_NOTE = {
    "exact": "Real record, unchanged. Every quote is really in its file. Should pass.",
    "fabricated": "One word in one quote was changed, so the quote no longer matches the file. Should reject.",
    "wrong_file": "A real quote cited against a file it does not come from. Should reject.",
    "paraphrase": "A quote reworded with the same meaning. Should pass, but demote confidence to candidate.",
    "whitespace": "A multi-line quote flattened onto one line. Counts as verbatim. Should pass, confidence unchanged.",
    "missing_file": "One cited file does not exist. Should pass with confidence candidate.",
    "missing_plus_fab": "One cited file does not exist and another quote is fabricated. The fabrication wins. Should reject.",
    "absence_true": "Adds a true 'X does not appear in this file' claim. Should pass.",
    "absence_false": "Adds a false 'X does not appear in this file' claim (X is in the file). Should reject.",
}


def word_change(a, b, limit=80):
    """Shortest 'old -> new' description of a word-level edit."""
    aw, bw = a.split(), b.split()
    i = 0
    while i < min(len(aw), len(bw)) and aw[i] == bw[i]:
        i += 1
    j = 0
    while j < min(len(aw), len(bw)) - i and aw[-1 - j] == bw[-1 - j]:
        j += 1
    old, new = " ".join(aw[i:len(aw) - j]), " ".join(bw[i:len(bw) - j])
    clip = lambda s: s if len(s) <= limit else s[:limit] + "..."
    return f"changed `{clip(old) or '(nothing)'}` to `{clip(new) or '(nothing)'}`"


def write_notes():
    """case_notes.jsonl: one plain-English line per case, read by scripts/eval-summary.py."""
    cases = [json.loads(l) for l in (HERE / "cases.jsonl").read_text().splitlines() if l.strip()]
    base = {c["fixture"]: c["record"]["evidence"] for c in cases if c["tags"][0] == "exact"}
    with open(HERE / "case_notes.jsonl", "w") as f:
        for c in cases:
            kind, orig, parts = c["tags"][0], base[c["fixture"]], []
            for k, e in enumerate(c["record"]["evidence"]):
                if e in orig:
                    continue
                o = orig[k] if k < len(orig) else None
                if o is None:
                    parts.append(f"added claim on `{e['ref']}`: \"{e['quote']}\"")
                elif o["ref"] != e["ref"]:
                    gone = not (HERE / "fixtures" / c["fixture"] / e["ref"]).exists()
                    parts.append(f"cited `{e['ref']}`{' (does not exist)' if gone else ''} instead of `{o['ref']}`")
                elif kind == "fabricated" or kind == "missing_plus_fab":
                    parts.append(word_change(o["quote"], e["quote"]))
                elif kind == "paraphrase":
                    parts.append(f"reworded the quote in `{e['ref']}`")
                elif kind == "whitespace":
                    parts.append(f"flattened line breaks in the quote from `{e['ref']}`")
            detail = (" Edit: " + "; ".join(parts) + ".") if parts else ""
            f.write(json.dumps({"id": c["id"], "note": KIND_NOTE.get(kind, "") + detail}) + "\n")
    print(f"OK: wrote case_notes.jsonl ({len(cases)} notes)")


def main():
    if "--fixtures" in sys.argv:
        materialize(json.loads((HERE / "fixtures.lock.json").read_text()))
        return
    if "--notes" in sys.argv:
        write_notes()
        return
    bases, lock = build_bases()
    (HERE / "fixtures.lock.json").write_text(json.dumps(lock, indent=2) + "\n")
    materialize(lock)
    cases = []
    for base, rec in bases.items():
        cases.append({"id": f"exact_{base}", "tags": ["exact", rec["confidence"], base], "fixture": base,
                      "record": json.loads(json.dumps(rec)),
                      "expected": {"verdict": "pass", "confidence": rec["confidence"], "write": True}})
    counts = {}
    for kind, base, op, args, verdict, conf in SPECS:
        counts[(kind, base)] = counts.get((kind, base), 0) + 1
        suffix = "" if counts[(kind, base)] == 1 else f"_{counts[(kind, base)]}"
        rec = json.loads(json.dumps(bases[base]))
        apply(rec, op, args, base, bases)
        cases.append({"id": f"{kind}_{base}{suffix}", "tags": [kind, bases[base]["confidence"], base], "fixture": base,
                      "record": rec,
                      "expected": {"verdict": verdict, "confidence": conf or bases[base]["confidence"], "write": verdict == "pass"}})
    for c in cases:
        check(c, c["fixture"], bases[c["fixture"]])
    with open(HERE / "cases.jsonl", "w") as f:
        for c in cases:
            f.write(json.dumps(c) + "\n")
    rej = sum(c["expected"]["verdict"] == "rejected" for c in cases)
    print(f"OK: {len(cases)} cases ({len(cases) - rej} pass, {rej} rejected), {len(lock)} fixture bases")


if __name__ == "__main__":
    main()
