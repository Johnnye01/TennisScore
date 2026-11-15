#!/usr/bin/env python3
"""Set a unique application identifier and optional Xcode Team ID locally."""

import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--bundle-prefix", required=True, help="For example com.yourname.courtcall")
parser.add_argument("--team", default="", help="Optional 10-character Apple Team ID; can also be selected in Xcode")
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_prefix):
    parser.error("Bundle prefix must use reverse-domain form, with letters, digits, dots, and hyphens only.")
if args.team and not re.fullmatch(r"[A-Za-z0-9]{10}", args.team):
    parser.error("An Apple Team ID has 10 letters/digits.")
destination = Path(__file__).resolve().parents[1] / "Config" / "Personal.xcconfig"
destination.parent.mkdir(exist_ok=True)
destination.write_text(
    "// Local signing configuration. This file contains no password or signing private key.\n"
    f"COURTCALL_BUNDLE_PREFIX = {args.bundle_prefix}\n"
    f"DEVELOPMENT_TEAM = {args.team}\n",
    encoding="utf-8",
)
print(f"Updated {destination.relative_to(destination.parents[1])}")
print(f"iPhone: {args.bundle_prefix}")
print(f"Watch:  {args.bundle_prefix}.watchkitapp")
print("Select the same Personal Team for both targets in Xcode if --team was omitted.")
