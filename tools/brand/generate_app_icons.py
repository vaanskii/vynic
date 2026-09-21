#!/usr/bin/env python3
"""Rasterize the Vynic Manager and Vynic Developer app marks.

Source of truth for the geometry is `tools/brand/*.svg`; the stroke tables below
mirror those files. Run this whenever a mark changes, then run
`dart run flutter_launcher_icons` in each app to fan the masters out to every
platform slot.

    python3 tools/brand/generate_app_icons.py

Writes the per-platform masters that `flutter_launcher_icons` consumes:
  apps/operations/assets/logo/manager_{app_icon,adaptive_fg}.png
  apps/devtool/assets/logo/developer_{app_icon,adaptive_fg,macos}.png

Then stages `apps/operations/branding/manager/`: the Manager icon rendered into
every native slot, which `apps/operations/tool/product.py` lays over the POS
tree for manager builds. The checked-in slots themselves stay Vynic POS.

Windows `.ico` files are written here directly as full 16–256 size sets (the
same set the POS icon ships), because flutter_launcher_icons emits one size.
Run `dart run flutter_launcher_icons` in `apps/devtool` afterwards for macOS.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[2]

# 100x100 viewBox, matching the brand sheet. (start, end, stroke width, colour)
# Manager keeps the POS icon's off-white ground and ink so the two read as one
# product; the V sits at the POS icon's exact coordinates and only the stem
# dropped from its exit terminal tells them apart.
MANAGER = {
    "name": "manager",
    "background": "#F7F6F4",
    "strokes": [
        ((22, 26), (52, 72), 19, "#111112"),
        ((52, 72), (84, 18), 11, "#111112"),
        ((84, 18), (84, 70), 11, "#111112"),
    ],
}

DEVELOPER = {
    "name": "developer",
    "background": "#1B1C22",
    "strokes": [
        ((22, 22), (52, 66), 19, "#FFFFFF"),
        ((52, 66), (84, 14), 11, "#FFFFFF"),
        ((26, 88), (74, 88), 10, "#8D73FF"),
    ],
}

# The 100-unit viewBox is centred and spans 74.2% of the tile, measured from the
# shipped POS icon (`vynic_app_icon.png`) so sibling marks line up exactly.
GLYPH_SCALE = 0.742
# Full-bleed rounded tiles (Windows, in-app) use the brand sheet's 22% radius.
TILE_RADIUS = 0.22
# macOS draws inside an 824/1024 content box with a 185/1024 corner radius.
MACOS_CONTENT = 824 / 1024
MACOS_RADIUS = 185 / 824

SUPERSAMPLE = 4
# Frame set of the checked-in POS app_icon.ico; Windows picks per context.
ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def _draw_glyph(draw: ImageDraw.ImageDraw, mark, box: float, cx: float, cy: float) -> None:
    """Draw the mark with its 100-unit viewBox spanning `box`, centred on (cx, cy)."""
    unit = box / 100
    ox = cx - 50 * unit
    oy = cy - 50 * unit

    for (sx, sy), (ex, ey), width, colour in mark["strokes"]:
        px0, py0 = ox + sx * unit, oy + sy * unit
        px1, py1 = ox + ex * unit, oy + ey * unit
        r = width * unit / 2
        draw.line((px0, py0, px1, py1), fill=colour, width=max(1, round(width * unit)))
        for px, py in ((px0, py0), (px1, py1)):
            draw.ellipse((px - r, py - r, px + r, py + r), fill=colour)


def _render(size: int, mark, *, shape: str) -> Image.Image:
    """Render one master. `shape` is square | rounded | macos | glyph."""
    s = size * SUPERSAMPLE
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    if shape == "square":
        draw.rectangle((0, 0, s, s), fill=mark["background"])
        box, cx, cy = s * GLYPH_SCALE, s / 2, s / 2
    elif shape == "rounded":
        draw.rounded_rectangle((0, 0, s - 1, s - 1), radius=s * TILE_RADIUS, fill=mark["background"])
        box, cx, cy = s * GLYPH_SCALE, s / 2, s / 2
    elif shape == "macos":
        content = s * MACOS_CONTENT
        inset = (s - content) / 2
        draw.rounded_rectangle(
            (inset, inset, s - inset - 1, s - inset - 1),
            radius=content * MACOS_RADIUS,
            fill=mark["background"],
        )
        box, cx, cy = content * GLYPH_SCALE, s / 2, s / 2
    elif shape == "glyph":
        box, cx, cy = s * GLYPH_SCALE, s / 2, s / 2
    else:
        raise ValueError(f"unknown shape {shape!r}")

    _draw_glyph(draw, mark, box, cx, cy)
    return canvas.resize((size, size), Image.LANCZOS)


def _write(image: Image.Image, path: Path, *, alpha: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not alpha:
        flat = Image.new("RGB", image.size, (255, 255, 255))
        flat.paste(image, mask=image.split()[3])
        image = flat
    image.save(path, "PNG")
    print(f"  {path.relative_to(REPO)}")


def _write_ico(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "ICO", sizes=ICO_SIZES)
    print(f"  {path.relative_to(REPO)}")


def generate(mark, out_dir: Path, *, desktop_tiles: bool) -> None:
    name = mark["name"]
    print(f"{name}:")
    # iOS and legacy Android mask the tile themselves, so ship it full-bleed and opaque.
    _write(_render(1024, mark, shape="square"), out_dir / f"{name}_app_icon.png", alpha=False)
    _write(_render(1024, mark, shape="glyph"), out_dir / f"{name}_adaptive_fg.png")
    if desktop_tiles:
        _write(_render(1024, mark, shape="macos"), out_dir / f"{name}_macos.png")


# Native icon slots harvested from flutter_launcher_icons, relative to the app
# root. The Windows .ico is written by _write_ico instead.
ICON_SLOTS = [
    "android/app/src/main/res/mipmap-*/ic_launcher.png",
    "android/app/src/main/res/drawable-*/ic_launcher_foreground.png",
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png",
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png",
]
WINDOWS_ICO = "windows/runner/resources/app_icon.ico"


def stage_manager_overlay() -> None:
    """Render the Manager icon into a scratch copy of apps/operations and keep only the slots."""
    app = REPO / "apps/operations"
    overlay = app / "branding/manager"
    print("manager overlay:")
    root = Path(tempfile.mkdtemp(prefix="vynic-brand-"))
    try:
        # Mirror the repository layout so pubspec's ../../packages paths resolve.
        work = root / "apps/operations"
        work.mkdir(parents=True)
        (root / "packages").symlink_to(REPO / "packages", target_is_directory=True)
        for name in ["android", "ios", "macos", "windows", "assets"]:
            shutil.copytree(
                app / name,
                work / name,
                ignore=shutil.ignore_patterns(".env*", "ephemeral", ".gradle", "build", "Pods", ".symlinks"),
            )
        for name in ["pubspec.yaml", "pubspec.lock", "manager_launcher_icons.yaml"]:
            shutil.copyfile(app / name, work / name)
        # `dart pub get`, not `flutter pub get`: the latter also resolves iOS/macOS
        # Swift packages into build/, which we neither need nor want to wait for.
        subprocess.run(["dart", "pub", "get"], cwd=work, check=True, capture_output=True)
        subprocess.run(
            ["dart", "run", "flutter_launcher_icons", "-f", "manager_launcher_icons.yaml"],
            cwd=work,
            check=True,
            capture_output=True,
        )
        if overlay.exists():
            shutil.rmtree(overlay)
        for pattern in ICON_SLOTS:
            for produced in sorted(work.glob(pattern)):
                relative = produced.relative_to(work)
                target = overlay / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(produced, target)
                print(f"  {target.relative_to(REPO)}")
    finally:
        shutil.rmtree(root)


if __name__ == "__main__":
    # Manager reuses the full-bleed square on every platform, exactly as POS does,
    # so the two icons match slot for slot. Developer is its own app and gets the
    # inset macOS and rounded Windows tiles.
    generate(MANAGER, REPO / "apps/operations/assets/logo", desktop_tiles=False)
    generate(DEVELOPER, REPO / "apps/devtool/assets/logo", desktop_tiles=True)
    stage_manager_overlay()
    print("windows:")
    _write_ico(_render(1024, MANAGER, shape="square"), REPO / "apps/operations/branding/manager" / WINDOWS_ICO)
    _write_ico(_render(1024, DEVELOPER, shape="rounded"), REPO / "apps/devtool" / WINDOWS_ICO)
