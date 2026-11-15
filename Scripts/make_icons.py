#!/usr/bin/env python3
"""Regenerate the bundled app icons. Optional design tool; requires Pillow."""

from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
NAVY = (14, 24, 30)
LIME = (205, 242, 103)
PALE = (244, 247, 230)


def icon():
    image = Image.new("RGB", (1024, 1024), NAVY)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((235, 154, 789, 870), radius=30, outline=LIME, width=27)
    draw.line((235, 512, 789, 512), fill=LIME, width=27)
    draw.line((235, 320, 789, 320), fill=LIME, width=20)
    draw.line((235, 704, 789, 704), fill=LIME, width=20)
    draw.line((512, 320, 512, 704), fill=LIME, width=20)
    draw.ellipse((416, 170, 788, 542), fill=NAVY)
    draw.ellipse((434, 188, 770, 524), fill=LIME)
    # Two curved seams read clearly on the smallest watch launch icon.
    draw.arc((302, 207, 602, 507), -74, 74, fill=PALE, width=18)
    draw.arc((602, 207, 902, 507), 106, 254, fill=PALE, width=18)
    return image


def write_json(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(content, indent=2) + "\n", encoding="utf-8")


source = icon()
for platform in ("iPhone", "Watch"):
    assets = ROOT / "Apple" / platform / "Assets.xcassets"
    write_json(assets / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    for name, color in [("AccentColor", LIME), ("LaunchBackground", NAVY)]:
        components = {channel: f"{value / 255:.6f}" for channel, value in zip(("red", "green", "blue"), color)}
        components["alpha"] = "1.000000"
        write_json(assets / f"{name}.colorset" / "Contents.json", {
            "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": components}}],
            "info": {"author": "xcode", "version": 1},
        })
    images = []
    if platform == "iPhone":
        for size in (20, 29, 40, 60):
            for scale in (2, 3):
                pixels = size * scale
                filename = f"icon-{pixels}.png"
                images.append({"idiom": "iphone", "size": f"{size}x{size}", "scale": f"{scale}x", "filename": filename})
        images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"})
    else:
        definitions = [
            (24, 2, "notificationCenter", "38mm"), (27.5, 2, "notificationCenter", "42mm"),
            (29, 2, "companionSettings", None), (29, 3, "companionSettings", None),
            (40, 2, "appLauncher", "38mm"), (44, 2, "appLauncher", "40mm"),
            (46, 2, "appLauncher", "41mm"), (50, 2, "appLauncher", "44mm"),
            (51, 2, "appLauncher", "45mm"), (54, 2, "appLauncher", "49mm"),
            (86, 2, "quickLook", "38mm"), (98, 2, "quickLook", "42mm"),
            (108, 2, "quickLook", "44mm"), (117, 2, "quickLook", "45mm"),
            (129, 2, "quickLook", "49mm"),
        ]
        for size, scale, role, subtype in definitions:
            entry = {"idiom": "watch", "size": f"{size:g}x{size:g}", "scale": f"{scale}x", "role": role,
                     "filename": f"icon-{round(size * scale)}.png"}
            if subtype:
                entry["subtype"] = subtype
            images.append(entry)
        images.append({"idiom": "watch-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"})
    icon_dir = assets / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    for entry in images:
        pixels = round(float(entry["size"].split("x")[0]) * float(entry["scale"][:-1]))
        source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(icon_dir / entry["filename"])
    write_json(icon_dir / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})
print("Generated opaque RGB app icons for iPhone and Apple Watch.")
