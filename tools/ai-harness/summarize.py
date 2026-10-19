"""Compares measured runs. Usage: python3 -I summarize.py <run-dir> [<run-dir> …]

Prints, per passage set and run, how many moments got a model name and how many recaps were
written (split into intense passages and calm controls), the errors, latency, and for moments
how often each field was filled.
"""
import collections, json, os, statistics, sys


def load(path):
    return [json.loads(line) for line in open(path)] if os.path.exists(path) else []


def percentile(values, fraction):
    return values[min(len(values) - 1, int(fraction * len(values)))] if values else 0


for passage_set in ("tuned", "heldout"):
    for mode in ("moment", "recap"):
        print(f"## {passage_set} {mode}")
        for run in sys.argv[1:]:
            rows = load(os.path.join(run, f"{passage_set}-{mode}.jsonl"))
            if not rows:
                continue
            ok = [r for r in rows if r["outcome"] != "error"]
            total = collections.Counter(r["kind"] for r in rows)
            passed = collections.Counter(r["kind"] for r in ok)
            errors = collections.Counter(r["error"] for r in rows if r["outcome"] == "error")
            seconds = sorted(r["seconds"] for r in ok)
            line = (f"{os.path.basename(os.path.normpath(run)):12} {len(ok)}/{len(rows)} ({100 * len(ok) / len(rows):.1f}%)"
                    f"  intense {passed['sensitive']}/{total['sensitive']}  controls {passed['control']}/{total['control']}"
                    f"  median {statistics.median(seconds) if seconds else 0:.1f}s p90 {percentile(seconds, 0.9):.1f}s")
            print(line + (f"  errors {dict(errors)}" if errors else ""))
            if mode == "moment" and ok:
                filled = {k: sum(1 for r in ok if r.get(k)) for k in ("note", "quote", "mood", "categories", "characters")}
                print(" " * 13 + "fields " + ", ".join(f"{k} {v}" for k, v in filled.items()))
            if mode == "recap" and ok:
                empty = sum(1 for r in ok if not r.get("headline"))
                print(" " * 13 + f"headline empty {empty}")
        print()
