#!/usr/bin/env python3
"""Check the committed Gifski candidate license inventory and evidence files."""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "ThirdPartyNotices" / "Gifski-1.34.0"
README = BASE / "README.md"
TREE = BASE / "source-evidence" / "aarch64-apple-darwin-dependency-tree.txt"


def fail(message: str) -> None:
    print(f"gifski notice check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


readme = README.read_text(encoding="utf-8")
tree = TREE.read_text(encoding="utf-8")
tree_packages = set(re.findall(r"([\w-]+) v([\w.+-]+)", tree))
inventory = re.findall(r"^\| `([\w-]+) ([\w.+-]+)` \| `[^`]+` \| (.+) \|$", readme, re.M)

if len(inventory) != 47:
    fail(f"expected 47 active crates in the inventory, found {len(inventory)}")

inventory_packages = {(name, version) for name, version, _ in inventory}
tree_packages.discard(("gifski", "1.34.0"))
if inventory_packages != tree_packages:
    missing = sorted(tree_packages - inventory_packages)
    extra = sorted(inventory_packages - tree_packages)
    fail(f"inventory differs from the pinned dependency graph; missing={missing}, extra={extra}")

for name, version, file_list in inventory:
    for relative in re.findall(r"`([^`]+)`", file_list):
        path = BASE / relative
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"missing or empty license/notice file: {relative}")

expected_hashes = {
    "source-evidence/Cargo.toml": "5738d2ed632ece91a87a129598c180b866b7133344c8bbe732dd13f18ef640ec",
    "source-evidence/Cargo.lock": "d407a44d19ad1527baccdc5a07477cdba2872dc60bb09f2c524503dd26a3ce2f",
    "source-evidence/gifski-license-page-2026-10-29.html": "dfdb14092ce04de8d71670316dbe222dededeb3ffc07bbf6c8448998dec326f8",
    "source-evidence/active-crate-checksums.tsv": "52f6bfd18b77e3c3dcd17e124fd5c45ba4d8f32cb01c4d17d7e76eb316bde5b0",
    "crates/imagequant-4.4.1/LICENSE-GPL-3.0-or-later.txt": "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986",
}
for relative, expected in expected_hashes.items():
    path = BASE / relative
    if not path.is_file():
        fail(f"missing source evidence: {relative}")
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        fail(f"SHA-256 mismatch for {relative}: expected {expected}, got {actual}")

lock = tomllib.loads((BASE / "source-evidence/Cargo.lock").read_text(encoding="utf-8"))
locked_crates = {
    (package["name"], package["version"]): package["checksum"]
    for package in lock["package"]
    if package.get("source", "").startswith("registry+")
}
checksum_lines = (BASE / "source-evidence/active-crate-checksums.tsv").read_text(encoding="utf-8").splitlines()[1:]
for line in checksum_lines:
    name, version, checksum = line.split("\t")
    if locked_crates.get((name, version)) != checksum:
        fail(f"active crate checksum differs from Cargo.lock: {name} {version}")
if {(line.split("\t")[0], line.split("\t")[1]) for line in checksum_lines} != inventory_packages:
    fail("active crate checksum list does not match the license inventory")

apache = BASE / "crates" / "gif-dispose-5.0.1" / "LICENSE-APACHE-2.0.txt"
if hashlib.sha256(apache.read_bytes()).hexdigest() != "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30":
    fail("canonical Apache-2.0 license text does not match the recorded checksum")

pngquant = (BASE / "imagequant" / "pngquant-publisher-notice.txt").read_text(encoding="utf-8")
for required in ("Jef Poskanzer", "Greg Roelofs", "Stefan Schneider", "Redistributions in binary form"):
    if required not in pngquant:
        fail(f"pngquant publisher notice is missing expected text: {required}")

if not (BASE / "gifski" / "LICENSE").is_file():
    fail("missing upstream Gifski license")

print("Gifski 1.34.0 notice inventory and pinned source checks pass")
