"""Run the real launchers against isolated inputs; no Godot/game assets needed."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
if os.name == "nt":
    git_bash = Path(r"C:\Program Files\Git\bin\bash.exe")
    BASH = str(git_bash) if git_bash.exists() else None
SENTINELS = (
    "data/character-presentations.json",
    "data/character_skills.json",
    "shaders/native_body_layer4.gdshader",
)


class LauncherFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="launcher tests ", dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "project with spaces"
        self.project.mkdir()
        for name in ("run-prototype.sh", "run-prototype.cmd"):
            shutil.copyfile(ROOT / name, self.project / name)
        self.env = os.environ.copy()
        for name in ("GODOT", "GODOT_EXE", "GODOT_BIN"):
            self.env.pop(name, None)

    def provide_inputs(self):
        for name in SENTINELS:
            path = self.project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture", encoding="utf-8")


@unittest.skipUnless(BASH, "Bash is unavailable")
class BashLauncherTests(LauncherFixture):
    def setUp(self):
        super().setUp()
        self.fake = self.base / "fake engine"
        fake_source = (
            '#!/usr/bin/env bash\n'
            'printf "%s\\0" CALL "$@" >> "$ENGINE_LOG"\n'
            'if [[ "$1" == --version ]]; then\n'
            '  printf "%s\\n" "${ENGINE_VERSION:-4.6.3.stable.official.fixture}"\n'
            '  exit "${VERSION_EXIT:-0}"\n'
            'fi\n'
            'for arg in "$@"; do\n'
            '  if [[ "$arg" == --import ]]; then exit "${IMPORT_EXIT:-0}"; fi\n'
            'done\n'
            'exit "${GAME_EXIT:-0}"\n'
        )
        with self.fake.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(fake_source)
        self.fake.chmod(0o755)
        self.log = self.base / "calls.log"
        self.env["ENGINE_LOG"] = self.log.as_posix()
        self.env["GODOT_BIN"] = self.fake.as_posix()

    def launch(self, *args):
        return subprocess.run(
            [BASH, str(self.project / "run-prototype.sh"), *args],
            cwd=self.base, env=self.env, capture_output=True, text=True, timeout=15,
        )

    def calls(self):
        if not self.log.exists():
            return []
        return [part.split(b"\0")[:-1] for part in self.log.read_bytes().split(b"CALL\0")[1:]]

    def test_missing_inputs_stop_before_engine_and_explain_import(self):
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/ASSET_IMPORT.zh-CN.md", result.stderr)
        self.assertIn("data/character-presentations.json", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_missing_shader_stops_even_when_data_exists(self):
        self.provide_inputs()
        (self.project / SENTINELS[2]).unlink()
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(SENTINELS[2], result.stderr)
        self.assertEqual(self.calls(), [])

    def test_unavailable_engine_is_reported(self):
        self.provide_inputs()
        self.env["GODOT_BIN"] = str(self.base / "missing engine")
        result = self.launch()
        self.assertEqual(result.returncode, 127)
        self.assertIn("Godot", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_unsupported_and_prerelease_versions_never_import(self):
        self.provide_inputs()
        for version in ("4.7.2.stable.official.hash", "4.6.2.stable.hash", "4.6.30.stable.hash", "4.6.3.rc1.hash", "garbage"):
            with self.subTest(version=version):
                self.log.unlink(missing_ok=True)
                self.env["ENGINE_VERSION"] = version
                result = self.launch()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("4.6.3", result.stderr)
                self.assertEqual(self.calls(), [[b"--version"]])

    def test_version_probe_failure_never_imports(self):
        self.provide_inputs()
        self.env["VERSION_EXIT"] = "23"
        result = self.launch()
        self.assertEqual(result.returncode, 23)
        self.assertIn("version", result.stderr.lower())
        self.assertEqual(self.calls(), [[b"--version"]])

    def test_space_paths_and_game_arguments_reach_engine_after_import(self):
        self.provide_inputs()
        result = self.launch("--headless", "--", "value with spaces", "a*b", "")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0], [b"--version"])
        self.assertEqual(calls[1][:3], [b"--headless", b"--editor", b"--path"])
        self.assertEqual(calls[1][-1], b"--import")
        self.assertEqual(calls[2], [b"--path", calls[1][3], b"--headless", b"--", b"value with spaces", b"a*b", b""])
        self.assertTrue(calls[1][3].endswith(b"/project with spaces"))

    def test_import_failure_code_propagates_without_starting_game(self):
        self.provide_inputs()
        self.env["IMPORT_EXIT"] = "37"
        result = self.launch()
        self.assertEqual(result.returncode, 37)
        self.assertEqual(len(self.calls()), 2)

    def test_game_failure_code_propagates(self):
        self.provide_inputs()
        self.env["GAME_EXIT"] = "41"
        result = self.launch()
        self.assertEqual(result.returncode, 41)
        self.assertEqual(len(self.calls()), 3)


@unittest.skipUnless(os.name == "nt", "Native Windows cmd is unavailable")
class WindowsLauncherTests(LauncherFixture):
    def launch(self, *args):
        # Pass cmd's enclosing quotes literally; Python's argv quoting escapes them.
        command = subprocess.list2cmdline([os.environ.get("COMSPEC", "cmd.exe")]) + ' /d /s /c "' + subprocess.list2cmdline([str(self.project / "run-prototype.cmd"), *args]) + '"'
        return subprocess.run(
            command,
            cwd=self.base, env=self.env, capture_output=True, text=True, timeout=15,
        )

    def test_missing_inputs_explain_import_before_engine_lookup(self):
        self.env["GODOT_EXE"] = str(self.base / "missing engine.exe")
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/ASSET_IMPORT.zh-CN.md", result.stdout + result.stderr)
        self.assertIn(SENTINELS[0], result.stdout + result.stderr)

    def test_explicit_missing_engine_is_reported(self):
        self.provide_inputs()
        self.env["GODOT_EXE"] = str(self.base / "missing engine.exe")
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Godot", result.stdout + result.stderr)

    def test_incompatible_executable_is_rejected_before_import(self):
        self.provide_inputs()
        self.env["GODOT_EXE"] = sys.executable
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("4.6.3", result.stdout + result.stderr)
        self.assertNotIn("unknown option", result.stdout + result.stderr)

    def test_ambient_godot_variable_cannot_select_an_engine(self):
        self.provide_inputs()
        self.env["GODOT"] = sys.executable
        self.env["PATH"] = ""
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Godot executable not found", result.stdout + result.stderr)
        self.assertNotIn("unknown option", result.stdout + result.stderr)


CSC = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"


@unittest.skipUnless(os.name == "nt" and CSC.exists(), "Optional native Windows test compiler is unavailable")
class WindowsEngineTests(LauncherFixture):
    @classmethod
    def setUpClass(cls):
        cls.engine_temp = tempfile.TemporaryDirectory(prefix="native fake engine ", dir=ROOT)
        cls.addClassCleanup(cls.engine_temp.cleanup)
        cls.fake = Path(cls.engine_temp.name) / "fake engine.exe"
        source = cls.fake.with_suffix(".cs")
        source.write_text(
            'using System; using System.IO;\n'
            'class FakeEngine { static int Main(string[] args) {\n'
            'File.AppendAllText(Environment.GetEnvironmentVariable("ENGINE_LOG"), "CALL\\0" + string.Join("\\0", args) + "\\0");\n'
            'if (args[0] == "--version") { Console.WriteLine(Environment.GetEnvironmentVariable("ENGINE_VERSION") ?? "4.6.3.stable.official.fixture"); return 0; }\n'
            'return int.Parse(Environment.GetEnvironmentVariable(Array.IndexOf(args, "--import") >= 0 ? "IMPORT_EXIT" : "GAME_EXIT") ?? "0");\n'
            '} }\n', encoding="utf-8",
        )
        result = subprocess.run([str(CSC), "/nologo", "/out:" + str(cls.fake), str(source)], capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError("Native test engine compilation failed: " + result.stdout + result.stderr)

    def setUp(self):
        super().setUp()
        self.provide_inputs()
        self.log = self.base / "calls.log"
        self.env["ENGINE_LOG"] = str(self.log)
        self.env["GODOT_EXE"] = str(self.fake)

    launch = WindowsLauncherTests.launch
    calls = BashLauncherTests.calls

    def test_space_paths_and_arguments_reach_native_engine(self):
        result = self.launch("--headless", "--", "value with spaces", "a*b", "")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        imports = [args for args in calls if b"--import" in args]
        self.assertEqual(len(imports), 1)
        self.assertEqual(imports[0][:3], [b"--headless", b"--editor", b"--path"])
        self.assertEqual(calls[-1], [b"--path", imports[0][3], b"--headless", b"--", b"value with spaces", b"a*b", b""])
        self.assertIn(b"project with spaces", imports[0][3])

    def test_native_import_and_game_failure_codes_propagate(self):
        for variable, code, game_started in (("IMPORT_EXIT", "37", False), ("GAME_EXIT", "41", True)):
            with self.subTest(variable=variable):
                self.log.unlink(missing_ok=True)
                self.env.pop("IMPORT_EXIT", None)
                self.env[variable] = code
                result = self.launch()
                self.assertEqual(result.returncode, int(code), result.stdout + result.stderr)
                self.assertEqual(any(args[:1] == [b"--path"] for args in self.calls()), game_started)

    def test_native_unsupported_versions_stop_before_import(self):
        for version in ("4.7.2.stable.official.hash", "4.6.30.stable.hash", "4.6.3.rc1.hash"):
            with self.subTest(version=version):
                self.log.unlink(missing_ok=True)
                self.env["ENGINE_VERSION"] = version
                result = self.launch()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("4.6.3", result.stdout + result.stderr)
                self.assertTrue(all(args == [b"--version"] for args in self.calls()), self.calls())


if __name__ == "__main__":
    unittest.main()
