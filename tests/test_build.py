import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.command_log = self.home / "commands.jsonl"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "COMMAND_LOG": str(self.command_log),
        }
        for name in ("docker", "npm", "claude", "codex"):
            command = self.bin / name
            command.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "name = Path(sys.argv[0]).name\n"
                "with open(os.environ['COMMAND_LOG'], 'a') as output:\n"
                "    output.write(json.dumps([name, *sys.argv[1:]]) + '\\n')\n"
                "sys.exit(int(os.environ.get(name.upper() + '_EXIT_STATUS', '0')))\n"
            )
            command.chmod(0o755)

    def commands(self):
        return [json.loads(line) for line in self.command_log.read_text().splitlines()]

    def install_ai_tools(self, **environment):
        dockerfile = (ROOT / "base/Dockerfile").read_text()
        command = next(
            line.removeprefix("RUN ")
            for line in dockerfile.replace("\\\n", "").splitlines()
            if line.startswith("RUN npm install -g")
        )
        return subprocess.run(
            ["/bin/sh", "-c", command],
            env={**self.env, **environment},
            capture_output=True,
            text=True,
        )

    def test_ai_install_failure_stops_build(self):
        result = self.install_ai_tools(NPM_EXIT_STATUS="23")
        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self.assertEqual([command[0] for command in self.commands()], ["npm"])

    def test_ai_version_check_failure_stops_build(self):
        result = self.install_ai_tools(CODEX_EXIT_STATUS="17")
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        self.assertEqual(
            [command[0] for command in self.commands()], ["npm", "claude", "codex"]
        )

    def test_ai_install_requests_latest_versions_online(self):
        result = self.install_ai_tools()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.commands()[0],
            [
                "npm", "install", "-g", "--prefer-online",
                "@anthropic-ai/claude-code@latest",
                "@openai/codex@latest",
            ],
        )
        self.assertEqual(
            [command[0] for command in self.commands()], ["npm", "claude", "codex", "npm"]
        )
        self.assertEqual(self.commands()[-1], ["npm", "cache", "clean", "--force"])

    def build_all(self, **environment):
        return subprocess.run(
            [
                "task", "--silent", "build-all",
                "REGISTRY=registry.example.invalid/team/runtime",
                "BASE_IMAGE=registry.example.invalid/team/runtime@sha256:" + "a" * 64,
                "TIMESTAMP=2026110300", "GIT_COMMIT=revision",
                "BUILD_DATE=2026-11-03T00:00:00Z",
            ],
            cwd=ROOT,
            env={**self.env, **environment},
            capture_output=True,
            text=True,
        )

    @unittest.skipUnless(shutil.which("task"), "Task is required to verify build commands")
    def test_build_all_refreshes_dependencies_and_uses_current_base_for_every_ide(self):
        result = self.build_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = self.commands()
        self.assertEqual(len(commands), 12)
        self.assertEqual(commands[0][:3], ["docker", "buildx", "build"])
        self.assertIn("base/Dockerfile", commands[0])
        self.assertIn(
            "registry.example.invalid/team/runtime:base-revision", commands[0]
        )
        for command in commands:
            self.assertIn("--pull", command)
            self.assertIn("--no-cache", command)
        expected_images = [
            "vscode", "vscode-web", "cursor", "intellij", "goland",
            "pycharm", "webstorm", "clion", "phpstorm", "rubymine", "rider",
        ]
        for command, image in zip(commands[1:], expected_images):
            with self.subTest(image=image):
                self.assertIn(
                    "BASE_IMAGE=registry.example.invalid/team/runtime@sha256:" + "a" * 64,
                    command,
                )
                self.assertIn(
                    f"registry.example.invalid/team/runtime:{image}-latest", command
                )
                self.assertFalse(any("IDE_VERSION=" in argument for argument in command))
        self.assertIn("IDE_PRODUCT_CODE=IIU", commands[4])
        self.assertIn("IDE_PRODUCT_CODE=PCP", commands[6])

    @unittest.skipUnless(shutil.which("task"), "Task is required to verify build commands")
    def test_failed_base_build_prevents_ide_builds(self):
        result = self.build_all(DOCKER_EXIT_STATUS="7")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.commands()), 1)
        self.assertIn("base/Dockerfile", self.commands()[0])


if __name__ == "__main__":
    unittest.main()
