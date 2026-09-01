--// MAN KAT1 Suspension
--// aspctt - 27.08.2026
--// The patch runs at file scope, so the happy path is already done by the time a spec
--// starts. What is asserted here is its result, and every path it can take instead.

local SCRIPT = "80manKat1"

Test("the shipped suspension is patched as the file loads", function()
	local Patched = getScriptManager():getVehicle(SCRIPT)
	AssertNotNil(Patched, "the harness seeds this script before any mod file loads")

	-- Loaded() scales travel and rest length by the model scale, 0.9 on this vehicle, and
	-- Load does not re-run it. So the patch has to write pre-scaled values, and what the
	-- game ends up holding is 20 * 0.9 and 0.5 * 0.9. Comparing against the raw 20 and 0.5
	-- is the mistake that shipped.
	local Scale = Patched:getModelScale()
	AssertNear(Scale, 0.9, 0.0001, "the KAT1 model scale")

	AssertNear(Patched:getSuspensionTravel(), 20 * Scale, 0.0001,
		"maxSuspensionTravelCm was not raised, or was written unscaled")
	AssertNear(Patched:getSuspensionRestLength(), 0.5 * Scale, 0.0001,
		"suspensionRestLength was not raised, or was written unscaled")

	-- Not scaled by Loaded(), so these go in raw.
	AssertEquals(Patched:getSuspensionStiffness(), 100, "stiffness was not raised")
	AssertEquals(Patched:getSuspensionDamping(), 4.88, "damping was not raised")
end)

Test("it matches what the standalone MAN KAT1 Suspension Fix produces", function()
	-- That mod ships a whole replacement 80manKat1.txt with these four values, and the
	-- game scales two of them on parse. Landing anywhere else means this does not
	-- actually reproduce the fix people report as working.
	local Patched = getScriptManager():getVehicle(SCRIPT)
	local Scale = Patched:getModelScale()

	AssertNear(Patched:getSuspensionTravel(), 18, 0.0001, "20 in the script, scaled")
	AssertNear(Patched:getSuspensionRestLength(), 0.45, 0.0001, "0.5f in the script, scaled")
	AssertEquals(Patched:getSuspensionStiffness(), 100, "100 in the script, unscaled")
	AssertEquals(Patched:getSuspensionDamping(), 4.88, "4.88 in the script, unscaled")
end)

Test("compression is left at what the vehicle already ships", function()
	-- The reported values list 4.83, which is what it already is, so the patch has no
	-- reason to restate it. If KI5 ever changes it, theirs should stand.
	AssertNear(getScriptManager():getVehicle(SCRIPT):getSuspensionCompression(), 4.83,
		0.0001, "the patch should not be writing compression at all")
	AssertFalse(string.find(Harness.VehicleScripts[SCRIPT].Loaded[1].Body,
		"suspensionCompression", 1, true), "compression should not appear in the patch")
end)

Test("the patch is applied to the vehicle's own script, under its own name", function()
	local Loaded = Harness.VehicleScripts[SCRIPT].Loaded
	AssertEquals(#Loaded, 1, "the script should be patched exactly once")
	AssertEquals(Loaded[1].Name, SCRIPT, "Load was called with the wrong script name")
end)

Test("it stands down when the vehicle is not installed", function()
	Harness.ClearVehicleScripts()

	-- Most people do not own this truck. Nothing should be said and nothing should throw.
	KI5GF.ApplyKat1Suspension()

	AssertNil(Harness.FindPrinted("MAN KAT1"), "an absent vehicle is not worth a word")
end)

Test("running twice is silent and changes nothing further", function()
	-- The shared tree loads once for the server context and again for the client on a
	-- hosted game, so this file runs twice against the same ScriptManager. The first
	-- version of the guard read its own work as an upstream change and said so on every
	-- server start, which is what a player reported.
	local Script = Harness.VehicleScripts[SCRIPT]
	local Before = #Script.Loaded

	KI5GF.ApplyKat1Suspension()

	AssertEquals(#Script.Loaded, Before, "the second pass should not patch again")
	AssertNil(Harness.FindPrinted("something else has changed it"),
		"recognising its own work is the whole point")
	AssertNil(Harness.FindPrinted("changed upstream"), "no upstream change has happened")
	AssertNear(Script:getSuspensionTravel(), 20 * Script:getModelScale(), 0.0001,
		"the patched values must survive")
end)

Test("it stands down when KI5 has changed the suspension upstream", function()
	Harness.ClearVehicleScripts()
	local Changed = Harness.NewVehicleScriptDefinition(SCRIPT, { Stiffness = 60 })

	KI5GF.ApplyKat1Suspension()

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
	local Ok = pcall(KI5GF.ApplyKat1Suspension)
	Harness.VehicleScriptLoadFails = nil

	AssertTrue(Ok, "the failure should be caught, not propagated")
	AssertNotNil(Harness.FindPrinted("could not patch"), "the failure should be reported")
end)
