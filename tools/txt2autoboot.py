#!/usr/bin/env python3
"""Turn a text file into a MAME -autoboot_command string.

MAME types the string on the emulated keyboard. Works for:
  - BASIC listings (e.g. HAMURABI.txt): use --prefix '\\nE000R\\n' --suffix 'RUN\\n'
  - Woz Monitor hex  (e.g. life.txt):   use --suffix '2000R\\n'

The text is upper-cased (the Apple I has no lowercase), line endings become
\\n, and backslashes / double quotes are escaped for MAME's Lua string.
"""
import argparse
import sys


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


ap = argparse.ArgumentParser()
ap.add_argument("textfile")
ap.add_argument("--prefix", default="\\n", help="already escaped, e.g. '\\nE000R\\n'")
ap.add_argument("--suffix", default="", help="already escaped, e.g. 'RUN\\n'")
a = ap.parse_args()

text = open(a.textfile, encoding="latin-1").read().replace("\r\n", "\n").replace("\r", "\n")
lines = [l.rstrip() for l in text.upper().split("\n")]
body = "\n".join(l for l in lines if l) + "\n"      # drop blank lines
sys.stdout.write(a.prefix + esc(body) + a.suffix)
