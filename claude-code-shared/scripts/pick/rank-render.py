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
"""
import json, sys

LABEL_TIER = {"pre-launch": 0, "opsec": 1, "legal": 1, "polish": 2,
              "seed-ready": 3, "post-launch": 8}


def label_tier(c):
    ts = [LABEL_TIER[l] for l in c.get("labels", []) if l in LABEL_TIER]
    return min(ts) if ts else 9


def rank(doc):
    sort = doc.get("sort", [])
    cands = list(doc["candidates"])
    if "hide-blocked" in sort:
        cands = [c for c in cands if not c.get("blockers")]

    def key(c):
        k = []
        if "label-tier" in sort:
            k.append(label_tier(c))
        if "smallest" in sort:
            p = c.get("points")
            k.append(p if p is not None else 1e9)
        k.append(c.get("created_at") or "")
        k.append(c["id"])
        return tuple(k)

    return sorted(cands, key=key)


def render(doc, top=5):
    ranked = rank(doc)[:top]
    lines = [f"{doc['repo']} / {doc['bucket']}  (top {len(ranked)})", ""]
    if not ranked:
        lines.append("No candidates found.")
    for n, c in enumerate(ranked, 1):
        tags = ",".join(c.get("labels", [])[:3])
        pts = f"  ~{c['points']}pt" if c.get("points") is not None else ""
        lines.append(f"{n}. {c['id']}  {c['title']}{pts}  [{tags}]")
        lines.append(f"   start: wt {c['branch']}  ->  /grill-me {c['id']}")
    return "\n".join(lines)


if __name__ == "__main__":
    args = sys.argv[1:]
    top = 5
    if "--top" in args:
        i = args.index("--top")
        top = int(args[i + 1])
        del args[i:i + 2]
    doc = json.loads(open(args[0]).read() if args else sys.stdin.read())
    print(render(doc, top))
