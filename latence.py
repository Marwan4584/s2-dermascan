"""Mesure 12 — latence de dix appels successifs a /predict.

    python3 latence.py                 # http://localhost:8000
    python3 latence.py http://localhost:8080
"""
import json
import statistics
import sys
import time

import requests

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000") + "/predict"
charge = json.load(open("charge.json"))

durees = []
for _ in range(10):
    t0 = time.perf_counter()
    r = requests.post(URL, json=charge, timeout=10)
    durees.append((time.perf_counter() - t0) * 1000)
    r.raise_for_status()

print(f"min {min(durees):.1f} ms | mediane {statistics.median(durees):.1f} ms | "
      f"max {max(durees):.1f} ms")
