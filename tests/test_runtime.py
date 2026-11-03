import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RuntimeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "HOME_DIR": str(self.home),
            "GIT_CONFIG_GLOBAL": str(self.home / ".gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "REPO_NAME": "project",
            "BRANCH": "main",
        }
        self.real_git = shutil.which("git")
        self.write_command(
            "git",
            'if [ "$1" = ls-remote ]; then exit 0; fi\n'
            f'exec "{self.real_git}" "$@"\n',
        )

    def write_command(self, name, body):
        command = self.bin / name
        command.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        command.chmod(0o755)

    def shell(self, script, *, success=True, **environment):
        result = subprocess.run(
            ["bash", "-c", script],
            env={**self.env, **environment},
            text=True,
            capture_output=True,
            cwd=self.home,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def repository(self):
        self.shell(
            'git init -q -b main project\n'
            'cd project\n'
            'printf "original\\n" > tracked.txt\n'
            'git add tracked.txt\n'
            'git -c user.name=Test -c user.email=test@example.invalid commit -qm initial\n'
            'git remote add origin https://harness:old-token@example.invalid/team/project.git\n'
        )
        return self.home / "project"

    def test_resume_rotates_origin_without_changing_worktree(self):
        repository = self.repository()
        (repository / "tracked.txt").write_text("local changes\n")
        (repository / "untracked.txt").write_text("keep me\n")
        self.write_command(
            "sudo",
            f'printf "unexpected sudo\\n" >> "{self.home}/sudo-calls"\nexit 1\n',
        )
        new_url = "https://harness:new-token@example.invalid/team/project.git"
        self.shell(
            f'source "{ROOT}/base/scripts/clone-repository.sh"\nclone_repository',
            REPO_URL=new_url,
        )
        origin = self.shell("git -C project remote get-url origin").stdout.strip()
        self.assertEqual(origin, new_url)
        self.assertEqual((repository / "tracked.txt").read_text(), "local changes\n")
        self.assertEqual((repository / "untracked.txt").read_text(), "keep me\n")
        self.assertFalse((self.home / "sudo-calls").exists())

    def test_web_requires_access_key(self):
        self.write_command("code-server", 'touch "$HOME/server-started"\n')
        self.shell(
            f'source "{ROOT}/vscode-web/gitspace-run.sh"\nstart_code_server',
            success=False,
            REPO_NAME="",
            GITSPACE_ACCESS_KEY="",
        )
        self.assertFalse((self.home / "server-started").exists())

    def test_web_password_stays_out_of_config_and_logs(self):
        password = "test-password: with 'quotes' # and spaces"
        self.write_command(
            "code-server",
            'printf "%s" "$PASSWORD" > "$HOME/server-password"\n'
            'printf "%s\\n" "$@" > "$HOME/server-args"\n',
        )
        result = self.shell(
            f'source "{ROOT}/vscode-web/gitspace-run.sh"\nstart_code_server',
            REPO_NAME="",
            GITSPACE_ACCESS_KEY=password,
        )
        config = self.home / ".config/code-server/config.yaml"
        self.assertIn("auth: password", config.read_text())
        self.assertNotIn(password, config.read_text())
        self.assertNotIn(password, result.stdout + result.stderr)
        self.assertEqual((self.home / "server-password").read_text(), password)
        self.assertIn("--config", (self.home / "server-args").read_text())
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)

    def ssh_script(self):
        return (
            f'source "{ROOT}/base/scripts/setup-ssh.sh"\n'
            'log_info() { :; }\n'
            'log_error() { printf "%s\\n" "$*" >&2; }\n'
            'run_as_root() {\n'
            '  case "$1" in chown|chpasswd|/usr/sbin/sshd) cat >/dev/null ;; *) "$@" ;; esac\n'
            '}\n'
            'configure_ssh_server "$HOME/sshd_config"\n'
        )

    def test_ssh_requires_credentials_and_rejects_unknown_access_type(self):
        for access_type in ("user_credentials", "ssh_key", "combined", "invalid"):
            with self.subTest(access_type=access_type):
                self.shell(
                    self.ssh_script(),
                    success=False,
                    GITSPACE_ACCESS_TYPE=access_type,
                    GITSPACE_ACCESS_KEY="",
                    SSH_PUBLIC_KEY="",
                    SSH_PORT="8088",
                )

    def test_ssh_persists_host_identity_and_removes_revoked_authorized_keys(self):
        self.shell(
            self.ssh_script(),
            GITSPACE_ACCESS_TYPE="combined",
            GITSPACE_ACCESS_KEY="password",
            SSH_PUBLIC_KEY="ssh-ed25519 test-public-key",
            SSH_PORT="8098",
        )
        private_key = self.home / ".gitspace/ssh-host-keys/ssh_host_ed25519_key"
        first_key = private_key.read_bytes()
        self.shell(
            self.ssh_script(),
            GITSPACE_ACCESS_TYPE="user_credentials",
            GITSPACE_ACCESS_KEY="new-password",
            SSH_PUBLIC_KEY="",
            SSH_PORT="8099",
        )
        self.assertEqual(private_key.read_bytes(), first_key)
        self.assertEqual(private_key.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.home / ".ssh/authorized_keys").read_text(), "")
        config = (self.home / "sshd_config").read_text()
        self.assertIn("Port 8099", config)
        self.assertIn("PermitEmptyPasswords no", config)
        self.assertIn("PubkeyAuthentication no", config)

    def test_jetbrains_gateway_path_points_at_selected_ide(self):
        ide = self.home / "preinstalled"
        (ide / "bin").mkdir(parents=True)
        (ide / "bin/remote-dev-server.sh").touch()
        self.shell(
            f'source "{ROOT}/jetbrains/gitspace-run.sh"\nresolve_ide_path',
            JETBRAINS_IDE_DIR=str(ide),
            IDE_TYPE="goland",
        )
        gateway = self.home / ".cache/JetBrains/RemoteDev/dist/goland"
        self.assertEqual(gateway.resolve(), ide.resolve())
        replacement = self.home / "replacement"
        (replacement / "bin").mkdir(parents=True)
        (replacement / "bin/remote-dev-server.sh").touch()
        self.shell(
            f'source "{ROOT}/jetbrains/gitspace-run.sh"\nresolve_ide_path',
            JETBRAINS_IDE_DIR=str(replacement),
            IDE_TYPE="goland",
        )
        self.assertEqual(gateway.resolve(), replacement.resolve())
        self.shell(
            f'source "{ROOT}/jetbrains/gitspace-run.sh"\nresolve_ide_path',
            JETBRAINS_IDE_DIR=str(gateway),
            IDE_TYPE="goland",
        )
        self.assertEqual(gateway.resolve(), replacement.resolve())

    def test_jetbrains_keeps_existing_gateway_directory(self):
        ide = self.home / "preinstalled"
        (ide / "bin").mkdir(parents=True)
        (ide / "bin/remote-dev-server.sh").touch()
        gateway = self.home / ".cache/JetBrains/RemoteDev/dist/goland"
        gateway.mkdir(parents=True)
        (gateway / "keep").write_text("preserved")
        self.shell(
            f'source "{ROOT}/jetbrains/gitspace-run.sh"\nresolve_ide_path',
            success=False,
            JETBRAINS_IDE_DIR=str(ide),
            IDE_TYPE="goland",
        )
        self.assertEqual((gateway / "keep").read_text(), "preserved")

    def test_ssh_key_mode_disables_password_authentication(self):
        self.shell(
            self.ssh_script(),
            GITSPACE_ACCESS_TYPE="ssh_key",
            GITSPACE_ACCESS_KEY="",
            SSH_PUBLIC_KEY="ssh-ed25519 test-public-key",
            SSH_PORT="8088",
        )
        config = (self.home / "sshd_config").read_text()
        self.assertIn("PasswordAuthentication no", config)
        self.assertIn("PubkeyAuthentication yes", config)

    def test_lifecycle_create_once_start_every_time_and_preserve_argv(self):
        self.repository()
        post_create = json.dumps(["bash", "-c", 'printf "%s\\n" "$1" >> created', "_", "a b;$literal"])
        post_start = json.dumps({"first": "echo start >> started", "second": ["touch", "second hook"]})
        script = (
            f'source "{ROOT}/base/scripts/run-lifecycle.sh"\n'
            'REPO_DIR="$HOME/project"\n'
            'run_gitspace_lifecycle\n'
            'run_gitspace_lifecycle\n'
        )
        self.shell(
            script,
            GITSPACE_POST_CREATE_COMMAND=post_create,
            GITSPACE_POST_START_COMMAND=post_start,
        )
        repository = self.home / "project"
        self.assertEqual((repository / "created").read_text(), "a b;$literal\n")
        self.assertEqual((repository / "started").read_text(), "start\nstart\n")
        self.assertTrue((repository / "second hook").exists())

    def test_failed_post_create_retries_and_does_not_run_post_start(self):
        self.repository()
        script = (
            f'source "{ROOT}/base/scripts/run-lifecycle.sh"\n'
            'REPO_DIR="$HOME/project"\n'
            'run_gitspace_lifecycle\n'
        )
        self.shell(
            script,
            success=False,
            GITSPACE_POST_CREATE_COMMAND=json.dumps("exit 7"),
            GITSPACE_POST_START_COMMAND=json.dumps("touch should-not-run"),
        )
        self.assertFalse((self.home / "project/should-not-run").exists())
        self.shell(
            script,
            GITSPACE_POST_CREATE_COMMAND=json.dumps("touch retried"),
            GITSPACE_POST_START_COMMAND=json.dumps("touch started"),
        )
        self.assertTrue((self.home / "project/retried").exists())
        self.assertTrue((self.home / "project/started").exists())

    def test_lifecycle_parallel_failure_waits_and_blocks_start(self):
        self.repository()
        self.shell(
            f'source "{ROOT}/base/scripts/run-lifecycle.sh"\n'
            'REPO_DIR="$HOME/project"\nrun_gitspace_lifecycle',
            success=False,
            GITSPACE_POST_CREATE_COMMAND=json.dumps({
                "failed": ["bash", "-c", "exit 3"],
                "succeeded": "sleep 0.1; touch parallel-completed",
            }),
            GITSPACE_POST_START_COMMAND=json.dumps("touch should-not-run"),
        )
        repository = self.home / "project"
        self.assertTrue((repository / "parallel-completed").exists())
        self.assertFalse((repository / "should-not-run").exists())
        self.assertFalse((repository / ".git/gitspace-post-create-complete").exists())

    def test_lifecycle_rejects_invalid_commands(self):
        for command in ("{", "12", '["echo", 3]'):
            with self.subTest(command=command):
                self.shell(
                    f'source "{ROOT}/base/scripts/run-lifecycle.sh"\n'
                    'run_lifecycle_command "$TEST_COMMAND"',
                    success=False,
                    TEST_COMMAND=command,
                )

    def test_image_entrypoint_and_base_contract(self):
        for name in ("vscode", "vscode-web", "cursor", "jetbrains"):
            with self.subTest(image=name):
                dockerfile = (ROOT / name / "Dockerfile").read_text()
                self.assertIn("ARG BASE_IMAGE=", dockerfile)
                self.assertIn("FROM ${BASE_IMAGE}", dockerfile)
                self.assertIn(f"COPY {name}/gitspace-run.sh /usr/local/bin/gitspace-run.sh", dockerfile)
                if name != "vscode-web":
                    self.assertNotIn("ssh-keygen -A", dockerfile)
                    self.assertIn("rm -f /etc/ssh/ssh_host_*", dockerfile)
        base = (ROOT / "base/Dockerfile").read_text()
        self.assertIn("WORKDIR /home/vscode", base)
        self.assertIn("COPY base/scripts/*.sh /usr/local/gitspace/scripts/common/", base)


if __name__ == "__main__":
    unittest.main()
