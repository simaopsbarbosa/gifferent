#!/usr/bin/env python3
"""check that local markdown links resolve inside the repository."""

from pathlib import Path
from urllib.parse import unquote, urlparse
import re
import sys


root = Path(__file__).resolve().parent.parent
link_pattern = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
errors = []

for document in sorted(root.glob("*.md")):
    for line_number, line in enumerate(document.read_text().splitlines(), start=1):
        for match in link_pattern.finditer(line):
            raw_link = match.group(1).split(maxsplit=1)[0].strip("<>")
            parsed = urlparse(raw_link)
            if parsed.scheme or raw_link.startswith("#"):
                continue
            target = (document.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(root) or not target.exists():
                errors.append(f"{document.name}:{line_number}: missing {raw_link}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print("local markdown links resolve")
