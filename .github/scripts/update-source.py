#!/usr/bin/env python3
"""
Puts a new release into the AltStore / SideStore source kept in a GitHub gist.

Run by the iOS workflow after a release is published. It finds Kultr in the
gist's JSON file (by bundle identifier, or by name), adds the new version at
the top of its `versions` list, and updates the older single-version fields
(`version`, `downloadURL`, …) if the source still has them. Everything else in
the file is left as it is.

Environment:
  GIST_TOKEN   a token that may edit the gist (classic token, "gist" scope)
  GIST_ID      the gist's id (the last part of its address)
  VERSION      e.g. 1.1.5
  BUILD        the build number
  NOTES_FILE   the release notes (Markdown); the part before "## Install" is used
  IPA          path to the built Kultr.ipa, for its size
  REPOSITORY   owner/repo, for the download address
"""

import datetime
import json
import os
import re
import sys
import urllib.request

BUNDLE_ID = "app.kultr.ios"
MIN_OS = "17.0"


def api(method, url, token, body=None):
    request = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body).encode())
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("User-Agent", "Kultr-iOS-release")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def plain_notes(path):
    """The release notes as AltStore shows them: plain text, up to the Install section."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return ""
    text = text.split("## Install")[0]
    lines = []
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)  # links → their text
        line = line.replace("**", "").replace("`", "")
        line = re.sub(r"^- ", "• ", line)
        lines.append(line.rstrip())
    return "\n".join(lines).strip()


def is_kultr(app):
    bundle = str(app.get("bundleIdentifier", ""))
    return bundle == BUNDLE_ID or bundle.startswith(BUNDLE_ID + ".") or str(app.get("name", "")).strip().lower() == "kultr"


def update_source(source, entry):
    """Adds the release to every Kultr app in the source. Returns how many were updated."""
    count = 0
    for app in source.get("apps", []):
        if not is_kultr(app):
            continue
        count += 1
        versions = [v for v in app.get("versions", []) if v.get("version") != entry["version"]]
        app["versions"] = [entry] + versions
        # Older sources describe a single version on the app itself.
        legacy = {
            "version": entry["version"],
            "versionDate": entry["date"],
            "versionDescription": entry["localizedDescription"],
            "downloadURL": entry["downloadURL"],
            "size": entry["size"],
        }
        for key, value in legacy.items():
            if key in app:
                app[key] = value
    return count


def indent_of(text):
    match = re.search(r'\n( +)"', text)
    return len(match.group(1)) if match else 2


def main():
    token = os.environ.get("GIST_TOKEN", "")
    gist_id = os.environ.get("GIST_ID", "").strip().rstrip("/").split("/")[-1]
    if not token or not gist_id:
        print("No GIST_TOKEN secret or gist id set up; the source gist is not updated.")
        return 0

    version = os.environ["VERSION"]
    repository = os.environ["REPOSITORY"]
    entry = {
        "version": version,
        "buildVersion": os.environ.get("BUILD", ""),
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": plain_notes(os.environ.get("NOTES_FILE", "")),
        "downloadURL": f"https://github.com/{repository}/releases/download/v{version}/Kultr.ipa",
        "size": os.path.getsize(os.environ["IPA"]),
        "minOSVersion": MIN_OS,
    }

    gist = api("GET", f"https://api.github.com/gists/{gist_id}", token)
    changed = {}
    for name, file in gist.get("files", {}).items():
        content = file.get("content") or ""
        if file.get("truncated") and file.get("raw_url"):
            with urllib.request.urlopen(file["raw_url"]) as response:
                content = response.read().decode("utf-8")
        try:
            source = json.loads(content)
        except ValueError:
            continue
        if not isinstance(source, dict) or not update_source(source, entry):
            continue
        text = json.dumps(source, indent=indent_of(content), ensure_ascii=False)
        if content.endswith("\n"):
            text += "\n"
        if text != content:
            changed[name] = {"content": text}

    if not changed:
        print("Found no source file with Kultr in the gist, or it was already up to date.", file=sys.stderr)
        return 1
    api("PATCH", f"https://api.github.com/gists/{gist_id}", token, {"files": changed})
    print(f"Updated {', '.join(changed)} in gist {gist_id} to Kultr {version}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
