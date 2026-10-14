#!/usr/bin/env python3
"""Freeze dictation audio, execute a batch adapter, and compare verified run artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time
import uuid
import wave
from pathlib import Path

from score_transcripts import score


SAFE_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,95}\Z")
STATES = ("first", "warm", "unknown")
ADAPTER_CASE_FIELDS = ("id", "audio_path", "audio_sha256", "frames", "sample_rate", "channels", "sample_width", "duration_seconds", "kind")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def file_hash(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def reject_constant(value):
    raise ValueError(f"non-finite JSON number {value}")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"), parse_constant=reject_constant)


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")


def read_jsonl(path):
    rows = []
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            row = json.loads(line, parse_constant=reject_constant)
            if not isinstance(row, dict):
                raise ValueError(f"{path}:{number}: expected object")
            rows.append(row)
    return rows


def number(value, name, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 or (positive and value == 0):
        raise ValueError(f"{name} must be a finite {'positive' if positive else 'nonnegative'} number")
    return value


def integer(value, name, minimum=0):
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")
    return value


def identifier(value):
    if not isinstance(value, str) or not SAFE_ID.fullmatch(value):
        raise ValueError(f"unsafe case id {value!r}")
    return value


def wav_metadata(path):
    with wave.open(str(path), "rb") as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 16000, "NONE"):
            raise ValueError(f"{path}: expected PCM16 mono 16000 Hz WAV")
        frames = audio.getnframes()
        if frames <= 0 or len(audio.readframes(frames)) != frames * 2:
            raise ValueError(f"{path}: empty or truncated WAV")
    return {"frames": frames, "sample_rate": 16000, "channels": 1, "sample_width": 2, "duration_seconds": frames / 16000}


def prepare(arguments):
    source = arguments.source.resolve()
    rows = read_jsonl(source)
    if not rows:
        raise ValueError("source corpus has no cases")
    ids = set()
    for row in rows:
        case_id = identifier(row.get("id"))
        if case_id in ids:
            raise ValueError(f"duplicate case id {case_id}")
        ids.add(case_id)
        if not isinstance(row.get("reference"), str):
            raise ValueError(f"{case_id}: reference must be a string")
        if row.get("type") == "silence":
            if row["reference"].strip() or "audio_path" in row:
                raise ValueError(f"{case_id}: generated silence requires an empty reference and no audio_path")
            number(row.get("duration_seconds"), "duration_seconds", positive=True)
        elif "audio_path" not in row and not arguments.synthesize:
            raise ValueError(f"{case_id}: supply audio_path or explicitly enable --synthesize")
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / "audio").mkdir()
    cases = []
    for row in rows:
        case_id = row["id"]
        destination = output / "audio" / f"{case_id}.wav"
        kind = "recorded"
        if row.get("type") == "silence":
            frames = round(row["duration_seconds"] * 16000)
            if frames < 1:
                raise ValueError("silence duration is shorter than one frame")
            with wave.open(str(destination), "wb") as audio:
                audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                block = b"\0" * (2 * min(frames, 16000))
                remaining = frames
                while remaining:
                    count = min(remaining, 16000)
                    audio.writeframesraw(block[:count * 2])
                    remaining -= count
            kind = "silence"
        elif "audio_path" in row:
            if not isinstance(row["audio_path"], str) or not row["audio_path"]:
                raise ValueError(f"{case_id}: audio_path must be a nonempty string")
            supplied = (source.parent / row["audio_path"]).resolve()
            wav_metadata(supplied)
            shutil.copyfile(supplied, destination)
        else:
            if sys.platform != "darwin":
                raise ValueError("--synthesize requires macOS say and afconvert")
            spoken = row.get("spoken", row["reference"])
            voice = row.get("voice", "Samantha")
            if not isinstance(spoken, str) or not spoken.strip() or not isinstance(voice, str) or not voice:
                raise ValueError(f"{case_id}: spoken text and voice must be nonempty strings")
            intermediate = destination.with_suffix(".aiff")
            subprocess.run(["/usr/bin/say", "-v", voice, "-o", str(intermediate), "--", spoken], check=True)
            subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(intermediate), str(destination)], check=True)
            intermediate.unlink()
            kind = "synthetic"
        case = {"id": case_id, "reference": row["reference"], "audio_path": f"audio/{case_id}.wav", "audio_sha256": file_hash(destination), "kind": kind, **wav_metadata(destination)}
        if kind == "synthetic":
            case["synthesis"] = {"voice": voice, "spoken": spoken, "host_os": platform.platform()}
        cases.append(case)
    corpus = {"schema_version": 1, "cases": cases}
    corpus["corpus_sha256"] = digest(corpus)
    write_json(output / "corpus.json", corpus)
    print(json.dumps({"corpus": str(output), "corpus_sha256": corpus["corpus_sha256"], "cases": len(cases)}))
    return 0


def verify_corpus(directory):
    directory = Path(directory).resolve()
    corpus = read_json(directory / "corpus.json")
    if not isinstance(corpus, dict) or type(corpus.get("schema_version")) is not int or corpus["schema_version"] != 1 or not isinstance(corpus.get("cases"), list) or not corpus["cases"]:
        raise ValueError("invalid corpus schema")
    if corpus.get("corpus_sha256") != digest({key: value for key, value in corpus.items() if key != "corpus_sha256"}):
        raise ValueError("corpus hash mismatch")
    ids = set()
    for case in corpus["cases"]:
        case_id = identifier(case.get("id"))
        if case_id in ids or not isinstance(case.get("reference"), str):
            raise ValueError("duplicate case or invalid reference")
        ids.add(case_id)
        if case.get("audio_path") != f"audio/{case_id}.wav":
            raise ValueError(f"{case_id}: unsafe audio path")
        path = directory / case["audio_path"]
        if path.is_symlink() or path.resolve().parent != (directory / "audio").resolve() or (directory / "audio").is_symlink():
            raise ValueError(f"{case_id}: audio path escapes corpus")
        if file_hash(path) != case.get("audio_sha256"):
            raise ValueError(f"{case_id}: audio hash mismatch")
        for key, value in wav_metadata(path).items():
            if case.get(key) != value:
                raise ValueError(f"{case_id}: audio metadata mismatch for {key}")
    return corpus


def validate_config(config):
    if not isinstance(config, dict) or type(config.get("schema_version")) is not int or config["schema_version"] != 1:
        raise ValueError("config schema_version must be 1")
    argv = config.get("adapter")
    if not isinstance(argv, list) or not argv or any(not isinstance(item, str) or not item for item in argv):
        raise ValueError("adapter must be a nonempty argv list")
    for key in ("engine", "model"):
        if not isinstance(config.get(key), dict) or any(not isinstance(config[key].get(field), str) or not config[key][field] for field in ("id", "revision")):
            raise ValueError(f"{key} requires nonempty id and declared revision")
    integer(config.get("repeats"), "repeats", 1)
    integer(config.get("warmup"), "warmup")
    if config.get("normalization") not in ("basic", "none"):
        raise ValueError("normalization must be basic or none")
    if config.get("process_lifecycle") not in ("persistent", "per_case"):
        raise ValueError("process_lifecycle must be persistent or per_case")
    if type(config.get("concurrency")) is not int or config["concurrency"] != 1:
        raise ValueError("only concurrency 1 is supported")
    number(config.get("timeout_seconds"), "timeout_seconds", positive=True)
    definitions = config.get("metric_definitions")
    if not isinstance(definitions, dict) or not definitions:
        raise ValueError("metric_definitions must declare measurement boundaries")
    for key, definition in definitions.items():
        identifier(key)
        if not isinstance(definition, dict) or definition.get("unit") != "ms" or not isinstance(definition.get("definition"), str) or not definition["definition"].strip():
            raise ValueError(f"{key}: requires unit ms and a measurement definition")
    if config.get("primary_metric") not in definitions:
        raise ValueError("primary_metric must name a declared metric")
    if not isinstance(config.get("adapter_config", {}), dict):
        raise ValueError("adapter_config must be an object")
    if not isinstance(config.get("configuration", {}), dict):
        raise ValueError("configuration must be an object of semantic engine settings")
    if "build_mode" in config and (not isinstance(config["build_mode"], str) or not config["build_mode"]):
        raise ValueError("build_mode must be a nonempty declaration")
    return config


def build_plan(cases, config):
    return [{"item_id": f"{phase}-{repeat}-{case['id']}", "case_id": case["id"], "repeat": repeat, "phase": phase}
            for phase, count in (("rehearsal", config["warmup"]), ("measured", config["repeats"]))
            for repeat in range(count) for case in cases]


def tree_hash(directory):
    directory = Path(directory).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("model.path must be a local directory")
    files = []
    for path in sorted(directory.rglob("*")):
        if path.is_symlink() and not path.is_file():
            raise ValueError(f"model tree contains a directory or broken symlink: {path}")
        if path.is_file():
            files.append([path.relative_to(directory).as_posix(), file_hash(path)])
    if not files:
        raise ValueError("model directory is empty")
    return digest(files)


def measured_assets(config):
    executable = shutil.which(config["adapter"][0])
    if not executable or not Path(executable).is_file():
        raise ValueError("adapter executable is missing")
    files = [{"argument": index, "sha256": file_hash(value)} for index, value in enumerate(config["adapter"][1:], 1) if Path(value).is_file()]
    cli_path = config.get("adapter_config", {}).get("cli_path")
    tokenizer_path = config.get("adapter_config", {}).get("tokenizer_path")
    return {"adapter_executable_sha256": file_hash(executable), "adapter_argv_files": files,
            "model_tree_sha256": tree_hash(config["model"]["path"]) if "path" in config["model"] else None,
            "cli_sha256": file_hash(cli_path) if cli_path else None,
            "tokenizer_tree_sha256": tree_hash(tokenizer_path) if tokenizer_path else None,
            "benchmark_script_sha256": file_hash(__file__), "scorer_script_sha256": file_hash(Path(__file__).with_name("score_transcripts.py"))}


def host_metadata():
    cpu = platform.processor() or platform.machine()
    if sys.platform == "darwin":
        completed = subprocess.run(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True)
        cpu = completed.stdout.strip() or cpu
    return {"hostname": platform.node(), "os": platform.platform(), "cpu": cpu, "machine": platform.machine(), "logical_cpus": os.cpu_count(), "python": platform.python_version()}


def git_metadata():
    root = Path(__file__).resolve().parents[2]
    revision = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True)
    dirty = subprocess.run(["git", "-C", str(root), "status", "--porcelain"], capture_output=True, text=True)
    diff = subprocess.run(["git", "-C", str(root), "diff", "HEAD", "--binary"], capture_output=True)
    untracked = subprocess.run(["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", "-z"], capture_output=True)
    files = [[path, file_hash(root / path)] for path in untracked.stdout.decode("utf-8").split("\0") if path and (root / path).is_file()]
    return {"revision": revision.stdout.strip() if revision.returncode == 0 else None, "dirty": bool(dirty.stdout.strip()) if dirty.returncode == 0 else None,
            "working_tree_sha256": digest({"diff_sha256": hashlib.sha256(diff.stdout).hexdigest(), "untracked": files}) if diff.returncode == 0 and untracked.returncode == 0 else None}


def run_observation():
    return {"wall_unix_seconds": time.time(), "monotonic_seconds": time.monotonic(),
            "load_average": list(os.getloadavg()) if hasattr(os, "getloadavg") else None}


def validate_rows(raw_rows, plan, cases, config):
    expected = {item["item_id"]: item for item in plan}
    case_map = {case["id"]: case for case in cases}
    received = {}
    issues = []
    session = None
    known_session_rows = 0
    for index, row in enumerate(raw_rows):
        try:
            item_id = row.get("item_id")
            if item_id not in expected:
                raise ValueError(f"unknown item_id {item_id!r}")
            if item_id in received:
                raise ValueError(f"duplicate item_id {item_id}")
            item = expected[item_id]
            if type(row.get("schema_version")) is not int or row["schema_version"] != 1 or type(row.get("repeat")) is not int or any(row.get(key) != item[key] for key in ("case_id", "repeat", "phase")):
                raise ValueError(f"{item_id}: identity does not match plan")
            if len(received) >= len(plan) or item_id != plan[len(received)]["item_id"]:
                raise ValueError(f"{item_id}: adapter rows must follow planned order")
            has_error = isinstance(row.get("error"), str) and bool(row["error"])
            if ("hypothesis" in row) == has_error or (not has_error and not isinstance(row.get("hypothesis"), str)):
                raise ValueError(f"{item_id}: requires exactly one hypothesis string or nonempty error")
            if "raw_hypothesis" in row and not isinstance(row["raw_hypothesis"], str):
                raise ValueError(f"{item_id}: raw_hypothesis must be a string")
            timings = row.get("timings_ms", {})
            if not isinstance(timings, dict) or any(key not in config["metric_definitions"] for key in timings):
                raise ValueError(f"{item_id}: unknown timing stage")
            for key, value in timings.items():
                number(value, f"{item_id}.{key}")
            state = row.get("model_state", "unknown")
            if state not in STATES:
                raise ValueError(f"{item_id}: invalid model_state")
            if state != "unknown":
                session_id = row.get("session_id")
                if config["process_lifecycle"] != "persistent" or not isinstance(session_id, str) or not session_id:
                    raise ValueError(f"{item_id}: first/warm requires a persistent identified model session")
                if session is None:
                    session = session_id
                if session_id != session or state != ("first" if known_session_rows == 0 and index == 0 else "warm") or (known_session_rows == 0 and index != 0):
                    raise ValueError(f"{item_id}: inconsistent first/warm model session")
                known_session_rows += 1
            elif known_session_rows:
                raise ValueError(f"{item_id}: identified session cannot become unknown")
            case = case_map[item["case_id"]]
            received[item_id] = {**row, **item, "reference": case["reference"], "audio_sha256": case["audio_sha256"], "model_state": state, "timings_ms": timings}
        except (ValueError, TypeError) as error:
            issues.append(str(error))
    results = []
    for item in plan:
        if item["item_id"] in received:
            results.append(received[item["item_id"]])
        else:
            issues.append(f"missing planned item {item['item_id']}")
            case = case_map[item["case_id"]]
            results.append({"schema_version": 1, **item, "reference": case["reference"], "audio_sha256": case["audio_sha256"], "error": "missing or invalid adapter result", "model_state": "unknown", "timings_ms": {}})
    return results, issues


def distribution(values):
    if not values:
        return None
    ordered = sorted(values)
    mean = ordered[-1] * statistics.fmean(value / ordered[-1] for value in values) if ordered[-1] else 0.0
    return {"count": len(values), "min": ordered[0], "mean": mean, "p50": ordered[math.ceil(len(values) * .5) - 1], "p95": ordered[math.ceil(len(values) * .95) - 1], "p99": ordered[math.ceil(len(values) * .99) - 1], "max": ordered[-1]}


def summarize(run, rows):
    measured = [row for row in rows if row["phase"] == "measured"]
    failures = [row["item_id"] for row in rows if "error" in row]
    complete = run.get("status") == "complete" and run.get("adapter_returncode") == 0 and not failures and not run.get("errors")
    transcript_rows = [{"id": row["item_id"], "reference": row["reference"], "hypothesis": row.get("hypothesis", "")} for row in measured]
    accuracy = score(transcript_rows, run["config"]["normalization"]) if complete else None
    raw_count = sum("raw_hypothesis" in row for row in measured)
    raw_accuracy = score([{**row, "hypothesis": original["raw_hypothesis"]} for row, original in zip(transcript_rows, measured)], run["config"]["normalization"]) if complete and raw_count == len(measured) else None
    timings = {}
    for stage in run["config"]["metric_definitions"]:
        timings[stage] = {}
        for phase in ("measured", "rehearsal"):
            selected = [row for row in rows if row["phase"] == phase]
            timings[stage][phase] = {state: distribution([row["timings_ms"][stage] for row in selected if stage in row["timings_ms"] and (state == "all" or row["model_state"] == state)]) for state in ("all", *STATES)}
    primary = timings[run["config"]["primary_metric"]]["measured"]["all"]
    return {"schema_version": 1, "run_id": run["run_id"], "complete": complete,
            "coverage": {"planned": len(run["plan"]), "rows": len(rows), "measured": len(measured), "rehearsal": len(rows) - len(measured), "errors": len(failures)},
            "errors": run.get("errors", []), "failed_items": failures, "accuracy": accuracy, "raw_accuracy": raw_accuracy,
            "raw_hypothesis_coverage": {"available": raw_count, "expected": len(measured)}, "timings_ms": timings,
            "primary_metric": run["config"]["primary_metric"], "primary_p95_ms": primary["p95"] if primary and primary["count"] == len(measured) and complete else None}


def run_benchmark(arguments):
    started = run_observation()
    corpus = verify_corpus(arguments.corpus)
    config = validate_config(read_json(arguments.config))
    assets = measured_assets(config)
    plan = build_plan(corpus["cases"], config)
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / "artifacts").mkdir()
    run = {"schema_version": 1, "run_id": str(uuid.uuid4()), "status": "running", "errors": [], "corpus": corpus, "corpus_directory": str(arguments.corpus.resolve()), "config": config, "plan": plan, "assets": assets, "host": host_metadata(), "gojo_git": git_metadata(), "created_unix_seconds": started["wall_unix_seconds"], "run_observations": {"started": started}}
    request = {"schema_version": 1, "run_id": run["run_id"], "config": config, "plan": plan, "artifact_dir": str(output / "artifacts"), "cases": [{key: value for key, value in case.items() if key in ADAPTER_CASE_FIELDS} | {"audio_path": str((arguments.corpus / case["audio_path"]).resolve())} for case in corpus["cases"]]}
    write_json(output / "run.json", run)
    write_json(output / "request.json", request)
    with (output / "adapter.stdout.jsonl").open("wb") as stdout, (output / "adapter.stderr.log").open("wb") as stderr:
        try:
            process = subprocess.Popen(config["adapter"], stdin=subprocess.PIPE, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                process.communicate(canonical(request), timeout=config["timeout_seconds"])
            except subprocess.TimeoutExpired:
                run["errors"].append("adapter timeout")
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                if process.returncode is None:
                    process.communicate()
            run["adapter_returncode"] = process.returncode
            if process.returncode:
                run["errors"].append(f"adapter exited {process.returncode}")
        except OSError as error:
            run["errors"].append(f"adapter could not start: {error}")
    raw_rows = []
    for number_, line in enumerate((output / "adapter.stdout.jsonl").read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if line.strip():
            try:
                row = json.loads(line, parse_constant=reject_constant)
                if not isinstance(row, dict):
                    raise ValueError("expected object")
                raw_rows.append(row)
            except ValueError as error:
                run["errors"].append(f"adapter stdout line {number_}: {error}")
    rows, issues = validate_rows(raw_rows, plan, corpus["cases"], config)
    run["errors"].extend(issues)
    try:
        if verify_corpus(arguments.corpus) != corpus:
            raise ValueError("corpus changed during run")
        if measured_assets(config) != assets:
            raise ValueError("model or executable assets changed during run")
    except (OSError, ValueError) as error:
        run["errors"].append(str(error))
    run["status"] = "failed" if run["errors"] or any("error" in row for row in rows) else "complete"
    finished = run_observation()
    run["completed_unix_seconds"] = finished["wall_unix_seconds"]
    run["run_observations"].update({"finished": finished, "elapsed_monotonic_seconds": finished["monotonic_seconds"] - started["monotonic_seconds"], "elapsed_wall_seconds": finished["wall_unix_seconds"] - started["wall_unix_seconds"]})
    write_json(output / "run.json", run)
    (output / "results.jsonl").write_text("".join(canonical(row).decode("utf-8") + "\n" for row in rows), encoding="utf-8")
    summary = summarize(run, rows)
    write_json(output / "summary.json", summary)
    print(json.dumps(summary, sort_keys=True, allow_nan=False))
    return 0 if summary["complete"] else 1


def load_run(directory):
    directory = Path(directory)
    run = read_json(directory / "run.json")
    if run.get("schema_version") != 1:
        raise ValueError("unsupported run schema")
    validate_config(run["config"])
    corpus = run["corpus"]
    if corpus.get("corpus_sha256") != digest({key: value for key, value in corpus.items() if key != "corpus_sha256"}):
        raise ValueError("run corpus snapshot hash mismatch")
    if run["plan"] != build_plan(corpus["cases"], run["config"]):
        raise ValueError("run plan does not match corpus/config")
    rows = read_jsonl(directory / "results.jsonl")
    validated, issues = validate_rows(rows, run["plan"], corpus["cases"], run["config"])
    if issues:
        raise ValueError("invalid saved results: " + "; ".join(issues))
    if rows != validated:
        raise ValueError("saved references/audio hashes or model metadata differ from owned corpus")
    return run, summarize(run, validated)


def thresholds(summary, arguments):
    failures = []
    if not summary["complete"]:
        failures.append("run is incomplete or contains errors")
    for name, limit in (("wer", arguments.max_wer), ("cer", arguments.max_cer), ("silence_hallucination_rate", arguments.max_silence_hallucination_rate), ("primary_p95_ms", arguments.max_p95_ms)):
        if limit is None:
            continue
        number(limit, name + " threshold")
        value = summary["primary_p95_ms"] if name == "primary_p95_ms" else (summary["accuracy"] or {}).get(name)
        if value is None:
            failures.append(f"requested {name} is unavailable")
        elif value > limit:
            failures.append(f"{name} {value:.6f} exceeds {limit:.6f}")
    return failures


def report(arguments):
    _, summary = load_run(arguments.run)
    failures = thresholds(summary, arguments)
    print(json.dumps({**summary, "gate_failures": failures}, indent=2, sort_keys=True))
    return 1 if failures else 0


def compare(arguments):
    baseline, base_summary = load_run(arguments.baseline)
    candidate, summary = load_run(arguments.candidate)
    failures = thresholds(summary, arguments)
    if not base_summary["complete"]:
        failures.append("baseline is incomplete or contains errors")
    for key in ("corpus", "plan"):
        if baseline[key] != candidate[key]:
            failures.append(f"incompatible {key}")
    left, right = baseline["config"], candidate["config"]
    for key in ("normalization", "metric_definitions", "primary_metric", "process_lifecycle", "concurrency"):
        if left[key] != right[key]:
            failures.append(f"incompatible {key}")
    if left.get("configuration", {}) != right.get("configuration", {}):
        failures.append("incompatible semantic configuration")
    if left["engine"]["id"] != right["engine"]["id"] and not arguments.allow_model_change:
        failures.append("incompatible engine identity; use --allow-model-change for an intentional engine/model comparison")
    if not arguments.allow_model_change:
        if left["model"]["id"] != right["model"]["id"]:
            failures.append("incompatible model identity; use --allow-model-change")
        for key in ("model_tree_sha256", "tokenizer_tree_sha256"):
            if baseline["assets"].get(key) != candidate["assets"].get(key):
                failures.append(f"incompatible measured {key}; use --allow-model-change")
        if baseline["assets"].get("model_tree_sha256") is None and left["model"]["revision"] != right["model"]["revision"]:
            failures.append("incompatible declared model revision without a measured model tree; use --allow-model-change")
    latency_gate = arguments.max_p95_ms is not None or arguments.max_p95_increase is not None
    if latency_gate:
        if baseline.get("host") != candidate.get("host") or not baseline.get("host"):
            failures.append("latency requires matching stable host")
        if not left.get("build_mode") or left.get("build_mode") != right.get("build_mode"):
            failures.append("latency requires matching declared build_mode")
    deltas = {}
    for metric, limit in (("wer", arguments.max_wer_increase), ("primary_p95_ms", arguments.max_p95_increase)):
        old = base_summary["primary_p95_ms"] if metric == "primary_p95_ms" else (base_summary["accuracy"] or {}).get(metric)
        new = summary["primary_p95_ms"] if metric == "primary_p95_ms" else (summary["accuracy"] or {}).get(metric)
        delta = None if old is None or new is None else (new - old if metric == "wer" else (new / old - 1 if old > 0 else None))
        deltas[metric] = delta
        if limit is not None:
            number(limit, metric + " increase threshold")
            if delta is None:
                failures.append(f"requested {metric} delta is unavailable (p95 baseline must be > 0)")
            elif delta > limit:
                failures.append(f"{metric} increase {delta:.6f} exceeds {limit:.6f}")
    provenance_changes = {key: {"baseline": baseline.get(key), "candidate": candidate.get(key)} for key in ("config", "assets", "gojo_git", "host") if baseline.get(key) != candidate.get(key)}
    print(json.dumps({"schema_version": 1, "baseline_run_id": baseline["run_id"], "candidate_run_id": candidate["run_id"], "passed": not failures, "deltas": deltas, "provenance_changes": provenance_changes, "gate_failures": failures}, indent=2, sort_keys=True))
    return 1 if failures else 0


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    command = commands.add_parser("prepare", help="freeze supplied WAVs or explicitly synthesize source JSONL")
    command.add_argument("source", type=Path)
    command.add_argument("--output", type=Path, required=True)
    command.add_argument("--synthesize", action="store_true")
    command.set_defaults(action=prepare)
    command = commands.add_parser("run", help="invoke one batch adapter with a versioned JSON request")
    command.add_argument("--corpus", type=Path, required=True)
    command.add_argument("--config", type=Path, required=True)
    command.add_argument("--output", type=Path, required=True)
    command.set_defaults(action=run_benchmark)
    for name, action in (("report", report), ("compare", compare)):
        command = commands.add_parser(name)
        if name == "report":
            command.add_argument("run", type=Path)
        else:
            command.add_argument("baseline", type=Path)
            command.add_argument("candidate", type=Path)
            command.add_argument("--allow-model-change", action="store_true")
            command.add_argument("--max-wer-increase", type=float, help="maximum absolute WER increase; zero forbids regression")
            command.add_argument("--max-p95-increase", type=float, help="maximum fractional primary p95 growth; zero forbids regression")
        command.add_argument("--max-wer", type=float)
        command.add_argument("--max-cer", type=float)
        command.add_argument("--max-silence-hallucination-rate", type=float)
        command.add_argument("--max-p95-ms", type=float)
        command.set_defaults(action=action)
    return result


def main():
    arguments = parser().parse_args()
    try:
        return arguments.action(arguments)
    except (OSError, ValueError, KeyError, TypeError, wave.Error, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
