#!/usr/bin/env python3
"""validate the approved adaptive menu bar mark and its app resource wiring."""

import json
from pathlib import Path
import re
import sys
from xml.etree import ElementTree


root = Path(__file__).resolve().parent.parent
imageset = root / "Assets.xcassets" / "MenuBarMark.imageset"
catalog = imageset / "Contents.json"
variants = {
    "light": (root / "Brand" / "mark-light.svg", "mark-light.svg"),
    "dark": (root / "Brand" / "mark-dark.svg", "mark-dark.svg"),
}
errors = []

try:
    contents = json.loads(catalog.read_text())
except (OSError, json.JSONDecodeError) as error:
    print(f"invalid menu bar asset catalog: {error}", file=sys.stderr)
    sys.exit(1)

actual_variants = {}
for image in contents.get("images", []):
    appearances = image.get("appearances", [])
    if len(appearances) == 1 and appearances[0].get("appearance") == "luminosity":
        actual_variants[appearances[0].get("value")] = image

if set(actual_variants) != set(variants):
    errors.append("asset catalog must contain exactly one light and one dark variant")

for appearance, (source, filename) in variants.items():
    image = actual_variants.get(appearance)
    if image is None:
        continue
    if image.get("filename") != filename or image.get("idiom") != "universal" or image.get(
        "scale"
    ) != "1x":
        errors.append(f"{appearance} variant has unexpected catalog metadata")
    bundled = imageset / filename
    try:
        if source.read_bytes() != bundled.read_bytes():
            errors.append(f"{filename} differs from the approved source artwork")
        document = ElementTree.parse(source)
        if document.getroot().attrib.get("viewBox") != "0 0 64 64":
            errors.append(f"{filename} has an unexpected viewBox")
        if "#D45D21" not in source.read_text():
            errors.append(f"{filename} is missing the approved orange accent")
    except (OSError, ElementTree.ParseError) as error:
        errors.append(f"{filename} is missing or invalid: {error}")

project_path = root / "gifferent.xcodeproj" / "project.pbxproj"
project = project_path.read_text()
app_resources = re.search(
    r"A2144E85F6F97DAA567E5DA2 /\* Resources \*/ = \{.*?files = \((.*?)\);",
    project,
    re.DOTALL,
)
if "path = Assets.xcassets;" not in project or app_resources is None or (
    "A00000000000000000000087 /* Assets.xcassets in Resources */"
    not in app_resources.group(1)
):
    errors.append("asset catalog is not included in the app resource build phase")

app_source = (root / "Sources" / "App" / "gifferentApp.swift").read_text()
required_label_parts = (
    'MenuBarExtra {',
    'Image("MenuBarMark")',
    '.frame(width: 16, height: 16)',
    '.renderingMode(.original)',
    '.accessibilityLabel("gifferent")',
)
if any(part not in app_source for part in required_label_parts):
    errors.append("menu bar mark must remain static, original-color, 16-point, and accessible")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print("approved light and dark menu bar mark resources validate")
