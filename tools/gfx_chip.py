"""
gfx_chip.py - the GFX chip of the Chiplab, emulated on the Mac.

Implements docs/gfx-chip.md (v1): registers at $F010-$F03F, six drawing
commands, a 320x200 screen with the 16 C64 colours. chiplab_run.py sends
every access to those addresses here.

The screen is shown in a pygame window (the pygame-ce package: same
`import pygame`, with wheels for recent Pythons), opened at the first access to a
GFX register, so text-only programs never open one. Without pygame (or
with --no-gfx-window) the chip still works and the screen can be saved
as a PNG.
"""
import os
import struct
import sys
import zlib

BASE = 0xF010
END = 0xF03F                    # last address of the chip
WIDTH, HEIGHT = 320, 200
VERSION = 0x01

# Register offsets from BASE (see docs/gfx-chip.md)
P0 = 0x00                       # P0-P7: 0x00-0x0F, 16 bit, low byte first
CMD = 0x10
STATUS = 0x11
VERSION_REG = 0x12
RESULT = 0x13
PEN = 0x18
PAPER = 0x19
MODE = 0x1A
CLIP = 0x1C                     # CLIP_X0, CLIP_Y0, CLIP_X1, CLIP_Y1: 0x1C-0x23
WRITABLE = set(range(0x00, 0x10)) | {PEN, PAPER, MODE} | set(range(0x1C, 0x24))

NOP, CLEAR, LINE, RECT, FILL_RECT, CIRCLE, FILL_CIRCLE = range(7)
ERR_UNKNOWN_CMD = 0x01
MODE_XOR = 1

# The C64 colours, "Colodore" palette (Philip "Pepto" Timmermann, 2017).
PALETTE = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x9F, 0x4E, 0x44), (0x6A, 0xBF, 0xC6),
    (0xA0, 0x57, 0xA3), (0x5C, 0xAB, 0x5E), (0x50, 0x45, 0x9B), (0xC9, 0xD4, 0x87),
    (0xA1, 0x68, 0x3C), (0x6D, 0x54, 0x12), (0xCB, 0x7E, 0x75), (0x62, 0x62, 0x62),
    (0x89, 0x89, 0x89), (0x9A, 0xE2, 0x9B), (0x88, 0x7E, 0xCB), (0xAD, 0xAD, 0xAD),
]


def signed16(v):
    return v - 0x10000 if v & 0x8000 else v


class GfxChip:
    def __init__(self, scale=3, window=True):
        self.scale = scale
        self.want_window = window
        self.window = None          # opened at the first access
        self.used = False
        self.reset()

    # --- registers --------------------------------------------------------

    def reset(self):
        self.regs = bytearray(END - BASE + 1)
        self.regs[PEN] = 1                              # white
        self.regs[PAPER] = 0                            # black
        self._set16(CLIP + 4, WIDTH - 1)
        self._set16(CLIP + 6, HEIGHT - 1)
        self.screen = bytearray(WIDTH * HEIGHT)         # all PAPER (0)

    @staticmethod
    def owns(addr):
        return BASE <= addr <= END

    def read(self, addr):
        self._touch()
        r = addr - BASE
        if r == VERSION_REG:
            return VERSION
        if r == STATUS or r == RESULT or r in WRITABLE:
            return self.regs[r]
        return 0                                        # CMD and reserved

    def write(self, addr, value):
        self._touch()
        r = addr - BASE
        if r == CMD:
            self.execute(value)
        elif r in WRITABLE:
            self.regs[r] = value                        # reserved: ignored

    def _get16(self, r):
        return self.regs[r] | self.regs[r + 1] << 8

    def _set16(self, r, v):
        self.regs[r] = v & 0xFF
        self.regs[r + 1] = (v >> 8) & 0xFF

    def p(self, n, signed=True):
        v = self._get16(P0 + 2 * n)
        return signed16(v) if signed else v

    # --- commands ---------------------------------------------------------

    def execute(self, code):
        self.regs[STATUS] = 0
        if code == NOP:
            return
        handler = {
            CLEAR: self.cmd_clear,
            LINE: self.cmd_line,
            RECT: self.cmd_rect,
            FILL_RECT: self.cmd_fill_rect,
            CIRCLE: self.cmd_circle,
            FILL_CIRCLE: self.cmd_fill_circle,
        }.get(code)
        if handler is None:
            self.regs[STATUS] = ERR_UNKNOWN_CMD
            return
        handler()
        self.refresh()

    def clip_box(self):
        """The clip rectangle, intersected with the screen (inclusive)."""
        x0 = max(signed16(self._get16(CLIP)), 0)
        y0 = max(signed16(self._get16(CLIP + 2)), 0)
        x1 = min(signed16(self._get16(CLIP + 4)), WIDTH - 1)
        y1 = min(signed16(self._get16(CLIP + 6)), HEIGHT - 1)
        return x0, y0, x1, y1

    def plot_points(self, points):
        """Draw a set of points: each pixel once, clipped, PEN and MODE."""
        x0, y0, x1, y1 = self.clip_box()
        pen = self.regs[PEN] & 0x0F
        xor = self.regs[MODE] == MODE_XOR
        s = self.screen
        for x, y in points:
            if x0 <= x <= x1 and y0 <= y <= y1:
                i = y * WIDTH + x
                s[i] = (s[i] ^ pen) if xor else pen

    def fill_spans(self, spans, colour=None):
        """Draw horizontal spans {y: (xa, xb)}, clipped. colour=None: PEN+MODE."""
        x0, y0, x1, y1 = self.clip_box()
        if colour is None:
            colour = self.regs[PEN] & 0x0F
            xor = self.regs[MODE] == MODE_XOR
        else:
            xor = False
        s = self.screen
        for y, (xa, xb) in spans.items():
            if not y0 <= y <= y1:
                continue
            xa, xb = max(xa, x0), min(xb, x1)
            if xa > xb:
                continue
            i, j = y * WIDTH + xa, y * WIDTH + xb + 1
            if xor:
                s[i:j] = bytes(c ^ colour for c in s[i:j])
            else:
                s[i:j] = bytes([colour]) * (j - i)

    def cmd_clear(self):
        x0, y0, x1, y1 = self.clip_box()
        self.fill_spans({y: (x0, x1) for y in range(y0, y1 + 1)},
                        colour=self.regs[PAPER] & 0x0F)

    def cmd_line(self):
        self.plot_points(line_points(self.p(0), self.p(1), self.p(2), self.p(3)))

    def rect_args(self):
        x, y = self.p(0), self.p(1)
        w, h = self.p(2, signed=False), self.p(3, signed=False)
        return x, y, w, h

    def cmd_rect(self):
        x, y, w, h = self.rect_args()
        if w == 0 or h == 0:
            return
        xr, yb = x + w - 1, y + h - 1
        # Only the rows and columns that can be visible: a huge rectangle
        # far off screen costs nothing.
        cx0, cy0, cx1, cy1 = self.clip_box()
        pts = set()
        for xx in range(max(x, cx0), min(xr, cx1) + 1):
            pts.add((xx, y))
            pts.add((xx, yb))
        for yy in range(max(y, cy0), min(yb, cy1) + 1):
            pts.add((x, yy))
            pts.add((xr, yy))
        self.plot_points(pts)          # a set: corners are drawn once

    def cmd_fill_rect(self):
        x, y, w, h = self.rect_args()
        if w == 0 or h == 0:
            return
        _, cy0, _, cy1 = self.clip_box()
        rows = range(max(y, cy0), min(y + h - 1, cy1) + 1)
        self.fill_spans({yy: (x, x + w - 1) for yy in rows})

    def circle_args(self):
        return self.p(0), self.p(1), self.p(2, signed=False)

    def cmd_circle(self):
        cx, cy, r = self.circle_args()
        self.plot_points(circle_points(cx, cy, r))

    def cmd_fill_circle(self):
        cx, cy, r = self.circle_args()
        spans = {}
        for x, y in circle_points(cx, cy, r):
            xa, xb = spans.get(y, (x, x))
            spans[y] = (min(xa, x), max(xb, x))
        self.fill_spans(spans)

    # --- window and PNG -----------------------------------------------------

    def _touch(self):
        if not self.used:
            self.used = True
            if self.want_window:
                self.window = open_window(self.scale)
            self.refresh()

    def refresh(self):
        if self.window:
            self.window.show(self.screen)

    def pump(self):
        """Keep the window responsive. Returns False if it was closed."""
        return self.window.pump() if self.window else True

    def save_png(self, path):
        write_png(path, self.screen)

    def finish(self):
        """At the end of a run: keep the window up until it is closed."""
        if self.window:
            print("[gfx] close the window (or press Esc) to finish",
                  file=sys.stderr)
            self.window.wait_close()


# --- drawing algorithms (docs/gfx-chip.md, "Shapes, exactly") ---------------

def line_points(x0, y0, x1, y1):
    """Bresenham's line, both end points included, every octant."""
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def circle_points(cx, cy, r):
    """Midpoint circle: a set, so pixels shared by two octants come once.

    Variant: x = 0, y = r, d = 1 - r; while x <= y, plot the 8 symmetric
    points, then x += 1 and, if d < 0, d += 2x + 1, else y -= 1 and
    d += 2(x - y) + 1. The C64 version of gfx.s must use the same steps.
    """
    pts = set()
    x, y, d = 0, r, 1 - r
    while x <= y:
        for px, py in ((x, y), (y, x), (-x, y), (-y, x),
                       (x, -y), (y, -x), (-x, -y), (-y, -x)):
            pts.add((cx + px, cy + py))
        x += 1
        if d < 0:
            d += 2 * x + 1
        else:
            y -= 1
            d += 2 * (x - y) + 1
    return pts


def write_png(path, screen):
    """A 320x200 indexed-colour PNG, no library needed."""
    raw = b"".join(b"\x00" + bytes(screen[y * WIDTH:(y + 1) * WIDTH])
                   for y in range(HEIGHT))

    def chunk(kind, data):
        c = kind + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 3, 0, 0, 0))
    png += chunk(b"PLTE", bytes(c for rgb in PALETTE for c in rgb))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# --- pygame window ------------------------------------------------------------

def open_window(scale):
    try:
        os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
        import pygame
    except ImportError:
        print("[gfx] pygame is not installed (make setup installs pygame-ce): no window, "
              "use --gfx-png to see the screen", file=sys.stderr)
        return None
    return Window(pygame, scale)


class Window:
    def __init__(self, pygame, scale):
        self.pg = pygame
        pygame.display.init()
        pygame.display.set_caption("Chiplab GFX 320x200")
        self.display = pygame.display.set_mode((WIDTH * scale, HEIGHT * scale))
        self.surface = pygame.Surface((WIDTH, HEIGHT), depth=8)
        self.surface.set_palette(PALETTE)
        self.closed = False

    def show(self, screen):
        pg = self.pg
        buf = self.surface.get_buffer()
        pitch = self.surface.get_pitch()
        if pitch == WIDTH:
            buf.write(bytes(screen), 0)
        else:
            for y in range(HEIGHT):
                buf.write(bytes(screen[y * WIDTH:(y + 1) * WIDTH]), y * pitch)
        del buf
        # scale the 8-bit image, then blit: blit converts the palette
        big = pg.transform.scale(self.surface, self.display.get_size())
        self.display.blit(big, (0, 0))
        pg.display.flip()
        self.pump()

    def pump(self):
        for ev in self.pg.event.get():
            if ev.type == self.pg.QUIT or (
                    ev.type == self.pg.KEYDOWN and ev.key == self.pg.K_ESCAPE):
                self.closed = True
        return not self.closed

    def wait_close(self):
        try:
            while self.pump():
                self.pg.time.wait(50)
        except KeyboardInterrupt:
            pass
        self.pg.display.quit()
