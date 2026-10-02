#!/usr/bin/env python3
"""build_cases.py — build the persona-accuracy eval case set.

Bases are real to-seed sessions that spawned persona-accuracy. For each base,
the session JSONL is cut at the persona spawn, run through the production
filter-session-transcript.sh, and the draft seed the persona saw
(/tmp/seed-<sid>.json, last write before the spawn) is recovered from the log.
The production persona's own reply is kept for reference.

Variants come from mutations.json (hand-authored, human-reviewed): each one
plants exactly one defect into one seed field via an exact find/replace that
must match once. Kinds:
  clean      - unmodified draft seed (expected: no accuracy refutation)
  planted    - one accuracy defect (drift / stale / scope / negation) in `field`
  distractor - one off-lens defect (unsupported claim, Grounding's lens) in `field`

fixtures/ is gitignored (private session content). fixtures.lock.json pins
sha256 of every fixture so a rebuild from a pruned/changed log fails loudly.

Usage:
  build_cases.py            # extract fixtures (if absent), apply mutations, write cases.jsonl
  build_cases.py --extract  # force re-extraction from session logs
"""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
FILTER = HERE.parent.parent / "scripts" / "filter-session-transcript.sh"
FIX = HERE / "fixtures"
LOCK = HERE / "fixtures.lock.json"
HOME = pathlib.Path.home()

# base id -> origin session JSONL (relative to $HOME)
BASES = {
    "ci-fix": ".cco/projects/-Users-eric-Documents-dev-Quaestor-Web/be45cda2-43e8-4a6e-aa58-8cea41e12e8a.jsonl",
    "improve-learnings": ".cch/projects/-Users-eric--dotfiles/3344ad81-2b2f-4c60-a749-d64c65e2e02f.jsonl",
    "relay-posting": ".cch/projects/-Users-eric--dotfiles/051bf740-5d0b-45b9-a5f4-8d2b47dde7e3.jsonl",
}

# Real accuracy defects already present in a base's unmodified draft seed.
NATIVE_DEFECTS = {
    # decisions[11] says "Three schemas updated" but lists (and the transcript has) two.
    "relay-posting": {"field": "decisions[11]", "type": "native-count",
                      "planted_text": "Three schemas updated"},
}


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def blocks(entry):
    c = (entry.get("message") or {}).get("content")
    return [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []


def extract(base, rel):
    src = HOME / rel
    if not src.is_file():
        raise SystemExit(f"{base}: origin session log missing: {src}")
    sid = src.stem
    lines = src.read_text(errors="ignore").splitlines(keepends=True)
    spawn_i, spawn_id = None, None
    for i, ln in enumerate(lines):
        if "persona-accuracy" not in ln:
            continue
        for b in blocks(json.loads(ln)):
            if b.get("type") == "tool_use" and "accuracy" in str(b.get("input", {}).get("subagent_type", "")):
                spawn_i, spawn_id = i, b["id"]
                break
        if spawn_i is not None:
            break
    if spawn_i is None:
        raise SystemExit(f"{base}: no persona-accuracy spawn in {src}")

    seed = None
    for ln in lines[:spawn_i]:
        if "/tmp/seed-" not in ln:
            continue
        for b in blocks(json.loads(ln)):
            if b.get("type") == "tool_use" and b.get("name") == "Write" and re.fullmatch(r"/tmp/seed-.*\.json", b["input"].get("file_path", "")):
                # literal '${CLAUDE_CODE_SESSION_ID}' paths happen in practice
                seed = b["input"]["content"]
    if seed is None:
        raise SystemExit(f"{base}: no Write to /tmp/seed-*.json before the spawn")
    json.loads(seed)  # must be valid JSON

    prod = None
    for ln in lines[spawn_i + 1:]:
        if spawn_id not in ln:
            continue
        for b in blocks(json.loads(ln)):
            if b.get("type") == "tool_result" and b.get("tool_use_id") == spawn_id:
                c = b.get("content")
                prod = "\n".join(x.get("text", "") for x in c) if isinstance(c, list) else str(c)
        if prod is not None:
            break

    # Background spawns return an ack; the real reply is the subagent log's last text.
    m = re.search(r"agentId: (\w+)", prod or "")
    if m:
        sub = src.parent / sid / "subagents" / f"agent-{m.group(1)}.jsonl"
        if sub.is_file():
            for ln in sub.read_text(errors="ignore").splitlines():
                e = json.loads(ln)
                if e.get("type") == "assistant":
                    t = [b.get("text", "") for b in blocks(e) if b.get("type") == "text"]
                    if t:
                        prod = "\n".join(t)

    d = FIX / base
    d.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as t:
        t.writelines(lines[:spawn_i])
        cut = t.name
    try:
        r = subprocess.run(["bash", str(FILTER), str(d / "transcript.jsonl")],
                           env={**os.environ, "transcript_path": cut}, capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit(f"{base}: filter failed: {r.stderr[:300]}")
    finally:
        os.unlink(cut)
    (d / "seed.clean.json").write_text(seed)
    (d / "prod_accuracy_output.txt").write_text(prod or "")
    print(f"{base}: cut at line {spawn_i}/{len(lines)}, transcript {(d / 'transcript.jsonl').stat().st_size // 1024}K, seed {len(seed) // 1024}K")


def get_field(obj, path):
    """Resolve 'decisions[2]' / 'summary' / 'open_threads[0].question' to (parent, key)."""
    parts = re.findall(r"[^.\[\]]+|\[\d+\]", path)
    cur = obj
    for p in parts[:-1]:
        cur = cur[int(p[1:-1])] if p.startswith("[") else cur[p]
    last = parts[-1]
    return cur, (int(last[1:-1]) if last.startswith("[") else last)


def write_review(cases, muts):
    """cases.md: the human sign-off sheet (one row per case, then before/after per mutation)."""
    out = ["# persona-accuracy cases", "",
           "Expected: `clean` and `distractor` -> no accuracy refutation; `planted` -> a refutation on `field`.", "",
           "| id | kind | type | field |", "|---|---|---|---|"]
    out += [f"| {c['id']} | {c['expected']['kind']} | {c['expected'].get('type') or ''} | {c['expected'].get('field') or ''} |"
            for c in cases]
    for c in cases:
        m = muts.get(c["id"])
        if not m:
            continue
        out += ["", f"## {m['id']}", "", f"**{m['kind']} / {m.get('type')}** in `{m['field']}`", "",
                f"- before: {m['find']}", f"- after: {m['replace']}", f"- transcript anchor: {m.get('anchor', '')}"]
    (HERE / "cases.md").write_text("\n".join(out) + "\n")


def main():
    if "--extract" in sys.argv or not all((FIX / b / "transcript.jsonl").is_file() for b in BASES):
        for b, rel in BASES.items():
            extract(b, rel)
        lock = {b: {f: sha(FIX / b / f) for f in ("transcript.jsonl", "seed.clean.json")} for b in BASES}
        LOCK.write_text(json.dumps(lock, indent=2) + "\n")
    lock = json.loads(LOCK.read_text())
    for b, files in lock.items():
        for f, want in files.items():
            if sha(FIX / b / f) != want:
                raise SystemExit(f"{b}/{f}: sha mismatch vs fixtures.lock.json")

    muts_path = HERE / "mutations.json"
    muts = json.loads(muts_path.read_text()) if muts_path.is_file() else []
    # Clean seeds get the same serialization as mutated ones, so formatting can't tell them apart.
    for b in BASES:
        (FIX / b / "seed.json").write_text(json.dumps(json.loads((FIX / b / "seed.clean.json").read_text()), indent=2) + "\n")
    cases = [{"id": f"{b}--clean", "base": b, "seed": f"{b}/seed.json",
              "tags": ["clean", b], "expected": {"kind": "clean"}} for b in BASES]
    # A "clean" draft seed that carries a real accuracy defect of its own is
    # scored as planted on that field (id kept so baseline traces still line up).
    for c in cases:
        if c["base"] in NATIVE_DEFECTS:
            n = NATIVE_DEFECTS[c["base"]]
            c["tags"] = ["planted", c["base"], n["type"]]
            c["expected"] = {"kind": "planted", "field": n["field"], "type": n["type"],
                             "planted_text": n["planted_text"]}
    for m in muts:
        b = m["base"]
        seed = json.loads((FIX / b / "seed.clean.json").read_text())
        parent, key = get_field(seed, m["field"])
        val = parent[key]
        if not isinstance(val, str):
            # object-valued field (e.g. a decision object): mutate the named subkey
            parent, key = val, m["subkey"]
            val = parent[key]
        if val.count(m["find"]) != 1:
            raise SystemExit(f"{m['id']}: find matches {val.count(m['find'])}x in {m['field']}")
        parent[key] = val.replace(m["find"], m["replace"])
        out = FIX / b / f"{m['id']}.seed.json"
        out.write_text(json.dumps(seed, indent=2) + "\n")
        cases.append({"id": m["id"], "base": b, "seed": f"{b}/{m['id']}.seed.json",
                      "tags": [m["kind"], b, m.get("type", "")],
                      "expected": {"kind": m["kind"], "field": m["field"], "type": m.get("type"),
                                   "planted_text": m["replace"]}})
    (HERE / "cases.jsonl").write_text("".join(json.dumps(c) + "\n" for c in cases))
    write_review(cases, {m["id"]: m for m in muts})
    print(f"{len(cases)} cases -> cases.jsonl")


if __name__ == "__main__":
    main()
