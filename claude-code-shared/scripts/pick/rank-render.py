#!/usr/bin/env python3
"""Cheap pre-sort and terminal render for /pick. Read-only, stdout only.

Input: normalized candidate JSON (stdin or file arg) from pick-fetch-*.sh.
Plug-in points for later tasks: scorer output (T-0030) adds a `score` per
candidate; blocker tiers (T-0031) replace the hide-blocked rule; overlap
annotations (T-0032) populate `notes`; other-repos (T-0034) groups by repo.

Sort steps come from the bucket's `sort` array:
  hide-blocked  drop candidates that have any blocker
  label-tier    order by label priority (LABEL_TIER, lower first)
  smallest      points ascending (unpointed last)
Ties break oldest first. Render: top N (default 5), one line per item plus a
start line 'wt <branch>  ->  /grill-me <id>'.
Scorer flow: --scorer-input prints the pick-scorer input (pre-sorted, capped at
25); --scores FILE re-ranks by score and adds a 'why:' line per item.
--focus <project> boosts matching-project items to the top (never filters).
Unpointed items always show '⚠ unpointed' and are never excluded.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blockers
import focus_boost

PRESORT_CAP = 25  # max candidates handed to pick-scorer

LABEL_TIER = {"pre-launch": 0, "opsec": 1, "legal": 1, "polish": 2,
              "seed-ready": 3, "post-launch": 8}


def label_tier(c):
    ts = [LABEL_TIER[l] for l in c.get("labels", []) if l in LABEL_TIER]
    return min(ts) if ts else 9


def rank(doc):
    sort = doc.get("sort", [])
    cands = list(doc["candidates"])
    doc["_hidden"] = 0
    if "hide-blocked" in sort:
        cands, doc["_hidden"] = blockers.apply(cands)

    def key(c):
        k = [c.get("_tier", 0)]
        if "label-tier" in sort:
            k.append(label_tier(c))
        if "smallest" in sort:
            p = c.get("points")
            k.append(p if p is not None else 1e9)
        k.append(c.get("created_at") or "")
        k.append(c["id"])
        return tuple(k)

    return focus_boost.boost(sorted(cands, key=key), doc.get("_focus"))


def scorer_input(doc):
    """Pre-sorted top PRESORT_CAP candidates, trimmed to the pick-scorer contract."""
    keep = ("id", "title", "labels", "points", "state", "project", "parent")
    cs = [{k: c.get(k) for k in keep} for c in rank(doc)[:PRESORT_CAP]]
    return {"repo": doc["repo"], "bucket": doc["bucket"], "candidates": cs}


def apply_scores(ranked, scores):
    """Stable re-rank by scorer effort (lower first); unscored keep pre-sort order."""
    by = {s["id"]: s for s in scores}
    for c in ranked:
        s = by.get(c["id"])
        c["_score"], c["_why"] = (s["score"], s["reason"]) if s else (99, None)
    return sorted(ranked, key=lambda c: c["_score"])


def render(doc, top=5, scores=None):
    ranked = rank(doc)[:PRESORT_CAP]
    if scores is not None:
        ranked = focus_boost.boost(apply_scores(ranked, scores), doc.get("_focus"))
    ranked = ranked[:top]
    lines = [f"{doc['repo']} / {doc['bucket']}  (top {len(ranked)})"]
    if focus_boost.active(doc.get("_focus")):
        lines.append(f"Focus: {doc['_focus']}")
    lines.append("")
    if not ranked:
        lines.append("No candidates found.")
    for n, c in enumerate(ranked, 1):
        tags = ",".join(c.get("labels", [])[:3])
        pts = f"  ~{c['points']}pt" if c.get("points") is not None else "  ⚠ unpointed"
        lines.append(f"{n}. {c['id']}  {c['title']}{pts}  [{tags}]")
        if c.get("_why"):
            lines.append(f"   why: {c['_why']}")
        for note in c.get("notes", []):
            lines.append(f"   {note}")
        base = f" {c['_base']}" if c.get("_base") else ""
        lines.append(f"   start: wt {c['branch']}{base}  ->  /grill-me {c['id']}")
    if doc.get("_hidden"):
        lines += ["", f"{doc['_hidden']} blocked hidden"]
    return "\n".join(lines)


if __name__ == "__main__":
    args = sys.argv[1:]
    top = 5
    if "--top" in args:
        i = args.index("--top")
        top = int(args[i + 1])
        del args[i:i + 2]
    scores_path = None
    if "--scores" in args:
        i = args.index("--scores")
        scores_path = args[i + 1]
        del args[i:i + 2]
    activity_path = None
    if "--activity" in args:  # teammate overlap (overlap.py)
        i = args.index("--activity")
        activity_path = args[i + 1]
        del args[i:i + 2]
    focus = None
    if "--focus" in args:
        i = args.index("--focus")
        focus = args[i + 1]
        del args[i:i + 2]
    want_input = "--scorer-input" in args
    if want_input:
        args.remove("--scorer-input")
    doc = json.loads(open(args[0]).read() if args else sys.stdin.read())
    if activity_path:
        import overlap
        doc = overlap.apply(doc, json.load(open(activity_path)))
    doc["_focus"] = focus
    if want_input:
        print(json.dumps(scorer_input(doc)))
    else:
        scores = json.load(open(scores_path))["scores"] if scores_path else None
        print(render(doc, top, scores))
