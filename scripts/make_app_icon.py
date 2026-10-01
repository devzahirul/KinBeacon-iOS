"""Renders the 1024x1024 App Store icon (opaque RGB, as App Store Connect requires). Run: make icon"""
import sys
from PIL import Image, ImageDraw, ImageFilter

SS = 2                      # supersampling for anti-aliased edges
S = 1024 * SS
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"


def bezier(p0, p1, p2, p3, steps=60):
    return [
        (
            (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t ** 2 * p2[0] + t ** 3 * p3[0],
            (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t ** 2 * p2[1] + t ** 3 * p3[1],
        )
        for t in (i / steps for i in range(steps + 1))
    ]


def mask(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


# Background: diagonal indigo gradient
img = Image.new("RGB", (S, S))
top, bottom = (118, 100, 255), (55, 42, 190)
grad = Image.linear_gradient("L").resize((S, S))
img = Image.composite(Image.new("RGB", (S, S), bottom), Image.new("RGB", (S, S), top), grad)

cx, cy = S // 2, int(S * 0.5)
# Beacon rings
for r, alpha in [(int(S * 0.43), 50), (int(S * 0.35), 70)]:
    ring = mask(lambda d, r=r: d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=int(S * 0.022)))
    img.paste((255, 255, 255), mask=ring.point(lambda v, a=alpha: v * a // 255))

# Shield outline (classic heater shield)
w, h = int(S * 0.5), int(S * 0.58)
x0, x1 = cx - w // 2, cx + w // 2
yt = cy - int(h * 0.5)
yb = yt + h
outline = []
outline += bezier((x0, yt + h * 0.12), (cx - w * 0.2, yt + h * 0.1), (cx - w * 0.1, yt), (cx, yt - h * 0.02))
outline += bezier((cx, yt - h * 0.02), (cx + w * 0.1, yt), (cx + w * 0.2, yt + h * 0.1), (x1, yt + h * 0.12))
outline += bezier((x1, yt + h * 0.12), (x1, yt + h * 0.55), (cx + w * 0.3, yt + h * 0.85), (cx, yb))
outline += bezier((cx, yb), (cx - w * 0.3, yt + h * 0.85), (x0, yt + h * 0.55), (x0, yt + h * 0.12))
shield = mask(lambda d: d.polygon(outline, fill=255))
shadow = shield.filter(ImageFilter.GaussianBlur(30 * SS)).point(lambda v: v * 0.45)
img.paste((30, 20, 120), (0, int(S * 0.015)), mask=shadow)
img.paste((255, 255, 255), mask=shield)

# Location pin inside the shield
pr = int(w * 0.24)
pcx, pcy = cx, yt + int(h * 0.42)
pin_outline = [(pcx, pcy + int(pr * 2.05))]
pin_outline += bezier((pcx, pcy + pr * 2.05), (pcx - pr * 0.6, pcy + pr * 1.2), (pcx - pr * 1.1, pcy + pr * 0.6), (pcx - pr, pcy))
pin_outline += bezier((pcx - pr, pcy), (pcx - pr, pcy - pr * 1.35), (pcx + pr, pcy - pr * 1.35), (pcx + pr, pcy))
pin_outline += bezier((pcx + pr, pcy), (pcx + pr * 1.1, pcy + pr * 0.6), (pcx + pr * 0.6, pcy + pr * 1.2), (pcx, pcy + pr * 2.05))
pin = mask(lambda d: d.polygon(pin_outline, fill=255))
img.paste((88, 72, 236), mask=pin)
dr = int(pr * 0.42)
img.paste((255, 255, 255), mask=mask(lambda d: d.ellipse([pcx - dr, pcy - dr, pcx + dr, pcy + dr], fill=255)))

img.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(out)
print("wrote", out)
