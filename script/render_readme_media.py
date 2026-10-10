#!/usr/bin/env python3
"""Render documentation illustrations from the Swift router's exported paths."""
import colorsys
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/media"
BG = "#11151b"
TEXT = "#eef2f8"
MUTED = "#919cab"
ACCENT = "#68d4e3"


def font(size, bold=False):
    names = ["/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/SFNS.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for name in names:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default(size=size)


def centre(draw, text, xy, typeface, fill=TEXT):
    box = draw.textbbox((0, 0), text, font=typeface)
    draw.text((xy[0] - (box[2] - box[0]) / 2, xy[1]), text, font=typeface, fill=fill)


def circle(draw, xy, radius, **kwargs):
    x, y = xy
    draw.ellipse((x-radius, y-radius, x+radius, y+radius), **kwargs)


def wire(draw, points, fill=ACCENT, width=2, radius=5):
    # Sample the same trimmed quadratic corners used by the AppKit renderer.
    rounded = [points[0]]
    for index in range(1, len(points)):
        corner = points[index]
        if index == len(points)-1:
            rounded.append(corner)
            continue
        before, after = points[index-1], points[index+1]
        incoming = ((corner[0]-before[0])**2 + (corner[1]-before[1])**2)**0.5
        outgoing = ((after[0]-corner[0])**2 + (after[1]-corner[1])**2)**0.5
        if min(incoming, outgoing) < 0.001:
            rounded.append(corner)
            continue
        trim = min(radius, incoming/2, outgoing/2)
        a = tuple(corner[j] + (before[j]-corner[j])*trim/incoming for j in range(2))
        b = tuple(corner[j] + (after[j]-corner[j])*trim/outgoing for j in range(2))
        rounded.append(a)
        for step in range(1, 9):
            t = step/8
            rounded.append(tuple((1-t)**2*a[j] + 2*(1-t)*t*corner[j] + t*t*b[j] for j in range(2)))
    draw.line(rounded, fill=fill, width=width, joint="curve")


def walkthrough_frame(frame):
    image = Image.new("RGB", (900, 600), BG)
    d = ImageDraw.Draw(image)
    d.text((34, 27), frame["title"], font=font(27, True), fill=TEXT)
    d.text((34, 67), frame["subtitle"], font=font(17), fill=MUTED)
    d.rounded_rectangle((34, 112, 866, 549), 18, fill="#191f28", outline="#333c49", width=1)
    centres = [(-175, 110), (175, 110), (-175, -110), (175, -110)]
    names = ["ICE", "SUGAR", "GLASS", "LEMON"]
    colours = ["#4bb4ca", "#ce6fa3", "#a98ad8", "#d2b55b"]
    def point(p):
        return (450+p[0], 331-p[1])
    for index, location in enumerate(centres):
        x, y = point(location)
        d.rounded_rectangle((x-110, y-66, x+110, y+66), 14, fill="#222c39", outline=colours[index], width=2)
        centre(d, names[index], (x, y-43), font(12, True), colours[index])
        centre(d, str(frame["counts"][index]), (x, y-17), font(38))
        centre(d, "clicks", (x, y+33), font(12), MUTED)
    for route in frame["routes"]:
        wire(d, [point(p) for p in route["points"]], "#5b9fae", 2, route["cornerRadius"])
    for location in frame["spots"]:
        xy = point(location)
        circle(d, xy, 7, outline="#edf5fb", width=2)
        circle(d, xy, 1.5, fill="#edf5fb")
    trigger = point(frame["trigger"])
    circle(d, trigger, 27, fill="#253543", outline="#78c9d7", width=2)
    # An icon-only trigger and a separate pointer show the gesture.
    x, y = trigger
    d.polygon([(x-5, y-9), (x-5, y+9), (x, y+5), (x+5, y+13), (x+8, y+11), (x+3, y+3), (x+11, y+3)], fill=TEXT)
    for a, b in [((x-14, y-9), (x-18, y-12)), ((x-8, y-16), (x-10, y-21)), ((x+1, y-16), (x+2, y-21))]:
        d.line([a, b], fill=TEXT, width=2)
    if "cursor" in frame:
        x, y = point(frame["cursor"])
        x += 5
        y += 5
        d.polygon([(x, y), (x, y+22), (x+5, y+16), (x+11, y+27), (x+15, y+25), (x+9, y+14), (x+18, y+14)],
                  fill="#f6f8fc", outline="#0e1219", width=2)
    centre(d, "Illustrated walkthrough · both modifiers can be rebound in Settings", (450, 568), font(14), MUTED)
    return image


def stress_panel(case, heading):
    image = Image.new("RGB", (560, 390), BG)
    d = ImageDraw.Draw(image)
    d.text((20, 15), heading, font=font(21, True), fill=TEXT)
    d.text((20, 45), f"{case['name']} · {len(case['spots'])} spots · {case['crossings']} crossings", font=font(14), fill=MUTED)
    points = [(0, 0)] + [tuple(s["position"]) for s in case["spots"]]
    points += [tuple(p) for route in case["routes"] for p in route["points"]]
    left, right = min(p[0] for p in points)-30, max(p[0] for p in points)+30
    bottom, top = min(p[1] for p in points)-30, max(p[1] for p in points)+30
    scale = min(500/(right-left), 285/(top-bottom))
    def point(p):
        return (280+(p[0]-(left+right)/2)*scale, 230-(p[1]-(top+bottom)/2)*scale)
    for index, route in enumerate(case["routes"]):
        colour = tuple(round(c*255) for c in colorsys.hsv_to_rgb(index/max(1, len(case["routes"])), 0.45, 0.85))
        wire(d, [point(p) for p in route["points"]], colour, 2, route.get("cornerRadius", 5)*scale)
    for spot in case["spots"]:
        circle(d, point(spot["position"]), max(2.5, 6*scale), outline="#e1e7f0", width=1)
    circle(d, point((0, 0)), 25*scale, fill="#253543", outline=ACCENT, width=2)
    return image


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    frames = json.loads((ROOT / "test-results/demo-routing.json").read_text())
    images = [walkthrough_frame(frame).quantize(colors=128) for frame in frames]
    images[0].save(OUT / "how-it-works.gif", save_all=True, append_images=images[1:], duration=85, loop=0, optimize=True, disposal=2)
    overview = next(frame for frame in frames if frame["title"] == "One click. All four buttons." and frame["counts"] == [1, 1, 1, 1])
    walkthrough_frame(overview).save(OUT / "overview.png", optimize=True)
    before = json.loads((OUT / "routing-baseline.json").read_text())
    after = json.loads((ROOT / "test-results/routing-after.json").read_text())
    selection = [0, 2, 3, 4]
    grid = Image.new("RGB", (1120, 390*len(selection)), "#26303b")
    for row, index in enumerate(selection):
        grid.paste(stress_panel(before[index], "Before"), (0, row*390))
        grid.paste(stress_panel(after[index], "After"), (560, row*390))
    grid.save(OUT / "routing-stress.png", optimize=True)
    print("Rendered overview, animated walkthrough, and routing comparison.")


if __name__ == "__main__":
    main()
