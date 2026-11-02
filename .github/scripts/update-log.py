#!/usr/bin/env python3
"""
Writes Kultr/Data/UpdateLog.generated.swift: every released version's notes,
for Settings → About → Update log. Run it after adding release notes for a
new version (.github/release-notes/vX.Y.Z.md) and commit the result.

Each notes file is read up to its "## Install" section: "## " lines become
section titles, "**Title**" lines on their own become sub-titles, "- " lines
become entries (lines indented under them are folded in), anything else is
plain text. Release dates come from .github/release-notes/dates.json.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NOTES = os.path.join(ROOT, ".github", "release-notes")
OUT = os.path.join(ROOT, "Kultr", "Data", "UpdateLog.generated.swift")

# Versions released before notes were kept in the repository.
EARLY = {
    "1.0.1": [{"title": "", "lines": [{"kind": "text", "text": "Fixes to the first release."}]}],
    "1.0.0": [{"title": "", "lines": [{"kind": "text", "text": "The first release of Kultr for iOS."}]}],
}


def version_key(version):
    return tuple(int(p) if p.isdigit() else 0 for p in version.split("."))


def parse(text):
    text = text.split("## Install")[0]
    sections = []
    current = {"title": "", "lines": []}
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith("## "):
            if current["lines"] or current["title"]:
                sections.append(current)
            current = {"title": line[3:].strip(), "lines": []}
        elif re.fullmatch(r"\*\*[^*]+\*\*", line.strip()):
            current["lines"].append({"kind": "heading", "text": line.strip().strip("*")})
        elif line.startswith("- "):
            current["lines"].append({"kind": "bullet", "text": line[2:].strip()})
        elif raw.startswith("  ") and current["lines"] and current["lines"][-1]["kind"] == "bullet":
            sub = line.strip()
            if sub.startswith("- "):
                current["lines"].append({"kind": "subbullet", "text": sub[2:].strip()})
            else:
                current["lines"][-1]["text"] += " " + sub
        elif raw.startswith("  ") and current["lines"] and current["lines"][-1]["kind"] == "subbullet":
            current["lines"][-1]["text"] += " " + line.strip()
        else:
            current["lines"].append({"kind": "text", "text": line.strip()})
    if current["lines"] or current["title"]:
        sections.append(current)
    return sections


def main():
    dates = {}
    dates_file = os.path.join(NOTES, "dates.json")
    if os.path.exists(dates_file):
        with open(dates_file, encoding="utf-8") as f:
            dates = json.load(f)
    entries = []
    for name in os.listdir(NOTES):
        match = re.fullmatch(r"v(\d+\.\d+\.\d+)\.md", name)
        if not match:
            continue
        with open(os.path.join(NOTES, name), encoding="utf-8") as f:
            entries.append({"version": match.group(1), "date": dates.get(match.group(1), ""), "sections": parse(f.read())})
    for version, sections in EARLY.items():
        if not any(e["version"] == version for e in entries):
            entries.append({"version": version, "date": dates.get(version, ""), "sections": sections})
    entries.sort(key=lambda e: version_key(e["version"]), reverse=True)
    payload = json.dumps(entries, ensure_ascii=False, indent=1)
    # A raw string with one more # than any run of them after a quote in the notes.
    longest = max([len(m) for m in re.findall(r'"(#+)', payload)] + [0])
    hashes = "#" * (longest + 1)
    swift = (
        "// Made by .github/scripts/update-log.py from .github/release-notes; don't edit by hand.\n\n"
        "/** Every released version's notes, newest first, as JSON. */\n"
        "let UPDATE_LOG_JSON = " + hashes + '"""\n' + payload + '\n"""' + hashes + "\n"
    )
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(swift)
    print(f"Update log: {len(entries)} versions, newest {entries[0]['version']}.")


if __name__ == "__main__":
    main()
