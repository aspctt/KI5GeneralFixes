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
	AssertContains(Body, "OBSOLETE = true",
		"obsolete keeps them out of the item browser and out of foraging")

	AssertTrue(#DeclaredIds() > 0, "the script declared no items at all")
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
