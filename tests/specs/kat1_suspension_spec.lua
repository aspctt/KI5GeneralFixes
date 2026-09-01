--// MAN KAT1 Suspension
--// aspctt - 27.08.2026
--// The patch runs at file scope, so the happy path is already done by the time a spec
--// starts. What is asserted here is its result, and every path it can take instead.

local SCRIPT = "80manKat1"

Test("the shipped suspension is patched as the file loads", function()
	local Patched = getScriptManager():getVehicle(SCRIPT)
	AssertNotNil(Patched, "the harness seeds this script before any mod file loads")

	-- Travel is the one that actually lets it climb back out of the ground.
	AssertEquals(Patched:getSuspensionTravel(), 20, "maxSuspensionTravelCm was not raised")
	AssertEquals(Patched:getSuspensionStiffness(), 100, "stiffness was not raised")
	AssertEquals(Patched:getSuspensionDamping(), 4.88, "damping was not raised")
	AssertNear(Patched:getSuspensionRestLength(), 0.5, 0.0001, "rest length was not raised")
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

Test("it stands down when KI5 has changed the suspension upstream", function()
	Harness.ClearVehicleScripts()
	local Changed = Harness.NewVehicleScriptDefinition(SCRIPT, { Stiffness = 60 })

	KI5GF.ApplyKat1Suspension()

	AssertEquals(#Changed.Loaded, 0, "an upstream fix must not be overwritten")
	AssertEquals(Changed:getSuspensionStiffness(), 60, "the upstream value should survive")
	AssertNotNil(Harness.FindPrinted("changed upstream"),
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
