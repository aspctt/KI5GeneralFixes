"""Rebuild the container id registration script from the vehicle scripts on this machine.

Every vehicle part that declares a `container` block gets an ItemContainer whose
`type` is the part's own id. `ItemPickInfo.GetPickInfo` looks that id up with
`ItemConfigurator.GetIdForString`, and when it comes back -1 it writes a line to
the debug log, once per container per loot roll, which is what stutters as a
vehicle streams into range.

`ItemConfigurator.Preprocess` only ever registers nine vehicle container names,
hardcoded in the engine, and they are vanilla's own part ids. A modded vehicle
that names its parts anything else is unregisterable through the vehicle script,
because nothing in Preprocess reads one.

It does register every item script whose ItemType is CONTAINER, by bare name. So
this writes one minimal container item per missing id. The items exist to seed
that string table and nothing else: Hidden keeps them out of the item browser and
out of foraging, and none of them is in any loot table or recipe, so none can ever
spawn.

Hidden rather than OBSOLETE, which was tried first and does not work. Both are
real script keywords and Item.DoParam parses both, but ScriptBucket.LoadScripts
tests getObsolete() and skips the object outright, so it never enters the bucket,
never reaches getAllItems(), and Preprocess never sees it. The whole point is to
be in that collection. LoadScripts does not test isHidden(), while both the item
browser and the foraging system do, which is exactly the split wanted here.

Registering an id does not by itself change what spawns. The id only matters if
some distribution bucket lists it, and none does. What it changes is that the
lookup stops failing, so the log line stops and a container keyed distribution
becomes possible for these containers at all, which today it is not.

    python tools/generate_container_ids.py [--check] [--root PATH ...]

--check reports without writing, and exits non-zero when the file is out of date.
"""

import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "KI5GeneralFixes", "Contents", "mods", "KI5GeneralFixes",
                      "42", "media", "scripts", "ki5gf_container_ids.txt")

MODULE = "KI5GF"

# zombie.inventory.ItemConfigurator.vehicle_containers, read out of the jar. These
# are the only vehicle container names the engine registers on its own.
VANILLA = (
    "TruckBed", "TruckBedOpen", "GloveBox",
    "SeatFrontLeft", "SeatFrontRight",
    "SeatMiddleLeft", "SeatMiddleRight",
    "SeatRearLeft", "SeatRearRight",
)

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT = re.compile(r"//[^\n]*")
PART_HEADER = re.compile(r"^part\s+([A-Za-z0-9_]+)$")
MODULE_LINE = re.compile(r"^\s*module\s+([A-Za-z0-9_]+)\s*$")
ITEM_LINE = re.compile(r"^\s*item\s+([A-Za-z0-9_]+)\s*$")


def find_roots():
    """Every place a vehicle script might live, in order of how much it covers."""
    roots = []

    # The unpacked reference mods, so the generator still does something useful on
    # a machine with no Steam library.
    local = os.path.join(ROOT, "other-mods")
    if os.path.isdir(local):
        roots.append(local)

    # Every Steam library, which is where the hundred or so KI5 vehicles actually
    # are. Beats hardcoding one machine's drive letter.
    for steam in (os.environ.get("ProgramFiles(x86)", ""), os.environ.get("ProgramFiles", "")):
        vdf = os.path.join(steam, "Steam", "steamapps", "libraryfolders.vdf")
        if not os.path.isfile(vdf):
            continue
        text = io.open(vdf, encoding="utf-8", errors="ignore").read()
        for path in re.findall(r'"path"\s*"([^"]+)"', text):
            path = path.replace("\\\\", "\\")
            for tail in (("steamapps", "workshop", "content", "108600"),
                         ("steamapps", "common", "ProjectZomboid", "media", "scripts")):
                candidate = os.path.join(path, *tail)
                if os.path.isdir(candidate):
                    roots.append(candidate)

    for letter in "CDEFGHIJKLMNOPQRSTUVWXYZ":
        for tail in (r":\SteamLibrary\steamapps\workshop\content\108600",
                     r":\SteamLibrary\steamapps\common\ProjectZomboid\media\scripts"):
            candidate = letter + tail
            if os.path.isdir(candidate) and candidate not in roots:
                roots.append(candidate)

    return roots


def container_parts(text):
    """Every part id in one script whose part declares a container block.

    Brace aware rather than line matching, because a `container` keyword only means
    this part's container when it sits directly inside the part's own block. Doing
    it by proximity attributes a container to whichever part was declared last,
    which is right most of the time and silently wrong the rest of it.
    """
    text = LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))

    found = set()
    stack = []      # the header of every block currently open
    header = []     # characters seen since the last brace or comma

    for char in text:
        if char == "{":
            stack.append(" ".join("".join(header).split()))
            header = []
            # A container block belongs to the nearest enclosing part.
            if stack[-1] == "container" and len(stack) >= 2:
                match = PART_HEADER.match(stack[-2])
                if match:
                    found.add(match.group(1))
        elif char == "}":
            if stack:
                stack.pop()
            header = []
        elif char == ",":
            header = []
        else:
            header.append(char)

    return found


def declared_items(text):
    """Every item a script declares, as (module, name).

    Needed because an id here has to be spelled exactly as the part is, so a real
    item that already carries that bare name ends up sharing it. Worth reporting
    rather than discovering later, see collisions().
    """
    module = "Base"
    found = []
    for line in text.split("\n"):
        match = MODULE_LINE.match(line)
        if match:
            module = match.group(1)
            continue
        match = ITEM_LINE.match(line)
        if match:
            found.append((module, match.group(1)))
    return found


def scan(roots):
    parts = set()
    items = {}
    for root in roots:
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                if not name.endswith(".txt"):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    text = io.open(path, encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                # Cheap reject. A script with neither word cannot declare a container.
                if "part" in text and "container" in text:
                    parts |= container_parts(text)
                if "item" in text:
                    for item_module, item_name in declared_items(text):
                        items.setdefault(item_name, set()).add(item_module)
    return parts, items


def collisions(ids, items):
    """Ids that some other mod already declares an item under, by bare name.

    ScriptManager.FindItem resolves a name carrying a module outright, and resolves
    a bare one against Base before falling through to the other modules. So a real
    item in Base still wins its own bare lookup and ours is simply never reached.
    A real item in some other module leaves the bare lookup genuinely ambiguous,
    which is worth knowing about even when, as today, nothing performs one.
    """
    shadowed, ambiguous = [], []
    for name in sorted(ids):
        modules = items.get(name)
        if not modules:
            continue
        if "Base" in modules:
            shadowed.append((name, sorted(modules)))
        else:
            ambiguous.append((name, sorted(modules)))
    return shadowed, ambiguous


def build(ids, shadowed, ambiguous):
    """The script itself, declarations only.

    Nothing may precede `module`, and there are no comments anywhere in the file.
    ScriptManager.CreateFromToken locates a block by `indexOf("module")` on the raw
    token and takes the module name from there to the opening brace, so a comment
    that merely contains the word steals the match and the real declaration is
    never seen. This file shipped with an explanatory header once and the whole
    fix silently did nothing: the module parsed as garbage and held no items.

    Not one of the game's 1004 item scripts has a comment or anything before
    `module`. The 28 files that do carry comments are xui skins, which go through
    a different parser. So the reasoning lives in this module's docstring and in
    README.md, and the shipped file stays declarations only. The collision report
    goes to the console rather than into the file for the same reason.
    """
    lines = ["module %s" % MODULE, "{"]
    for name in sorted(ids):
        lines += [
            "	item %s" % name,
            "	{",
            "		ItemType = base:container,",
            "		Weight = 1.0,",
            "		Capacity = 1,",
            "		Hidden = true,",
            "	}",
            "",
        ]
    if lines[-1] == "":
        lines.pop()
    lines += ["}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report without writing")
    parser.add_argument("--root", action="append", default=[],
                        help="extra folder to scan, repeatable")
    args = parser.parse_args()

    roots = args.root + find_roots()
    if not roots:
        sys.exit("No vehicle scripts found. Pass --root with a folder to scan.")

    for root in roots:
        print("scanning %s" % root)

    found, items = scan(roots)
    missing = sorted(found - set(VANILLA))
    shadowed, ambiguous = collisions(missing, items)

    print("")
    print("container part ids found:  %d" % len(found))
    print("registered by the engine:  %d" % len(found & set(VANILLA)))
    print("needing registration here: %d" % len(missing))
    print("real item names seen:      %d" % len(items))

    if shadowed or ambiguous:
        print("")
        print("bare names shared with a real item: %d" % (len(shadowed) + len(ambiguous)))
        for name, modules in shadowed:
            print("  %-24s also in %s, which wins any bare lookup" % (name, ", ".join(modules)))
        for name, modules in ambiguous:
            print("  %-24s also in %s, neither in Base, so a bare lookup is ambiguous"
                  % (name, ", ".join(modules)))

    built = build(missing, shadowed, ambiguous)

    current = ""
    if os.path.isfile(TARGET):
        current = io.open(TARGET, encoding="utf-8", newline="").read()
    if current == built:
        print("%s already matches" % os.path.basename(TARGET))
        return

    if args.check:
        print("%s is OUT OF DATE, run without --check to rewrite it" % os.path.basename(TARGET))
        sys.exit(1)

    directory = os.path.dirname(TARGET)
    if not os.path.isdir(directory):
        os.makedirs(directory)
    io.open(TARGET, "w", encoding="utf-8", newline="\n").write(built)
    print("%s rewritten" % os.path.basename(TARGET))


if __name__ == "__main__":
    main()
