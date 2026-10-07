#!/usr/bin/env python3
"""Rebuild daily Claude Code work time from ~/.claude/projects transcripts
(the days before hook.sh existed) into backfill.json for the 잔디 grid."""
import json, glob, os
from collections import defaultdict
from datetime import datetime

GAP_CAP = 10 * 60  # ponytail: a >10min silence inside a turn counts as 10min (stuck on approval, lunch...)


def ts(e):
    return datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")).timestamp()


def is_prompt(e):
    if e.get("type") != "user" or e.get("isMeta") or e.get("isSidechain"):
        return False
    c = e.get("message", {}).get("content")
    if isinstance(c, list):
        return not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)
    return isinstance(c, str)


def turns(entries):
    """Yield (start_ts, active_seconds) per prompt→last reply turn."""
    start = prev = None
    active = 0.0
    for e in entries:
        if "timestamp" not in e or e.get("isSidechain"):
            continue
        t = ts(e)
        if is_prompt(e):
            if start is not None:
                yield start, active
            start, prev, active = t, t, 0.0
        elif start is not None and e.get("type") == "assistant":
            active += min(t - prev, GAP_CAP)
            prev = t
    if start is not None:
        yield start, active


def main():
    days = defaultdict(float)
    for path in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
        entries = []
        with open(path, errors="ignore") as f:
            for line in f:
                try:
                    entries.append(json.loads(line))
                except ValueError:
                    pass
        for start, sec in turns(entries):
            days[datetime.fromtimestamp(start).strftime("%Y-%m-%d")] += sec
    out = os.path.expanduser("~/.capywork/backfill.json")
    with open(out, "w") as f:
        json.dump(dict(sorted(days.items())), f, indent=0)
    print(f"{len(days)} days → {out}")


def demo():
    e = lambda typ, t, **kw: {"type": typ, "timestamp": f"2026-10-07T00:{t}Z", **kw}
    log = [e("user", "00:00", message={"content": "hi"}),
           e("assistant", "01:00"),
           e("user", "01:30", message={"content": [{"type": "tool_result"}]}),
           e("assistant", "02:00"),
           e("user", "40:00", message={"content": "again"}),
           e("assistant", "59:00")]  # 19min gap → capped at 10
    got = [round(s) for _, s in turns(log)]
    assert got == [120, 600], got


if __name__ == "__main__":
    demo()
    main()
