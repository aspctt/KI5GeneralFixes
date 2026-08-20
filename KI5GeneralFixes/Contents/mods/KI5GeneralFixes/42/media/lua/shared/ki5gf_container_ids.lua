--// Container Id Audit
--// aspctt - 20.08.2026
--// Names a vehicle container the registration script does not cover, once, so a KI5
--// release we have never seen shows up as one line rather than as a stutter.

--// Background
-- A vehicle part that declares a container gets an ItemContainer whose type is the
-- part's own id. ItemPickInfo.GetPickInfo resolves that id through
-- ItemConfigurator.GetIdForString and writes a debug log line every time it comes back
-- -1, which is once per container per loot roll, as a vehicle streams into range.
--
-- ItemConfigurator.Preprocess registers only nine vehicle container names, hardcoded in
-- the engine and all of them vanilla's own part ids. Nothing in it reads a container
-- declaration out of a vehicle script, so a modded vehicle naming its parts anything
-- else can never resolve.
--
-- The fix is entirely in scripts/ki5gf_container_ids.txt: Preprocess registers every
-- item whose ItemType is CONTAINER by bare name, so one minimal item per missing id
-- makes the lookup succeed. That file is generated, and nothing here is needed to make
-- it work. This file only reports what it missed.

--// Reachability
-- The audit cannot run at load, where it would be most useful, because nothing there
-- can tell which parts have containers. VehicleScript.Part exposes getId() and no
-- container accessor, VehicleScript.Container is not exposed at all, and Kahlua's
-- exposer does not carry public fields, so part.container is unreadable from lua.
--
-- A spawned vehicle is different: VehiclePart.getItemContainer works, so the audit
-- rides OnSpawnVehicleEnd instead. Too late to register anything for this session,
-- which is why the covering file is generated ahead of time rather than discovered.

KI5GF = KI5GF or {}

-- Every container name the engine registers on its own, from
-- ItemConfigurator.vehicle_containers. These are vanilla part ids and always resolve.
local VANILLA = {
	TruckBed = true, TruckBedOpen = true, GloveBox = true,
	SeatFrontLeft = true, SeatFrontRight = true,
	SeatMiddleLeft = true, SeatMiddleRight = true,
	SeatRearLeft = true, SeatRearRight = true
}

-- The module the generated script declares its items in. Asking the script manager
-- whether an item exists is how the audit knows what is covered, so the generated file
-- stays the only list and nothing here has to be kept in step with it.
local MODULE = "KI5GF"

-- Names already examined this session, covered or not. A container type is looked up
-- once and never again, so the audit costs one table read per part after the first
-- vehicle of a given kind.
local Examined = {}

-- Names found to be missing, in the order they turned up. Kept on the global so a
-- player can read it back out of the console when reporting one.
KI5GF.MissingContainerIds = {}

-- Said once, the first time anything is found wrong. Presence of an entry is checked
-- one id at a time above, which cannot tell "the script never loaded" from "this one id
-- is missing from it". Counting what the module actually holds separates the two, and
-- it is the question worth answering first when a report says the fix did nothing.
local Summarised = false

local function SummariseModule()
	if Summarised then return end
	Summarised = true

	local Items = getScriptManager():getAllItems()
	if not Items then
		print("KI5 General Fixes: the script manager returned no item list at all.")
		return
	end

	local Declared, Containers = 0, 0
	for Index = 0, Items:size() - 1 do
		local Item = Items:get(Index)
		if Item and Item:getModuleName() == MODULE then
			Declared = Declared + 1
			if Item:isItemType(ItemType.CONTAINER) then Containers = Containers + 1 end
		end
	end

	print("KI5 General Fixes: registration script holds " .. Declared .. " item(s), "
		.. Containers .. " of them containers. Zero means the script never loaded; "
		.. "items but no containers means ItemType is not being read.")
end

local function Examine(Type)
	if Type == nil or Type == "" then return end
	if VANILLA[Type] then return end
	if Examined[Type] then return end
	Examined[Type] = true

	local Item = getScriptManager():getItem(MODULE .. "." .. Type)

	-- Present is not the same as counted. Preprocess registers an item only if its
	-- ItemType is CONTAINER, so an entry that parsed but carries the wrong type
	-- registers nothing while looking entirely fine from here. Worth telling apart,
	-- because the two have completely different causes and the first version of this
	-- file could not distinguish them.
	local Reason
	if not Item then
		Reason = "no entry for it in the registration script"
	elseif not Item:isItemType(ItemType.CONTAINER) then
		Reason = "its entry is not a container item, so the game does not register it"
	else
		return
	end

	SummariseModule()

	table.insert(KI5GF.MissingContainerIds, Type)
	print("KI5 General Fixes: vehicle container '" .. Type .. "' is not registered, "
		.. Reason .. ". Rebuild with tools/generate_container_ids.py, or report this id.")
end

local function AuditVehicle(Vehicle)
	if not Vehicle then return end

	-- By index from zero. getParts() hands back a zombie.vehicles.VehicleParts, which is
	-- not exposed, so reading anything off it throws from inside Kahlua with no line of
	-- mod source in the trace.
	for Index = 0, Vehicle:getPartCount() - 1 do
		local Part = Vehicle:getPartByIndex(Index)
		local Container = Part and Part:getItemContainer()
		if Container then
			Examine(Container:getType())
		end
	end
end

-- End rather than Start. On Start the vehicle is not created yet and its parts have no
-- containers to read, which is what vanilla's own ProfessionVehicles.CheckSwap relies on
-- when it tests isCreated() there.
Events.OnSpawnVehicleEnd.Add(AuditVehicle)
