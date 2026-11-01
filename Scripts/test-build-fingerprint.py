#!/usr/bin/env python3
"""reject stale test binaries when reusing a build across test invocations."""

import hashlib
import os
from pathlib import Path
import subprocess


def fingerprint(root):
    digest = hashlib.sha256()
    digest.update(str(root).encode())
    digest.update(subprocess.check_output(["xcodebuild", "-version"]))
    digest.update(subprocess.check_output(["xcode-select", "-p"]))
    for name in ("DEVELOPER_DIR", "GIFFERENT_TEST_DEVELOPMENT_TEAM"):
        digest.update(f"{name}={os.environ.get(name, '')}\0".encode())
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
         "--", "Sources", "Tests", "Brand", "Vendor", "ThirdPartyNotices",
         "gifferent.xcodeproj", "gifferent.xctestplan", "Scripts"], cwd=root
    ).split(b"\0")
    for raw in sorted(set(paths) - {b""}):
        path = root / os.fsdecode(raw)
        if path.is_file():
            digest.update(raw + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


if __name__ == "__main__":
    print(fingerprint(Path(__file__).resolve().parent.parent))
