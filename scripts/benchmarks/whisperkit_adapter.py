#!/usr/bin/env python3
"""Batch protocol adapter for an installed Argmax/WhisperKit transcribe CLI."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

from dictation_benchmark import canonical, file_hash, number, read_json, reject_constant, validate_config, write_json


def prerequisites(request):
    if type(request.get("schema_version")) is not int or request["schema_version"] != 1:
        raise ValueError("request schema_version must be 1")
    config = validate_config(request["config"])
    if config["process_lifecycle"] != "per_case":
        raise ValueError("WhisperKit CLI adapter requires process_lifecycle per_case")
    options = config.get("adapter_config", {})
    cli = Path(options.get("cli_path", "")).resolve()
    if not cli.is_file() or not os.access(cli, os.X_OK):
        raise ValueError("cli_path must identify an installed executable; no build or download is performed")
    if not isinstance(options.get("cli_revision"), str) or not options["cli_revision"]:
        raise ValueError("adapter_config.cli_revision must declare the installed CLI revision")
    model = Path(config["model"].get("path", "")).resolve()
    if not config["model"].get("path") or not model.is_dir():
        raise ValueError("model.path must identify an installed local WhisperKit model")
    for name in ("AudioEncoder", "TextDecoder", "MelSpectrogram"):
        if not any((model / (name + suffix)).is_dir() for suffix in (".mlmodelc", ".mlpackage")):
            raise ValueError(f"installed model is missing {name}.mlmodelc or .mlpackage")
    tokenizer = Path(options.get("tokenizer_path", str(model))).resolve()
    for name in ("tokenizer.json", "tokenizer_config.json"):
        if not (tokenizer / name).is_file():
            raise ValueError(f"local tokenizer is missing {name}; set adapter_config.tokenizer_path")
        if not isinstance(read_json(tokenizer / name), dict):
            raise ValueError(f"{name} must contain an object")
    timeout = number(options.get("case_timeout_seconds", 300), "case_timeout_seconds", positive=True)
    if sys.platform != "darwin" or not Path("/usr/bin/sandbox-exec").is_file():
        raise ValueError("WhisperKit adapter requires macOS sandbox-exec to deny all network access")
    if set(config["metric_definitions"]) != {"engine_pipeline", "subprocess_wall"}:
        raise ValueError("WhisperKit adapter requires engine_pipeline and subprocess_wall metric definitions")
    if set(config.get("configuration", {})) - {"language"}:
        raise ValueError("WhisperKit adapter only supports the semantic configuration.language option")
    prefix = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", str(cli)]
    help_result = subprocess.run([*prefix, "transcribe", "--help"], capture_output=True, text=True, timeout=30)
    if help_result.returncode:
        raise ValueError(f"installed CLI help probe failed: {help_result.stderr.strip()}")
    help_text = help_result.stdout
    required = ("--audio-path", "--model-path", "--report", "--report-path", "--download-tokenizer-path", "--concurrent-worker-count")
    if any(flag not in help_text for flag in required):
        raise ValueError("installed CLI does not support the pinned transcribe/report/tokenizer options")
    return config, options, model, tokenizer, timeout, prefix, help_text


def main():
    try:
        request = json.loads(sys.stdin.read(), parse_constant=reject_constant)
        config, options, model, tokenizer, timeout, prefix, help_text = prerequisites(request)
        artifact_dir = Path(request["artifact_dir"]).resolve()
        artifact_dir.mkdir(parents=True, exist_ok=True)
        (artifact_dir / "cli-help.txt").write_text(help_text, encoding="utf-8")
        write_json(artifact_dir / "adapter-provenance.json", {"process_lifecycle": "per_case", "model_state": "unknown", "cli_declared_revision": options["cli_revision"], "cli_sha256": file_hash(prefix[-1]), "network_policy": "sandbox-exec deny network*", "supports_no_download_flag": "--no-download" in help_text, "tokenizer_path": str(tokenizer)})
        cases = {case["id"]: case for case in request["cases"]}
        for item in request["plan"]:
            case = cases[item["case_id"]]
            output = artifact_dir / item["item_id"]
            output.mkdir(exist_ok=False)
            command = [*prefix, "transcribe", "--audio-path", case["audio_path"], "--model-path", str(model), "--download-tokenizer-path", str(tokenizer), "--report", "--report-path", str(output), "--concurrent-worker-count", "1"]
            if "--no-download" in help_text:
                command.append("--no-download")
            if "language" in config.get("configuration", {}):
                language = config["configuration"]["language"]
                if not isinstance(language, str) or not language:
                    raise ValueError("configuration.language must be a nonempty language code")
                command.extend(["--language", language])
            write_json(output / "command.json", command)
            row = {"schema_version": 1, **item, "model_state": "unknown", "timings_ms": {}}
            started = time.monotonic()
            try:
                with (output / "stdout.log").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
                    started = time.monotonic()
                    subprocess.run(command, stdout=stdout, stderr=stderr, timeout=timeout, check=True)
                row["timings_ms"]["subprocess_wall"] = (time.monotonic() - started) * 1000
                report = read_json(output / (Path(case["audio_path"]).stem + ".json"))
                if not isinstance(report, dict):
                    raise ValueError("CLI JSON report must contain an object")
                if not isinstance(report.get("text"), str):
                    raise ValueError("CLI JSON report has no text string")
                timings = report.get("timings")
                if not isinstance(timings, dict):
                    raise ValueError("CLI JSON report timings must contain an object")
                pipeline = number(timings.get("fullPipeline"), "CLI timings.fullPipeline")
                row["hypothesis"] = report["text"]
                row["raw_hypothesis"] = report["text"]
                row["timings_ms"]["engine_pipeline"] = pipeline * 1000
            except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
                row.pop("hypothesis", None)
                row.pop("raw_hypothesis", None)
                row["error"] = str(error)
                row["timings_ms"].setdefault("subprocess_wall", (time.monotonic() - started) * 1000)
                print(f"{item['item_id']}: {error}", file=sys.stderr, flush=True)
            print(canonical(row).decode("utf-8"), flush=True)
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"WhisperKit adapter prerequisite/protocol failure: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
