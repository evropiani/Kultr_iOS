#!/usr/bin/env python3
"""
Writes the KultrPre source: an AltStore / SideStore source listing the
newest KultrPre test builds, made fresh from this repository's pre-releases
(tags like pre-v1.4.2-130 with a KultrPre.ipa) on every KultrPre build.

It has the older single-version fields (version, downloadURL, …), which
every store reads, and a `versions` list with build numbers, so stores that
read it can tell two builds of the same version apart.

Usage: pre-source.py OUTPUT.json
Environment:
  GH_TOKEN    a token that may read the repository's releases
  REPOSITORY  owner/repo
"""

import json
import os
import re
import sys
import urllib.request

BUNDLE_ID = "app.kultr.ios.pre"
MIN_OS = "26.0"
KEEP = 10


def api(url, token):
    request = urllib.request.Request(url)
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("User-Agent", "Kultr-iOS-pre-source")
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def plain_notes(text):
    """A release's notes as the stores show them: plain text, up to the Install section."""
    text = (text or "").split("## Install")[0]
    lines = []
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        line = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", line)
        line = line.replace("**", "").replace("`", "").replace("_", "")
        line = re.sub(r"^(\s*)- ", r"\1• ", line)
        lines.append(line.rstrip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def main():
    output = sys.argv[1]
    token = os.environ.get("GH_TOKEN", "")
    repository = os.environ["REPOSITORY"]
    builds = []
    for page in (1, 2):
        releases = api(f"https://api.github.com/repos/{repository}/releases?per_page=100&page={page}", token)
        for release in releases:
            match = re.fullmatch(r"pre-v(\d+(?:\.\d+)*)-(\d+)", release.get("tag_name", ""))
            ipa = next((a for a in release.get("assets", []) if a.get("name") == "KultrPre.ipa"), None)
            if not match or not ipa or release.get("draft"):
                continue
            builds.append({
                "version": match.group(1),
                "buildVersion": match.group(2),
                "date": release.get("published_at") or release.get("created_at"),
                "localizedDescription": plain_notes(release.get("body")),
                "downloadURL": ipa["browser_download_url"],
                "size": ipa["size"],
                "minOSVersion": MIN_OS,
            })
        if len(releases) < 100:
            break
    if not builds:
        print("No KultrPre builds found among the releases.", file=sys.stderr)
        return 1
    builds.sort(key=lambda b: int(b["buildVersion"]), reverse=True)
    builds = builds[:KEEP]
    newest = builds[0]

    raw = f"https://raw.githubusercontent.com/{repository}/main"
    with open(".github/source/kultr.json", encoding="utf-8") as f:
        details = json.load(f)
    app = {
        "name": "Kultr Pre",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": repository.split("/")[0],
        "subtitle": "Test builds of Kultr, next to the real one.",
        "localizedDescription": (
            "Kultr Pre is the test build of Kultr: new features arrive here first. It installs next to Kultr "
            "as its own app, with its own bundle ID, App Group and data, so your Kultr stays as it is.\n\n"
            + details.get("localizedDescription", "")
        ),
        "iconURL": details.get("iconURL", f"{raw}/docs/icon.png"),
        "tintColor": details.get("tintColor", "#C2410C"),
        "category": "entertainment",
        "screenshots": details.get("screenshots", []),
        "screenshotURLs": details.get("screenshotURLs", []),
        # The single newest build, for stores that read only these.
        "version": newest["version"],
        "versionDate": newest["date"],
        "versionDescription": newest["localizedDescription"],
        "downloadURL": newest["downloadURL"],
        "size": newest["size"],
        "versions": builds,
    }
    source = {
        "name": "Kultr Pre",
        "identifier": "app.kultr.ios.pre.source",
        "subtitle": "Test builds of Kultr for iOS.",
        "description": "The newest KultrPre test builds, updated with every build.",
        "iconURL": app["iconURL"],
        "website": f"https://github.com/{repository}",
        "tintColor": app["tintColor"],
        "apps": [app],
        "news": [],
    }
    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    with open(output, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"KultrPre source: {len(builds)} builds, newest {newest['version']} ({newest['buildVersion']}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
