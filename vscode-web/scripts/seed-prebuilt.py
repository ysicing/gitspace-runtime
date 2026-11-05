import json
from pathlib import Path
import shutil
import sys
import tempfile


def ensure_directory(home, relative):
    target = home
    for component in Path(relative).parts:
        target = target / component
        if target.is_symlink():
            raise ValueError(f"Cache target must not be a symbolic link: {target}")
        target.mkdir(exist_ok=True)
    return target


def seed_directory(prebuilt, home, relative, ignored=()):
    source = prebuilt / relative
    if not source.is_dir():
        return
    target = ensure_directory(home, relative)
    obsolete = {}
    if (target / ".obsolete").is_file():
        obsolete = json.loads((target / ".obsolete").read_text())
    for cached in sorted(source.iterdir()):
        destination = target / cached.name
        if cached.name in ignored or obsolete.get(cached.name):
            continue
        if destination.exists() or destination.is_symlink():
            continue
        with tempfile.TemporaryDirectory(prefix=".gitspace-seed-", dir=target) as temporary:
            staged = Path(temporary) / cached.name
            if cached.is_dir():
                shutil.copytree(cached, staged, symlinks=True)
            else:
                shutil.copy2(cached, staged, follow_symlinks=False)
            if not destination.exists() and not destination.is_symlink():
                staged.rename(destination)
                print(f"Migrate: added {relative}/{cached.name}")


if __name__ == "__main__":
    prebuilt = Path(sys.argv[1])
    home = Path(sys.argv[2])
    if home.is_symlink():
        raise ValueError("HOME must not be a symbolic link")
    seed_directory(prebuilt, home, ".config/code-server")
    seed_directory(
        prebuilt,
        home,
        ".local/share/code-server/extensions",
        ignored=("extensions.json", ".obsolete"),
    )
