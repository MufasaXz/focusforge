#!/usr/bin/env python3
"""Frame actual Flutter captures for the GitHub README. Requires Pillow.

Run after `flutter test tool/capture_readme_test.dart`. The screenshot pixels
come from build/readme-captures; this script adds only a neutral phone border.
"""

from pathlib import Path
from shutil import copyfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "build/readme-captures"
OUTPUT = ROOT / "docs/screenshots"
SIZE = (680, 1416)
SCREEN = (22, 20, 658, 1396)
SCALE = 4


def silhouette():
    canvas = Image.new("RGBA", (SIZE[0] * SCALE, SIZE[1] * SCALE))
    draw = ImageDraw.Draw(canvas)

    def rect(box, radius, fill, outline=None, width=1):
        draw.rounded_rectangle(
            tuple(value * SCALE for value in box),
            radius=radius * SCALE,
            fill=fill,
            outline=outline,
            width=width * SCALE,
        )

    rect((667, 244, 672, 342), 2, "#7e848b")
    rect((667, 366, 672, 437), 2, "#7e848b")
    rect((8, 271, 13, 325), 2, "#7e848b")
    rect((10, 8, 670, 1408), 62, "#16191d", "#90969d", 2)
    rect((15, 13, 665, 1403), 57, "#0c0e11", "#3e444a", 1)
    return canvas.resize(SIZE, Image.Resampling.LANCZOS)


FRAME = silhouette()
MASK = Image.new("L", (SIZE[0] * SCALE, SIZE[1] * SCALE))
ImageDraw.Draw(MASK).rounded_rectangle(
    tuple(value * SCALE for value in SCREEN), radius=47 * SCALE, fill=255
)
MASK = MASK.resize(SIZE, Image.Resampling.LANCZOS)


def framed(source):
    with Image.open(source) as image:
        image = image.convert("RGBA").resize(
            (SCREEN[2] - SCREEN[0], SCREEN[3] - SCREEN[1]),
            Image.Resampling.LANCZOS,
        )
    content = Image.new("RGBA", SIZE)
    content.paste(image, SCREEN[:2])
    content.putalpha(MASK)
    return Image.alpha_composite(FRAME, content)


def main():
    source_directory = OUTPUT / "source"
    source_directory.mkdir(parents=True, exist_ok=True)
    for theme, directory in (("light", OUTPUT), ("dark", OUTPUT / "dark")):
        directory.mkdir(parents=True, exist_ok=True)
        gallery = Image.new("RGBA", (2620, 1340))
        labels = ImageDraw.Draw(gallery)
        font = ImageFont.truetype(str(ROOT / "assets/fonts/Inter-SemiBold.ttf"), 38)
        for name in ("01-dashboard", "02-shield", "03-focus", "04-you"):
            capture = CAPTURES / theme / f"{name}.png"
            screen_name = "profile" if name == "04-you" else name[3:]
            copyfile(capture, source_directory / f"{screen_name}-{theme}.png")
            result = framed(capture)
            result.save(directory / f"{name}.png", optimize=True)
            index = int(name[:2]) - 1
            gallery.alpha_composite(
                result.resize((600, 1249), Image.Resampling.LANCZOS),
                (40 + index * 650, 0),
            )
            label = ("HOME", "SHIELD", "FOCUS", "YOU")[index]
            labels.rounded_rectangle(
                (240 + index * 650, 1260, 440 + index * 650, 1330),
                radius=24,
                fill="#202428" if theme == "dark" else "#f3f0e9",
            )
            labels.text(
                (340 + index * 650, 1295),
                label,
                font=font,
                fill="#ece8df" if theme == "dark" else "#514c45",
                anchor="mm",
            )
        gallery.save(
            OUTPUT / ("gallery-day.png" if theme == "light" else "gallery-dark.png"),
            optimize=True,
        )

    # Keep an accessible still first. The animation captures the app's actual
    # press/release transition; it does not accelerate the running countdown.
    frames = [
        framed(path).resize((340, 708), Image.Resampling.LANCZOS)
        for path in sorted((CAPTURES / "focus-frames").glob("*.png"))
    ]
    if not frames:
        raise ValueError("No focus motion frames: run the Flutter capture first.")
    # GIF only supports binary transparency. A shared palette prevents color
    # flicker when a small button is the only changing part of the app.
    sheet = Image.new("RGB", (340 * len(frames), 708), "#0c0e11")
    for index, frame in enumerate(frames):
        background = Image.new("RGB", frame.size, "#0c0e11")
        background.paste(frame.convert("RGB"), mask=frame.getchannel("A"))
        sheet.paste(background, (340 * index, 0))
    palette = sheet.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    gif_frames = []
    for frame in frames:
        background = Image.new("RGB", frame.size, "#0c0e11")
        background.paste(frame.convert("RGB"), mask=frame.getchannel("A"))
        result = background.quantize(palette=palette, dither=Image.Dither.NONE)
        alpha = frame.getchannel("A").point(lambda value: 255 if value < 128 else 0)
        result.paste(255, mask=alpha)
        gif_frames.append(result)
    durations = [80] * len(gif_frames)
    durations[0] = 800
    durations[-1] = 1600
    gif_frames[0].save(
        OUTPUT / "03-focus.gif",
        save_all=True,
        append_images=gif_frames[1:],
        duration=durations,
        loop=0,
        transparency=255,
        disposal=2,
        optimize=False,
    )
    print("Created eight framed captures, two theme galleries and the real Focus motion GIF.")


if __name__ == "__main__":
    main()
