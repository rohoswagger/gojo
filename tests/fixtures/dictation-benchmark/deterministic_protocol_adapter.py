#!/usr/bin/env python3
"""Deterministic adapter protocol fixture. It does not recognize speech or measure ASR."""

import json
import subprocess
import sys
import time
from pathlib import Path


request = json.load(sys.stdin)
options = request["config"].get("adapter_config", {})
mode = options.get("test_behavior", "complete")
Path(request["artifact_dir"], "fixture-request.json").write_text(json.dumps(request), encoding="utf-8")
print("deterministic protocol fixture; no ASR inference", file=sys.stderr, flush=True)
if mode in ("timeout", "child-exit", "child-complete"):
    child = subprocess.Popen([sys.executable, "-c", "import pathlib,sys,time; directory=pathlib.Path(sys.argv[1]); (directory/'child-ready.txt').write_text('ready'); print('ready',flush=True); time.sleep(1); (directory/'child-leaked.txt').write_text('leaked')", request["artifact_dir"]], stdout=subprocess.PIPE)
    if child.stdout.readline() != b"ready\n":
        raise RuntimeError("fixture child did not start")
    child.stdout.close()
if mode == "timeout":
    time.sleep(5)
    raise SystemExit(0)
if mode == "child-exit":
    raise SystemExit(7)
if mode == "exit":
    raise SystemExit(9)
if mode == "malformed":
    print("not-json", flush=True)
    raise SystemExit(0)
for index, item in enumerate(request["plan"]):
    row = {"schema_version": 1, **item, "hypothesis": options.get("hypotheses", {}).get(item["case_id"], ""), "model_state": "unknown", "timings_ms": {"fixture_stage": options.get("latency_ms", 10)}}
    if options.get("raw_hypotheses") is not None:
        row["raw_hypothesis"] = options["raw_hypotheses"].get(item["case_id"], "")
    if mode == "partial" and index == len(request["plan"]) - 1:
        break
    if mode == "error" and index == 0:
        del row["hypothesis"]
        row["error"] = "intentional fixture failure"
    if mode == "unknown" and index == 0:
        row["item_id"] = "unplanned-item"
    if mode == "wrong-repeat" and index == 0:
        row["repeat"] = 999
    if mode in ("negative", "bool", "infinity", "nan"):
        row["timings_ms"]["fixture_stage"] = {"negative": -1, "bool": True, "infinity": float("inf"), "nan": float("nan")}[mode]
    if mode == "missing-stage":
        row["timings_ms"] = {}
    if mode in ("warm-without-session", "first-warm", "warm-first", "new-session"):
        row["model_state"] = "first" if index == 0 else "warm"
        if mode != "warm-without-session":
            row["session_id"] = "fixture-session"
        if mode == "warm-first":
            row["model_state"] = "warm"
        if mode == "new-session" and index:
            row["session_id"] = "replacement-session"
    print(json.dumps(row), flush=True)
    if mode == "duplicate" and index == 0:
        print(json.dumps(row), flush=True)
