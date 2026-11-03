#!/usr/bin/env python3
"""validate the menu bar comparison mark and its app resource wiring."""

import json
from pathlib import Path
import re
import sys
from xml.etree import ElementTree


root = Path(__file__).resolve().parent.parent
imageset = root / "Assets.xcassets" / "MenuBarMark.imageset"
catalog = imageset / "Contents.json"
errors = []
try:
    contents = json.loads(catalog.read_text())
    images = contents.get("images", [])
    properties = contents.get("properties", {})
    if images != [{"filename": "menu-bar-candidate.svg", "idiom": "universal"}]:
        errors.append("menu bar catalog must contain the universal vector candidate")
    if properties.get("template-rendering-intent") != "template" or not properties.get(
        "preserves-vector-representation"
    ):
        errors.append("menu bar candidate must preserve its vector and use template tinting")
    source = root / "Brand" / "menu-bar-candidate.svg"
    if source.read_bytes() != (imageset / "menu-bar-candidate.svg").read_bytes():
        errors.append("bundled menu bar candidate differs from source artwork")
    if ElementTree.parse(source).getroot().attrib.get("viewBox") != "0 0 20 20":
        errors.append("menu bar candidate has an unexpected viewBox")
except (OSError, json.JSONDecodeError, ElementTree.ParseError) as error:
    errors.append(f"invalid menu bar candidate: {error}")

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
    '.frame(width: 20, height: 20)',
    '.renderingMode(.template)',
    '.accessibilityLabel("gifferent")',
)
if any(part not in app_source for part in required_label_parts):
    errors.append("menu bar mark must remain static, system-tinted, 20-point, and accessible")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print("menu bar comparison mark resources validate")
