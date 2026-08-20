--// Project Zomboid API Stubs
--// aspctt - 20.08.2026
--// Fakes the slice of the game these fixes touch, so the mod can run headless.
--//
--// This file grows with the fixes. Anything here is here because a fix reads it, not
--// because the game has it. A stub written ahead of the code that needs it is a guess,
--// and a guess that is never exercised is worse than nothing: it passes.

--// Harness
-- Control surface the specs drive. CharacterTrait is injected by TestRunner from the
-- shipped jar, so a constant that no longer exists is simply nil here too.
Harness = {}
Harness.EventHandlers = {}
Harness.ClientCommands = {}
Harness.TriggeredEvents = {}
Harness.MissingText = {}
Harness.Draws = {}
Harness.Vehicles = {}
Harness.ScreenX = 1920
Harness.ScreenY = 1080
Harness.HasPlayer = true

function Harness.SetScreenSize(Width, Height)
	Harness.ScreenX = Width
	Harness.ScreenY = Height
end

function Harness.ClearDraws()
	Harness.Draws = {}
end

function Harness.Fire(Name, A, B, C, D)
	local Handlers = Harness.EventHandlers[Name]
	if not Handlers then return 0 end
	for _, Handler in ipairs(Handlers) do
		Handler(A, B, C, D)
	end
	return #Handlers
end

function Harness.FireFrames(Count)
	for _ = 1, Count do
		Harness.Fire("OnPreUIDraw")
	end
end

function Harness.HandlerCount(Name)
	local Handlers = Harness.EventHandlers[Name]
	if not Handlers then return 0 end
	return #Handlers
end

-- Finds the most recent draw whose texture path contains Fragment
function Harness.FindDraw(Fragment)
	for Index = #Harness.Draws, 1, -1 do
		local Draw = Harness.Draws[Index]
		if Draw.Texture and Draw.Texture.Path and string.find(Draw.Texture.Path, Fragment, 1, true) then
			return Draw
		end
	end
	return nil
end

--// Events
-- Auto-creates an event object the first time a mod touches one, so a new fix does not
-- need this file updated.
Events = setmetatable({}, {
	__index = function(Table, Name)
		local Event = {}
		Harness.EventHandlers[Name] = Harness.EventHandlers[Name] or {}

		function Event.Add(Handler)
			table.insert(Harness.EventHandlers[Name], Handler)
		end

		function Event.Remove(Handler)
			for Index, Existing in ipairs(Harness.EventHandlers[Name]) do
				if Existing == Handler then
					table.remove(Harness.EventHandlers[Name], Index)
					return
				end
			end
		end

		rawset(Table, Name, Event)
		return Event
	end
})

--// Rendering
UIManager = {}

function UIManager.DrawTexture(Texture, X, Y, Width, Height, Alpha)
	table.insert(Harness.Draws, {
		Texture = Texture,
		Alpha = Alpha,
		Height = Height,
		Width = Width,
		X = X,
		Y = Y
	})
end

-- Size stands in for the real texture's pixel dimensions. Kept so a spec can catch an
-- icon being drawn larger than the box it is meant to sit in.
Harness.TextureSize = 32

function getTexture(Path)
	return { Path = Path, Size = Harness.TextureSize }
end

--// Core
local CoreStub = {}

function CoreStub:getScreenWidth()
	return Harness.ScreenX
end

function CoreStub:getScreenHeight()
	return Harness.ScreenY
end

-- The game returns -1 for a binding that does not exist, which is what makes a
-- keyed action on an unbound key do nothing.
Harness.BoundKeys = {}

function CoreStub:getKey(Name)
	return Harness.BoundKeys[Name] or -1
end

-- The two highlight colours the game picks between to say yes or no. Only their channels
-- are ever read, so a spec can tell which one a fix chose.
local function NewColour(R, G, B)
	local Colour = {}
	function Colour:getR() return R end
	function Colour:getG() return G end
	function Colour:getB() return B end
	return Colour
end

function CoreStub:getGoodHighlitedColor() return NewColour(0, 1, 0) end
function CoreStub:getBadHighlitedColor() return NewColour(1, 0, 0) end

function getCore()
	return CoreStub
end

--// Clock
-- Fixes that pace themselves off elapsed time read this. Specs move it by hand so a
-- test never has to wait on a real second.
Harness.NowMs = 0

function Harness.Advance(Milliseconds)
	Harness.NowMs = Harness.NowMs + Milliseconds
end

function getTimestampMs()
	return Harness.NowMs
end

--// Java Collections
-- ArrayList and friends are indexed from zero through get(), which is the single most
-- common way lua written against this API goes wrong.
local function NewJavaList(Items)
	local List = {}
	function List:size() return #Items end
	function List:get(Index) return Items[Index + 1] end
	function List:getItemByIndex(Index) return Items[Index + 1] end

	-- Real ArrayList.contains, which mods use to test for another mod by id
	function List:contains(Value)
		for _, Item in ipairs(Items) do
			if Item == Value then return true end
		end
		return false
	end

	return List
end

Harness.NewJavaList = NewJavaList

-- A java object lua is handed but was never exposed to call into. Reading anything off
-- one throws from inside Kahlua rather than coming back nil, which is why it reads as
-- "attempted index: size of non-table" with no line of mod source anywhere in the trace.
--
-- BaseVehicle.getParts is the one that matters here: it hands back a VehicleParts, which
-- is not on LuaManager's exposed list, so the only safe way through a vehicle's parts is
-- getPartCount and getPartByIndex.
--
-- Stubbed as a function rather than a table with metamethods, because Lua 5.1 does not
-- consult __len on a table at all. A table would quietly answer #Parts with 0 and let a
-- spec pass on the exact mistake this is here to catch. Indexing a function, calling a
-- method on it or taking its length all throw, which is the behaviour that matters.
local function NewOpaqueJavaObject(ClassName)
	return function()
		error("attempted to call into " .. ClassName .. ", which lua is not exposed to", 2)
	end
end

Harness.NewOpaqueJavaObject = NewOpaqueJavaObject

--// Vehicles
-- The shape KI5's own code drives, taken from what its vehicle scripts and the game's
-- ISInventoryPage actually call. Parts are reached by index from zero or by id, never by
-- iterating what getParts hands back.
local function NewVehicleDoor(Values)
	Values = Values or {}
	local Door = {}
	Door.Open = Values.Open and true or false
	Door.Locked = Values.Locked and true or false

	function Door:isOpen() return self.Open end
	function Door:setOpen(Value) self.Open = Value and true or false end
	function Door:isLocked() return self.Locked end
	function Door:setLocked(Value) self.Locked = Value and true or false end

	return Door
end

Harness.NewVehicleDoor = NewVehicleDoor

local function NewVehiclePart(Id, Values)
	Values = Values or {}
	local Part = {}
	Part.Id = Id
	Part.Condition = Values.Condition or 100
	Part.Door = Values.Door
	Part.InventoryItem = Values.InventoryItem
	Part.Container = Values.Container

	function Part:getId() return self.Id end
	function Part:getCondition() return self.Condition end
	function Part:setCondition(Value) self.Condition = Value end
	function Part:getDoor() return self.Door end
	function Part:getInventoryItem() return self.InventoryItem end
	function Part:getItemContainer() return self.Container end

	return Part
end

Harness.NewVehiclePart = NewVehiclePart

-- ScriptName is the full "Base.91lexusLS400" a fix compares against, and getName gives
-- the bare half, which is the distinction KI5's registrations turn on.
local function NewVehicleScript(ScriptName)
	local Script = {}
	local Bare = string.match(ScriptName or "", "([^.]+)$") or ScriptName

	function Script:getFullName() return ScriptName end
	function Script:getName() return Bare end

	return Script
end

Harness.NewVehicleScript = NewVehicleScript

-- Values.Parts is a list of parts in the order the game holds them. Anything a fix wants
-- to assert on afterwards is recorded on the vehicle: PartAnims for playPartAnim, so a
-- spec can prove an animation was asked for without an animation system to run it.
function Harness.NewVehicle(ScriptName, Values)
	Values = Values or {}
	local Vehicle = {}
	local Script = NewVehicleScript(ScriptName)
	local Parts = Values.Parts or {}

	Vehicle.PartAnims = {}
	Vehicle.Id = Values.Id or (#Harness.Vehicles + 1)

	function Vehicle:getScript() return Script end
	function Vehicle:getId() return self.Id end

	function Vehicle:getPartCount() return #Parts end
	function Vehicle:getPartByIndex(Index) return Parts[Index + 1] end

	function Vehicle:getPartById(Id)
		for _, Part in ipairs(Parts) do
			if Part:getId() == Id then return Part end
		end
		return nil
	end

	-- The trap this mod exists partly to avoid. Returns something lua cannot read, the
	-- same as the game does.
	function Vehicle:getParts()
		return NewOpaqueJavaObject("zombie.vehicles.VehicleParts")
	end

	function Vehicle:playPartAnim(Part, Anim)
		table.insert(self.PartAnims, { Part = Part and Part:getId() or nil, Anim = Anim })
	end

	table.insert(Harness.Vehicles, Vehicle)
	return Vehicle
end

function Harness.ResetVehicles()
	Harness.Vehicles = {}
end

--// Item Containers
-- Only the type, which is the whole of what a vehicle container is judged on. On a
-- vehicle part the type is the part's own id, not a separate declaration: there is no
-- type field in a vehicle script's container block at all.
function Harness.NewItemContainer(Type)
	local Container = {}
	Container.Type = Type

	function Container:getType() return self.Type end
	function Container:setType(Value) self.Type = Value end

	return Container
end

--// Script Manager
-- Every item the mod's own scripts declare, keyed the way getItem is called, as
-- "Module.Name". Parsed from the shipped script text the runner hands over rather than
-- restated here, so a generated script is checked as it was actually written.
local ModItems

-- "base:container" in a script is ItemType.CONTAINER at runtime. Only the local half
-- is the constant, and the game upper cases it.
local function ParseItemType(Value)
	local Local = string.match(Value, "([%w_]+)%s*$")
	return Local and string.upper(Local) or nil
end

local function ParseModItems()
	local Items = {}
	for _, Text in pairs(KI5GF_MOD_SCRIPTS or {}) do
		local Module = "Base"
		local Current

		for Line in string.gmatch(Text, "[^\n]+") do
			local Declared = string.match(Line, "^%s*module%s+([%w_]+)%s*$")
			if Declared then Module = Declared end

			local Name = string.match(Line, "^%s*item%s+([%w_]+)%s*$")
			if Name then
				Current = { Module = Module, Name = Name }
				function Current:getName() return self.Name end
				function Current:getModuleName() return self.Module end
				function Current:getFullName() return self.Module .. "." .. self.Name end

				-- Presence is not the whole story. Preprocess registers an item's name
				-- only when its ItemType is CONTAINER, so a spec has to be able to tell
				-- an entry that registers from one that merely parses.
				function Current:isItemType(Wanted) return self.ItemType == Wanted end
				function Current:getItemType() return self.ItemType end
				function Current:isHidden() return self.Hidden == true end

				Items[Module .. "." .. Name] = Current
			end

			if Current then
				local Type = string.match(Line, "^%s*ItemType%s*=%s*([%w_:]+)%s*,?%s*$")
				if Type then Current.ItemType = ParseItemType(Type) end

				local Hidden = string.match(Line, "^%s*Hidden%s*=%s*(%a+)%s*,?%s*$")
				if Hidden then Current.Hidden = string.lower(Hidden) == "true" end

				-- An obsolete item never enters the bucket, so the script manager would
				-- not hand it back at all. Modelled, because shipping OBSOLETE here is
				-- the mistake that made the fix a no-op in game.
				local Obsolete = string.match(Line, "^%s*OBSOLETE%s*=%s*(%a+)%s*,?%s*$")
				if Obsolete and string.lower(Obsolete) == "true" then
					Items[Current.Module .. "." .. Current.Name] = nil
				end
			end
		end
	end
	return Items
end

local ScriptManagerStub = {}

function ScriptManagerStub:getItem(FullType)
	ModItems = ModItems or ParseModItems()
	return ModItems[FullType]
end

-- A java ArrayList, indexed from zero, the same as the real one. Order is not
-- guaranteed by the game, so nothing should depend on it.
function ScriptManagerStub:getAllItems()
	ModItems = ModItems or ParseModItems()

	local Ordered = {}
	for _, Item in pairs(ModItems) do table.insert(Ordered, Item) end
	table.sort(Ordered, function(A, B) return A:getFullName() < B:getFullName() end)

	return NewJavaList(Ordered)
end

function getScriptManager()
	return ScriptManagerStub
end

--// Console
-- print is Kahlua's own and writes to the runner's output, which a spec cannot read
-- back. Wrapped so anything a mod prints is also recorded, since a diagnostic that
-- reports the wrong thing, or reports the same thing every frame, is a real failure.
Harness.Printed = {}

local RealPrint = print

function print(...)
	local Parts = {}
	for Index = 1, select("#", ...) do
		Parts[Index] = tostring(select(Index, ...))
	end
	local Line = table.concat(Parts, "\t")
	table.insert(Harness.Printed, Line)
	RealPrint(Line)
end

function Harness.FindPrinted(Fragment)
	for _, Line in ipairs(Harness.Printed) do
		if string.find(Line, Fragment, 1, true) then return Line end
	end
	return nil
end

function Harness.CountPrinted(Fragment)
	local Count = 0
	for _, Line in ipairs(Harness.Printed) do
		if string.find(Line, Fragment, 1, true) then Count = Count + 1 end
	end
	return Count
end

--// Sandbox
-- Server controlled balance. Seeded from the defaults TestRunner parsed out of
-- 42/media/sandbox-options.txt, so these numbers are never restated here.
SandboxVars = { KI5GF = {} }

function Harness.ResetSandbox()
	SandboxVars.KI5GF = {}

	if not KI5GF_SANDBOX_DEFAULTS then return end
	for Name, Value in pairs(KI5GF_SANDBOX_DEFAULTS) do
		SandboxVars.KI5GF[Name] = Value
	end
end

-- A save made before a fix existed has no values at all, which the mod has to cope
-- with. This is how a spec reproduces that.
function Harness.ClearSandbox()
	SandboxVars.KI5GF = nil
end

Harness.ResetSandbox()

--// Translation
-- Build 42 translations are flat json. TestRunner parses every file in the mod's
-- Translate folder into one Translations table, so a key resolves here the same way it
-- would in game regardless of which file declared it.
function getText(Key, ...)
	local Value = Translations and Translations[Key]
	if Value == nil then
		Harness.MissingText[Key] = true
		return Key
	end

	-- The game runs these through String.format. Only positional %1 and %2 are worth
	-- reproducing, which is all vanilla uses in the strings this mod touches.
	local Args = { ... }
	for Index, Argument in ipairs(Args) do
		Value = string.gsub(Value, "%%" .. Index, tostring(Argument))
	end
	return Value
end

function getTextOrNull(Key)
	if Translations and Translations[Key] ~= nil then return Translations[Key] end
	return nil
end

--// File IO
-- Only reached if a mod calls PZAPI.ModOptions save or load. Reads yield no lines,
-- so options keep their declared defaults during tests.
function getFileReader()
	local Reader = {}
	function Reader:readLine() return nil end
	function Reader:close() end
	return Reader
end

function getFileWriter()
	local Writer = {}
	function Writer:write() end
	function Writer:close() end
	return Writer
end

--// Module Loading
-- Mod files declare their dependencies with require, e.g. require "Hooks/DAMN_VehicleMenu".
-- The runner has already loaded every stub by the time any mod file runs, so this only
-- has to not be nil. Anything genuinely missing fails later on use, with a better error
-- than a require would give.
Harness.Required = {}

function require(Path)
	Harness.Required[Path] = true
	return _G[string.match(tostring(Path), "([^/]+)$")] or {}
end

--// Utility
luautils = luautils or {}

function luautils.split(Text, Separator)
	local Parts = {}
	for Part in string.gmatch(Text, "([^" .. Separator .. "]+)") do
		table.insert(Parts, Part)
	end
	return Parts
end

--// Randomness
-- Deterministic by default so rolls can be tested exactly. Harness.NextRandom is the
-- value ZombRand will return.
Harness.NextRandom = 0

-- A queue for the cases where consecutive rolls mean different things. Seeding one value
-- cannot tell those apart. Once the queue runs dry it falls back to NextRandom, so a
-- spec only states the rolls it cares about.
Harness.RandomQueue = {}

function Harness.SetRandom(Values)
	Harness.RandomQueue = {}
	for Index, Value in ipairs(Values or {}) do Harness.RandomQueue[Index] = Value end
end

function ZombRand(Low, High)
	if High == nil then
		High = Low
		Low = 0
	end

	local Next = Harness.NextRandom
	if #Harness.RandomQueue > 0 then Next = table.remove(Harness.RandomQueue, 1) end

	local Value = Low + Next
	if Value >= High then return High - 1 end
	return Value
end

--// Mod Scripts
-- A script this mod ships, by file name. For the handful of things that live in a script
-- rather than in lua, where the only honest assertion is about what was actually written.
-- Handed over by the runner, since Kahlua has no io library of its own.
function Harness.ReadModScript(Name)
	return (KI5GF_MOD_SCRIPTS or {})[Name] or ""
end

--// Multiplayer
-- Both false is singleplayer. A dedicated server is isServer, a client on one is
-- isClient, and the two never both hold.
Harness.IsClient = false
Harness.IsServer = false

function isClient() return Harness.IsClient end
function isServer() return Harness.IsServer end

--// Installed Mods
-- getActivatedMods returns a java ArrayList of mod ids, indexed from zero, the ids being
-- the id= line from each mod.info. A spec adds one to stand another mod up beside this
-- one and prove a fix gets out of its way.
--
-- Seeded before any mod file loads, because a guard deciding whether a fix installs
-- itself at all runs at file scope and has already made its decision by the time a spec
-- could change this. KI5GF_EXTRA_MODS carries the other mods for the run, see the second
-- pass in run-tests.ps1.
Harness.ActivatedMods = { "KI5GeneralFixes" }

if KI5GF_EXTRA_MODS then
	for _, Name in ipairs(KI5GF_EXTRA_MODS) do
		table.insert(Harness.ActivatedMods, Name)
	end
end

function getActivatedMods()
	return NewJavaList(Harness.ActivatedMods)
end

--// UI Elements
-- Enough of ISUIElement for a panel to be built, positioned and measured. Positions live
-- on the lowercase fields, because vanilla reads self.width, self.height, self.x and
-- self.y directly as often as it calls the getters. Only exposing the accessors leaves
-- those reads nil, and the failure surfaces as a comparison against nil somewhere far
-- from the cause.
function Harness.NewUIElement(X, Y, Width, Height)
	local Element = {}
	Element.x = X or 0
	Element.y = Y or 0
	Element.width = Width or 0
	Element.height = Height or 0
	Element.Visible = true

	function Element:setX(Value) self.x = Value end
	function Element:setY(Value) self.y = Value end
	function Element:getX() return self.x end
	function Element:getY() return self.y end
	function Element:setWidth(Value) self.width = Value end
	function Element:setHeight(Value) self.height = Value end
	function Element:getWidth() return self.width end
	function Element:getHeight() return self.height end
	function Element:setVisible(Value) self.Visible = Value and true or false end
	function Element:isVisible() return self.Visible end

	return Element
end
