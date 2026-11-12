"""Generate Sources/AulaCore/Layouts.swift from the vendor configs in reference/.

F75 Pro: reference/device-cfg.ini, from AULA's F75 Windows installer. Its [KEY]
section lists each key as
    ;Label
    Kn=x1,y1,x2,y2, 0x02,<Windows VK>,0x00,<LED index>
Aula ships the ISO layout; ANSI variants of the keys that differ (Left Shift,
backslash, Enter) are added here by hand, using OpenRGB's ANSI F75 map for the
backslash LED (80). F75 Pro key slots equal LED indexes (from a recording of AULA's
driver), except that backslash is slot 75 on both layouts.

S75 Pro: reference/s75-pro/device.xml, from AULA's S75 Pro Windows installer.
Each <key> gives its HID usage, remap slot (key_index), LED slot (light_index)
and position.
"""
import html
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent

# Windows virtual-key code -> USB HID keyboard usage (page 0x07).
vk_to_hid = {
    0x1B: 0x29, 0x08: 0x2A, 0x09: 0x2B, 0x20: 0x2C, 0x0D: 0x28, 0x14: 0x39,
    0xBD: 0x2D, 0xBB: 0x2E, 0xDB: 0x2F, 0xDD: 0x30, 0xDC: 0x31, 0xBA: 0x33,
    0xDE: 0x34, 0xC0: 0x35, 0xBC: 0x36, 0xBE: 0x37, 0xBF: 0x38,
    0x2E: 0x4C, 0x23: 0x4D, 0x21: 0x4B, 0x22: 0x4E,
    0x27: 0x4F, 0x25: 0x50, 0x28: 0x51, 0x26: 0x52, 0xE2: 0x64,
    0xA2: 0xE0, 0xA0: 0xE1, 0xA4: 0xE2, 0x5B: 0xE3, 0xA1: 0xE5, 0xA5: 0xE6,
}
vk_to_hid.update({0x41 + i: 0x04 + i for i in range(26)})          # A-Z
vk_to_hid.update({0x31 + i: 0x1E + i for i in range(9)})           # 1-9
vk_to_hid[0x30] = 0x27                                             # 0
vk_to_hid.update({0x70 + i: 0x3A + i for i in range(12)})          # F1-F12

f75_pretty = {
    "Backspace": "Back", "CapsLock": "Caps", "LShift": "Shift", "RShift": "Shift",
    "LCtrl": "Ctrl", "LWin": "Win", "LAlt": "Alt", "RAlt": "Alt", "FN": "Fn",
    "><": "<>", "Delete": "Del", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
    "Space": "",
}

s75_pretty = {
    "Backspace": "Back", "CapsLock": "Caps", "Shift_L": "Shift", "Shift_R": "Shift",
    "Ctrl_L": "Ctrl", "Ctrl_R": "Ctrl", "Win_L": "Win", "Alt_L": "Alt", "Alt_R": "Alt",
    "Space": "", "del": "Del", "home": "Home", "end": "End",
}


def f75_keys():
    ini = (root / "reference" / "device-cfg.ini").read_text(encoding="utf-8")
    section = ini.split("[KEY]", 1)[1].split("[FN1]", 1)[0]
    keys, label = [], None
    for line in section.splitlines():
        line = line.strip()
        if line.startswith(";"):
            label = line[1:]
            continue
        m = re.match(r"K\d+=(\d+),(\d+),(\d+),(\d+),\s*0x02,(0x[0-9A-Fa-f]+),0x00,(\d+)", line)
        if not m:
            continue
        x1, y1, x2, y2 = (int(v) for v in m.groups()[:4])
        vk, led = int(m.group(5), 16), int(m.group(6))
        keys.append({"label": label, "rect": (x1, y1, x2 - x1, y2 - y1), "led": led, "remap": led,
                     "hid": [vk_to_hid[vk]] if vk in vk_to_hid else [], "layout": "both", "fnLocked": label == "FN"})

    def find(name):
        return next(k for k in keys if k["label"] == name)

    lshift, iso_key, backslash, enter = find("LShift"), find("><"), find("\\"), find("Enter")
    for k in (lshift, iso_key, backslash, enter):
        k["layout"] = "iso"
    backslash["hid"] = [0x32, 0x31]
    enter["rect"] = (566, 127, 46, 68)
    keys += [
        {**lshift, "rect": (27, 207, 76, 28), "layout": "ansi"},
        {**backslash, "rect": (566, 128, 46, 28), "led": 80, "remap": 75, "hid": [0x31], "layout": "ansi"},
        {**enter, "rect": (536, 168, 76, 28), "layout": "ansi"},
    ]
    for k in keys:
        k["label"] = f75_pretty.get(k["label"], k["label"])
    return keys


def s75_keys():
    xml = (root / "reference" / "s75-pro" / "device.xml").read_text(encoding="utf-8")
    keys = []
    for attrs in re.findall(r"<key ([^>]*)/>", xml):
        a = {k: html.unescape(v) for k, v in re.findall(r'(\w+)="([^"]*)"', attrs)}
        name = a["name"]
        # Two-character legends hold the shifted and unshifted characters; show the unshifted one.
        legends = {"~`": "`", "!1": "1", "@2": "2", "#3": "3", "$4": "4", "%5": "5", "^6": "6", "&7": "7",
                   "*8": "8", "(9": "9", ")0": "0", "_-": "-", "+=": "=", "{[": "[", "}}": "]", "|\\": "\\",
                   ":;": ";", "\"'": "'", ",<": ",", ".>": ".", "/?": "/"}
        label = s75_pretty.get(name, legends.get(name, name))
        hid = int(a["code"], 16)
        keys.append({
            "label": label,
            "rect": (int(a["rect_left"]), int(a["rect_top"]), int(a["rect_width"]), int(a["rect_height"])),
            "led": int(a["light_index"]), "remap": int(a["key_index"]),
            # Fn reports a vendor code (0xAF), not a HID usage.
            "hid": [] if name == "Fn" else [hid],
            "layout": "both", "fnLocked": name == "Fn" or a["fnlayer_disable"] == "1",
        })
    return keys


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


UNIT = 40  # points per key unit in the generated grid


def snap_to_grid(keys):
    """Turn the vendor's loosely spaced key drawing into a standard key-unit grid,
    like a keycap layout: 1u keys, 0.25u steps, rows one unit apart with a quarter
    unit after the function row. Keys then sit flush, with the gap drawn by the UI."""
    def q(v):
        return round(v * 4) / 4

    smallest = min(k["rect"][2] for k in keys)
    unit_w = sorted(k["rect"][2] for k in keys if k["rect"][2] <= smallest + 2)[0]
    # Pitch: the most common distance between neighbouring 1u keys in a row.
    by_y = sorted(keys, key=lambda k: (k["rect"][1], k["rect"][0]))
    steps = []
    for a, b in zip(by_y, by_y[1:]):
        if abs(a["rect"][1] - b["rect"][1]) < 4 and a["rect"][2] <= unit_w + 2 and b["rect"][2] <= unit_w + 2:
            steps.append(b["rect"][0] - a["rect"][0])
    pitch = max(set(steps), key=steps.count)
    gap = pitch - unit_w

    # Rows: cluster the keys' tops, so slightly lowered arrow keys stay in their row.
    tops = sorted({k["rect"][1] for k in keys})
    rows = []
    for t in tops:
        if rows and t - rows[-1][-1] < pitch * 0.5:
            rows[-1].append(t)
        else:
            rows.append([t])
    row_of = {t: i for i, r in enumerate(rows) for t in r}
    row_pitch = sorted(r2[0] - r1[0] for r1, r2 in zip(rows[1:], rows[2:]))[len(rows) // 2 - 1]

    origin_x = min(k["rect"][0] for k in keys)
    for k in keys:
        x, y, w, h = k["rect"]
        row = row_of[y]
        col = q((x - origin_x) / pitch)
        width = q((w + gap) / pitch)
        height = max(1, round((h + (row_pitch - unit_w)) / row_pitch))
        top = row + (0.25 if row >= 1 else 0)
        k["grid"] = (col * UNIT, top * UNIT, width * UNIT, height * UNIT)
    # A two-row ISO Enter is narrower at the bottom; draw its 1.25u lower part so
    # it doesn't overlap the key to its left.
    for k in keys:
        x, y, w, h = k["grid"]
        if k["label"] == "Enter" and h > UNIT:
            k["grid"] = (x + w - 1.25 * UNIT, y, 1.25 * UNIT, h)
    return keys


def emit(name, keys, pad):
    keys = snap_to_grid(keys)
    for k in keys:
        k["rect"] = tuple(round(v, 2) for v in k["grid"])
    xs = [k["rect"][0] for k in keys]
    ys = [k["rect"][1] for k in keys]
    x2 = [k["rect"][0] + k["rect"][2] for k in keys]
    y2 = [k["rect"][1] + k["rect"][3] for k in keys]
    bx, by = min(xs) - pad, min(ys) - pad
    bw, bh = max(x2) + pad - bx, max(y2) + pad - by
    lines = [f"    static let {name} = KeyboardLayout(", f"        bounds: CGRect(x: {bx}, y: {by}, width: {bw}, height: {bh}),", "        keys: ["]
    for i, k in enumerate(keys):
        x, y, w, h = k["rect"]
        variants = {"both": "[.ansi, .iso]", "iso": "[.iso]", "ansi": "[.ansi]"}[k["layout"]]
        hid = "[" + ", ".join(f"0x{v:02X}" for v in k["hid"]) + "]"
        lines.append(
            f"            KeyDef(id: {i}, label: {swift_str(k['label'])}, rect: CGRect(x: {x}, y: {y}, width: {w}, height: {h}), "
            f"led: {k['led']}, remapIndex: {k['remap']}, hidUsages: {hid}, variants: {variants}, fnLocked: {'true' if k['fnLocked'] else 'false'}),")
    lines += ["        ]", "    )", ""]
    return lines


out = [
    "// Generated by tools/gen_layout.py from the vendor configs in reference/. Do not edit by hand.",
    "",
    "import CoreGraphics",
    "",
    "public enum Layouts {",
]
out += emit("f75Pro", f75_keys(), 12)
out += emit("s75Pro", s75_keys(), 12)
out += ["}", ""]
dest = root / "Sources" / "AulaCore" / "Layouts.swift"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text("\n".join(out), encoding="utf-8")
print(f"wrote {dest}")
