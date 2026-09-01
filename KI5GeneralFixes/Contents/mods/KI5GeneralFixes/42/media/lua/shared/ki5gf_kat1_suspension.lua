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

KI5GF = KI5GF or {}

local SCRIPT = "80manKat1"

-- What the vehicle ships with today. If any of it has moved, KI5 has been at the
-- suspension and this stands down rather than overwriting their work.
local SHIPPED = {
	Stiffness = 41,
	Damping = 3.88,
	Compression = 4.83,
	RestLength = 0.15
}

-- suspensionCompression is deliberately absent: it is already 4.83 and the patch has no
-- reason to restate it.
local PATCH = [[{
	suspensionStiffness = 100,
	suspensionDamping = 4.88,
	maxSuspensionTravelCm = 20,
	suspensionRestLength = 0.5,
}]]

-- Floats out of the jar will not compare exactly against a literal written here.
local function Near(Value, Expected)
	local Difference = Value - Expected
	if Difference < 0 then Difference = -Difference end
	return Difference < 0.005
end

local function Apply()
	if not ScriptManager or not ScriptManager.instance then return end

	-- Absent when the vehicle is not installed, which is most people.
	local Script = ScriptManager.instance:getVehicle(SCRIPT)
	if not Script then return end

	if not (Near(Script:getSuspensionStiffness(), SHIPPED.Stiffness)
		and Near(Script:getSuspensionDamping(), SHIPPED.Damping)
		and Near(Script:getSuspensionCompression(), SHIPPED.Compression)
		and Near(Script:getSuspensionRestLength(), SHIPPED.RestLength)) then
		print("KI5 General Fixes: the MAN KAT1 suspension has changed upstream, "
			.. "leaving it alone. The sinking fix can probably be dropped.")
		return
	end

	-- Load is declared to throw, and a script that fails to parse should not take the
	-- rest of the mod's load with it.
	local Ok, Err = pcall(function() Script:Load(SCRIPT, PATCH) end)
	if not Ok then
		print("KI5 General Fixes: could not patch the MAN KAT1 suspension: " .. tostring(Err))
	end
end

-- Runs once as this file loads, which is after the game has parsed every script and
-- before any vehicle exists. Exposed as well, because a decision made at file scope has
-- already been taken by the time a spec could set anything up, and the stand-down path
-- is worth proving rather than assuming.
KI5GF.ApplyKat1Suspension = Apply

Apply()
