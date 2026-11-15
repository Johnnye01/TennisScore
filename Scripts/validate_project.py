#!/usr/bin/env python3
"""Validate project syntax, object references, source membership, plists and icons.

This structural check runs on macOS or Linux using only the Python standard
library. It does not replace xcodebuild or testing on paired Apple devices.
"""

from __future__ import annotations

import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class OpenStepParser:
    def __init__(self, text: str):
        self.text = text
        self.position = 0

    def whitespace(self):
        while self.position < len(self.text):
            if self.text[self.position].isspace():
                self.position += 1
            elif self.text.startswith("//", self.position):
                end = self.text.find("\n", self.position)
                self.position = len(self.text) if end < 0 else end + 1
            elif self.text.startswith("/*", self.position):
                end = self.text.find("*/", self.position + 2)
                assert end >= 0, "Unterminated PBX comment"
                self.position = end + 2
            else:
                return

    def take(self, expected):
        self.whitespace()
        assert self.text.startswith(expected, self.position), f"Expected {expected!r} at offset {self.position}"
        self.position += len(expected)

    def value(self):
        self.whitespace()
        char = self.text[self.position]
        if char == "{":
            self.position += 1
            values = {}
            while True:
                self.whitespace()
                if self.text[self.position] == "}":
                    self.position += 1
                    return values
                key = self.value()
                assert isinstance(key, str), "PBX dictionary key must be a string"
                assert key not in values, f"Duplicate PBX key {key}"
                self.take("=")
                values[key] = self.value()
                self.take(";")
        if char == "(":
            self.position += 1
            values = []
            while True:
                self.whitespace()
                if self.text[self.position] == ")":
                    self.position += 1
                    return values
                values.append(self.value())
                self.whitespace()
                if self.text[self.position] == ",":
                    self.position += 1
                else:
                    self.take(")")
                    return values
        if char == '"':
            value, length = json.JSONDecoder().raw_decode(self.text[self.position:])
            self.position += length
            return value
        match = re.match(r"[^\s{}()=;,]+", self.text[self.position:])
        assert match, f"Unexpected PBX token at offset {self.position}"
        token = match.group(0)
        self.position += len(token)
        return int(token) if token.isdigit() else token

    def parse(self):
        data = self.value()
        self.whitespace()
        assert self.position == len(self.text), "Trailing data after PBX project"
        return data


def main():
    pbx = ROOT / "CourtCall.xcodeproj" / "project.pbxproj"
    project = OpenStepParser(pbx.read_text(encoding="utf-8")).parse()
    objects = project["objects"]
    assert objects[project["rootObject"]]["isa"] == "PBXProject"

    def references(value):
        if isinstance(value, dict):
            for item in value.values():
                references(item)
        elif isinstance(value, list):
            for item in value:
                references(item)
        elif isinstance(value, str) and re.fullmatch(r"[0-9A-F]{24}", value):
            assert value in objects, f"Dangling project reference {value}"
    references(project)
    for item in objects.values():
        if item["isa"] == "PBXFileReference" and item["sourceTree"] == "<group>":
            assert (ROOT / item["path"]).exists(), f"Missing project file {item['path']}"

    targets = {item["name"]: (key, item) for key, item in objects.items() if item["isa"] == "PBXNativeTarget"}
    assert set(targets) == {"CourtCall", "CourtCallWatch"}, "Expected iPhone and single-target Watch apps"
    common = set()
    for folder in ("Sources/CourtCore", "Sources/CourtSession", "Apple/Shared"):
        common.update(path.relative_to(ROOT).as_posix() for path in (ROOT / folder).rglob("*.swift"))
    counts = {}
    for name, platform in (("CourtCall", "iPhone"), ("CourtCallWatch", "Watch")):
        _, target = targets[name]
        assert target["productType"] == "com.apple.product-type.application"
        actual = set()
        for phase_id in target["buildPhases"]:
            phase = objects[phase_id]
            if phase["isa"] == "PBXSourcesBuildPhase":
                actual.update(objects[objects[key]["fileRef"]]["path"] for key in phase["files"])
        expected = common | {p.relative_to(ROOT).as_posix() for p in (ROOT / "Apple" / platform).rglob("*.swift")}
        assert actual == expected, f"Source membership differs for {name}; rerun Scripts/generate_project.py. Missing: {expected - actual}; extra: {actual - expected}"
        assert actual, f"No Swift sources in {name}"
        counts[name] = len(actual)
        scheme = ET.parse(ROOT / "CourtCall.xcodeproj" / "xcshareddata" / "xcschemes" / f"{name}.xcscheme")
        assert all(ref.attrib["BlueprintIdentifier"] == targets[name][0] for ref in scheme.iter("BuildableReference"))
        settings = [objects[key]["buildSettings"] for key in objects[target["buildConfigurationList"]]["buildConfigurations"]]
        assert all(item["SDKROOT"] == ("iphoneos" if platform == "iPhone" else "watchos") for item in settings)
        assert all(item["CODE_SIGN_STYLE"] == "Automatic" for item in settings)
    phone = targets["CourtCall"][1]
    assert len(phone["dependencies"]) == 1
    assert objects[phone["dependencies"][0]]["target"] == targets["CourtCallWatch"][0]
    embeds = [objects[key] for key in phone["buildPhases"] if objects[key]["isa"] == "PBXCopyFilesBuildPhase"]
    assert len(embeds) == 1 and embeds[0]["dstPath"] == "$(CONTENTS_FOLDER_PATH)/Watch"
    assert embeds[0]["dstSubfolderSpec"] == 16

    plist_count = 0
    for path in ROOT.rglob("*.plist"):
        if ".build" in path.parts:
            continue
        with path.open("rb") as handle:
            plistlib.load(handle)
        plist_count += 1
    with (ROOT / "Apple/Watch/Info.plist").open("rb") as handle:
        watch_info = plistlib.load(handle)
    assert watch_info["WKApplication"] is True
    assert watch_info["WKRunsIndependentlyOfCompanionApp"] is True
    assert watch_info["WKCompanionAppBundleIdentifier"] == "$(COURTCALL_BUNDLE_PREFIX)"
    assert not watch_info.get("WKWatchOnly", False), "This watch app has an iPhone companion"

    icon_count = 0
    for path in ROOT.glob("Apple/*/Assets.xcassets/**/Contents.json"):
        data = json.loads(path.read_text())
        for image in data.get("images", []):
            pixels = (path.parent / image["filename"]).read_bytes()
            assert pixels[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG {image['filename']}"
            width, height, bit_depth, color_type = struct.unpack(">IIBB", pixels[16:26])
            expected_size = round(float(image["size"].split("x")[0]) * float(image["scale"][:-1]))
            assert width == height == expected_size, f"Wrong icon size {image['filename']}"
            assert bit_depth == 8 and color_type == 2, f"App icon must be opaque RGB: {image['filename']}"
            icon_count += 1
    assert icon_count >= 10
    print(f"Project structure OK: {len(objects)} PBX objects; " + "; ".join(f"{key}: {count} Swift files" for key, count in counts.items()))
    print(f"Plists, shared schemes, embedded watch identity, and {icon_count} icon declarations OK.")
    print("Apple SDK compilation and paired-device behavior require Xcode / real Apple devices.")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, ValueError, OSError) as error:
        print(f"Project validation failed: {error}", file=sys.stderr)
        sys.exit(1)
