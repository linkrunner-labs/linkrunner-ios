import collections, json, os, sys

path = sys.argv[1]
quiet = "--quiet" in sys.argv
expected = 446
rows = [json.loads(l) for l in open(path)] if os.path.exists(path) else []
events = [r for r in rows if r["path"] == "/api/client/capture-event" and r["status"] == 200]
ids = collections.Counter(r["i"] for r in events)
ok = len(ids) == expected and all(c == 1 for c in ids.values())
if quiet:
    sys.exit(0 if len(ids) >= expected else 1)
times = [r["t"] for r in rows]
gaps = sorted(b - a for a, b in zip(times, times[1:]))
print(f"events={len(events)} unique={len(ids)} duplicates={sum(c - 1 for c in ids.values())} "
      f"missing={expected - len(ids)} tokens={sorted({r['token'] for r in rows if r['token']})}")
if len(times) > 1:
    print(f"requests={len(rows)} rate_per_s={len(rows) / (times[-1] - times[0]):.2f} p50_gap_ms={gaps[len(gaps) // 2] * 1000:.0f}")
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
