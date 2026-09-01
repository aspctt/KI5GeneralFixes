--// MAN KAT1 Suspension
--// aspctt - 01.09.2026
--// The patch rides OnInitGlobalModData, because it reads a sandbox value and there is
--// no world, and so no SandboxVars, while lua is still loading.

local SCRIPT = "80manKat1"

-- 0.9 on this vehicle. Loaded() multiplies travel and rest length by it on parse, and
-- Load does not re-run Loaded(), so the patch writes pre-scaled values. Comparing
-- against the raw 20 and 0.5 is the mistake that shipped in 1.0.2 and did nothing.
local function Scale()
	return Harness.VehicleScripts[SCRIPT]:getModelScale()
end

local function Fire()
	return Harness.Fire("OnInitGlobalModData")
end

-- The option ships off, so anything asserting the patch applied has to turn it on first.
local function FireEnabled()
	Harness.ResetSandbox()
	SandboxVars.KI5GF.FixKat1Suspension = true
	return Fire()
end

Test("the fix runs on OnInitGlobalModData, not at file scope", function()
	-- At file scope there is no world and no SandboxVars, so the setting could not be
	-- read. Nothing should have happened until the event fires.
	AssertEquals(#Harness.VehicleScripts[SCRIPT].Loaded, 0,
		"the patch must not run while lua is still loading")
	AssertTrue(FireEnabled() > 0, "nothing is listening on OnInitGlobalModData")
	AssertEquals(#Harness.VehicleScripts[SCRIPT].Loaded, 1, "the event did not patch")
end)

Test("nothing happens unless the host asks for it", function()
	Harness.ResetSandbox()
	AssertFalse(SandboxVars.KI5GF.FixKat1Suspension, "the option should ship off")

	Fire()

	AssertEquals(#Harness.VehicleScripts[SCRIPT].Loaded, 0,
		"the truck must be left alone until a host turns this on")
	AssertNear(Harness.VehicleScripts[SCRIPT]:getSuspensionTravel(), 14 * Scale(), 0.0001,
		"the shipped travel should survive untouched")
	AssertNil(Harness.FindPrinted("MAN KAT1"), "staying out of the way is not worth a word")
end)

Test("the shipped suspension is patched when the setting is on", function()
	FireEnabled()
	local Patched = getScriptManager():getVehicle(SCRIPT)

	AssertNear(Patched:getSuspensionTravel(), 20 * Scale(), 0.0001,
		"maxSuspensionTravelCm was not raised, or was written unscaled")
	AssertNear(Patched:getSuspensionRestLength(), 0.5 * Scale(), 0.0001,
		"suspensionRestLength was not raised, or was written unscaled")
	AssertEquals(Patched:getSuspensionStiffness(), 100, "stiffness was not raised")
	AssertEquals(Patched:getSuspensionDamping(), 4.88, "damping was not raised")
end)

Test("it matches what the standalone MAN KAT1 Suspension Fix produces", function()
	-- That mod ships a whole replacement 80manKat1.txt with these four values, and the
	-- game scales two of them on parse. Landing anywhere else means this does not
	-- reproduce the fix people report as working.
	FireEnabled()
	local Patched = getScriptManager():getVehicle(SCRIPT)

	AssertNear(Patched:getSuspensionTravel(), 18, 0.0001, "20 in the script, scaled")
	AssertNear(Patched:getSuspensionRestLength(), 0.45, 0.0001, "0.5f in the script, scaled")
	AssertEquals(Patched:getSuspensionStiffness(), 100, "100 in the script, unscaled")
	AssertEquals(Patched:getSuspensionDamping(), 4.88, "4.88 in the script, unscaled")
end)

Test("a save older than the setting is left alone", function()
	-- SandboxVars.KI5GF is absent entirely on a world made before this option existed.
	-- The fallback has to agree with the shipped default, or an old save would quietly
	-- get a handling change a new one would not.
	Harness.ClearSandbox()

	Fire()

	AssertEquals(#Harness.VehicleScripts[SCRIPT].Loaded, 0,
		"an absent setting should fall back to off, matching what the option ships as")
end)

Test("compression is left at what the vehicle already ships", function()
	FireEnabled()
	AssertNear(getScriptManager():getVehicle(SCRIPT):getSuspensionCompression(), 4.83,
		0.0001, "the patch should not be writing compression at all")
	AssertFalse(string.find(Harness.VehicleScripts[SCRIPT].Loaded[1].Body,
		"suspensionCompression", 1, true), "compression should not appear in the patch")
end)

Test("the patch is applied to the vehicle's own script, under its own name", function()
	FireEnabled()
	local Loaded = Harness.VehicleScripts[SCRIPT].Loaded
	AssertEquals(#Loaded, 1, "the script should be patched exactly once")
	AssertEquals(Loaded[1].Name, SCRIPT, "Load was called with the wrong script name")
end)

Test("it stands down when the vehicle is not installed", function()
	Harness.ClearVehicleScripts()

	-- Most people do not own this truck. Nothing said, nothing thrown.
	FireEnabled()

	AssertNil(Harness.FindPrinted("MAN KAT1"), "an absent vehicle is not worth a word")
end)

Test("running twice is silent and changes nothing further", function()
	-- The shared tree loads once for the server context and again for the client on a
	-- hosted game, and the event can fire per world load.
	FireEnabled()
	local Script = Harness.VehicleScripts[SCRIPT]
	local Before = #Script.Loaded

	Fire()

	AssertEquals(#Script.Loaded, Before, "the second pass should not patch again")
	AssertNil(Harness.FindPrinted("something else has changed it"),
		"recognising its own work is the whole point")
	AssertNear(Script:getSuspensionTravel(), 20 * Scale(), 0.0001,
		"the patched values must survive")
end)

Test("it stands down when KI5 has changed the suspension upstream", function()
	Harness.ClearVehicleScripts()
	local Changed = Harness.NewVehicleScriptDefinition(SCRIPT, { Stiffness = 60 })

	FireEnabled()

	AssertEquals(#Changed.Loaded, 0, "an upstream fix must not be overwritten")
	AssertEquals(Changed:getSuspensionStiffness(), 60, "the upstream value should survive")
	AssertNotNil(Harness.FindPrinted("something else has changed it"),
		"standing down silently would leave the author unaware the patch is stale")
end)

Test("a script that will not parse does not take the mod down with it", function()
	Harness.ClearVehicleScripts()
	Harness.NewVehicleScriptDefinition(SCRIPT)
	Harness.VehicleScriptLoadFails = true

	-- Load is declared to throw. Unguarded, that aborts this file and every fix after it.
	local Ok = pcall(FireEnabled)
	Harness.VehicleScriptLoadFails = nil

	AssertTrue(Ok, "the failure should be caught, not propagated")
	AssertNotNil(Harness.FindPrinted("could not patch"), "the failure should be reported")
end)
