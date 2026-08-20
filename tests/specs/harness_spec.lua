--// Harness Contract
--// aspctt - 20.08.2026
--// Pins the two things about the vehicle API that mod code gets wrong, so the stub
--// keeps behaving like the game rather than like a convenient table.

Test("parts are indexed from zero", function()
	local Sunroof = Harness.NewVehiclePart("LS400Sunroof")
	local Trunk = Harness.NewVehiclePart("LS400Trunk")
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Sunroof, Trunk } })

	AssertEquals(Vehicle:getPartCount(), 2, "the vehicle should hold both parts")
	AssertEquals(Vehicle:getPartByIndex(0), Sunroof, "index zero is the first part")
	AssertEquals(Vehicle:getPartByIndex(1), Trunk, "index one is the second")
	AssertNil(Vehicle:getPartByIndex(2), "one past the end is nil, not an error")
end)

Test("getParts hands back something lua cannot read", function()
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400")
	local Parts = Vehicle:getParts()

	-- The game returns a zombie.vehicles.VehicleParts, which is not on LuaManager's
	-- exposed list. Reading anything off it throws from inside Kahlua with no line of
	-- mod source in the trace, which is how it reaches a player as a stutter rather
	-- than as an error anyone can act on.
	local Ok = pcall(function() return #Parts end)
	AssertFalse(Ok, "taking the size of VehicleParts should throw, the same as in game")
end)

Test("a part id resolves through the vehicle, not through the parts object", function()
	local Sunroof = Harness.NewVehiclePart("LS400Sunroof", { Door = Harness.NewVehicleDoor() })
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400", { Parts = { Sunroof } })

	AssertEquals(Vehicle:getPartById("LS400Sunroof"), Sunroof, "the id should find the part")
	AssertNil(Vehicle:getPartById("LS400Roofrack"), "a part this vehicle lacks is nil")
end)

Test("the script name keeps both halves", function()
	local Vehicle = Harness.NewVehicle("Base.91lexusLS400")

	AssertEquals(Vehicle:getScript():getFullName(), "Base.91lexusLS400", "the module travels with it")
	AssertEquals(Vehicle:getScript():getName(), "91lexusLS400", "getName drops the module")
end)
