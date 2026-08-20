"""Copy the Photoshop exports into the places the game and Steam read them.

Three files come out of photoshop/ and land in three different places, none of
them next to each other:

    photoshop/icon.png   -> 42/icon.png        the mod list icon, named in mod.info
    photoshop/poster.png -> 42/poster.png      the mod list poster, named in mod.info
    photoshop/poster.png -> preview.png        the Workshop thumbnail, beside workshop.txt

Doing it by hand means one of the three is eventually a version behind, and the
one that gets missed is the Workshop thumbnail, because it is the only one not
visible from inside the game.

Photoshop writes an XMP metadata block into every PNG it exports, carrying layer
names and layer text among other things. Those travel from whatever document the
file was derived from, so an export descended from another project's poster still
names that project inside it. It is invisible in game and it still ships. The
copies written here are stripped of every ancillary text chunk, which touches no
pixels: only tEXt, iTXt and zTXt are dropped.

    python tools/sync_art.py [--check]

--check reports without writing, and exits non-zero when anything is stale.
"""

import argparse
import io
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "KI5GeneralFixes", "Contents", "mods", "KI5GeneralFixes")

COPIES = (
    (os.path.join(ROOT, "photoshop", "icon.png"), os.path.join(MOD, "42", "icon.png")),
    (os.path.join(ROOT, "photoshop", "poster.png"), os.path.join(MOD, "42", "poster.png")),
    (os.path.join(ROOT, "photoshop", "poster.png"),
     os.path.join(ROOT, "KI5GeneralFixes", "preview.png")),
)

# Ancillary chunks that carry text. Everything else, pixels included, is kept
# byte for byte.
TEXT_CHUNKS = (b"tEXt", b"iTXt", b"zTXt")

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def strip_text_chunks(data):
    """The same PNG without its text chunks, and what was dropped."""
    if not data.startswith(PNG_MAGIC):
        raise ValueError("not a PNG")

    out = [PNG_MAGIC]
    dropped = []
    pos = len(PNG_MAGIC)

    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos:pos + 12 + length]

        if ctype in TEXT_CHUNKS:
            dropped.append((ctype.decode("ascii"), length, chunk))
        else:
            out.append(chunk)

        pos += 12 + length
        if ctype == b"IEND":
            break

    return b"".join(out), dropped


def describe(dropped):
    """Any project name a dropped chunk was carrying, so it is named out loud."""
    names = set()
    for _ctype, _length, chunk in dropped:
        text = chunk.decode("utf-8", "replace").replace("﻿", "")
        for match in re.finditer(r"<photoshop:Layer(?:Name|Text)>([^<]+)</photoshop:Layer(?:Name|Text)>",
                                 text):
            names.add(match.group(1).strip())
    return sorted(n for n in names if n)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report without writing")
    args = parser.parse_args()

    stale = 0
    for source, target in COPIES:
        label = os.path.relpath(target, ROOT)

        if not os.path.isfile(source):
            print("MISSING  %s, nothing to copy from" % os.path.relpath(source, ROOT))
            stale += 1
            continue

        data = io.open(source, "rb").read()
        cleaned, dropped = strip_text_chunks(data)

        current = io.open(target, "rb").read() if os.path.isfile(target) else None
        if current == cleaned:
            print("ok       %s" % label)
            continue

        stale += 1
        saved = len(data) - len(cleaned)
        note = ""
        if dropped:
            note = ", dropping %s (%d bytes)" % (
                ", ".join(sorted(set(c for c, _l, _b in dropped))), saved)
            layers = describe(dropped)
            if layers:
                note += " naming " + ", ".join('"%s"' % n for n in layers)

        if args.check:
            print("STALE    %s%s" % (label, note))
            continue

        directory = os.path.dirname(target)
        if not os.path.isdir(directory):
            os.makedirs(directory)
        io.open(target, "wb").write(cleaned)
        print("written  %s%s" % (label, note))

    if args.check and stale:
        print("")
        print("%d file(s) out of date, run without --check to copy them" % stale)
        sys.exit(1)


if __name__ == "__main__":
    main()
