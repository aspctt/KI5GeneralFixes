--// MAN KAT1 Suspension
--// aspctt - 27.08.2026
--// Stops the '80 MAN KAT1 sinking into the ground and staying there.

--// Background
-- The vehicle ships with 14cm of suspension travel carrying an 820 mass on a chassis
-- 7.8 long. Loaded, the wheels bottom out, the body drops through the terrain and there
-- is not enough travel left for it to climb back out, so it stays sunk.
--
-- Raising maxSuspensionTravelCm is what lets it come back up. The rest of the values
-- are here because travel alone leaves it wallowing: a longer rest length holds the
-- body higher to begin with, and the stiffness and damping stop the extra travel
-- turning into a bounce.
--
-- These numbers are a player's, arrived at by driving it from Ekron to West Point fully
-- loaded, not derived from anything. They make the truck usable rather than correct.
-- Wheel size and spacing are still wrong and only KI5 can fix those.

--// Approach
-- ScriptManager hands back the parsed VehicleScript, and Load merges a partial
-- definition into it, which is how KI5 Mini-fixes patches the Power Wagon's truck bed
-- and the Mini's enter offset. Nothing of KI5's is edited or shipped: the change is
-- applied to the script the game already loaded, in memory, every load.

--// When
-- On OnInitGlobalModData rather than at file scope, because this is a sandbox setting
-- and SandboxVars does not exist while lua is still loading: there is no world yet.
-- That event fires during IsoWorld.init, after the sandbox is populated and well before
-- any chunk streams a vehicle in, so the script is patched before the first KAT1 has
-- its physics built. It is where QoLCompendium reads its own sandbox values too.

KI5GF = KI5GF or {}

local SCRIPT = "80manKat1"

--// Model scale
-- VehicleScript.Loaded() runs once after the initial parse and multiplies a handful of
-- fields by the model's scale, maxSuspensionTravelCm and suspensionRestLength among
-- them. The KAT1's model is 0.9, so the 14 and 0.15 written in KI5's script are held as
-- 12.6 and 0.135. That is also why the player who worked these numbers out reported the
-- script as saying 12: they were reading the scaled value.
--
-- Load() does not re-run Loaded(), and it must not, because it would scale the extents,
-- the chassis shape and the centre of mass a second time. So everything here works in
-- the scaled space: what is compared against, and what is written.
--
-- Stiffness, damping and compression are not scaled by Loaded(), so those stay raw.

-- As KI5 writes them, before scaling.
local SHIPPED = {
	Stiffness = 41,
	Damping = 3.88,
	Compression = 4.83,
	RestLength = 0.15,
	Travel = 14
}

-- What this sets, before scaling. suspensionCompression is deliberately absent: it is
-- already 4.83 and the patch has no reason to restate it.
local TARGET = {
	Stiffness = 100,
	Damping = 4.88,
	RestLength = 0.5,
	Travel = 20
}

-- Floats out of the jar will not compare exactly against a literal written here.
local function Near(Value, Expected)
	local Difference = Value - Expected
	if Difference < 0 then Difference = -Difference end
	return Difference < 0.005
end

local function Matches(Script, Values, Scale)
	return Near(Script:getSuspensionStiffness(), Values.Stiffness)
		and Near(Script:getSuspensionDamping(), Values.Damping)
		and Near(Script:getSuspensionRestLength(), Values.RestLength * Scale)
		and Near(Script:getSuspensionTravel(), Values.Travel * Scale)
end

-- Off unless a host asks for it. This changes how a vehicle handles, on numbers that are
-- one player's tuning rather than anything derived, so it is not something to do to
-- someone's game uninvited.
--
-- An absent SandboxVars means the option was never reached, on a save older than this
-- setting or in a context with no world. That falls back to off as well, so the shipped
-- default and the fallback agree and nobody gets the change without choosing it.
local function Enabled()
	local Options = SandboxVars and SandboxVars.KI5GF
	if not Options then return false end
	return Options.FixKat1Suspension == true
end

local function Apply()
	if not Enabled() then return end
	if not ScriptManager or not ScriptManager.instance then return end

	-- Absent when the vehicle is not installed, which is most people.
	local Script = ScriptManager.instance:getVehicle(SCRIPT)
	if not Script then return end

	local Scale = Script:getModelScale()
	if not Scale or Scale <= 0 then return end

	-- Already done, on an earlier pass of this same file. The shared tree loads once for
	-- the server context and again for the client on a hosted game, so this runs twice.
	if Matches(Script, TARGET, Scale) then return end

	if not (Matches(Script, SHIPPED, Scale)
		and Near(Script:getSuspensionCompression(), SHIPPED.Compression)) then
		print("KI5 General Fixes: the MAN KAT1 suspension is neither what the vehicle "
			.. "ships nor what this sets, so something else has changed it. Leaving it alone.")
		return
	end

	-- Written already scaled, because Loaded() has been and gone and will not run again.
	local Patch = string.format([[{
		suspensionStiffness = %s,
		suspensionDamping = %s,
		maxSuspensionTravelCm = %s,
		suspensionRestLength = %s,
	}]], TARGET.Stiffness, TARGET.Damping, TARGET.Travel * Scale, TARGET.RestLength * Scale)

	-- Load is declared to throw, and a script that fails to parse should not take the
	-- rest of the mod's load with it.
	local Ok, Err = pcall(function() Script:Load(SCRIPT, Patch) end)
	if not Ok then
		print("KI5 General Fixes: could not patch the MAN KAT1 suspension: " .. tostring(Err))
	end
end

-- Exposed so a spec can drive every path, including the ones the event only reaches
-- once per world load.
KI5GF.ApplyKat1Suspension = Apply

Events.OnInitGlobalModData.Add(Apply)
