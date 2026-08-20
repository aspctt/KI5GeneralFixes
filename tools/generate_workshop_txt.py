"""Rebuild KI5GeneralFixes/workshop.txt from workshop-description.txt.

The Project Zomboid uploader reads the description out of workshop.txt, one
"description=" line per line of text. workshop-description.txt is where that text
is actually written and reviewed, so the two drift apart the moment one is edited
on its own. That drift is silent: the upload succeeds and ships the old text.

Steam rejects a description over 8000 characters with EResult 8, InvalidParam,
which reads as "Failed to update, result 8" in the uploader and says nothing about
length. So the limit is checked here, where the message can be useful.

    python tools/generate_workshop_txt.py [--check]

--check reports without writing, for a quick look before uploading.
"""

import argparse
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "workshop-description.txt")
TARGET = os.path.join(ROOT, "KI5GeneralFixes", "workshop.txt")

# k_cchPublishedDocumentDescriptionMax in the Steam API.
DESCRIPTION_MAX = 8000

# Everything workshop.txt carries that is not the description, in the order the
# uploader writes them. id and visibility do not exist until the item has been
# published once, so they are carried through when present rather than required.
HEADER_KEYS = ("version", "id", "title", "tags", "visibility")
REQUIRED_KEYS = ("version", "title")


def read(path):
    # newline="" so nothing is translated on the way in, then CR is dropped outright.
    # The repository is LF only, but a workshop.txt written by the game's own uploader
    # arrives with CRLF, and carrying that CR into a header value puts it back on the
    # line this rebuilds.
    return io.open(path, encoding="utf-8", newline="").read().replace("\r\n", "\n")


def parse_header(text):
    """The non-description settings already in workshop.txt, kept as they are."""
    header = {}
    for line in text.split("\n"):
        key, _, value = line.partition("=")
        if key in HEADER_KEYS and key not in header:
            header[key] = value
    return header


def build(description, header):
    lines = ["%s=%s" % (key, header[key]) for key in HEADER_KEYS if key in header]
    for line in description.rstrip("\n").split("\n"):
        lines.append("description=" + line)
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="report without writing")
    args = parser.parse_args()

    description = read(SOURCE)
    header = parse_header(read(TARGET))

    missing = [k for k in REQUIRED_KEYS if k not in header]
    if missing:
        sys.exit("workshop.txt is missing: " + ", ".join(missing))

    # Expected before the first upload. Said out loud so it is not mistaken for the
    # uploader having dropped them afterwards, which would silently create a second item.
    unpublished = [k for k in ("id", "visibility") if k not in header]
    if unpublished:
        print("not published yet: no " + ", ".join(unpublished)
              + ". The uploader adds these on the first upload.")

    size = len(description)
    print("description: %d characters, limit %d" % (size, DESCRIPTION_MAX))
    if size > DESCRIPTION_MAX:
        sys.exit("over the limit by %d. Steam will refuse this with result 8."
                 % (size - DESCRIPTION_MAX))
    print("           : %d to spare" % (DESCRIPTION_MAX - size))

    built = build(description, header)

    # Against the file as it actually is, not the normalised copy read() hands back, or a
    # workshop.txt that differs only by its line endings reads as already correct.
    current = io.open(TARGET, encoding="utf-8", newline="").read()
    if current == built:
        print("workshop.txt already matches")
        return

    if args.check:
        print("workshop.txt is OUT OF DATE, run without --check to rewrite it")
        sys.exit(1)

    io.open(TARGET, "w", encoding="utf-8", newline="\n").write(built)
    print("workshop.txt rewritten")


if __name__ == "__main__":
    main()
