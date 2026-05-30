#!/usr/bin/env python3
"""Claude Code usage profiler — aggregates across profiles (office + personal).

Reads session JSONL transcripts and produces benchmark distributions:
  - volume (sessions, turns, projects, date range), split by profile
  - model mix
  - token usage + rough cost
  - thinking ("deep thinking") ratio
  - tool frequency
  - slash command / skill usage
  - git branch work-type mix
  - per-request intent classification (heuristic)

Heuristic only. No network, no LLM. Transparent + tunable.

Profiles (Claude Code session stores):
  office   -> ~/.cco/projects   (work)
  personal -> ~/.cch/projects   (home)

Usage:
  cc-usage-bench.py                  # all profiles, aggregated + per-profile split
  cc-usage-bench.py --profile office
  cc-usage-bench.py --profile personal
  cc-usage-bench.py --roots /path/a /path/b   # override roots
"""
import argparse
import datetime
import json
import os
import re
import sys
from collections import Counter, defaultdict
from glob import glob

TIER_CONFIG = os.path.expanduser("~/.dotfiles/claude-code-shared/resources/skill-tiers.json")

# profile -> projects root
PROFILES = {
    "office":   os.path.expanduser("~/.cco/projects"),
    "personal": os.path.expanduser("~/.cch/projects"),
}

# ---- rough price per 1M tokens (USD). Adjust as needed. ----
PRICE = {
    "opus":   {"in": 15.0, "out": 75.0, "cache_w": 18.75, "cache_r": 1.50},
    "sonnet": {"in": 3.0,  "out": 15.0, "cache_w": 3.75,  "cache_r": 0.30},
    "haiku":  {"in": 1.0,  "out": 5.0,  "cache_w": 1.25,  "cache_r": 0.10},
}

def model_family(m):
    if not m or m == "<synthetic>":
        return "synthetic"
    m = m.lower()
    if "opus" in m: return "opus"
    if "sonnet" in m: return "sonnet"
    if "haiku" in m: return "haiku"
    return "other"

def text_of(content):
    """Flatten a message.content into plain text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for c in content:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "text":
                out.append(c.get("text", ""))
        return "\n".join(out)
    return ""

def is_tool_result_turn(content):
    """A user record that is actually a tool_result, not a human prompt."""
    if isinstance(content, list):
        return any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return False

SLASH_RE = re.compile(r"<command-name>\s*/?([\w:-]+)\s*</command-name>")

def slash_cmd(raw_text):
    m = SLASH_RE.search(raw_text)
    return m.group(1).lower() if m else None

NOISE_RE = re.compile(r"<local-command-caveat>|<command-name>\s*/?exit\s*</command-name>|local-command-stdout", re.I)
def is_noise(raw, cmd):
    """Control/system records that are not human work requests."""
    if cmd == "exit":
        return True
    if NOISE_RE.search(raw):
        return True
    return False

ACK_RE = re.compile(r"^(y|n|ya|yo|ok|k|go|yes|yep|yup|nope|no|sure|do it|continue|cont|next|proceed|"
                    r"thanks|thx|ty|great|nice|perfect|good|lgtm|looks good|afk|done|stop|wait|"
                    r"[a-f]|[0-9]{1,3}|[a-f]\s*[\+,&]\s*[a-f]|[0-9]+\s*-\s*[0-9]+)$", re.I)
def is_continuation(raw):
    """Short ack or AskUserQuestion answer (a/b/c, yes, go, 1-5, b+c)."""
    s = raw.strip()
    if len(s) <= 3:
        return True
    if ACK_RE.match(s):
        return True
    return False

QUESTION_RE = re.compile(r"^\s*(can (we|i|you)|could (we|i|you)|will it|will that|does (it|this|that)|"
                         r"do (we|you)|should (we|i)|is it|is that|are (we|you)|why (does|is|do)|"
                         r"what (about|if|is|happens)|how (does|come)|wont|won't|isnt|isn't)\b", re.I)

def branch_prefix(b):
    if not b:
        return "none"
    return b.split("/")[0].lower() if "/" in b else b.lower()

# ---- intent classification ----
PLAN_CMDS   = {"to-prd-html", "to-prd", "grill-me", "grill-with-docs", "to-tasks", "prototype", "plan"}
TEST_CMDS   = {"tdd", "to-e2e-tests"}
REVIEW_CMDS = {"review", "code-review", "security-review", "caveman-review"}
REFAC_CMDS  = {"improve-component", "improve-codebase-architecture", "simplify"}
RESEARCH_CMDS = {"how-to", "deep-research", "tldr-tech"}
RUNTASK_CMDS = {"run-tasks", "run-task-followups", "tasks-to-linear"}

TEST_BASH = re.compile(r"\b(pytest|jest|vitest|playwright|npm (run )?test|yarn test|go test|cargo test|rspec|mocha|tox|unittest)\b", re.I)
GIT_COMMIT_BASH = re.compile(r"\bgit (commit|push|merge|rebase|cherry-pick)\b", re.I)
GIT_BRANCH_BASH = re.compile(r"\bgit (checkout -b|switch -c|branch)\b", re.I)

def classify(prompt, cmd, tools, bash_cmds, thinking_tokens, branch, edits, writes):
    """Return (primary_bucket, set_of_labels)."""
    p = prompt.lower()
    labels = set()

    # command-driven (strong signal)
    if cmd in PLAN_CMDS: labels.add("planning")
    if cmd in TEST_CMDS: labels.add("testing")
    if cmd in REVIEW_CMDS: labels.add("review")
    if cmd in REFAC_CMDS: labels.add("refactor")
    if cmd in RESEARCH_CMDS: labels.add("research")
    if cmd in RUNTASK_CMDS: labels.add("feature-code")

    # bash-driven
    if any(TEST_BASH.search(b) for b in bash_cmds): labels.add("testing")
    if any(GIT_COMMIT_BASH.search(b) for b in bash_cmds): labels.add("git-ops")
    if any(GIT_BRANCH_BASH.search(b) for b in bash_cmds): labels.add("git-ops")

    # keyword-driven
    if re.search(r"\b(plan|design|architect|approach|strategy|spec|prd|think through|brainstorm)\b", p): labels.add("planning")
    if re.search(r"\b(test|spec|coverage|e2e|unit test|integration test)\b", p): labels.add("testing")
    if re.search(r"\b(rename|refactor|extract|move|clean ?up|reorganize|simplify|dedupe|consolidate)\b", p): labels.add("refactor")
    if re.search(r"\b(fix|bug|broken|failing|error|crash|regression|not working|doesn't work)\b", p): labels.add("bugfix")
    if re.search(r"\b(add|implement|build|create|feature|new (page|component|endpoint|screen)|make (it|the|a|sure)|change|update|set|use|show|color|wire|hook up|support|enable)\b", p): labels.add("feature-code")
    if re.search(r"\b(review|audit|look over|check my)\b", p): labels.add("review")
    if re.search(r"\b(commit|push|open (a )?pr|pull request|merge)\b", p): labels.add("git-ops")
    if re.search(r"\b(how do i|how to|what is|explain|why does|research|investigate|find out)\b", p): labels.add("research")

    # tool/branch-driven
    bp = branch_prefix(branch)
    if bp in ("feat", "feature"): labels.add("feature-code")
    if bp == "fix": labels.add("bugfix")
    if bp == "spike": labels.add("research")
    if edits + writes >= 3: labels.add("feature-code")

    # deep-thinking proxy
    if thinking_tokens >= 2000: labels.add("planning")

    # discussion: question-form prompt with no work signal
    if not labels and QUESTION_RE.search(prompt):
        labels.add("discussion")

    if not labels:
        labels.add("other")

    # primary = priority order
    for b in ["planning", "review", "testing", "refactor", "bugfix", "git-ops",
              "research", "feature-code", "discussion", "other"]:
        if b in labels:
            return b, labels
    return "other", labels


def new_stats():
    return {
        "sessions": 0,
        "user_prompts": 0,
        "asst_turns": 0,
        "proj": Counter(),
        "models": Counter(),
        "tok": defaultdict(lambda: defaultdict(int)),
        "tools": Counter(),
        "cmds": Counter(),
        "branches": Counter(),
        "thinking_turns": 0,
        "primary": Counter(),
        "labels": Counter(),
        "noise": 0,
        "continuation": 0,
        "dates": [],
    }

def merge(dst, src):
    dst["sessions"] += src["sessions"]
    dst["user_prompts"] += src["user_prompts"]
    dst["asst_turns"] += src["asst_turns"]
    dst["proj"].update(src["proj"])
    dst["models"].update(src["models"])
    for fam, d in src["tok"].items():
        for k, v in d.items():
            dst["tok"][fam][k] += v
    dst["tools"].update(src["tools"])
    dst["cmds"].update(src["cmds"])
    dst["branches"].update(src["branches"])
    dst["thinking_turns"] += src["thinking_turns"]
    dst["primary"].update(src["primary"])
    dst["labels"].update(src["labels"])
    dst["noise"] += src["noise"]
    dst["continuation"] += src["continuation"]
    dst["dates"].extend(src["dates"])


def scan_root(root, S):
    """Scan one projects root into stats dict S. Main sessions only (depth: root/proj/file)."""
    files = sorted(glob(os.path.join(root, "*", "*.jsonl")))
    for f in files:
        S["sessions"] += 1
        proj = os.path.basename(os.path.dirname(f))
        S["proj"][proj] += 1
        try:
            with open(f) as fh:
                recs = [json.loads(l) for l in fh if l.strip()]
        except Exception:
            continue

        cur = None

        def flush(cur):
            if cur is None:
                return
            primary, labels = classify(
                cur["prompt"], cur["cmd"], cur["tools"], cur["bash"],
                cur["think"], cur["branch"], cur["edits"], cur["writes"])
            S["primary"][primary] += 1
            for l in labels:
                S["labels"][l] += 1

        for d in recs:
            t = d.get("type")
            if t == "user":
                if d.get("isSidechain"):
                    continue
                content = d.get("message", {}).get("content")
                if is_tool_result_turn(content):
                    continue
                raw = content if isinstance(content, str) else text_of(content)
                cmd = slash_cmd(raw if isinstance(content, str) else json.dumps(content))
                if is_noise(raw, cmd):
                    cur = None
                    S["noise"] += 1
                    continue
                flush(cur)
                S["user_prompts"] += 1
                if cmd:
                    S["cmds"][cmd] += 1
                branch = d.get("gitBranch")
                S["branches"][branch_prefix(branch)] += 1
                ts = d.get("timestamp", "")
                if ts:
                    S["dates"].append(ts[:10])
                if is_continuation(raw) and not cmd:
                    S["continuation"] += 1
                    cur = None
                    continue
                cur = {"prompt": raw, "cmd": cmd, "tools": Counter(), "bash": [],
                       "think": 0, "branch": branch, "edits": 0, "writes": 0}
            elif t == "assistant":
                if d.get("isSidechain"):
                    continue
                S["asst_turns"] += 1
                m = d.get("message", {})
                fam = model_family(m.get("model"))
                S["models"][fam] += 1
                u = m.get("usage", {}) or {}
                S["tok"][fam]["in"] += u.get("input_tokens", 0)
                S["tok"][fam]["out"] += u.get("output_tokens", 0)
                S["tok"][fam]["cache_w"] += u.get("cache_creation_input_tokens", 0)
                S["tok"][fam]["cache_r"] += u.get("cache_read_input_tokens", 0)
                content = m.get("content", [])
                if isinstance(content, list):
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        ct = c.get("type")
                        if ct == "thinking":
                            if cur is not None:
                                cur["think"] += len(c.get("thinking", "")) // 4
                        elif ct == "tool_use":
                            name = c.get("name", "?")
                            S["tools"][name] += 1
                            if cur is not None:
                                cur["tools"][name] += 1
                                if name == "Edit": cur["edits"] += 1
                                elif name == "Write": cur["writes"] += 1
                                elif name == "Bash":
                                    cmd_str = (c.get("input", {}) or {}).get("command", "")
                                    cur["bash"].append(cmd_str)
                    if any(isinstance(c, dict) and c.get("type") == "thinking" for c in content):
                        S["thinking_turns"] += 1
        flush(cur)


def pct(n, d):
    return f"{(100.0*n/d):5.1f}%" if d else "  0.0%"

def cost_of(tok):
    grand = 0.0
    rows = []
    for fam in ("opus", "sonnet", "haiku"):
        if fam not in tok:
            continue
        d = tok[fam]
        pr = PRICE[fam]
        cost = (d["in"]*pr["in"] + d["out"]*pr["out"]
                + d["cache_w"]*pr["cache_w"] + d["cache_r"]*pr["cache_r"]) / 1e6
        grand += cost
        rows.append((fam, d, cost))
    return rows, grand


def report(title, S, detailed=True):
    print("=" * 64)
    print(title)
    print("=" * 64)
    work_reqs = sum(S["primary"].values())
    if S["dates"]:
        print(f"Date range : {min(S['dates'])} -> {max(S['dates'])}")
    print(f"Sessions   : {S['sessions']}")
    print(f"Human reqs : {S['user_prompts']}  (work={work_reqs}, continuation/ack={S['continuation']})")
    print(f"Noise dropped: {S['noise']}  (/exit, local-command-caveat)")
    print(f"Asst turns : {S['asst_turns']}")
    if S["sessions"]:
        print(f"Reqs/session: {S['user_prompts']/S['sessions']:.1f}")

    if detailed:
        print("\n--- PROJECTS (sessions) ---")
        for p, n in S["proj"].most_common(12):
            print(f"  {n:4d}  {p}")

    print("\n--- MODEL MIX (assistant turns) ---")
    tot_m = sum(S["models"].values())
    for fam, n in S["models"].most_common():
        print(f"  {pct(n,tot_m)}  {fam:10s} {n}")

    print("\n--- TOKENS + ROUGH COST (USD) ---")
    rows, grand = cost_of(S["tok"])
    for fam, d, cost in rows:
        print(f"  {fam:8s} in={d['in']:>10,} out={d['out']:>9,} "
              f"cacheW={d['cache_w']:>11,} cacheR={d['cache_r']:>12,}  ${cost:,.2f}")
    print(f"  {'TOTAL':8s} ~ ${grand:,.2f}")

    print("\n--- DEEP THINKING ---")
    print(f"  {pct(S['thinking_turns'], S['asst_turns'])} of assistant turns had a thinking block ({S['thinking_turns']})")

    if detailed:
        print("\n--- TOP TOOLS ---")
        tot_t = sum(S["tools"].values())
        for name, n in S["tools"].most_common(15):
            print(f"  {pct(n,tot_t)}  {name:34s} {n}")

        print("\n--- SLASH COMMANDS / SKILLS ---")
        for name, n in S["cmds"].most_common(25):
            print(f"  {n:4d}  /{name}")

        print("\n--- GIT BRANCH WORK-TYPE (by prompt) ---")
        tot_b = sum(S["branches"].values())
        for name, n in S["branches"].most_common(12):
            print(f"  {pct(n,tot_b)}  {name:18s} {n}")

    print("\n--- REQUEST INTENT (primary bucket, work requests only) ---")
    tot_p = sum(S["primary"].values())
    for name, n in S["primary"].most_common():
        print(f"  {pct(n,tot_p)}  {name:14s} {n}")

    print("\n--- REQUEST INTENT (all labels, multi-count) ---")
    for name, n in S["labels"].most_common():
        print(f"  {pct(n,tot_p)}  {name:14s} {n}")
    print()


def _iso_week(ts):
    try:
        y, w, _ = datetime.date.fromisoformat(ts[:10]).isocalendar()
        return f"{y}-W{w:02d}"
    except Exception:
        return None


def trend_report(roots):
    """Weekly model-mix + est cost. Shows the shift over time (e.g. post-tiering)."""
    weeks = {}
    for name, root in roots.items():
        for f in sorted(glob(os.path.join(root, "*", "*.jsonl"))):
            try:
                recs = [json.loads(l) for l in open(f) if l.strip()]
            except Exception:
                continue
            for d in recs:
                if d.get("type") != "assistant" or d.get("isSidechain"):
                    continue
                wk = _iso_week(d.get("timestamp", ""))
                if not wk:
                    continue
                m = d.get("message", {})
                fam = model_family(m.get("model"))
                if fam not in ("opus", "sonnet", "haiku"):
                    continue
                W = weeks.setdefault(wk, {"turns": Counter(),
                                          "tok": defaultdict(lambda: defaultdict(int))})
                W["turns"][fam] += 1
                u = m.get("usage", {}) or {}
                W["tok"][fam]["in"] += u.get("input_tokens", 0)
                W["tok"][fam]["out"] += u.get("output_tokens", 0)
                W["tok"][fam]["cache_w"] += u.get("cache_creation_input_tokens", 0)
                W["tok"][fam]["cache_r"] += u.get("cache_read_input_tokens", 0)

    print("=" * 64)
    print("WEEKLY MODEL TREND (assistant turns + est cost)")
    print("=" * 64)
    print(f"  {'week':9s} {'turns':>6} {'opus%':>6} {'son%':>6} {'hai%':>6} {'est$':>9}")
    for wk in sorted(weeks):
        W = weeks[wk]
        t = W["turns"]
        tot = sum(t.values()) or 1
        _, cost = cost_of(W["tok"])
        print(f"  {wk:9s} {tot:6d} {100*t['opus']//tot:5d}% "
              f"{100*t['sonnet']//tot:5d}% {100*t['haiku']//tot:5d}% ${cost:8,.0f}")
    print()


SKILL_BODY_RE = re.compile(r"skills/([a-z0-9-]+)/SKILL\.md", re.I)

def detect_skill(raw, cmd):
    if cmd:
        return cmd
    m = SKILL_BODY_RE.search(raw)
    return m.group(1) if m else None


def adherence_report(roots, config_path):
    """Per-skill expected (config) vs actual model used during its invocations."""
    try:
        cfg = json.load(open(config_path))
    except Exception as e:
        print(f"cannot read tier config {config_path}: {e}", file=sys.stderr)
        return
    tiers, assign = cfg["tiers"], cfg["skills"]
    expected = {s: tiers[t]["model"] for s, t in assign.items()}
    per = defaultdict(Counter)  # skill -> Counter(actual dominant model)

    for name, root in roots.items():
        for f in sorted(glob(os.path.join(root, "*", "*.jsonl"))):
            try:
                recs = [json.loads(l) for l in open(f) if l.strip()]
            except Exception:
                continue
            cur = None

            def flush(cur):
                if cur is None or not cur["skill"] or not cur["models"]:
                    return
                if cur["skill"] not in expected:
                    return
                per[cur["skill"]][cur["models"].most_common(1)[0][0]] += 1

            for d in recs:
                t = d.get("type")
                if t == "user":
                    if d.get("isSidechain"):
                        continue
                    c = d.get("message", {}).get("content")
                    if is_tool_result_turn(c):
                        continue
                    raw = c if isinstance(c, str) else text_of(c)
                    cmd = slash_cmd(raw if isinstance(c, str) else json.dumps(c))
                    if is_noise(raw, cmd):
                        cur = None
                        continue
                    flush(cur)
                    cur = {"skill": detect_skill(raw, cmd), "models": Counter()}
                elif t == "assistant":
                    if d.get("isSidechain") or cur is None:
                        continue
                    fam = model_family(d.get("message", {}).get("model"))
                    if fam in ("opus", "sonnet", "haiku"):
                        cur["models"][fam] += 1
            flush(cur)

    print("=" * 64)
    print("TIER ADHERENCE (skill invocations: expected vs actual model)")
    print("=" * 64)
    print("  Only meaningful for sessions AFTER tiering rollout (older runs used the session model).")
    print(f"  {'skill':32s} {'exp':7s} {'match':>6} {'n':>5}  actual-mix")
    tot_match = tot = 0
    for s in sorted(expected):
        c = per.get(s)
        if not c:
            continue
        n = sum(c.values())
        match = c.get(expected[s], 0)
        tot_match += match
        tot += n
        mix = ", ".join(f"{k}:{v}" for k, v in c.most_common())
        print(f"  {s:32s} {expected[s]:7s} {pct(match,n).strip():>6} {n:5d}  {mix}")
    print(f"\n  OVERALL adherence: {pct(tot_match,tot).strip()} ({tot_match}/{tot})")
    print()


def main():
    ap = argparse.ArgumentParser(description="Claude Code usage benchmark across profiles.")
    ap.add_argument("--profile", choices=list(PROFILES) + ["all"], default="all",
                    help="which session profile to scan (default: all)")
    ap.add_argument("--roots", nargs="+", help="override: explicit projects roots to scan")
    ap.add_argument("--trend", action="store_true",
                    help="weekly model-mix + est cost trend (shows the shift over time)")
    ap.add_argument("--adherence", action="store_true",
                    help="per-skill expected (config) vs actual model used")
    ap.add_argument("--config", default=TIER_CONFIG, help="path to skill-tiers.json")
    args = ap.parse_args()

    if args.roots:
        roots = {f"root{i}": r for i, r in enumerate(args.roots)}
    elif args.profile == "all":
        roots = PROFILES
    else:
        roots = {args.profile: PROFILES[args.profile]}

    if args.trend:
        trend_report(roots)
        return
    if args.adherence:
        adherence_report(roots, args.config)
        return

    per = {}
    agg = new_stats()
    for name, root in roots.items():
        if not os.path.isdir(root):
            print(f"[skip] {name}: no dir at {root}", file=sys.stderr)
            continue
        S = new_stats()
        scan_root(root, S)
        per[name] = S
        merge(agg, S)

    # per-profile reports
    for name, S in per.items():
        report(f"PROFILE: {name.upper()}  ({roots[name]})", S, detailed=True)

    # aggregate (only if >1 profile scanned)
    if len(per) > 1:
        report("AGGREGATE (all profiles combined)", agg, detailed=True)

        # compact side-by-side intent split
        print("=" * 64)
        print("INTENT SPLIT BY PROFILE (primary %)")
        print("=" * 64)
        names = list(per)
        buckets = ["planning", "feature-code", "testing", "bugfix", "review",
                   "refactor", "research", "git-ops", "discussion", "other"]
        hdr = "  " + "bucket".ljust(14) + "".join(n.ljust(12) for n in names) + "AGG"
        print(hdr)
        for b in buckets:
            row = "  " + b.ljust(14)
            for n in names:
                tp = sum(per[n]["primary"].values())
                row += pct(per[n]["primary"].get(b, 0), tp).strip().ljust(12)
            ta = sum(agg["primary"].values())
            row += pct(agg["primary"].get(b, 0), ta).strip()
            print(row)
        print()

if __name__ == "__main__":
    main()
