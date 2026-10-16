#!/usr/bin/env python3
"""Compose tablet store banners from actual Flutter captures. Requires Pillow.

Run flutter test tool/capture_tablet_test.dart first, then this script.
The app pixels are preserved at their original aspect ratio; only the tablet
border, typography and background are composed here. All account data is fictional.
"""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'build/tablet-captures'
OUTPUT = ROOT / 'build/tablet-promos'
SIZE = (2560, 1600)
CREAM = '#f3ecd6'
GOLD = '#d8bd7b'


def font(size, weight='SemiBold'):
    return ImageFont.truetype(str(ROOT / f'assets/fonts/Inter-{weight}.ttf'), size)


def compose(name, capture, eyebrow, title, subtitle):
    canvas = Image.new('RGB', SIZE, '#0c201d')
    draw = ImageDraw.Draw(canvas)
    # Quiet concentric lines echo the rounded device and timer dial.
    for radius in (660, 840, 1020):
        draw.ellipse((2200-radius, 1350-radius, 2200+radius, 1350+radius),
                     outline='#1d3730', width=2)
    draw.text((150, 90), 'FOCUSFORGE', font=font(30), fill=CREAM)
    draw.line((150, 144, 2410, 144), fill='#30483d', width=2)
    draw.text((150, 195), eyebrow, font=font(33), fill=GOLD)
    draw.text((150, 247), title, font=font(102, 'Bold'), fill=CREAM)
    draw.text((155, 381), subtitle, font=font(31, 'Regular'), fill='#c2cfc2')

    # Landscape tablet: exact 16:10 content, neutral hardware with thin bezel.
    screen_size = (1592, 995)
    screen_origin = (484, 510)
    frame_box = (452, 478, 2108, 1537)
    shadow = Image.new('RGBA', SIZE)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (452, 500, 2108, 1559), radius=58, fill=(0, 0, 0, 150))
    canvas = Image.alpha_composite(canvas.convert('RGBA'), shadow.filter(ImageFilter.GaussianBlur(22)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(frame_box, radius=58, fill='#101516', outline='#7c827b', width=3)
    draw.rounded_rectangle((461, 487, 2099, 1528), radius=51, outline='#303a36', width=2)
    draw.ellipse((1268, 489, 1276, 497), fill='#42534b')
    source = SOURCE / capture
    with Image.open(source) as image:
        assert image.width * screen_size[1] == image.height * screen_size[0], 'Capture would be stretched'
        content = image.convert('RGB').resize(screen_size, Image.Resampling.LANCZOS)
    mask = Image.new('L', screen_size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_size[0], screen_size[1]), radius=27, fill=255)
    canvas.paste(content, screen_origin, mask)
    path = OUTPUT / f'{name}.png'
    canvas.convert('RGB').save(path, optimize=True)
    return {'file': path.name, 'pixels': list(SIZE), 'source': capture,
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    specs = [
        ('01-home', 'dashboard-dark.png', 'MAKE ROOM.', 'For focus.', 'Your goals, subjects and progress. One clear view.'),
        ('02-shield', 'shield-dark.png', 'LESS SCROLL.', 'More control.', 'Choose the apps that can wait.'),
        ('03-youtube', 'youtube-dark.png', 'KEEP THE LESSON.', 'Skip the feed.', 'Close Shorts and feeds. Make space for what matters.'),
        ('04-focus', 'focus-dark.png', 'ONE SUBJECT.', 'Your full attention.', 'A focused timer. An ambient mix. Room to think.'),
    ]
    manifest = [compose(*spec) for spec in specs]
    (OUTPUT / 'provenance.json').write_text(json.dumps(manifest, indent=2))
    (OUTPUT / 'README.txt').write_text(
        'FocusForge tablet store banners: 2560 x 1600 PNG.\n'
        'Actual current Flutter UI captured at 1280 x 800 with fictional local data.\n'
        'App screenshots retain their aspect ratio; tablet frame and typography are composited.\n'
        'Reproduce: flutter test tool/capture_tablet_test.dart; python3 tool/compose_tablet_promos.py\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
