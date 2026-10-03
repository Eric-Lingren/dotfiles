#!/usr/bin/env python3
"""summary.py <agent>   write the plain-English summary page for an agent and print its path.

Output: <bench>/<agent>/summary.html  (default .claude/agent-bench/<agent>/summary.html)
Reads (all optional, missing pieces are said so on the page):
  queue.json                      stage the agent is at now
  <agent>/iterations.json         every iteration: check, kind, decision, reasons, sha, per-case results, stuck list
  <evals>/<agent>/scores.json     current pass rates per check (written when a fix is kept)
  <evals>/<agent>/contract.json   check ids and what each one verifies
Separate from hillclimb and eval-report.sh; it shares nothing with them. Run it after every invocation of
/improve-agent-benchmarks, whatever stage ran. Env: AGENT_BENCH_DIR, AGENT_EVALS_DIR as in bench_lib.
"""
import html
import os
import sys

import bench_lib as L

CSS = ("body{font:15px/1.5 -apple-system,system-ui,sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem;color:#1d1d1f}"
       "h1{font-size:1.5rem}h2{font-size:1.1rem;margin-top:1.8rem}table{border-collapse:collapse;width:100%}"
       "td,th{border-bottom:1px solid #ddd;padding:.35rem .5rem;text-align:left;vertical-align:top}"
       ".ok{color:#1a7f37}.bad{color:#b42318}.warn{color:#9a6700}.muted{color:#666}code{background:#f2f2f2;padding:0 .25rem}")


def e(x):
    return html.escape(str(x))


def pct(p, t):
    return f"{p}/{t} ({round(100 * p / t)}%)" if t else "no graded cases"


def verdict_line(it):
    d = it.get("decision") or {}
    st = it.get("status")
    if st == "kept":
        sha = it.get("sha")
        return ("<span class='ok'>Kept</span>, commit " + (f"<code>{e(sha[:10])}</code>" if sha else "not committed (dry run)"))
    if st == "aborted":
        return "<span class='warn'>Aborted</span> (usage limit); the edit was reverted and this does not count toward stuck"
    return "<span class='bad'>Reverted</span>; the edit was rolled back and the tree is clean"


def case_rows(it):
    pc = (it.get("decision") or {}).get("per_case") or {}
    rows = []
    for cid, r in pc.items():
        if r.get("role") == "target":
            f = lambda v: "pass" if v else ("fail" if v is False else "not run")
            rows.append(f"<tr><td>{e(cid)}</td><td>target</td><td>run 1: {f(r.get('run1'))}, run 2: {f(r.get('run2'))}</td></tr>")
        else:
            bad = r.get("regressed") or []
            rows.append(f"<tr><td>{e(cid)}</td><td>sentinel</td><td>" +
                        (f"<span class='bad'>regressed on {e(', '.join(bad))}</span>" if bad else "<span class='ok'>no regression</span>") + "</td></tr>")
    return "".join(rows)


def build(agent):
    bench = L.bench_dir()
    q = L.load_queue()["agents"].get(agent)
    st = L.read_json(os.path.join(bench, agent, "iterations.json"), {"iterations": [], "stuck": []})
    scores = L.read_json(os.path.join(L.evals_dir(), agent, "scores.json"))
    contract = L.read_json(os.path.join(L.evals_dir(), agent, "contract.json"))
    its = st.get("iterations", [])
    desc = {}
    for c in (contract or {}).get("checks", []):
        s = c.get("source") or {}
        desc[c["id"]] = f"{c.get('type', '')}" + (f", from {s.get('file')}:{s.get('line')}" if s.get("file") else "")

    out = [f"<!doctype html><meta charset=utf-8><title>{e(agent)} benchmark summary</title><style>{CSS}</style>",
           f"<h1>{e(agent)}: benchmark summary</h1>",
           f"<p class='muted'>Generated {e(L.now())}. Stage now: <b>{e(q['stage'] if q else 'not queued')}</b>.</p>"]

    # latest invocation
    out.append("<h2>This invocation</h2>")
    if not its:
        out.append("<p>No iteration has run yet for this agent. Stage work (contract, cases) is recorded in the queue only.</p>")
    else:
        it = its[-1]
        d = it.get("decision") or {}
        flipped = d.get("flipped_run1") or []
        conf = d.get("confirmed_2of2") or []
        tgt = it.get("targets") or []
        out.append("<ul>")
        out.append(f"<li>Stage done: <b>iterate</b>, iteration #{e(it['n'])} at {e(it.get('ts'))}</li>")
        out.append(f"<li>Check worked on: <code>{e(it['check'])}</code> ({e(desc.get(it['check'], 'not in contract'))})</li>")
        out.append(f"<li>Fix tried: {e(it.get('kind'))} fix. {e(it.get('rationale'))}</li>")
        out.append(f"<li>Checks flipped to passing on the first re-run: {len(flipped)} of {len(tgt)} targeted cases"
                   f" ({e(', '.join(flipped) or 'none')})</li>")
        out.append(f"<li>Confirmation (passes on both runs): {len(conf)} of {len(tgt)} targeted cases"
                   f"; the keep rule needs at least {-(-len(tgt) // 2)}</li>")
        out.append(f"<li>Outcome: {verdict_line(it)}</li>")
        for r in d.get("reasons") or []:
            out.append(f"<li class='bad'>Reason: {e(r)}</li>")
        tk = d.get("tokens_per_case") or {}
        if tk.get("ratio"):
            out.append(f"<li>Tokens per case: {e(tk['baseline'])} before, {e(tk['candidate'])} after ({e(tk['ratio'])}x)</li>")
        out.append("</ul>")
        if case_rows(it):
            out.append("<table><tr><th>case</th><th>role</th><th>result</th></tr>" + case_rows(it) + "</table>")

    # stuck
    out.append("<h2>Stuck checks</h2>")
    stuck = st.get("stuck") or []
    if not stuck:
        out.append("<p>None.</p>")
    for cid in stuck:
        att = [i for i in its if i["check"] == cid][-2:]
        out.append(f"<p class='warn'><code>{e(cid)}</code> is stuck: two fixes in a row were reverted, so it is skipped from now on.</p><ul>" +
                   "".join(f"<li>#{e(i['n'])} {e(i.get('kind'))}: {e(i.get('rationale'))} &rarr; {e(', '.join((i.get('decision') or {}).get('reasons') or []))}</li>" for i in att) + "</ul>")

    # scores
    out.append("<h2>Current pass rates (from scores.json)</h2>")
    if not scores:
        out.append("<p>No scores file yet: it is written the first time a fix is kept.</p>")
    else:
        out.append(f"<p class='muted'>Updated {e(scores.get('updated'))}, after iteration #{e(scores.get('iteration'))} "
                   f"(fixed <code>{e(scores.get('check_fixed'))}</code>), over {len(scores.get('cases', []))} cases.</p>")
        out.append("<table><tr><th>check</th><th>passing</th></tr>" +
                   "".join(f"<tr><td><code>{e(k)}</code></td><td>{e(pct(v['pass'], v['total']))}</td></tr>" for k, v in scores.get("rates", {}).items()) + "</table>")

    # history
    out.append("<h2>All iterations</h2>")
    if not its:
        out.append("<p>None.</p>")
    else:
        out.append("<table><tr><th>#</th><th>check</th><th>kind</th><th>outcome</th><th>commit</th></tr>" +
                   "".join(f"<tr><td>{e(i['n'])}</td><td><code>{e(i['check'])}</code></td><td>{e(i.get('kind'))}</td>"
                           f"<td>{e(i.get('status'))}</td><td>{e((i.get('sha') or '-')[:10])}</td></tr>" for i in its) + "</table>")
    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    agent = sys.argv[1]
    path = os.path.join(L.bench_dir(), agent, "summary.html")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(build(agent))
    print(f"summary: {path}")


if __name__ == "__main__":
    main()
