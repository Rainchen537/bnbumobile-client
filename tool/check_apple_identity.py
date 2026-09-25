#!/usr/bin/env python3
"""Validate Apple naming and purpose without printing local signing identities."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def read_config(path):
    values = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*", line)
        if match:
            values[match[1]] = match[2]
    for _ in range(8):
        values = {
            key: re.sub(r"\$\(([A-Z0-9_]+)\)",
                        lambda m: values.get(m[1], m[0]), value)
            for key, value in values.items()
        }
    return values


def validate(values, platform, configuration, distribution_only=False):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    development = configuration != "Release"
    purpose = values.get("BNBU_APPLE_IDENTITY_PURPOSE", "")
    prefix = values.get("BNBU_APPLE_DEVELOPER_PREFIX", "")
    allowed = {"development"} if development else {"local-acceptance", "distribution"}
    require(purpose in allowed, "Identity purpose does not match the build lane.")
    require(not distribution_only or purpose == "distribution",
            "Personal acceptance identities cannot create distribution artifacts.")
    require(values.get("BNBU_APPLE_IDENTITY_CONFIGURED") == "YES",
            "Apple identity is not configured.")
    if purpose == "distribution":
        require(not prefix, "Distribution identities must not have a personal prefix.")
    else:
        require(bool(re.fullmatch(r"[a-z][a-z0-9-]{0,62}", prefix)) and
                not prefix.endswith("-") and prefix != "yourname",
                "A developer-owned lowercase prefix is required.")
    base = (prefix + "." if prefix else "") + "me.bnbu.app"
    if platform == "macos":
        base += ".macos"
    if development:
        base += ".debug"
    if platform == "ios":
        lane = "DEVELOPMENT" if development else "RELEASE"
        key = "BNBU_IOS_" + lane
        team = values.get(key + "_TEAM", "")
        expected = {
            key + "_BUNDLE_IDENTIFIER": base,
            key + "_WIDGET_BUNDLE_IDENTIFIER": base + ".widgets",
            key + "_WATCH_BUNDLE_IDENTIFIER": base + ".watchkitapp",
            key + "_APP_GROUP_IDENTIFIER": "group." + base,
        }
    else:
        team = values.get("BNBU_MACOS_TEAM_IDENTIFIER", "")
        expected = {
            "BNBU_MACOS_APP_BUNDLE_IDENTIFIER": base,
            "BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER": base + ".widgets",
            "BNBU_MACOS_APP_GROUP_IDENTIFIER": team + "." + base,
        }
    require(bool(re.fullmatch(r"[A-Z0-9]{10}", team)) and team != "YOURTEAMID",
            "A valid team configuration is required.")
    for key, expected_value in expected.items():
        require(values.get(key) == expected_value,
                key + " does not match the declared naming policy.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["ios", "macos"], required=True)
    parser.add_argument("--configuration", choices=["Debug", "Profile", "Release"], required=True)
    parser.add_argument("--distribution-only", action="store_true")
    parser.add_argument("--xcode", action="store_true")
    args = parser.parse_args()
    if args.xcode and not args.distribution_only and (
        os.environ.get("CODE_SIGNING_ALLOWED") == "NO"
        or os.environ.get("PLATFORM_NAME", "").endswith("simulator")
    ):
        print("Unsigned/simulator compilation: signing identity check skipped.")
        return 0
    root = Path(__file__).resolve().parent.parent
    name = "Signing.release.local.xcconfig" if args.configuration == "Release" else "Signing.local.xcconfig"
    path = Path(args.platform, "Flutter", name)
    ignored = subprocess.run(["git", "check-ignore", "-q", str(path)], cwd=root).returncode == 0
    tracked = subprocess.run(["git", "ls-files", "--error-unmatch", str(path)], cwd=root,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    try:
        if not ignored or tracked:
            raise ValueError("Real Apple configuration must be ignored and untracked.")
        values = dict(os.environ) if args.xcode else read_config(root / path)
        validate(values, args.platform, args.configuration, args.distribution_only)
    except (ValueError, OSError):
        # Config values and filesystem paths may identify a developer. Do not echo them.
        print("Apple identity validation failed: check local purpose, prefix, team and target IDs.", file=sys.stderr)
        return 1
    print("Apple identity naming and purpose validated; signing materials not verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
