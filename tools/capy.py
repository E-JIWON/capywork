"""Pixel-art source for the capybara poses (26×15 grid).
Run `python3 tools/capy.py` → groups.json; the frames are pasted into Sources/CapyKit/Sprites.swift."""
W, H = 26, 15   # extra headroom for the yuzu, extra width for the rolling one
OY = 3          # everything drawn 3 rows down so the yuzu fits on top

def ell(cx, cy, rx, ry):
    return {(x, y) for x in range(W) for y in range(-3, H) if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1}

def head(dx=0, dy=0, jaw=0):
    rows = {1: (11, 18), 2: (10, 20), 3: (10, 21), 4: (10, 21), 5: (10, 21), 6: (11, 21 - jaw), 7: (12, 20 - jaw)}
    return {(x + dx, y + dy) for y, (a, b) in rows.items() for x in range(a, b + 1)}

def blk(x0, x1, y0, y1): return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}

def yuzu(cx, top):  # 5-wide orange with a leaf
    return {"o": [(cx - 1, top), (cx, top), (cx + 1, top), (cx - 2, top + 1), (cx - 1, top + 1), (cx, top + 1),
                  (cx + 1, top + 1), (cx + 2, top + 1), (cx - 1, top + 2), (cx, top + 2), (cx + 1, top + 2)],
            "l": [(cx, top - 1), (cx + 1, top - 2)]}

def render(shape, marks):
    g = [["."] * W for _ in range(H)]
    shape = {(x, y + OY) for x, y in shape if 0 <= x < W and 0 <= y + OY < H}
    for x, y in shape: g[y][x] = "#"
    for x, y in shape:
        if any((x + a, y + b) not in shape for a, b in [(1, 0), (-1, 0), (0, 1), (0, -1)]): g[y][x] = "d"
    for c, pts in marks:
        for x, y in pts:
            if 0 <= x < W and 0 <= y + OY < H: g[y + OY][x] = c
    return g

def capy(legs, dy=0, jaw=0, extra=(), hat=True, eye="x"):
    body = ell(7.5, 7.2 + dy, 7, 3.9)
    marks = [("d", [(11, 0 + dy), (12, 0 + dy)]), (eye, [(15, 3 + dy)]), ("x", [(21, 3 + dy)])]
    if hat:
        y = yuzu(15, -2 + dy); marks += [("o", y["o"]), ("l", y["l"])]
    return render(body | head(0, dy, jaw) | legs, marks + list(extra))

L1 = blk(3, 4, 10, 11) | blk(10, 11, 10, 11)
L2 = blk(2, 3, 11, 11) | blk(11, 12, 11, 11)   # squat: body dips, legs splay
groups = {}
groups["① 헤엄치기"] = []
for i in range(3):
    body = ell(8.5, 9.5, 7, 3.6)
    marks = [("d", [(11, 3), (12, 3)]), ("x", [(15, 6), (21, 6)])]
    y = yuzu(15, 1 + (i == 1)); marks += [("o", y["o"]), ("l", y["l"])]   # yuzu bobs
    g = render(body | head(0, 3), marks)
    for x in range(W):
        top = 9 + OY + ((x + i * 2) // 2) % 2
        for yy in range(top, H): g[yy][x] = "w" if yy == top else "."
    groups["① 헤엄치기"].append(g)
groups["② 걷기"] = [capy(L1), capy(L2, dy=1)]
grass = [("g", [(22, 6), (23, 5), (24, 4), (25, 3), (23, 7), (24, 7), (25, 8)])]
grass2 = [("g", [(21, 6), (22, 5), (23, 4), (22, 7), (23, 8)])]
groups["③ 풀 오물오물"] = [capy(L1, extra=grass), capy(L1, jaw=1, extra=grass2)]
def ball(cx, cy, leaf):
    pts = [(cx + a, cy + b) for a in range(-1, 2) for b in range(-1, 2)] + [(cx, cy - 2), (cx, cy + 2), (cx - 2, cy), (cx + 2, cy)]
    return [("O", pts), ("h", [(cx - 1, cy - 1)]), ("l", [leaf])]
# leaf travels top → right → bottom so the yuzu reads as rolling
groups["④ 귤 굴리기"] = [capy(L1, hat=False, extra=ball(23, 8, (23, 6))),
                       capy(L1, hat=False, extra=ball(23, 8, (25, 8))),
                       capy(L1, hat=False, extra=ball(23, 8, (23, 10)))]
# Flailing: sinking head, splashes flying (repeated tool failures)
groups["허우적"] = []
for i in range(2):
    body = ell(8.5, 10 + i * 0.5, 7, 3.6)
    marks = [("d", [(11, 4 - i), (12, 4 - i)]), ("x", [(15, 7 - i), (21, 7 - i)])]
    y = yuzu(17 if i else 13, 1); marks += [("o", y["o"]), ("l", y["l"])]          # yuzu sliding around
    g = render(body | head(0, 4 - i), marks)
    for x in range(W):
        top = 9 + OY + ((x + i) // 2) % 2
        for yy in range(top, H): g[yy][x] = "w" if yy == top else "."
    drops = [(2, 7), (4, 5), (23, 6), (25, 4)] if i == 0 else [(3, 5), (5, 7), (22, 4), (24, 6)]
    for x, yy in drops: g[yy + OY][x] = "w"
    groups["허우적"].append(g)
# Clock-out: hop and fling the yuzu up and away, with sparkles
groups["퇴근"] = []
for i, (cx, top, dy) in enumerate([(15, -2, 0), (17, -3, -1), (20, -3, -1), (23, -1, 0)]):
    marks = [(k, v) for k, v in yuzu(cx, top).items()]
    if i >= 2: marks.append(("s", [(cx - 3, top), (cx + 3, top + 3), (cx - 2, top + 4)]))
    legs = L1 if dy == 0 else blk(3, 4, 9, 10) | blk(10, 11, 9, 10)
    body = ell(7.5, 7.2 + dy, 7, 3.9)
    groups["퇴근"].append(render(body | head(0, dy) | legs,
                               [("d", [(11, dy), (12, dy)]), ("x", [(15, 3 + dy), (21, 3 + dy)])] + marks))
groups["대기 (결재·새 답변)"] = [capy(L1)]
sleep = render(ell(9.5, 10.6, 8.6, 3.3) | head(0, 4), [("d", [(11, 4), (12, 4)]), ("x", [(15, 7), (16, 7), (21, 7)])]
               + [(k, v) for k, v in yuzu(15, 2).items()]
               + [("z", [(20, -2), (21, -2), (22, -2), (23, -2), (22, -1), (21, 0), (20, 1), (21, 1), (22, 1), (23, 1)])])
groups["낮잠"] = [sleep]
moon = render(set(), [("m", [(2, -3), (3, -3), (1, -2), (1, -1), (2, 0), (3, 0)])])
groups["달"] = [moon]
import json
json.dump({k: ["".join(r) for g in v for r in g + [["|"]]] for k, v in groups.items()}, open("groups.json", "w"), ensure_ascii=False)
