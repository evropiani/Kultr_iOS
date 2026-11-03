#!/usr/bin/env python3
"""
Kultr's translations.

The German text lives in .github/l10n/de.json: each English line, as the app
shows it, with its German. A value is a string, or {"one": …, "other": …}
when the German changes with a number. Lines with a number or a name in them
use the placeholders Swift gives them: %lld for a whole number, %@ for text,
%lf for a decimal ("%lld tracks" → "%lld Titel").

    strings.py build              writes Shared/Localizable.xcstrings from de.json
    strings.py audit [files…]     lists the English in the code that de.json lacks
    strings.py check DERIVED      after a build: the lines the compiler found
                                  that de.json lacks (DERIVED is -derivedDataPath)

Run build after changing de.json and commit both. The catalog is in Shared/,
so the app and the widget both use it.
"""

import glob
import json
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, ".github", "l10n", "de.json")
CATALOG = os.path.join(ROOT, "Shared", "Localizable.xcstrings")
CODE = ["Kultr", "Shared", "KultrWidget"]
SKIP_FILES = {"UpdateLog.generated.swift", "ScreenshotDriver.swift"}


def load():
    with open(SOURCE, encoding="utf-8") as f:
        data = json.load(f)
    return {k: v for k, v in data.items() if not k.startswith("//")}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def build():
    data = load()
    strings = {}
    for key in sorted(data, key=lambda k: k.lower()):
        value = data[key]
        if isinstance(value, dict):
            german = {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
        else:
            german = unit(value)
        strings[key] = {"extractionState": "manual", "localizations": {"de": german}}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")
    print(f"{len(strings)} lines in {os.path.relpath(CATALOG, ROOT)}")


# Calls whose first text SwiftUI looks up by itself, and Kultr's own views
# and helpers that look theirs up with .loc.
LOOKED_UP = re.compile(
    r"(?:\bText|\bLabel|\bButton|\bToggle|\bSection|\.navigationTitle|\bTextField|\bSecureField|\bPicker|"
    r"\bMenu|\bLabeledContent|\.alert|\.confirmationDialog|\bContentUnavailableView|\bLink|\bStepper|"
    r"\bNavigationLink|\.help|\.accessibilityLabel|\.accessibilityHint|\.accessibilityValue|\.badge|"
    r"prompt:|String\(localized:|LocalizedStringResource\(|\.configurationDisplayName|\.description|"
    r"\bPill|\bSectionHeader|\bEyebrow|\bWideButton|\bEmptyState|\bNoMatches|\bSettingsRow|\bToggleRow|"
    r"\bChoiceRow|\bInfoRow|\bShelf|\bTileHeader|\bStatTile|\.loc\b|messages\.(?:show|error|success)\(|Words\.t\()"
)


def literals(text):
    """Every "…" literal outside comments: (offset, body)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            i = text.find("\n", i)
            i = n if i < 0 else i
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            i = n if j < 0 else j + 3
            continue
        if text[i] == "#" and text.startswith('#"', i):
            j = text.find('"#', i + 2)
            i = n if j < 0 else j + 2
            continue
        if text[i] == '"':
            start = i
            i += 1
            body = []
            while i < n and text[i] != '"' and text[i] != "\n":
                if text[i] == "\\" and i + 1 < n and text[i + 1] == "(":
                    depth, j = 1, i + 2
                    while j < n and depth:
                        if text[j] == "(":
                            depth += 1
                        elif text[j] == ")":
                            depth -= 1
                        elif text[j] == '"':
                            k = text.find('"', j + 1)
                            j = k if k > 0 else j
                        j += 1
                    body.append(text[i:j])
                    i = j
                    continue
                if text[i] == "\\" and i + 1 < n:
                    body.append(text[i:i + 2])
                    i += 2
                    continue
                body.append(text[i])
                i += 1
            out.append((start, "".join(body)))
            i += 1
            continue
        i += 1
    return out


INTEGER = re.compile(r"(count|minutes|hours|days|total|number|index|tracks|songs|albums|seconds|n|plays|\bInt\()", re.I)


def key_of(body):
    """The key Swift makes of a literal: interpolations become placeholders."""
    def spec(match):
        expr = match.group(1)
        m = re.search(r'specifier:\s*"([^"]+)"', expr)
        if m:
            return m.group(1)
        if re.search(r"\b(Int|count)\b|\.count\b|minutes|Minutes", expr):
            return "%lld"
        return "%@"
    key = re.sub(r"\\\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)", spec, body)
    return key.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


PLACEHOLDER = re.compile(r"%(\d+\$)?(lld|llu|ld|lu|lf|d|u|f|@|\.\d+f)")


def wordy(key):
    """A line with words in it, beyond its placeholders."""
    return re.search(r"[A-Za-z]{2}", PLACEHOLDER.sub("", key)) is not None


def audit(paths):
    have = set(load())
    files = paths or [p for d in CODE for p in glob.glob(os.path.join(ROOT, d, "**", "*.swift"), recursive=True)]
    missing = 0
    for path in sorted(files):
        if os.path.basename(path) in SKIP_FILES:
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for start, body in literals(text):
            if not wordy(key_of(body)):
                continue
            before = text[max(0, start - 160):start]
            line_start = text.rfind("\n", 0, start) + 1
            line_end = text.find("\n", start)
            line = text[line_start:line_end].strip()
            call = re.search(LOOKED_UP.pattern + r"[^\n\"]*$", before)
            if not call:
                continue
            if re.search(r"(systemImage|systemName|Image)\s*[:(]\s*$", before):
                continue
            key = key_of(body)
            if key in have:
                continue
            missing += 1
            lineno = text.count("\n", 0, start) + 1
            print(f"{os.path.relpath(path, ROOT)}:{lineno}: {json.dumps(key, ensure_ascii=False)}    | {line[:110]}")
    print(f"{missing} missing", file=sys.stderr)


def stringsdata(derived):
    keys = {}
    for path in glob.glob(os.path.join(derived, "**", "*.stringsdata"), recursive=True):
        with open(path, "rb") as f:
            raw = f.read()
        try:
            data = json.loads(raw)
        except ValueError:
            data = plistlib.loads(raw)
        source = os.path.relpath(data.get("source", path), ROOT) if data.get("source") else path
        for table, entries in (data.get("tables") or {}).items():
            if table != "Localizable":
                continue
            for entry in entries:
                keys.setdefault(entry["key"], source)
    return keys


def check(derived):
    have = set(load())
    found = stringsdata(derived)
    if not found:
        print("No .stringsdata found: is SWIFT_EMIT_LOC_STRINGS on?")
        return
    missing = sorted(k for k in found if k not in have and wordy(k))
    for key in missing:
        print(f"MISSING {json.dumps(key, ensure_ascii=False)}    ({found[key]})")
    unused = sorted(k for k in have if k not in found)
    print(f"{len(found)} lines found by the compiler, {len(missing)} without German, "
          f"{len(unused)} in de.json looked up at run time (.loc) or unused")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "build"
    if command == "build":
        build()
    elif command == "audit":
        audit(sys.argv[2:])
    elif command == "check":
        check(sys.argv[2] if len(sys.argv) > 2 else "build")
    else:
        sys.exit(__doc__)
