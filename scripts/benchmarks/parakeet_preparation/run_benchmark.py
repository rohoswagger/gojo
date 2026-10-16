from pathlib import Path
import argparse
import hashlib
import json
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Compare Parakeet validation in alternating fresh processes.")
parser.add_argument("--binary", type=Path, default=root / ".build/GojoParakeetValidationBenchmark")
parser.add_argument("--provenance", type=Path, default=root / ".build/build-provenance.json")
parser.add_argument("--model-folder", type=Path, required=True)
parser.add_argument("--output-dir", type=Path, required=True)
parser.add_argument("--runs-per-side", type=int, default=5)
args = parser.parse_args()
if args.runs_per_side < 5:
    parser.error("A comparison requires at least five runs per side.")
provenance = json.loads(args.provenance.read_text())
if provenance["configuration"] != "optimized-validation-component":
    parser.error("Build the optimized runner with build.sh.")
if hashlib.sha256(args.binary.read_bytes()).hexdigest() != provenance["binarySHA256"]:
    parser.error("The binary does not match its build provenance.")
args.output_dir.mkdir(parents=True, exist_ok=False)
(args.output_dir / "build-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
environment = {
    "command": sys.argv,
    "uptime": subprocess.check_output(["uptime"], text=True).strip(),
    "cores": subprocess.check_output(["sysctl", "-n", "hw.ncpu"], text=True).strip(),
    "topProcesses": subprocess.check_output(["ps", "-axo", "pid,pcpu,pmem,comm", "-r"], text=True).splitlines()[:12],
    "protocol": "ABAB; fresh process each run; warm filesystem caches; no profiler; optimized validation only; no SDK load or inference",
}
(args.output_dir / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
runs = []
for index in range(args.runs_per_side):
    for mode in ("baseline", "candidate"):
        name = f"{index + 1:02d}-{mode}"
        output = args.output_dir / f"{name}.json"
        command = [str(args.binary), "--mode", mode, "--model-folder", str(args.model_folder), "--output", str(output)]
        load = subprocess.check_output(["uptime"], text=True).strip()
        with (args.output_dir / f"{name}.log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            report = json.loads(output.read_text())
            passes = 2 if mode == "baseline" else 1
            expected_bytes = provenance["manifest"]["maximumBytes"] * passes
            if result.returncode or report["errors"] or report["shaPasses"] != passes or report["hashedBytes"] != expected_bytes:
                raise ValueError("Run failed or performed incorrect SHA work")
            if report["modelRevision"] != provenance["manifest"]["revision"]:
                raise ValueError("Model revision does not match build provenance")
            if mode == "candidate" and report["candidateImplementation"] != provenance["manifest"]["cacheSourceSHA256"]:
                raise ValueError("Cache source does not match build provenance")
        except (OSError, ValueError, KeyError, TypeError) as error:
            (args.output_dir / "errors.json").write_text(json.dumps({"run": name, "error": str(error), "returnCode": result.returncode}, indent=2) + "\n")
            sys.exit(1)
        report["environmentUptime"] = load
        runs.append(report)
        print(f"{name} OK validationSeconds={sum(p['seconds'] for p in report['phases']):.6f}", flush=True)


def distribution(values):
    return {"medianSeconds": statistics.median(values), "minimumSeconds": min(values), "maximumSeconds": max(values), "samples": len(values)}


summary = {"errors": 0, "successfulRuns": len(runs), "modes": {}}
for mode in ("baseline", "candidate"):
    reports = [report for report in runs if report["mode"] == mode]
    phases = [phase["name"] for phase in reports[0]["phases"]]
    summary["modes"][mode] = {
        "validationTotal": distribution([sum(phase["seconds"] for phase in report["phases"]) for report in reports]),
        "phases": {name: distribution([next(phase["seconds"] for phase in report["phases"] if phase["name"] == name) for report in reports]) for name in phases},
        "shaPassesPerRun": reports[0]["shaPasses"],
        "hashedBytesPerRun": reports[0]["hashedBytes"],
    }
(args.output_dir / "runs.json").write_text(json.dumps(runs, indent=2) + "\n")
(args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
