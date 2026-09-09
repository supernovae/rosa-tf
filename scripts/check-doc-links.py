#!/usr/bin/env python3
"""Check local Markdown file links, excluding ignored/private workspace files."""
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.md"],
    cwd=ROOT, text=True,
).splitlines()
errors = []
checked = 0
for filename in set(paths):
    path = ROOT / filename
    if not path.exists():
        continue
    for target in re.findall(r'\]\(([^\s)]+)(?:\s+"[^\"]*")?\)', path.read_text()):
        target = target.strip("<>")
        if target.startswith(("#", "/")) or urlsplit(target).scheme:
            continue
        relative = unquote(target.split("#", 1)[0])
        if not relative:
            continue
        checked += 1
        if not (path.parent / relative).exists():
            errors.append(f"{filename}: missing {target}")
if errors:
    raise SystemExit("\n".join(sorted(set(errors))))
print(f"PASS: {checked} local documentation file links (anchors/external URLs not checked)")
