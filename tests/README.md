# KI5 General Fixes tests

Runs the mod's real Lua against Project Zomboid's own VM, without launching the game.

```
pwsh tests/run-tests.ps1
```

A full run takes under a second.

## How it works

`projectzomboid.jar` contains Kahlua, the Lua 5.1 VM the game runs mods on. The runner
boots that same VM outside the game, installs a stubbed game API, loads the real mod
source, and drives it frame by frame.

Because it is the shipped VM and the shipped `PZAPI/ModOptions.lua`, the tests break
when a game update changes the API, rather than silently passing against a hand-written
imitation.

Load order, assembled by `run-tests.ps1`:

| Layer | Source |
| --- | --- |
| Game API stubs | `harness/pz_stubs.lua` |
| Translations | the mod's `Translate/EN/*.json`, parsed as flat json |
| Mod options API | the real one from the game install |
| Assertions | `harness/test_lib.lua` |
| Code under test | every `.lua` in the mod's `shared`, `client` and `server` folders |
| Specs | `specs/*_spec.lua` |

Singleplayer loads all three lua folders, so the harness does too. Multiplayer does
not, which is exactly why where a file lives is a decision rather than a detail.

Each test runs in a completely fresh environment. A mod's file-level locals cannot leak
from one test into the next.

## The reference mods

Two checks resolve names against the mods this one patches: KI5's vehicles, that DAMN
Library, Specific Loot and Yet Another PZ Library, unpacked under `other-mods/`.

That folder is other people's work and is not in the repository, so `run-tests.ps1`
passes it through `KI5GF_REFERENCE` only when it is there, and both checks stand down
when it is not. A clean clone runs green; a machine with the reference mods runs green
and checks more.

## What it checks

Beyond the specs themselves, every run performs a set of static checks first:

- **Syntax**, by compiling each file with the game's own compiler.
- **Returns lua cannot touch.** Every `local x = obj:method()` is resolved against what
  that method really returns, read out of the jar, and reported when the type is not on
  `LuaManager`'s exposed list and the local is then used as an object. This is the first
  crash a vehicle mod hits: `getParts()` hands back a `zombie.vehicles.VehicleParts`, so
  indexing it throws `attempted index: size of non-table` from inside Kahlua, with no
  line of mod source anywhere in the trace. The safe way through a vehicle's parts is
  `getPartCount` and `getPartByIndex`, and this is what says so before the game does.
- **Vehicle part ids.** Every `getPartById("X")` is resolved against the parts the
  vehicle scripts on this machine declare. A part id that no longer exists comes back
  nil and a fix guarded on it quietly stops doing anything. A script may name a family
  rather than a part, as `part Door*` does, so a wildcard matches by prefix. Needs the
  reference mods.
- **Item and vehicle script names.** Every `"Module.Name"` literal in shipped mod source
  is resolved against the items and vehicle scripts this build defines, the mod's own
  scripts first, then the reference mods, then the game's. A retired name is completely
  silent: the lookup simply stops matching. Vehicle names need the reference mods.
- **Constant validity.** Every `CharacterTrait.X` in shipped mod source is verified
  against the constants actually present in the installed build, read straight out of
  the jar, reported with file and line. Comments are skipped, since they routinely name
  a retired constant to explain why it is gone.
- **Sandbox options.** Types are checked against the five the game's parser accepts, and
  every option and page must have its label in `Sandbox.json`. Neither mistake crashes:
  the option is silently dropped or renders as a raw key.
- **Translation escaping.** The game runs every string through `String.format`, so a
  bare `%` is an invalid conversion and the whole string fails to render.
- **Texture paths.** Every `getTexture` path is resolved against the mod's own trees and
  the game install. A wrong path is not an error at runtime: the texture is simply null
  and nothing draws. Paths built with `string.format` are resolved as far as the folder.

## Conflict passes

Some guards decide **at file scope** whether a fix installs itself at all, because
standing down before touching anything is the only arrangement where load order between
two mods stops mattering. A spec cannot reach those: the decision was made before it ran.

So the suite runs again, once per folder under `specs-conflicts/`, with the whole mod
loaded a second time and that folder's name added to the mod list:

```
specs-conflicts/KI5MiniFixes/mini_fixes_spec.lua
```

The folder name is the other mod's id, the `id=` line from its `mod.info` and what
`getActivatedMods` returns. `run-tests.ps1` passes it through the `KI5GF_MODS`
environment variable, and `pz_stubs.lua` seeds `Harness.ActivatedMods` from it before
any mod file loads. Adding a conflict is a folder and a spec, no runner changes.

Every such spec asserts what did **not** happen, and an assertion of absence passes just
as happily against the wrong mod list, so each one starts by proving the pass is really
set up the way it claims.

## Writing a spec

```lua
Test("description of the behaviour", function()
    local Sunroof = Harness.NewVehiclePart("LS400Sunroof", { Door = Harness.NewVehicleDoor() })
    local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Sunroof } })

    Harness.Fire("OnGameBoot")
    Harness.Fire("OnEnterVehicle", Vehicle)

    AssertEquals(#Vehicle.PartAnims, 1, "the sunroof animation was not asked for")
end)
```

Vehicle surface: `NewVehicle(ScriptName, Values)`, `NewVehiclePart(Id, Values)`,
`NewVehicleDoor(Values)` and `NewVehicleScript(Name)`. Parts are reached from zero
through `getPartByIndex` or by id, never by iterating what `getParts` returns, which
throws here exactly as it does in game. `playPartAnim` records onto `Vehicle.PartAnims`,
so a spec can prove an animation was asked for without an animation system to run it.
`ResetVehicles` clears the list between setups.

`NewItemContainer(Type)` gives a part its container. On a vehicle part the type is the
part's own id, not a separate declaration: a vehicle script's `container` block has no
type field at all, which is the whole reason the container id fix exists.

`getScriptManager():getItem("Module.Name")` resolves against the mod's own shipped
script text, parsed as written rather than restated in the stub. That is what lets a
spec assert on a generated script without keeping a second copy of its contents.

General surface: `Fire`, `FireFrames`, `SetScreenSize`, `ClearDraws`, `FindDraw`,
`HandlerCount`, `Advance(Milliseconds)` for the clock `getTimestampMs` reads, and
`SetRandom` for an exact sequence of rolls. `ResetSandbox` and `ClearSandbox` set up the
server side balance, the latter reproducing a save made before a fix existed.

`Printed`, `FindPrinted(Fragment)` and `CountPrinted(Fragment)` record anything the mod
prints. A diagnostic that reports the wrong thing, or reports the same thing on every
vehicle, is the failure it was written to prevent, so it is asserted on rather than
eyeballed.

`ClientCommands` records anything a client would have sent to a server, and
`Harness.IsClient` switches between singleplayer and a multiplayer client, which is how
the networked half is tested without a server.

Assertions: `AssertTrue`, `AssertFalse`, `AssertNil`, `AssertNotNil`, `AssertEquals`,
`AssertNear`, `AssertContains`.

## Adding a fix

Drop `specs/<fix>_spec.lua` in place. The runner picks up new specs and new mod source
automatically, no configuration.

If a fix calls a game function the stubs do not cover yet, add it to `pz_stubs.lua`.
Events need no work: any `Events.Anything.Add` is captured on first use.

Stubs are written when the code that needs them exists, not before. A stub written ahead
of its caller is a guess, and a guess nothing exercises is worse than no stub at all,
because it passes.

## Requirements

A JDK. The JRE bundled with the game has no compiler, so the runner looks for one in
`Program Files`, Adoptium and the JetBrains runtime included with IntelliJ both work.
Tests execute from the game directory, because Kahlua resolves `stdlib.lua` relative to
the working directory. Set `KI5GF_PZ_DIR` if the install is somewhere the search misses.
