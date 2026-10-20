#!/usr/bin/env python3
"""Development signing checks. Pass --app for a real signed build validation."""

import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("gojo_dev", ROOT / "scripts/dev.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)
SIGNED_APP = None


def status(**changes):
    result = {
        "probeID": str(uuid.uuid4()),
        "available": True,
        "helperInstanceID": str(uuid.uuid4()),
        "protocolVersion": 1,
        "accessibilityAuthorized": False,
    }
    result.update(changes)
    return result


class SigningPolicyTests(unittest.TestCase):
    def test_preflight_requirement_matches_helper_caller_requirement(self):
        source = (ROOT / "GojoXPCHelper/main.swift").read_text()
        self.assertIn('#"' + dev.APP_REQUIREMENT + '"#', source)

    def test_identity_selection_ignores_revoked_and_other_team_certificates(self):
        output = '\n'.join([
            f'  1) {"A" * 40} "Apple Development: Example ({dev.TEAM})" (CSSMERR_TP_CERT_REVOKED)',
            f'  2) {"B" * 40} "Apple Development: Example (OTHERTEAM)"',
            f'  3) {"C" * 40} "Developer ID Application: Example ({dev.TEAM})"',
        ])
        self.assertEqual(dev.signing_identities(output), [
            ("C" * 40, f"Developer ID Application: Example ({dev.TEAM})"),
        ])

    def test_missing_matching_identity_fails_before_build(self):
        with patch.object(dev, "checked", return_value="0 valid identities found"):
            with self.assertRaisesRegex(dev.DevError, "No valid Apple signing identity"):
                dev.signing_identity()

    def test_explicit_identity_must_match_valid_team_identity(self):
        output = f'  1) {"C" * 40} "Developer ID Application: Example ({dev.TEAM})"'
        with patch.object(dev, "checked", return_value=output):
            with self.assertRaisesRegex(dev.DevError, "No valid Apple signing identity"):
                dev.signing_identity("-")

    def test_accessibility_denial_is_a_successful_helper_handshake(self):
        payload = status()
        self.assertEqual(dev.validate_handshake(payload), payload)

    def test_transport_or_signature_failure_stays_an_error(self):
        with self.assertRaisesRegex(dev.DevError, "signature rejected"):
            dev.validate_handshake(status(available=False, error="signature rejected"))

    def test_incomplete_status_cannot_prove_a_handshake(self):
        for payload in [status(helperInstanceID=""), status(protocolVersion=True),
                        status(accessibilityAuthorized="false"), {"available": True}, []]:
            with self.subTest(payload=payload), self.assertRaises(dev.DevError):
                dev.validate_handshake(payload)

    def test_signature_failure_prevents_both_probe_and_ordinary_launch(self):
        with patch.object(dev, "preflight", side_effect=dev.DevError("signature rejected")):
            with patch.object(dev.subprocess, "Popen") as launch:
                with self.assertRaisesRegex(dev.DevError, "signature rejected"):
                    dev.run(Path("/unused/Gojo.app"))
                launch.assert_not_called()

    def test_running_installed_app_is_not_replaced(self):
        with patch.object(dev, "preflight", return_value=Path("/build/Gojo.app/Contents/MacOS/Gojo")):
            with patch.object(dev, "running_instances", return_value=[(123, "/Applications/Gojo.app/Contents/MacOS/Gojo")]):
                with patch.object(dev.subprocess, "Popen") as launch:
                    with self.assertRaisesRegex(dev.DevError, "Gojo is already running"):
                        dev.run(Path("/build/Gojo.app"))
                    launch.assert_not_called()

    def test_process_lookup_preserves_spaces_and_ignores_other_programs(self):
        output = " 123 /Applications/Gojo.app/Contents/MacOS/Gojo\n 456 /Users/Name/My Build/Gojo.app/Contents/MacOS/Gojo\n 789 /usr/bin/true\n"
        with patch.object(dev, "checked", return_value=output):
            self.assertEqual(dev.running_instances(), [
                (123, "/Applications/Gojo.app/Contents/MacOS/Gojo"),
                (456, "/Users/Name/My Build/Gojo.app/Contents/MacOS/Gojo"),
            ])

    def test_blank_license_override_defaults_without_accessing_real_license(self):
        self.assertEqual(dev.license_override(" "), "lifetime")
        self.assertEqual(dev.license_override(" TRIAL:5 "), "trial:5")
        for value in ["invalid", "trial:0", "trial:-1", "trial:9999999999999999999999"]:
            with self.subTest(value=value), self.assertRaises(dev.DevError):
                dev.license_override(value)

    def test_successful_run_uses_explicit_executable_and_license_environment(self):
        executable = Path("/build/Gojo.app/Contents/MacOS/Gojo")
        with patch.object(dev, "preflight", return_value=executable):
            with patch.object(dev, "running_instances", return_value=[]):
                with patch.object(dev, "handshake") as probe:
                    with patch.object(dev, "checked") as launch:
                        process = dev.ProcessInfo(123, 1, "start", str(executable))
                        with patch.dict(os.environ, {"GOJO_LICENSE": "", dev.PROBE_ENV: "/old/result"}):
                            with patch.object(dev, "process_snapshot", return_value={123: process}):
                                with contextlib.redirect_stdout(io.StringIO()):
                                    dev.run(Path("/build/Gojo.app"))
                        probe.assert_called_once()
                        self.assertEqual(launch.call_args.args[0], [
                            "/usr/bin/open", "-n", "--env", "GOJO_LICENSE=lifetime",
                            "--env", dev.PROBE_ENV + "=0", "/build/Gojo.app",
                        ])

    def test_probe_id_mismatch_and_missing_id_are_rejected(self):
        for payload in [status(), status(probeID=""), status(probeID=None)]:
            with self.subTest(payload=payload), self.assertRaisesRegex(dev.DevError, "probe ID"):
                dev.validate_handshake(payload, str(uuid.uuid4()))

    def test_instance_appearing_during_probe_blocks_ordinary_launch(self):
        with patch.object(dev, "preflight", return_value=Path("/build/Gojo.app/Contents/MacOS/Gojo")):
            with patch.object(dev, "running_instances", side_effect=[[], [(123, "/Applications/Gojo.app/Contents/MacOS/Gojo")]]):
                with patch.object(dev, "handshake"):
                    with patch.object(dev, "checked") as launch:
                        with self.assertRaisesRegex(dev.DevError, "started while the handshake"):
                            dev.run(Path("/build/Gojo.app"))
                        launch.assert_not_called()


class ProbeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="gojo-probe-test-")
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.executable = Path(dev.process_snapshot()[os.getpid()].executable).resolve()
        self.real_popen = subprocess.Popen
        self.commands = []
        self.pid_file = self.home / "child.pid"
        self.launcher = self.home / "launcher.py"
        self.launcher.write_text(
            'import os, subprocess, sys\n'
            'output, error, body, pid_file, nonce = sys.argv[1:]\n'
            'with open(output, "wb") as out, open(error, "wb") as err:\n'
            f' child = subprocess.Popen([sys.executable, "-c", body, {dev.PROBE_ARGUMENT!r}, nonce], stdout=out, stderr=err)\n'
            ' open(pid_file, "w").write(str(child.pid))\n'
            ' raise SystemExit(child.wait())\n'
        )

    def fixture(self, body):
        self.body = 'import json, os, sys, time\n' + body

    def fake_open(self, command, **kwargs):
        if command[0] != "/usr/bin/open":
            return self.real_popen(command, **kwargs)
        self.commands.append(command)
        self.assertEqual(command[:3], ["/usr/bin/open", "-n", "-W"])
        output = Path(command[command.index("--stdout") + 1])
        error = Path(command[command.index("--stderr") + 1])
        self.output_directory = output.parent
        self.assertEqual(output.parent.stat().st_mode & 0o777, 0o700)
        self.assertNotIn("/Library/Containers/", str(output))
        self.assertEqual(command[-2], dev.PROBE_ARGUMENT)
        environment = os.environ.copy()
        for index, argument in enumerate(command):
            if argument == "--env":
                key, value = command[index + 1].split("=", 1)
                environment[key] = value
        self.open_process = self.real_popen([
            sys.executable, str(self.launcher), str(output), str(error),
            self.body, str(self.pid_file), command[-1],
        ], env=environment, **kwargs)
        deadline = time.monotonic() + 3
        while not self.pid_file.exists():
            if self.open_process.poll() is not None or time.monotonic() >= deadline:
                self.fail("Fixture launcher did not start its probe child")
            time.sleep(0.01)
        return self.open_process

    def probe(self, timeout=2):
        with patch.object(dev, "preflight", return_value=self.executable):
            with patch.object(dev, "supports_handshake", return_value=True):
                with patch.object(dev.Path, "home", side_effect=AssertionError("Must not access app container")):
                    with patch.object(dev.subprocess, "Popen", side_effect=self.fake_open):
                        with contextlib.redirect_stdout(io.StringIO()):
                            return dev.handshake(Path("/unused/Gojo.app"), timeout)

    def assert_probe_files_removed(self):
        self.assertFalse(self.output_directory.exists())

    def test_launchservices_stdout_result_and_license_override(self):
        payload = status()
        self.fixture(
            'assert os.environ["GOJO_LICENSE"] == "lifetime"\n'
            f'assert os.environ[{dev.PROBE_ENV!r}] == "1"\n'
            f'p = {payload!r}\np["probeID"] = sys.argv[-1]\nprint(json.dumps(p))\n'
        )
        result = self.probe()
        self.assertEqual(result["helperInstanceID"], payload["helperInstanceID"])
        self.assertEqual(result["probeID"], self.commands[0][-1])
        self.assertNotIn("GOJO_HELPER_HANDSHAKE_OUTPUT", " ".join(self.commands[0]))
        self.assert_probe_files_removed()

    def test_timeout_stops_actual_probe_app_and_launcher(self):
        self.fixture('time.sleep(60)\n')
        with self.assertRaisesRegex(dev.DevError, "timed out"):
            self.probe(timeout=0.2)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(self.pid_file.read_text()), 0)
        self.assertIsNotNone(self.open_process.poll())
        self.assert_probe_files_removed()

    def test_failure_reports_helper_error(self):
        self.fixture('print(json.dumps({"probeID": sys.argv[-1], "available": False, "error": "XPC rejected"}))\nraise SystemExit(1)\n')
        with self.assertRaisesRegex(dev.DevError, "XPC rejected"):
            self.probe()
        self.assert_probe_files_removed()

    def test_missing_result_reports_child_stderr(self):
        self.fixture('import sys\nprint("probe startup failed", file=sys.stderr)\nraise SystemExit(4)\n')
        with self.assertRaisesRegex(dev.DevError, "probe startup failed"):
            self.probe()
        self.assert_probe_files_removed()

    def test_binary_without_probe_is_never_launched(self):
        old = self.home / "old-probe"
        old.write_text("GOJO_HELPER_HANDSHAKE_OUTPUT")
        with patch.object(dev, "preflight", return_value=old):
            with patch.object(dev.subprocess, "Popen") as launch:
                with self.assertRaisesRegex(dev.DevError, "does not support the helper handshake probe"):
                    dev.handshake(Path("/unused/Gojo.app"))
                launch.assert_not_called()

    def test_xcode_linked_debug_dylib_probe_is_supported(self):
        executable = self.home / "probe"
        debug_dylib = executable.with_name(executable.name + ".debug.dylib")
        debug_dylib.write_bytes(dev.PROBE_ENV.encode())
        executable.write_bytes(b"old executable without debug dylib link")
        self.assertFalse(dev.supports_handshake(executable))
        executable.write_bytes(("@rpath/" + debug_dylib.name).encode())
        self.assertTrue(dev.supports_handshake(executable))


class StopRunnerTests(unittest.TestCase):
    def setUp(self):
        self.app = Path("/tmp/My Build/Gojo.app").resolve()
        self.executable = self.app / "Contents/MacOS/Gojo"

    def process(self, pid, path, parent=1, started="Mon Oct 19 12:00:00 2026"):
        return dev.ProcessInfo(pid, parent, started, str(path))

    def test_snapshot_keeps_full_paths_with_spaces_and_start_time(self):
        output = f" 123 1 Mon Oct 19 12:00:00 2026 {self.executable}\n"
        with patch.object(dev, "checked", return_value=output):
            self.assertEqual(dev.process_snapshot(), {123: self.process(123, self.executable)})

    def test_probe_selection_requires_exact_path_and_unique_nonce(self):
        nonce = str(uuid.uuid4())
        processes = [
            self.process(10, self.executable),
            self.process(11, self.executable),
            self.process(12, self.executable),
            self.process(13, "/Applications/Gojo.app/Contents/MacOS/Gojo"),
            self.process(14, self.executable),
        ]
        arguments = {
            10: str(self.executable),
            11: f"{self.executable} {dev.PROBE_ARGUMENT} {nonce} -psn_0_123",
            12: f"{self.executable} {dev.PROBE_ARGUMENT} {uuid.uuid4()}",
            13: f"/Applications/Gojo.app/Contents/MacOS/Gojo {dev.PROBE_ARGUMENT} {nonce}",
            14: f"{self.executable} {dev.PROBE_ARGUMENT} {nonce}extra",
        }
        with patch.object(dev, "process_snapshot", return_value={p.pid: p for p in processes}):
            with patch.object(dev, "process_arguments", side_effect=arguments.get):
                targets = dev.probe_targets(self.executable, nonce)
        self.assertEqual([target[0].pid for target in targets], [11])

    def test_only_exact_bundle_and_its_media_child_are_selected(self):
        helper = "Contents/XPCServices/GojoXPCHelper.xpc/Contents/MacOS/GojoXPCHelper"
        own_media = f"/usr/bin/perl {self.app}/Contents/Resources/mediaremote-adapter.pl {self.app}/Contents/Frameworks/MediaRemoteAdapter.framework stream"
        processes = [
            self.process(10, self.executable),
            self.process(11, self.app / helper),
            self.process(12, "/usr/bin/perl", parent=10),
            self.process(13, "/usr/bin/perl", parent=999),
            self.process(14, "/usr/bin/sleep", parent=10),
            self.process(15, "/Applications/Gojo.app/Contents/MacOS/Gojo"),
            self.process(16, Path("/Applications/Gojo.app") / helper),
            self.process(17, "/tmp/Other Build/Gojo.app/Contents/MacOS/Gojo"),
            self.process(18, "/usr/bin/perl", parent=10),
            self.process(19, self.app / "Contents/Frameworks/Sparkle.framework/Versions/B/Downloader"),
            self.process(20, "/Applications/Gojo.app/Contents/Frameworks/Sparkle.framework/Versions/B/Downloader"),
        ]
        arguments = {12: own_media, 13: own_media, 18: "/usr/bin/perl /unrelated/adapter.pl"}
        with patch.object(dev, "process_arguments", side_effect=arguments.get):
            targets = dev.stop_targets(self.app, self.executable, {p.pid: p for p in processes})
        self.assertEqual([target[0].pid for target in targets], [10, 11, 12, 19])

    def test_reused_pid_or_relaunched_different_path_is_not_signalled(self):
        original = self.process(10, self.executable)
        replacements = [
            {},
            {10: self.process(10, "/Applications/Gojo.app/Contents/MacOS/Gojo")},
            {10: self.process(10, self.executable, started="Mon Oct 19 12:00:01 2026")},
        ]
        for snapshot in replacements:
            with self.subTest(snapshot=snapshot):
                with patch.object(dev, "process_snapshot", return_value=snapshot):
                    with patch.object(dev.os, "kill") as kill:
                        dev.signal_targets([(original, None)], signal.SIGKILL)
                        kill.assert_not_called()

    def test_media_arguments_are_rechecked_before_signal(self):
        process = self.process(12, "/usr/bin/perl", parent=10)
        with patch.object(dev, "process_snapshot", return_value={12: process}):
            with patch.object(dev, "process_arguments", return_value="/usr/bin/perl /unrelated/script.pl"):
                with patch.object(dev.os, "kill") as kill:
                    dev.signal_targets([(process, "/usr/bin/perl /own/script.pl")], signal.SIGTERM)
                    kill.assert_not_called()

    def test_disappeared_pid_between_recheck_and_signal_is_harmless(self):
        process = self.process(10, self.executable)
        with patch.object(dev, "process_snapshot", return_value={10: process}):
            with patch.object(dev.os, "kill", side_effect=ProcessLookupError):
                dev.signal_targets([(process, None)], signal.SIGTERM)

    def test_force_kill_uses_the_same_targets_and_bounded_wait(self):
        process = self.process(10, self.executable)
        targets = [(process, None)]
        with patch.object(dev, "app_executable", return_value=self.executable):
            with patch.object(dev, "process_snapshot", return_value={10: process}):
                with patch.object(dev, "stop_targets", return_value=targets):
                    with patch.object(dev, "wait_for_targets", side_effect=[targets, []]) as wait:
                        with patch.object(dev.os, "kill") as kill:
                            with contextlib.redirect_stdout(io.StringIO()):
                                dev.stop(self.app, timeout=0.25)
                        self.assertEqual(kill.call_args_list, [
                            unittest.mock.call(10, signal.SIGTERM),
                            unittest.mock.call(10, signal.SIGKILL),
                        ])
                        self.assertEqual([call.args[1] for call in wait.call_args_list], [0.25, 0.25])

    def test_wait_returns_after_deadline_without_reselecting_new_processes(self):
        process = self.process(10, self.executable)
        relaunched = self.process(20, self.executable)
        with patch.object(dev, "process_snapshot", return_value={10: process, 20: relaunched}):
            with patch.object(dev.time, "monotonic", side_effect=[0, 1]):
                self.assertEqual(dev.wait_for_targets([(process, None)], timeout=0.1), [(process, None)])

    @unittest.skipUnless(sys.platform == "darwin", "Requires macOS process paths")
    def test_real_stop_terminates_only_the_requested_fixture_bundle(self):
        with tempfile.TemporaryDirectory(prefix="gojo-stop-test-") as directory:
            apps = [Path(directory) / name / "Gojo.app" for name in ["Own Build", "Other Build"]]
            children = []
            fixture_source = r"""#include <signal.h>
#include <unistd.h>
int main(void) {
    signal(SIGTERM, SIG_IGN);
    if (write(STDOUT_FILENO, "ready\n", 6) != 6) return 1;
    for (;;) pause();
}
"""
            def compile_fixture(executable):
                subprocess.run(
                    ["/usr/bin/cc", "-x", "c", "-", "-o", str(executable)],
                    input=fixture_source, text=True, check=True, capture_output=True,
                )

            try:
                executables = []
                for app in apps:
                    executable = app / "Contents/MacOS/Gojo"
                    executable.parent.mkdir(parents=True)
                    compile_fixture(executable)
                    with (app / "Contents/Info.plist").open("wb") as stream:
                        plistlib.dump({"CFBundleIdentifier": dev.APP_ID, "CFBundleExecutable": "Gojo"}, stream)
                    executables.append(executable)
                helper = apps[0] / "Contents/XPCServices/GojoXPCHelper.xpc/Contents/MacOS/GojoXPCHelper"
                helper.parent.mkdir(parents=True)
                compile_fixture(helper)
                with (helper.parent.parent / "Info.plist").open("wb") as stream:
                    plistlib.dump({"CFBundleIdentifier": dev.APP_ID + ".GojoXPCHelper", "CFBundleExecutable": "GojoXPCHelper"}, stream)
                for bundle in [helper.parents[2], *apps]:
                    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(bundle)], check=True, capture_output=True)
                children = [subprocess.Popen([str(executable)], stdout=subprocess.PIPE)
                            for executable in [*executables, helper]]
                for child in children:
                    self.assertTrue(select.select([child.stdout], [], [], 2)[0], "Fixture never reported readiness")
                    self.assertEqual(child.stdout.readline(), b"ready\n", f"Fixture exited before readiness: {child.poll()}")
                deadline = time.monotonic() + 2
                while True:
                    self.assertTrue(all(child.poll() is None for child in children), "Fixture exited before stop")
                    processes = dev.process_snapshot()
                    if all(child.pid in processes and Path(processes[child.pid].executable).resolve() == path.resolve()
                           for child, path in zip(children, [*executables, helper])):
                        break
                    self.assertLess(time.monotonic(), deadline, "Fixture processes did not become observable")
                    time.sleep(0.01)
                with patch.object(dev.os, "kill", wraps=os.kill) as kill:
                    with contextlib.redirect_stdout(io.StringIO()):
                        dev.stop(apps[0], timeout=0.3)
                own_pids = {children[0].pid, children[2].pid}
                self.assertEqual({call.args[0] for call in kill.call_args_list}, own_pids)
                for pid in own_pids:
                    actions = [call.args[1] for call in kill.call_args_list if call.args[0] == pid]
                    self.assertEqual(actions, [signal.SIGTERM, signal.SIGKILL])
                for child in [children[0], children[2]]:
                    self.assertEqual(child.wait(timeout=2), -signal.SIGKILL)
                self.assertIsNone(children[1].poll())
            finally:
                for child in children:
                    if child.poll() is None:
                        child.kill()
                    child.wait(timeout=2)
                    child.stdout.close()


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS code signing")
class RealSignatureTests(unittest.TestCase):
    def test_adhoc_client_is_cryptographically_rejected(self):
        with tempfile.TemporaryDirectory(prefix="gojo-adhoc-test-") as directory:
            app = Path(directory) / "Gojo.app"
            helper = app / "Contents/XPCServices/GojoXPCHelper.xpc"
            for bundle, bundle_id, executable in [
                (helper, dev.APP_ID + ".GojoXPCHelper", "GojoXPCHelper"),
                (app, dev.APP_ID, "Gojo"),
            ]:
                (bundle / "Contents/MacOS").mkdir(parents=True)
                with (bundle / "Contents/Info.plist").open("wb") as stream:
                    plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleExecutable": executable}, stream)
                shutil.copy("/usr/bin/true", bundle / "Contents/MacOS" / executable)
                subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(bundle)], check=True, capture_output=True)
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)
            with self.assertRaisesRegex(dev.DevError, "Signing preflight rejected"):
                dev.preflight(app)

    def test_real_built_app_and_embedded_helper(self):
        if SIGNED_APP is None:
            self.skipTest("Pass --app /path/to/signed/Gojo.app to validate an actual build")
        with contextlib.redirect_stdout(io.StringIO()):
            executable = dev.preflight(SIGNED_APP)
        self.assertTrue(executable.is_file())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    args, unittest_args = parser.parse_known_args()
    SIGNED_APP = args.app
    unittest.main(argv=[sys.argv[0]] + unittest_args)
