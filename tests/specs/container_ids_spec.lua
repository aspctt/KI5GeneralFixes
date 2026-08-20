--// Container Ids
--// aspctt - 20.08.2026
--// The registration script is generated, so what is checked here is its shape and the
--// audit that reports what it missed. Whether the ids themselves are right is settled
--// by the generator reading the same vehicle scripts the game does.

local SCRIPT = "ki5gf_container_ids.txt"

-- ItemConfigurator.vehicle_containers, the nine the engine registers on its own.
local VANILLA = {
	"TruckBed", "TruckBedOpen", "GloveBox",
	"SeatFrontLeft", "SeatFrontRight",
	"SeatMiddleLeft", "SeatMiddleRight",
	"SeatRearLeft", "SeatRearRight"
}

local function DeclaredIds()
	local Ids = {}
	for Line in string.gmatch(Harness.ReadModScript(SCRIPT), "[^\n]+") do
		local Name = string.match(Line, "^%s*item%s+([%w_]+)%s*$")
		if Name then table.insert(Ids, Name) end
	end
	return Ids
end

Test("the registration script declares container items in its own module", function()
	local Body = Harness.ReadModScript(SCRIPT)

	AssertContains(Body, "module KI5GF", "the items must not land in Base")
	AssertContains(Body, "ItemType = base:container",
		"Preprocess only registers items whose ItemType is CONTAINER")
	AssertContains(Body, "Hidden = true",
		"hidden keeps them out of the item browser and out of foraging")

	AssertTrue(#DeclaredIds() > 0, "the script declared no items at all")
end)

Test("nothing precedes the module declaration", function()
	-- Shipped wrong once, and the fix silently did nothing. ScriptManager.CreateFromToken
	-- finds a block with indexOf("module") on the raw token and reads the module name
	-- from there to the opening brace, so a header comment that merely contains the word
	-- steals the match and the real declaration is never reached. Nothing errors: the
	-- module parses as garbage and holds no items.
	local Body = Harness.ReadModScript(SCRIPT)
	local First

	for Line in string.gmatch(Body, "[^\n]+") do
		if string.match(Line, "%S") then First = Line break end
	end

	AssertNotNil(First, "the script is empty")
	AssertEquals(First, "module KI5GF",
		"the module declaration has to be the very first thing in the file")
end)

Test("the registration script carries no comments at all", function()
	-- Not one of the game's own item scripts has a comment. The parser is not comment
	-- aware, and any occurrence of module or item inside one is read as a declaration,
	-- so the reasoning lives in the generator and in README.md instead.
	local Body = Harness.ReadModScript(SCRIPT)

	AssertFalse(string.find(Body, "/*", 1, true), "a block comment breaks the parser")
	AssertFalse(string.find(Body, "//", 1, true), "a line comment breaks the parser")
end)

Test("the registration script is never marked obsolete", function()
	-- The mistake that made the whole fix a no-op in game, shipped once.
	-- ScriptBucket.LoadScripts tests getObsolete() and skips the object outright, so an
	-- obsolete item never enters the bucket, never reaches getAllItems(), and Preprocess
	-- never registers its name. It parses cleanly and reports nothing, so only the
	-- absence of the name gives it away.
	-- Parameter lines only. The file's own header names the keyword to explain why it
	-- is not used, and matching that would fail the moment the reasoning is written down.
	for Line in string.gmatch(Harness.ReadModScript(SCRIPT), "[^\n]+") do
		AssertFalse(string.match(Line, "^%s*OBSOLETE%s*="),
			"OBSOLETE drops the item before it reaches the collection Preprocess walks, "
			.. "which is the one place it has to be. Hidden is the flag that hides it "
			.. "without removing it.")
	end
end)

Test("every declared id resolves to an item the game would register", function()
	-- Presence alone proved too weak: the shipped script parsed, and the items were
	-- still absent from the bucket. This asserts what Preprocess actually tests.
	local Checked = 0
	for _, Id in ipairs(DeclaredIds()) do
		local Item = getScriptManager():getItem("KI5GF." .. Id)
		AssertNotNil(Item, Id .. " did not reach the script manager at all")
		AssertTrue(Item:isItemType(ItemType.CONTAINER),
			Id .. " is not a container item, so its name would never be registered")
		Checked = Checked + 1
	end
	AssertTrue(Checked > 300, "expected the full set of ids, got " .. Checked)
end)

Test("the declared items are hidden from the browser and from foraging", function()
	local Item = getScriptManager():getItem("KI5GF.LS400Trunk")
	AssertNotNil(Item, "LS400Trunk should be covered")
	AssertTrue(Item:isHidden(),
		"without Hidden these turn up in the item browser and in forage results")
end)

Test("every declared id is a plain part id", function()
	for _, Id in ipairs(DeclaredIds()) do
		AssertFalse(string.find(Id, "%*"), "a wildcard is a part family, not an id: " .. Id)
		AssertFalse(string.find(Id, "%."), "an id carries no module: " .. Id)
	end
end)

Test("the nine the engine already registers are left alone", function()
	local Declared = {}
	for _, Id in ipairs(DeclaredIds()) do Declared[Id] = true end

	for _, Id in ipairs(VANILLA) do
		AssertFalse(Declared[Id],
			Id .. " is registered by ItemConfigurator already, declaring it again means "
			.. "the generator's own list of the nine has drifted from the engine's")
	end
end)

Test("a covered container passes without a word", function()
	-- A real id out of the generated script, so this fails if the generator ever stops
	-- covering the reference vehicle.
	AssertNotNil(getScriptManager():getItem("KI5GF.LS400Trunk"),
		"LS400Trunk should be covered, regenerate with tools/generate_container_ids.py")

	local Part = Harness.NewVehiclePart("LS400Trunk",
		{ Container = Harness.NewItemContainer("LS400Trunk") })
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Part } })

	Harness.Fire("OnSpawnVehicleEnd", Vehicle)

	AssertEquals(#KI5GF.MissingContainerIds, 0, "a covered container was reported as missing")
	AssertNil(Harness.FindPrinted("LS400Trunk"), "nothing should have been printed")
end)

Test("a container the engine registers itself passes without a word", function()
	local Part = Harness.NewVehiclePart("GloveBox",
		{ Container = Harness.NewItemContainer("GloveBox") })
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Part } })

	Harness.Fire("OnSpawnVehicleEnd", Vehicle)

	AssertEquals(#KI5GF.MissingContainerIds, 0, "a vanilla container was reported as missing")
end)

Test("an uncovered container is named once, not once per vehicle", function()
	local function NewCar()
		local Part = Harness.NewVehiclePart("XX99Trunk",
			{ Container = Harness.NewItemContainer("XX99Trunk") })
		return Harness.NewVehicle("Base.99madeUpCar", { Parts = { Part } })
	end

	Harness.Fire("OnSpawnVehicleEnd", NewCar())
	Harness.Fire("OnSpawnVehicleEnd", NewCar())
	Harness.Fire("OnSpawnVehicleEnd", NewCar())

	AssertEquals(Harness.CountPrinted("XX99Trunk"), 1,
		"the audit must not repeat itself, or it becomes the spam it reports")
	AssertEquals(#KI5GF.MissingContainerIds, 1, "the id should be recorded exactly once")
	AssertEquals(KI5GF.MissingContainerIds[1], "XX99Trunk", "the wrong id was recorded")
end)

Test("a missing id also reports what the module actually holds", function()
	-- Checking one id at a time cannot tell "the script never loaded" from "this one id
	-- is missing", and the two have completely different fixes. The summary separates
	-- them, and it runs through a path that has to resolve a local declared before its
	-- caller, which is a compile-clean way to ship a nil call.
	local Part = Harness.NewVehiclePart("XX99Trunk",
		{ Container = Harness.NewItemContainer("XX99Trunk") })
	local Vehicle = Harness.NewVehicle("Base.99madeUpCar", { Parts = { Part } })

	Harness.Fire("OnSpawnVehicleEnd", Vehicle)

	local Line = Harness.FindPrinted("registration script holds")
	AssertNotNil(Line, "no summary was printed alongside the missing id")
	AssertContains(Line, "of them containers", "the summary should count container items")
	AssertFalse(string.find(Line, "holds 0 item(s)", 1, true),
		"the module should not be empty, the generated script declares 371 items")
end)

Test("the summary is printed once however many ids are missing", function()
	local function NewCar(Id)
		local Part = Harness.NewVehiclePart(Id, { Container = Harness.NewItemContainer(Id) })
		return Harness.NewVehicle("Base.99madeUpCar", { Parts = { Part } })
	end

	Harness.Fire("OnSpawnVehicleEnd", NewCar("XX99Trunk"))
	Harness.Fire("OnSpawnVehicleEnd", NewCar("XX99Roofrack"))

	AssertEquals(Harness.CountPrinted("registration script holds"), 1,
		"the summary must not repeat, it is context for the first failure only")
end)

Test("a part with no container is skipped", function()
	local Part = Harness.NewVehiclePart("EngineDoor")
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Part } })

	Harness.Fire("OnSpawnVehicleEnd", Vehicle)

	AssertEquals(#KI5GF.MissingContainerIds, 0, "a part with no container has no type to check")
end)

Test("the audit reaches the parts without touching getParts", function()
	-- getParts hands back a zombie.vehicles.VehicleParts, which lua is not exposed to.
	-- The stub throws on any use, so this passing is the proof.
	local Part = Harness.NewVehiclePart("LS400Trunk",
		{ Container = Harness.NewItemContainer("LS400Trunk") })
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Part } })

	AssertEquals(Harness.Fire("OnSpawnVehicleEnd", Vehicle), 1, "the audit did not run")
end)
