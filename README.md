KI5 General Fixes
=================

A single mod that fixes problems shared across KI5's vehicles, rather than one car at a
time.

KI5 builds from a common template, so a fault in the template is a fault in every vehicle
that uses it. Patching them one by one means a hundred near identical mods to keep in
step. This targets the shared surface instead: fix it once, and every KI5 vehicle in the
load order gets it.

**Build 42.20+ | Singleplayer and multiplayer**


Fixes
-----

**Vehicle Container Ids** - Stops the stutter as a vehicle streams into range, and the
`cannot get ID for container` lines that come with it.

A vehicle part that declares a container gets an `ItemContainer` whose type is the
part's own id. `ItemPickInfo.GetPickInfo` resolves that id through
`ItemConfigurator.GetIdForString`, and writes a debug log line every time it comes back
-1. That is once per container per loot roll, and each one is a synchronous write to two
files, so a car with ten containers pays it ten times over while its loot is being
rolled.

`ItemConfigurator.Preprocess` registers exactly nine vehicle container names, hardcoded
in the engine, and all nine are vanilla's own part ids: `TruckBed`, `TruckBedOpen`,
`GloveBox`, and the six numbered seats. Nothing in it reads a container declaration out
of a vehicle script, so a vehicle that names its parts anything else can never resolve.
It is an engine gap rather than a KI5 one, and this covers any vehicle that hits it.

There is a second half nobody sees. `ItemPickInfo.isMatch` resolves a container selector
with `containsSelectorID(containerId)`, so at -1 no container keyed distribution can
match at all. These containers are not empty, because buckets with no selector still
match, but nothing can currently be written to fill one specifically.

Preprocess does register every item script whose ItemType is `CONTAINER`, by bare name,
which is the one registration path a mod can reach. So the fix is a generated script of
minimal container items, one per missing id, 371 of them across every vehicle mod on the
author's machine. They are marked `OBSOLETE`, which keeps them out of the item browser
and out of foraging, and none is in any loot table or recipe, so none can spawn.
Registering a name does not change what a container receives: the id only matters to a
distribution bucket that lists it, and none does.

Nothing needs to run for that to work. The lua that ships alongside it only audits: on
each vehicle spawn it names, once, any container id the generated script did not cover,
so a KI5 release we have never seen shows up as a single line instead of a stutter.


Requirements
------------

that DAMN Library, which every KI5 vehicle already requires. It is declared in
`mod.info`, so the game enforces it and sorts it ahead of this on its own.

**Load order does not matter.** Every enabled mod's scripts are loaded during mod
loading, and `ItemConfigurator.Preprocess` does not run until the world loads, long
afterwards, reading whatever `getAllItems()` holds by then. Nothing here overrides a
file another mod ships, and the registration items live in their own `KI5GF` module, so
there is no last-one-wins contest to lose.

Worth knowing rather than guessing at: loading this **after** the vehicles does not let
it see more of them. The list of container ids is baked by the generator when the mod is
built, not discovered at runtime, because nothing at load time can tell which vehicle
parts have containers. A vehicle mod installed after the last regeneration is not
covered no matter where it sits in the order, and the audit will name it in the console
when one spawns.


Options
-------

Anything cosmetic will be configurable in **Options -> Mods**, with each fix in its own
section. These settings are per player.

Anything that changes game balance lives in the **KI5 General Fixes** sandbox page
instead, set when the world is created or by the server admin. That way every player in
a multiplayer game is playing to the same numbers, rather than each client quietly
running its own.


Installation
------------

Subscribe on the Steam Workshop, then enable it in the mod list.

To install by hand, copy `KI5GeneralFixes/Contents/mods/KI5GeneralFixes` into
`%UserProfile%\Zomboid\mods\`. For a server, add `KI5GeneralFixes` to `Mods=` in your
server config, and the Workshop id to `WorkshopItems=`.

This repository is laid out the way Steam expects a Workshop item, so the mod itself
sits at `KI5GeneralFixes/Contents/mods/KI5GeneralFixes/`.


Building on other people's work
-------------------------------

This mod patches other people's mods and ships none of their files. Everything here is
written from scratch against what those mods actually load, and every fix stands down
when the thing it targets is absent.

| Mod | By | |
| --- | --- | --- |
| [KI5's vehicles](https://steamcommunity.com/profiles/76561198030597952/myworkshopfiles/?appid=108600) | KI5 / bikinihorst | The vehicles this exists to fix. No files taken. |
| [that DAMN Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3171167894) | KI5 / bikinihorst | The shared runtime every KI5 vehicle requires. A hard dependency, not bundled. |
| [KI5 Mini-fixes](https://steamcommunity.com/sharedfiles/filedetails/?id=3740300378) | Пупсич | Covers the same ground in places. Anything it already fixes is left to it. |
| [Specific Loot (KI5)](https://steamcommunity.com/sharedfiles/filedetails/?id=3457132019) | Пупсич | Vehicle loot for KI5's cars. Not touched here. |
| [Yet Another PZ Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3624971238) | Пупсич | What Specific Loot sits on. Not a dependency here. |

Their unpacked source is kept locally under `other-mods/` so fixes can be written against
what the game really loads. That folder is not published, and is in `.gitignore` for
that reason. See [NOTICE](NOTICE).

If you are one of these authors and would rather not be involved, say so and your work
comes out.


Development
-----------

The mod runs on Project Zomboid's own Lua VM, so it can be tested without launching the
game:

```
pwsh tests/run-tests.ps1
```

That loads the real mod source into the VM out of `projectzomboid.jar`, stubs the game
API, and runs the specs in `tests/specs`. It also checks every file compiles, that no
call hands lua a Java object it cannot read, and that every part id and script name still
exists in the mods being patched. A full run takes under a second. See
[tests/README.md](tests/README.md).

The Steam description is written in `workshop-description.txt`. The uploader reads it
from `workshop.txt` instead, one `description=` line per line of text, so the two drift
apart silently the moment one is edited on its own:

```
python tools/generate_workshop_txt.py
```

`--check` reports without writing, which is the thing to run before an upload.

The container id script is generated too, by scanning every vehicle script in the Steam
workshop folder and the game install:

```
python tools/generate_container_ids.py
```

It is the only list of ids anywhere: the audit asks the script manager what exists
rather than carrying a copy. Rerun it when a new vehicle mod is installed, which the
audit will have told you about. It also reports any id that shares a bare name with a
real item, and records those in the generated file's header.

The Photoshop exports go to three places, one of which is only visible on the Workshop:

```
python tools/sync_art.py
```

`icon.png` and `poster.png` land beside `mod.info`, and `poster.png` doubles as the
Workshop thumbnail at `preview.png`. Photoshop writes an XMP block into every export
carrying layer names and layer text, which travel from whatever document the file
descended from, so the copies are stripped of every text chunk on the way. No pixel is
touched.


Licence
-------

All Rights Reserved. See [LICENSE](LICENSE), and [NOTICE](NOTICE) for third party work.

Project Zomboid is the property of The Indie Stone. This is an unofficial mod and is not
affiliated with or endorsed by them.
