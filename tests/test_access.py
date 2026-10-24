import json
import os
from pathlib import Path
import select
import signal
import stat
import subprocess
import tempfile
import time
import unittest
from urllib.parse import unquote, urlsplit

if os.name == "posix":
    import pty
    import termios


SCRIPT = Path(__file__).resolve().parents[1] / "skills/connectome/scripts/setup-connection.sh"
ENDPOINT = "postgres://example.invalid:5432/sample?application_name=O'Neil&sslmode=require"
USERNAME = " user @name:'\\漢字 "
PASSWORD = "  " + "".join(chr(value) for value in range(32, 127)) + "漢字🙂  "


def terminal(command, inputs, before_input=None, env=None):
    pid, descriptor = pty.fork()
    if pid == 0:
        os.execvpe(command[0], command, env or os.environ.copy())
    output = bytearray()
    no_echo = []
    sent = 0
    status = None
    deadline = time.monotonic() + 12
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([descriptor], [], [], 0.1)
            if ready:
                try:
                    part = os.read(descriptor, 65536)
                except OSError:
                    break
                if not part:
                    break
                output.extend(part)
            if sent < len(inputs) and [b"Username: ", b"Password: "][sent] in output:
                no_echo.append(not (termios.tcgetattr(descriptor)[3] & termios.ECHO))
                if before_input:
                    before_input(sent)
                value = inputs[sent]
                os.write(descriptor, value if isinstance(value, bytes) else (value + "\n").encode())
                sent += 1
        else:
            raise RuntimeError("The local terminal did not finish setup.")
        _, status = os.waitpid(pid, 0)
        restored_echo = bool(termios.tcgetattr(descriptor)[3] & termios.ECHO)
        return os.waitstatus_to_exitcode(status), bytes(output), no_echo, restored_echo
    finally:
        if status is None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(descriptor)


def saved_url(path):
    lines = path.read_text().splitlines()
    value = lines[1].split(": ", 1)[1]
    return urlsplit(value[1:-1].replace("''", "'"))


@unittest.skipUnless(os.name == "posix", "The shell helper requires a POSIX terminal.")
class AccessTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="connectome-access-")
        self.root = Path(self.scratch.name).resolve()
        self.profile = self.root / "private" / "sample.yaml"
        self.command = ["/bin/bash", str(SCRIPT), str(self.profile), "sample", ENDPOINT]

    def tearDown(self):
        self.scratch.cleanup()

    def create(self):
        code, output, no_echo, restored = terminal(self.command, [USERNAME, PASSWORD])
        self.assertEqual(code, 0)
        self.assertEqual(no_echo, [True, True])
        self.assertTrue(restored)
        self.assertNotIn(USERNAME.encode(), output)
        self.assertNotIn(PASSWORD.encode(), output)
        return self.profile.read_bytes()

    def headless(self, command=None):
        return subprocess.run(command or self.command, input=b"do-not-consume\n", capture_output=True, timeout=5)

    def test_private_prompt_round_trips_special_characters(self):
        self.create()
        value = saved_url(self.profile)
        self.assertTrue(unquote(value.username) == USERNAME, "The username changed during setup.")
        self.assertTrue(unquote(value.password) == PASSWORD, "The password changed during setup.")
        self.assertEqual(value.hostname, "example.invalid")
        self.assertEqual(value.port, 5432)
        self.assertEqual(value.query, "application_name=O'Neil&sslmode=require")
        self.assertEqual(stat.S_IMODE(self.profile.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.profile.parent.stat().st_mode), 0o700)
        self.assertEqual(list(self.profile.parent.glob(".setup-*")), [])

    def test_repeat_keeps_profile_without_prompt(self):
        before = self.create()
        modified = self.profile.stat().st_mtime_ns
        result = self.headless()
        self.assertEqual(result.returncode, 0)
        self.assertTrue(self.profile.read_bytes() == before)
        self.assertEqual(self.profile.stat().st_mtime_ns, modified)
        self.assertNotIn(b"Username", result.stdout + result.stderr)

    def test_headless_input_cannot_create_or_renew(self):
        result = self.headless()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.profile.parent.exists())
        before = self.create()
        result = self.headless(self.command + ["--renew"])
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.profile.read_bytes() == before)

    def test_renewal_preserves_unrelated_profiles_and_default_config(self):
        self.create()
        default = self.root / "native-default.yaml"
        unrelated = self.profile.parent / "other.yaml"
        original = b"# keep comments\nconnections:\n  legacy: 'sqlite3::memory:'\ninit: |\n  \\echo keep this\n"
        default.write_bytes(original)
        unrelated.write_bytes(original)
        environment = os.environ.copy()
        environment["USQL_CONFIG"] = str(default)
        code, output, no_echo, _ = terminal(self.command + ["--renew"], [USERNAME, "changed " + PASSWORD], env=environment)
        self.assertEqual(code, 0)
        self.assertEqual(no_echo, [True, True])
        self.assertNotIn(PASSWORD.encode(), output)
        self.assertTrue(unquote(saved_url(self.profile).password) == "changed " + PASSWORD)
        self.assertTrue(default.read_bytes() == original)
        self.assertTrue(unrelated.read_bytes() == original)

    def test_renewal_refuses_unfamiliar_yaml(self):
        self.create()
        with self.profile.open("a") as stream:
            stream.write("  another_connection: 'sqlite3::memory:'\n")
        before = self.profile.read_bytes()
        result = self.headless(self.command + ["--renew"])
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.profile.read_bytes() == before)
        self.assertNotIn(b"Username", result.stdout + result.stderr)

    def test_cancel_and_eof_preserve_state_and_restore_terminal(self):
        code, _, _, restored = terminal(self.command, [b"\x04"])
        self.assertNotEqual(code, 0)
        self.assertTrue(restored)
        self.assertFalse(self.profile.exists())
        before = self.create()
        code, _, no_echo, restored = terminal(self.command + ["--renew"], [USERNAME, b"\x03"])
        self.assertNotEqual(code, 0)
        self.assertEqual(no_echo, [True, True])
        self.assertTrue(restored)
        self.assertTrue(self.profile.read_bytes() == before)
        self.assertEqual(list(self.profile.parent.glob(".setup-*")), [])

    def test_symlinks_and_shared_permissions_are_not_modified(self):
        real = self.root / "real"
        real.mkdir(mode=0o700)
        self.profile.parent.symlink_to(real, target_is_directory=True)
        self.assertNotEqual(self.headless().returncode, 0)
        self.assertEqual(list(real.iterdir()), [])
        self.profile.parent.unlink()
        self.profile.parent.mkdir(mode=0o700)
        target = real / "target.yaml"
        target.write_text("preserve me\n")
        self.profile.symlink_to(target)
        self.assertNotEqual(self.headless().returncode, 0)
        self.assertEqual(target.read_text(), "preserve me\n")
        self.profile.unlink()
        self.profile.parent.chmod(0o755)
        self.assertNotEqual(self.headless().returncode, 0)
        self.assertEqual(stat.S_IMODE(self.profile.parent.stat().st_mode), 0o755)
        self.assertFalse(self.profile.exists())

    def test_credentials_and_invalid_names_are_rejected_before_input(self):
        for endpoint in ("postgres://user:password@example.invalid/db", "postgres://host/db?password=secret", "postgres://host/db?token=secret"):
            command = self.command[:-1] + [endpoint]
            result = self.headless(command)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(endpoint.encode(), result.stdout + result.stderr)
        self.assertNotEqual(self.headless(self.command[:3] + ["../escape", ENDPOINT]).returncode, 0)
        self.assertFalse(self.profile.parent.exists())

    def test_concurrent_creation_does_not_replace_winner(self):
        winner = b"connections:\n  someone_else: 'sqlite3::memory:'\n"

        def publish_first(prompt):
            if prompt == 1:
                self.profile.parent.mkdir(mode=0o700)
                self.profile.write_bytes(winner)
                self.profile.chmod(0o600)

        code, _, _, _ = terminal(self.command, [USERNAME, PASSWORD], before_input=publish_first)
        self.assertNotEqual(code, 0)
        self.assertTrue(self.profile.read_bytes() == winner)
        self.assertEqual(list(self.profile.parent.glob(".setup-*")), [])

    def test_renewal_does_not_replace_changes_made_during_input(self):
        self.create()
        changed = self.profile.read_bytes() + b"  another: 'sqlite3::memory:'\n"

        def edit_during_input(prompt):
            if prompt == 1:
                self.profile.write_bytes(changed)

        code, _, _, _ = terminal(self.command + ["--renew"], [USERNAME, PASSWORD], before_input=edit_during_input)
        self.assertNotEqual(code, 0)
        self.assertTrue(self.profile.read_bytes() == changed)

    @unittest.skipUnless(os.environ.get("USQL_BIN"), "Set USQL_BIN to test the actual upstream client.")
    def test_upstream_usql_reads_saved_uri_in_separate_processes(self):
        self.create()
        command = [os.environ["USQL_BIN"], "-X", "-w", "--config", str(self.profile), "-c", "\\cset"]
        for _ in range(2):
            result = subprocess.run(command, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, "Upstream usql could not read the saved configuration.")
            values = [line.partition(" = ")[2][1:-1] for line in result.stdout.decode().splitlines() if line.partition(" = ")[0].strip() == "sample"]
            self.assertEqual(len(values), 1)
            parsed = urlsplit(values[0])
            self.assertTrue(unquote(parsed.username) == USERNAME, "Upstream usql changed the username.")
            self.assertTrue(unquote(parsed.password) == PASSWORD, "Upstream usql changed the password.")

    @unittest.skipUnless(os.environ.get("USQL_BIN") and os.environ.get("CONNECTOME_AUTH_FIXTURE"), "Set USQL_BIN and CONNECTOME_AUTH_FIXTURE for an authorized live authentication check.")
    def test_live_authentication_reuses_profile(self):
        with open(os.environ["CONNECTOME_AUTH_FIXTURE"]) as stream:
            fixture = json.load(stream)
        command = self.command[:-1] + [fixture["base_url"]]
        code, output, no_echo, _ = terminal(command, [fixture["username"], fixture["password"]])
        self.assertEqual(code, 0, "Private setup failed.")
        self.assertEqual(no_echo, [True, True])
        for key in ("username", "password"):
            self.assertTrue(fixture[key].encode() not in output, "The terminal echoed a credential.")
        before = self.profile.read_bytes()
        self.assertEqual(self.headless(command).returncode, 0)
        self.assertTrue(self.profile.read_bytes() == before)
        query = [os.environ["USQL_BIN"], "-X", "-w", "--config", str(self.profile), "sample", "-t", "-A", "-c", "SELECT 1;"]
        for _ in range(2):
            result = subprocess.run(query, capture_output=True, timeout=25)
            self.assertEqual(result.returncode, 0, "The live connection check failed. Client diagnostics are withheld to protect credentials.")
            self.assertTrue(result.stdout.strip() == b"1", "The live query returned an unexpected result.")


if __name__ == "__main__":
    unittest.main(verbosity=2)
