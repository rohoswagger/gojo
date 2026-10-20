#!/usr/bin/env python3
"""Build and launch the development app with the helper's signing requirement."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import NamedTuple
import uuid


ROOT = Path(__file__).resolve().parent.parent
TEAM = "L6U44C67P5"
APP_ID = "rohoswagger.gojo"
APP_REQUIREMENT = (
    'identifier "rohoswagger.gojo" and anchor apple generic '
    'and certificate leaf[subject.OU] = "L6U44C67P5"'
)
TEAM_REQUIREMENT = 'anchor apple generic and certificate leaf[subject.OU] = "L6U44C67P5"'
PROBE_ENV = "GOJO_HELPER_HANDSHAKE_STDOUT_V1"
PROBE_ARGUMENT = "--gojo-helper-handshake"


class DevError(Exception):
    pass


def checked(command, *, timeout=30):
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise DevError(f"Could not run {command[0]}: {error}") from error
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise DevError(f"{command[0]} failed ({result.returncode}): {detail}")
    return result.stdout


def verify_signature(path, requirement):
    checked([
        "/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2",
        "--test-requirement", "=" + requirement, str(path),
    ])


def app_executable(app):
    try:
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        executable = info["CFBundleExecutable"]
        if info["CFBundleIdentifier"] != APP_ID:
            raise ValueError(f"Expected bundle identifier {APP_ID}")
        if not isinstance(executable, str) or Path(executable).name != executable:
            raise ValueError("Invalid CFBundleExecutable")
        path = app / "Contents/MacOS" / executable
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError(f"Missing executable: {path}")
        return path
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        raise DevError(f"Invalid Gojo app at {app}: {error}") from error


def preflight(app):
    app = Path(app).resolve()
    executable = app_executable(app)
    helper = app / "Contents/XPCServices/GojoXPCHelper.xpc"
    try:
        verify_signature(app, APP_REQUIREMENT)
        verify_signature(helper, TEAM_REQUIREMENT)
    except DevError as error:
        raise DevError(
            f"Signing preflight rejected {app}. The helper requires a {APP_ID} "
            f"client signed with an Apple-issued certificate for team {TEAM}; "
            "ad-hoc builds cannot connect. "
            f"Run `make build` with that team's certificate installed.\n{error}"
        ) from error
    print(f"App and helper signatures verified: {app}", flush=True)
    return executable


def signing_identities(output):
    identities = []
    for line in output.splitlines():
        match = re.fullmatch(r'\s*\d+\) ([A-Fa-f0-9]{40}) "(.+)"\s*', line)
        if match and match[2].endswith(f"({TEAM})"):
            identities.append((match[1], match[2]))
    return identities


def signing_identity(requested=None):
    identities = signing_identities(checked([
        "/usr/bin/security", "find-identity", "-v", "-p", "codesigning",
    ]))
    if requested:
        identities = [
            pair for pair in identities
            if requested.upper() == pair[0].upper() or requested == pair[1]
        ]
    if not identities:
        selection = f" matching {requested!r}" if requested else ""
        raise DevError(
            f"No valid Apple signing identity for team {TEAM}{selection}. "
            "Install the team's development or Developer ID Application certificate "
            "and private key, then retry. Unsigned builds support compile checks only."
        )
    identity, name = sorted(identities, key=lambda pair: (not pair[1].startswith("Apple Development:"), pair[0]))[0]
    with tempfile.TemporaryDirectory(prefix="gojo-signing-identity-") as directory:
        fixture = Path(directory) / "identity-check"
        shutil.copyfile("/usr/bin/true", fixture)
        checked([
            "/usr/bin/codesign", "--force", "--sign", identity,
            "--identifier", APP_ID, "--timestamp=none", str(fixture),
        ])
        verify_signature(fixture, APP_REQUIREMENT)
    print(f"Development signing identity: {name}", flush=True)
    return identity


def build(args):
    identity = signing_identity(args.identity)
    derived_data = Path(args.derived_data).resolve()
    command = [
        "/usr/bin/xcodebuild", "-project", str(ROOT / "Gojo.xcodeproj"),
        "-scheme", "Gojo", "-configuration", args.configuration,
        "-destination", "platform=macOS", "-derivedDataPath", str(derived_data),
        "build", f"CODE_SIGN_IDENTITY={identity}", f"DEVELOPMENT_TEAM={TEAM}",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_STYLE=Manual",
    ]
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode:
        raise DevError(f"Signed {args.configuration} build failed ({result.returncode}).")
    preflight(derived_data / "Build/Products" / args.configuration / "Gojo.app")


def validate_handshake(payload, probe_id=None):
    try:
        received_probe_id = uuid.UUID(payload["probeID"])
        if probe_id is not None and received_probe_id != uuid.UUID(probe_id):
            raise ValueError("Probe ID mismatch")
    except (KeyError, TypeError, ValueError, AttributeError) as error:
        raise DevError("Helper handshake returned an invalid or mismatched probe ID") from error
    if not isinstance(payload, dict) or payload.get("available") is not True:
        detail = payload.get("error", "Helper did not become available") if isinstance(payload, dict) else "Expected a JSON object"
        raise DevError(f"Helper handshake failed: {detail}")
    try:
        uuid.UUID(payload["helperInstanceID"])
    except (KeyError, TypeError, ValueError, AttributeError) as error:
        raise DevError("Helper handshake returned no valid helper instance ID") from error
    version = payload.get("protocolVersion")
    if type(version) is not int or version < 1:
        raise DevError("Helper handshake returned no valid protocol version")
    if "accessibilityAuthorized" in payload and type(payload["accessibilityAuthorized"]) is not bool:
        raise DevError("Helper handshake returned an invalid Accessibility authorization value")
    return payload


def stop_probe(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def supports_handshake(executable):
    binary = executable.read_bytes()
    if PROBE_ENV.encode() in binary:
        return True
    debug_dylib = executable.with_name(executable.name + ".debug.dylib")
    return (
        ("@rpath/" + debug_dylib.name).encode() in binary
        and debug_dylib.is_file()
        and PROBE_ENV.encode() in debug_dylib.read_bytes()
    )


def handshake(app, timeout=15):
    app = Path(app).resolve()
    executable = preflight(app)
    if not supports_handshake(executable):
        raise DevError("This app does not support the helper handshake probe. Rebuild before running the handshake.")
    probe_id = str(uuid.uuid4())
    with tempfile.TemporaryDirectory(prefix="gojo-helper-handshake-") as directory:
        output = Path(directory) / "stdout.json"
        error_output = Path(directory) / "stderr.log"
        command = [
            "/usr/bin/open", "-n", "-W", "--env", PROBE_ENV + "=1",
            "--env", "GOJO_LICENSE=lifetime", "--stdout", str(output),
            "--stderr", str(error_output), str(app), "--args", PROBE_ARGUMENT, probe_id,
        ]
        with error_output.open("wb") as errors:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=errors)
        try:
            try:
                returncode = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                raise DevError(f"Helper handshake timed out after {timeout:g}s; only its nonce-tagged probe was stopped.") from error
            try:
                payload = validate_handshake(json.loads(output.read_text()), probe_id)
            except (OSError, ValueError) as error:
                detail = error_output.read_text(errors="replace")[-4000:].strip() if error_output.exists() else ""
                raise DevError(
                    f"Helper probe launcher exited {returncode} without a valid result. "
                    f"Rebuild the app and check its helper connection.\n{detail}"
                ) from error
            if returncode:
                raise DevError(f"Helper probe returned success data but its launcher exited {returncode}.")
        finally:
            cleanup_probe(process, executable, probe_id)
    print(f"Helper handshake passed: {json.dumps(payload, sort_keys=True)}", flush=True)
    return payload


def run(app, timeout=15):
    app = Path(app).resolve()
    executable = preflight(app)
    license_state = license_override(os.environ.get("GOJO_LICENSE", ""))
    instances = running_instances()
    if instances:
        detail = "\n".join(f"  pid {pid}: {path}" for pid, path in instances)
        raise DevError(f"Gojo is already running. Quit that instance before launching this build:\n{detail}")
    handshake(app, timeout)
    if running_instances():
        raise DevError("Gojo started while the handshake was running. Stop that instance before retrying.")
    checked([
        "/usr/bin/open", "-n", "--env", "GOJO_LICENSE=" + license_state,
        "--env", PROBE_ENV + "=0", str(app),
    ])
    deadline = time.monotonic() + timeout
    while True:
        processes = [p for p in process_snapshot().values() if Path(p.executable).resolve() == executable.resolve()]
        if processes:
            print(f"Launched {app} (pid {processes[0].pid})", flush=True)
            return
        if time.monotonic() >= deadline:
            raise DevError(f"LaunchServices did not leave {app} running within {timeout:g}s.")
        time.sleep(0.05)


def license_override(raw):
    value = raw.strip().lower() or "lifetime"
    if value in {"lifetime", "monthly", "subscription", "trial", "locked"}:
        return value
    if re.fullmatch(r"trial:\+?[0-9]+", value):
        days = int(value.split(":", 1)[1])
        if 0 < days <= sys.maxsize:
            return value
    raise DevError("Invalid GOJO_LICENSE override; use lifetime, monthly, trial, trial:<positive days>, or locked.")


def running_instances():
    output = checked(["/bin/ps", "-axo", "pid=,comm="])
    instances = []
    for line in output.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[1].endswith(".app/Contents/MacOS/Gojo"):
            continue
        instances.append((int(parts[0]), parts[1]))
    return instances


class ProcessInfo(NamedTuple):
    pid: int
    parent: int
    started: str
    executable: str


def process_snapshot():
    output = checked(["/bin/ps", "-ww", "-axo", "pid=,ppid=,lstart=,comm="])
    processes = {}
    for line in output.splitlines():
        parts = line.split(None, 7)
        if len(parts) == 8:
            process = ProcessInfo(int(parts[0]), int(parts[1]), " ".join(parts[2:7]), parts[7])
            processes[process.pid] = process
    return processes


def process_arguments(pid):
    try:
        return checked(["/bin/ps", "-ww", "-p", str(pid), "-o", "args="]).strip()
    except DevError:
        return None


def stop_targets(app, executable, processes):
    helper = app / "Contents/XPCServices/GojoXPCHelper.xpc/Contents/MacOS/GojoXPCHelper"
    sparkle = app / "Contents/Frameworks/Sparkle.framework"
    app_pids = {
        process.pid for process in processes.values()
        if Path(process.executable).resolve() == executable
    }
    media_prefix = f"/usr/bin/perl {app}/Contents/Resources/mediaremote-adapter.pl {app}/Contents/Frameworks/MediaRemoteAdapter.framework "
    targets = []
    for process in processes.values():
        path = Path(process.executable).resolve()
        if path in {executable, helper} or (path.name == "Downloader" and path.is_relative_to(sparkle)):
            targets.append((process, None))
        elif process.parent in app_pids and path == Path("/usr/bin/perl").resolve():
            arguments = process_arguments(process.pid)
            if arguments and arguments.startswith(media_prefix):
                targets.append((process, arguments))
    return targets


def target_running(target, processes):
    original, arguments = target
    current = processes.get(original.pid)
    if current is None or current.started != original.started or current.executable != original.executable:
        return False
    return arguments is None or process_arguments(current.pid) == arguments


def probe_targets(executable, probe_id):
    targets = []
    nonce_argument = re.compile(r"(?:^|\s)" + re.escape(PROBE_ARGUMENT) + r"\s+" + re.escape(probe_id) + r"(?=\s|$)")
    for process in process_snapshot().values():
        if Path(process.executable).resolve() == executable.resolve():
            arguments = process_arguments(process.pid)
            if arguments and nonce_argument.search(arguments):
                targets.append((process, arguments))
    return targets


def cleanup_probe(launcher, executable, probe_id):
    try:
        terminate_targets(probe_targets(executable, probe_id), 2)
        try:
            launcher.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
    finally:
        stop_probe(launcher)
    terminate_targets(probe_targets(executable, probe_id), 2)


def signal_targets(targets, action):
    for target in targets:
        if target_running(target, process_snapshot()):
            try:
                os.kill(target[0].pid, action)
            except ProcessLookupError:
                pass


def wait_for_targets(targets, timeout):
    deadline = time.monotonic() + timeout
    while True:
        processes = process_snapshot()
        remaining = [target for target in targets if target_running(target, processes)]
        if not remaining or time.monotonic() >= deadline:
            return remaining
        time.sleep(min(0.05, max(0, deadline - time.monotonic())))


def stop(app, timeout=2):
    app = Path(app).resolve()
    executable = app_executable(app).resolve()
    targets = stop_targets(app, executable, process_snapshot())
    if not targets:
        print(f"No processes running from {app}", flush=True)
        return
    terminate_targets(targets, timeout)
    print(f"Stopped processes from {app}: {[target[0].pid for target in targets]}", flush=True)


def terminate_targets(targets, timeout):
    if not targets:
        return
    signal_targets(targets, signal.SIGTERM)
    remaining = wait_for_targets(targets, timeout)
    signal_targets(remaining, signal.SIGKILL)
    remaining = wait_for_targets(remaining, timeout)
    if remaining:
        raise DevError(f"Could not stop Gojo processes: {[target[0].pid for target in remaining]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build", help="Build with an Apple identity trusted by the helper")
    build_parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug")
    build_parser.add_argument("--derived-data", default=str(ROOT / ".build/DerivedData"))
    build_parser.add_argument("--identity", default=os.environ.get("GOJO_SIGNING_IDENTITY"), help="Certificate SHA-1 or exact identity name")
    for command in ("preflight", "handshake", "run", "stop"):
        command_parser = commands.add_parser(command)
        command_parser.add_argument("app", type=Path)
        if command != "preflight":
            command_parser.add_argument("--timeout", type=float, default=2 if command == "stop" else 15)
    args = parser.parse_args()
    if hasattr(args, "timeout") and not 0 < args.timeout <= 120:
        parser.error("--timeout must be greater than 0 and at most 120 seconds")
    try:
        if args.command == "build":
            build(args)
        elif args.command == "preflight":
            preflight(args.app)
        elif args.command == "handshake":
            handshake(args.app, args.timeout)
        elif args.command == "stop":
            stop(args.app, args.timeout)
        else:
            run(args.app, args.timeout)
    except (DevError, OSError) as error:
        print(f"Gojo development check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
