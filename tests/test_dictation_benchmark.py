"""Offline CLI contract tests. Fixed fixture outputs are not speech-recognition evidence."""

import hashlib
import contextlib
import io
import json
import math
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCHMARK = ROOT / "scripts/benchmarks/dictation_benchmark.py"
WHISPER_ADAPTER = ROOT / "scripts/benchmarks/whisperkit_adapter.py"
FIXTURE = ROOT / "tests/fixtures/dictation-benchmark/deterministic_protocol_adapter.py"


class DictationBenchmarkCLI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name).resolve()
        self.source = self.directory / "source.jsonl"
        self.source.write_text(json.dumps({"id": "speech", "reference": "Hello world", "audio_path": "source.wav"}) + "\n" + json.dumps({"id": "silence", "type": "silence", "reference": "", "duration_seconds": .1}) + "\n", encoding="utf-8")
        with wave.open(str(self.directory / "source.wav"), "wb") as audio:
            audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            audio.writeframes(b"\0\0" * 1600)
        self.corpus = self.directory / "corpus"
        self.invoke("prepare", self.source, "--output", self.corpus)
        self.config = {"schema_version": 1, "adapter": [sys.executable, str(FIXTURE)], "engine": {"id": "deterministic-protocol-fixture", "revision": "test-only"}, "model": {"id": "no-asr-model", "revision": "test-only"}, "normalization": "basic", "repeats": 2, "warmup": 1, "process_lifecycle": "per_case", "concurrency": 1, "metric_definitions": {"fixture_stage": {"unit": "ms", "definition": "Literal deterministic protocol fixture value; not ASR latency"}}, "primary_metric": "fixture_stage", "timeout_seconds": 5, "configuration": {}, "build_mode": "protocol-fixture", "adapter_config": {"hypotheses": {"speech": "hello there", "silence": ""}}}
        self.counter = 0

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, *arguments, expected=0):
        result = subprocess.run([sys.executable, str(BENCHMARK), *map(str, arguments)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def run_fixture(self, behavior="complete", expected=0):
        self.counter += 1
        config = json.loads(json.dumps(self.config))
        config["adapter_config"]["test_behavior"] = behavior
        config_path = self.directory / f"config-{self.counter}.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        output = self.directory / f"run-{self.counter}"
        result = self.invoke("run", "--corpus", self.corpus, "--config", config_path, "--output", output, expected=expected)
        return output, json.loads(result.stdout) if result.stdout.strip() else None

    def clone_run(self, original):
        self.counter += 1
        output = self.directory / f"clone-{self.counter}"
        shutil.copytree(original, output)
        return output

    def change_json(self, path, change):
        value = json.loads(path.read_text(encoding="utf-8"))
        change(value)
        path.write_text(json.dumps(value), encoding="utf-8")

    def test_prepare_freezes_relative_wavs_and_never_overwrites(self):
        corpus = json.loads((self.corpus / "corpus.json").read_text())
        self.assertEqual([row["id"] for row in corpus["cases"]], ["speech", "silence"])
        self.assertEqual(corpus["cases"][0]["frames"], 1600)
        self.assertEqual(corpus["cases"][1]["duration_seconds"], .1)
        self.assertEqual((self.corpus / "audio/speech.wav").read_bytes(), (self.directory / "source.wav").read_bytes())
        original = (self.corpus / "corpus.json").read_bytes()
        self.invoke("prepare", self.source, "--output", self.corpus, expected=2)
        self.assertEqual((self.corpus / "corpus.json").read_bytes(), original)
        self.assertEqual(len(corpus["corpus_sha256"]), 64)

    def test_supplied_wav_format_and_synthesis_opt_in(self):
        with wave.open(str(self.directory / "source.wav"), "wb") as audio:
            audio.setparams((2, 2, 44100, 0, "NONE", "not compressed"))
            audio.writeframes(b"\0" * 400)
        result = self.invoke("prepare", self.source, "--output", self.directory / "bad-format", expected=2)
        self.assertIn("PCM16 mono 16000", result.stderr)
        self.source.write_text('{"id":"tts","reference":"hello"}\n')
        result = self.invoke("prepare", self.source, "--output", self.directory / "no-tts", expected=2)
        self.assertIn("--synthesize", result.stderr)

    def test_unsafe_and_duplicate_source_ids_fail(self):
        for source in ('{"id":"../escape","reference":""}', '{"id":"same","reference":""}\n{"id":"same","reference":""}'):
            self.source.write_text(source)
            self.invoke("prepare", self.source, "--output", self.directory / "invalid", expected=2)

    def test_corpus_reference_audio_and_path_tampering_fail(self):
        for modification in ("reference", "path", "audio"):
            with self.subTest(modification=modification):
                snapshot = self.directory / f"tampered-{modification}"
                shutil.copytree(self.corpus, snapshot)
                if modification == "audio":
                    path = snapshot / "audio/speech.wav"
                    path.write_bytes(path.read_bytes()[:-2] + b"\1\1")
                else:
                    self.change_json(snapshot / "corpus.json", lambda corpus: corpus["cases"][0].update({"reference": "changed"} if modification == "reference" else {"audio_path": "../source.wav"}))
                config = self.directory / "tamper-config.json"
                config.write_text(json.dumps(self.config))
                self.invoke("run", "--corpus", snapshot, "--config", config, "--output", self.directory / f"bad-run-{modification}", expected=2)

    def test_scores_plan_raw_final_and_provenance_are_literal(self):
        self.config["adapter_config"]["raw_hypotheses"] = {"speech": "hello world", "silence": "noise"}
        output, result = self.run_fixture()
        self.assertEqual(result["coverage"], {"planned": 6, "rows": 6, "measured": 4, "rehearsal": 2, "errors": 0})
        self.assertEqual(result["accuracy"]["wer"], .5)
        self.assertEqual(result["accuracy"]["cer"], .5)
        self.assertEqual(result["accuracy"]["silence_hallucination_rate"], 0)
        self.assertEqual(result["raw_accuracy"]["wer"], .5)
        self.assertEqual(result["raw_accuracy"]["silence_hallucination_rate"], 1)
        self.assertEqual(result["primary_p95_ms"], 10)
        self.assertEqual(result["timings_ms"]["fixture_stage"]["measured"]["unknown"]["count"], 4)
        run = json.loads((output / "run.json").read_text())
        self.assertEqual([row["item_id"] for row in run["plan"]], ["rehearsal-0-speech", "rehearsal-0-silence", "measured-0-speech", "measured-0-silence", "measured-1-speech", "measured-1-silence"])
        self.assertEqual(run["config"]["engine"]["revision"], "test-only")
        self.assertEqual(len(run["assets"]["adapter_executable_sha256"]), 64)
        self.assertEqual(len(run["assets"]["adapter_argv_files"][0]["sha256"]), 64)
        self.assertIn("working_tree_sha256", run["gojo_git"])
        self.assertEqual(len(run["run_observations"]["started"]["load_average"]), 3)
        self.assertEqual(len(run["run_observations"]["finished"]["load_average"]), 3)
        self.assertNotIn("load_average", run["host"])
        request = json.loads((output / "artifacts/fixture-request.json").read_text())
        self.assertEqual(Path(request["cases"][0]["audio_path"]).is_absolute(), True)
        self.assertNotIn("reference", request["cases"][0])

    def test_adapter_request_contains_only_engine_inputs_for_synthetic_cases(self):
        corpus_path = self.corpus / "corpus.json"
        corpus = json.loads(corpus_path.read_text())
        case = corpus["cases"][0]
        case.update(kind="synthetic", synthesis={"voice": "Samantha", "spoken": "private spoken answer"}, spoken="private case answer", tagsAnswer="private tagged answer")
        corpus["corpus_sha256"] = hashlib.sha256(json.dumps({key: value for key, value in corpus.items() if key != "corpus_sha256"}, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")).hexdigest()
        corpus_path.write_text(json.dumps(corpus))
        output, result = self.run_fixture()
        self.assertEqual(result["complete"], True)
        request = json.loads((output / "request.json").read_text())
        self.assertEqual(json.loads((output / "artifacts/fixture-request.json").read_text()), request)
        for requested in request["cases"]:
            self.assertEqual(set(requested), {"id", "audio_path", "audio_sha256", "frames", "sample_rate", "channels", "sample_width", "duration_seconds", "kind"})
        self.assertEqual(request["cases"][0], {"id": "speech", "audio_path": str(self.corpus / "audio/speech.wav"), "audio_sha256": case["audio_sha256"], "frames": 1600, "sample_rate": 16000, "channels": 1, "sample_width": 2, "duration_seconds": .1, "kind": "synthetic"})
        self.assertEqual(json.loads((output / "run.json").read_text())["corpus"], corpus)
        self.assertEqual(json.loads(corpus_path.read_text()), corpus)

    def test_errors_partial_duplicates_unknown_repeat_and_bad_stdout_fail_closed(self):
        for behavior in ("error", "partial", "duplicate", "unknown", "wrong-repeat", "malformed", "exit"):
            with self.subTest(behavior=behavior):
                output, result = self.run_fixture(behavior, expected=1)
                self.assertEqual(result["complete"], False)
                self.assertEqual(result["coverage"]["rows"], 6)
                self.assertIsNone(result["accuracy"])
                self.assertIn("no ASR inference", (output / "adapter.stderr.log").read_text())
                self.invoke("report", output, expected=1)

    def test_timeout_kills_owned_process_group_and_retains_failures(self):
        self.config["timeout_seconds"] = .15
        output, result = self.run_fixture("timeout", expected=1)
        self.assertIn("adapter timeout", result["errors"])
        self.assertEqual(result["coverage"]["errors"], 6)
        time.sleep(1.1)
        self.assertFalse((output / "artifacts/child-leaked.txt").exists())

    def test_adapter_exit_kills_owned_children_after_failure_and_success(self):
        for behavior, expected in (("child-exit", 1), ("child-complete", 0)):
            with self.subTest(behavior=behavior):
                output, result = self.run_fixture(behavior, expected=expected)
                self.assertEqual((output / "artifacts/child-ready.txt").read_text(), "ready")
                self.assertEqual(result["complete"], expected == 0)
                if expected:
                    self.assertIn("adapter exited 7", result["errors"])
                    self.assertEqual(result["coverage"]["errors"], 6)
                    self.assertIsNone(result["accuracy"])
                else:
                    self.assertEqual(result["coverage"]["rows"], 6)
                    self.assertEqual(result["accuracy"]["wer"], .5)
                time.sleep(1.1)
                self.assertFalse((output / "artifacts/child-leaked.txt").exists())

    def test_timing_validation_rejects_negative_boolean_and_nonfinite(self):
        for behavior in ("negative", "bool", "infinity", "nan"):
            with self.subTest(behavior=behavior):
                _, result = self.run_fixture(behavior, expected=1)
                self.assertIsNone(result["primary_p95_ms"])
                self.assertEqual(result["complete"], False)

    def test_absent_metric_stays_unavailable_and_requested_gate_fails(self):
        output, result = self.run_fixture("missing-stage")
        self.assertIsNone(result["primary_p95_ms"])
        self.assertIsNone(result["timings_ms"]["fixture_stage"]["measured"]["all"])
        result = self.invoke("report", output, "--max-p95-ms", 100, expected=1)
        self.assertIn("unavailable", result.stdout)

    def test_warmth_requires_persistent_identified_consistent_session(self):
        self.run_fixture("first-warm", expected=1)
        self.config["process_lifecycle"] = "persistent"
        for behavior in ("warm-without-session", "warm-first", "new-session"):
            self.run_fixture(behavior, expected=1)
        _, result = self.run_fixture("first-warm")
        self.assertIsNone(result["timings_ms"]["fixture_stage"]["measured"]["first"])
        self.assertEqual(result["timings_ms"]["fixture_stage"]["rehearsal"]["first"]["count"], 1)
        self.assertEqual(result["timings_ms"]["fixture_stage"]["measured"]["warm"]["count"], 4)

    def test_report_recomputes_results_ignoring_cached_summary(self):
        output, _ = self.run_fixture()
        (output / "summary.json").write_text('{"accuracy":{"wer":0}}')
        result = self.invoke("report", output, "--max-wer", .4, expected=1)
        self.assertEqual(json.loads(result.stdout)["accuracy"]["wer"], .5)
        self.invoke("report", output, "--max-wer", .5, "--max-p95-ms", 10)
        path = output / "results.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        rows[0]["reference"] = "forged reference"
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        self.invoke("report", output, expected=2)

    def test_compare_matching_runs_and_accuracy_latency_regressions(self):
        baseline, _ = self.run_fixture()
        candidate = self.clone_run(baseline)
        result = self.invoke("compare", baseline, candidate, "--max-wer-increase", 0, "--max-p95-increase", 0)
        self.assertEqual(json.loads(result.stdout)["deltas"], {"wer": 0, "primary_p95_ms": 0})
        path = candidate / "results.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        for row in rows:
            if row["case_id"] == "speech":
                row["hypothesis"] = "unrelated phrase"
            row["timings_ms"]["fixture_stage"] = 12
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        result = self.invoke("compare", baseline, candidate, "--max-wer-increase", .1, "--max-p95-increase", .1, expected=1)
        deltas = json.loads(result.stdout)["deltas"]
        self.assertEqual(deltas["wer"], .5)
        self.assertTrue(math.isclose(deltas["primary_p95_ms"], .2))

    def test_code_revision_and_operational_paths_are_reported_not_rejected(self):
        baseline, _ = self.run_fixture()
        candidate = self.clone_run(baseline)
        def change(run):
            run["config"]["adapter"] = ["/different/python", "/different/adapter"]
            run["config"]["engine"]["revision"] = "upgraded-sdk"
            run["config"]["model"]["path"] = "/same-bytes/new-location"
            run["config"]["adapter_config"]["cli_path"] = "/new/cli"
            run["gojo_git"]["revision"] = "new-code-revision"
            run["assets"]["adapter_executable_sha256"] = "new-binary-hash"
        self.change_json(candidate / "run.json", change)
        result = self.invoke("compare", baseline, candidate, "--max-p95-increase", 0)
        self.assertEqual(json.loads(result.stdout)["passed"], True)
        self.assertEqual(set(json.loads(result.stdout)["provenance_changes"]), {"config", "gojo_git", "assets"})

    def test_compare_rejects_incompatible_metrics_configuration_model_and_host(self):
        baseline, _ = self.run_fixture()
        changes = [lambda run: run["config"].update(normalization="none"), lambda run: run["config"]["metric_definitions"]["fixture_stage"].update(definition="different boundary"), lambda run: run["config"].update(configuration={"language": "fr"}), lambda run: run["config"]["model"].update(id="other-model"), lambda run: run["host"].update(cpu="different-cpu"), lambda run: run["config"].update(build_mode="different-mode")]
        for change in changes:
            candidate = self.clone_run(baseline)
            self.change_json(candidate / "run.json", change)
            self.invoke("compare", baseline, candidate, "--max-p95-increase", .1, expected=1)
        candidate = self.clone_run(baseline)
        self.change_json(candidate / "run.json", lambda run: run["config"]["model"].update(id="other-model"))
        self.invoke("compare", baseline, candidate, "--allow-model-change", "--max-wer-increase", 0)

    def test_compare_rejects_other_corpus_and_incomplete_plan(self):
        baseline, _ = self.run_fixture()
        other_corpus = self.clone_run(baseline)
        def change_corpus(run):
            run["corpus"]["cases"][0]["reference"] = "a different reference"
            content = {key: value for key, value in run["corpus"].items() if key != "corpus_sha256"}
            run["corpus"]["corpus_sha256"] = hashlib.sha256(json.dumps(content, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        self.change_json(other_corpus / "run.json", change_corpus)
        path = other_corpus / "results.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        for row in rows:
            if row["case_id"] == "speech":
                row["reference"] = "a different reference"
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        result = self.invoke("compare", baseline, other_corpus, expected=1)
        self.assertIn("incompatible corpus", json.loads(result.stdout)["gate_failures"])
        candidate = self.clone_run(baseline)
        self.change_json(candidate / "run.json", lambda run: run["plan"].pop())
        self.invoke("compare", baseline, candidate, expected=2)
        incomplete, _ = self.run_fixture("partial", expected=1)
        self.invoke("compare", baseline, incomplete, expected=1)

    def test_config_invalid_numbers_and_missing_adapter_or_model_fail(self):
        for field, value in (("timeout_seconds", True), ("timeout_seconds", float("nan")), ("repeats", True), ("concurrency", 2)):
            prior = self.config[field]
            self.config[field] = value
            self.run_fixture(expected=2)
            self.config[field] = prior
        self.config["adapter"] = ["/missing/adapter"]
        self.run_fixture(expected=2)
        self.config["adapter"] = [sys.executable, str(FIXTURE)]
        self.config["model"]["path"] = str(self.directory / "missing-model")
        self.run_fixture(expected=2)

    def test_whisper_adapter_missing_prerequisites_fail_before_inference(self):
        request = {"schema_version": 1, "config": self.config}
        self.config["adapter_config"] = {"cli_path": "/missing/whisper-cli", "cli_revision": "declared"}
        result = subprocess.run([sys.executable, str(WHISPER_ADAPTER)], input=json.dumps(request), capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("installed executable", result.stderr)
        self.assertEqual(result.stdout, "")
        self.config["adapter_config"]["cli_path"] = sys.executable
        self.config["model"]["path"] = str(self.directory / "missing-model")
        result = subprocess.run([sys.executable, str(WHISPER_ADAPTER)], input=json.dumps(request), capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("installed local WhisperKit model", result.stderr)

    def test_whisper_adapter_local_command_reports_and_failure_rows(self):
        sys.path.insert(0, str(BENCHMARK.parent))
        try:
            import whisperkit_adapter
        finally:
            sys.path.pop(0)
        model = self.directory / "installed-model"
        model.mkdir()
        for name in ("AudioEncoder", "TextDecoder", "MelSpectrogram"):
            (model / (name + ".mlmodelc")).mkdir()
        tokenizer = self.directory / "installed-tokenizer"
        tokenizer.mkdir()
        for name in ("tokenizer.json", "tokenizer_config.json"):
            (tokenizer / name).write_text("{}")
        cli = self.directory / "installed-cli"
        cli.write_text("test boundary is intercepted, never executed")
        cli.chmod(0o755)
        config = json.loads(json.dumps(self.config))
        config["model"]["path"] = str(model)
        config["metric_definitions"] = {"engine_pipeline": {"unit": "ms", "definition": "CLI fullPipeline seconds multiplied by 1000"}, "subprocess_wall": {"unit": "ms", "definition": "Monotonic child process lifetime"}}
        config["primary_metric"] = "engine_pipeline"
        config["configuration"] = {"language": "en"}
        config["adapter_config"] = {"cli_path": str(cli), "cli_revision": "declared-test-cli", "tokenizer_path": str(tokenizer), "case_timeout_seconds": 3}
        items = [{"item_id": f"measured-{repeat}-speech", "case_id": "speech", "repeat": repeat, "phase": "measured"} for repeat in range(2)]
        real_is_file = Path.is_file
        def platform_file(path):
            return True if str(path) == "/usr/bin/sandbox-exec" else real_is_file(path)
        for behavior in ("success", "bad-text", "nan", "malformed", "report-array", "timings-array", "failed-process", "timeout", "supports-no-download"):
            with self.subTest(behavior=behavior):
                artifact_dir = self.directory / ("adapter-" + behavior)
                report_dir = artifact_dir / items[0]["item_id"]
                request = {"schema_version": 1, "config": config, "run_id": "test-run", "cases": [{"id": "speech", "audio_path": str(self.directory / "source.wav")}], "plan": items, "artifact_dir": str(artifact_dir)}
                expected_command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", str(cli), "transcribe", "--audio-path", str(self.directory / "source.wav"), "--model-path", str(model), "--download-tokenizer-path", str(tokenizer), "--report", "--report-path", str(report_dir), "--concurrent-worker-count", "1"]
                if behavior == "supports-no-download":
                    expected_command.append("--no-download")
                expected_command.extend(["--language", "en"])
                calls = []
                def run_boundary(argv, **kwargs):
                    if argv[-1] == "--help":
                        self.assertEqual(argv[:5], expected_command[:5])
                        help_text = "--audio-path --model-path --report --report-path --download-tokenizer-path --concurrent-worker-count"
                        return subprocess.CompletedProcess(argv, 0, stdout=help_text + (" --no-download" if behavior == "supports-no-download" else ""), stderr="")
                    current_dir = artifact_dir / items[len(calls)]["item_id"]
                    command = list(expected_command)
                    command[command.index("--report-path") + 1] = str(current_dir)
                    self.assertEqual(argv, command)
                    calls.append(argv)
                    self.assertEqual(kwargs["timeout"], 3)
                    kwargs["stdout"].write(b"raw CLI output retained\n")
                    current_behavior = behavior if len(calls) == 1 else "success"
                    if current_behavior == "failed-process":
                        raise subprocess.CalledProcessError(7, argv)
                    if current_behavior == "timeout":
                        raise subprocess.TimeoutExpired(argv, 3)
                    report = {"text": "  Opus, Go Joe!  ", "timings": {"fullPipeline": .125}}
                    if current_behavior == "bad-text":
                        report["text"] = None
                    if current_behavior == "nan":
                        report["timings"]["fullPipeline"] = float("nan")
                    if current_behavior == "report-array":
                        report = []
                    if current_behavior == "timings-array":
                        report["timings"] = []
                    (current_dir / "source.json").write_text("broken JSON" if current_behavior == "malformed" else json.dumps(report))
                    return subprocess.CompletedProcess(argv, 0)
                stdout, stderr = io.StringIO(), io.StringIO()
                with mock.patch.object(whisperkit_adapter.sys, "platform", "darwin"), mock.patch.object(Path, "is_file", platform_file), mock.patch.object(whisperkit_adapter.subprocess, "run", side_effect=run_boundary), mock.patch.object(whisperkit_adapter.sys, "stdin", io.StringIO(json.dumps(request))), mock.patch.object(whisperkit_adapter.time, "monotonic", side_effect=(10 + index / 4 for index in range(20))), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    self.assertEqual(whisperkit_adapter.main(), 0)
                rows = [json.loads(line) for line in stdout.getvalue().splitlines()]
                self.assertEqual([row["item_id"] for row in rows], [item["item_id"] for item in items])
                row = rows[0]
                self.assertEqual(row["model_state"], "unknown")
                self.assertEqual((report_dir / "stdout.log").read_text(), "raw CLI output retained\n")
                if behavior in ("success", "supports-no-download"):
                    self.assertEqual(row["hypothesis"], "  Opus, Go Joe!  ")
                    self.assertEqual(row["raw_hypothesis"], "  Opus, Go Joe!  ")
                    self.assertEqual(row["timings_ms"], {"engine_pipeline": 125, "subprocess_wall": 250})
                    self.assertEqual(json.loads((report_dir / "source.json").read_text())["timings"]["fullPipeline"], .125)
                else:
                    self.assertIsInstance(row["error"], str)
                    self.assertNotIn("hypothesis", row)
                    self.assertNotIn("engine_pipeline", row["timings_ms"])
                    if behavior == "report-array":
                        self.assertEqual(row["error"], "CLI JSON report must contain an object")
                    if behavior == "timings-array":
                        self.assertEqual(row["error"], "CLI JSON report timings must contain an object")
                self.assertEqual(rows[1]["hypothesis"], "  Opus, Go Joe!  ")
                self.assertEqual(rows[1]["raw_hypothesis"], "  Opus, Go Joe!  ")
                self.assertEqual(rows[1]["timings_ms"], {"engine_pipeline": 125, "subprocess_wall": 250})
                self.assertNotIn("error", rows[1])


if __name__ == "__main__":
    unittest.main()
