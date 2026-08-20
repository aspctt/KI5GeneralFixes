--// Test Library
--// aspctt - 09.08.2026
--// Registration and assertions. TestRunner rebuilds the whole environment for each
--// test, so state never leaks from one test into the next.

--// Registry
Tests = {}
Tests.Registered = {}

function Test(Name, Body)
	table.insert(Tests.Registered, { Name = Name, Body = Body })
end

--// Assertions
local function Describe(Value)
	if type(Value) == "string" then return '"' .. Value .. '"' end
	return tostring(Value)
end

function AssertTrue(Value, Message)
	if not Value then
		error((Message or "expected a truthy value") .. ", got " .. Describe(Value), 2)
	end
end

function AssertFalse(Value, Message)
	if Value then
		error((Message or "expected a falsy value") .. ", got " .. Describe(Value), 2)
	end
end

function AssertNil(Value, Message)
	if Value ~= nil then
		error((Message or "expected nil") .. ", got " .. Describe(Value), 2)
	end
end

function AssertNotNil(Value, Message)
	if Value == nil then
		error(Message or "expected a value, got nil", 2)
	end
end

function AssertEquals(Actual, Expected, Message)
	if Actual ~= Expected then
		error((Message or "values differ")
			.. "\nexpected " .. Describe(Expected)
			.. "\nactual   " .. Describe(Actual), 2)
	end
end

function AssertNear(Actual, Expected, Tolerance, Message)
	Tolerance = Tolerance or 0.000001
	if type(Actual) ~= "number" then
		error((Message or "expected a number") .. ", got " .. Describe(Actual), 2)
	end
	local Difference = Actual - Expected
	if Difference < 0 then Difference = -Difference end
	if Difference > Tolerance then
		error((Message or "values differ")
			.. "\nexpected " .. Describe(Expected) .. " +/- " .. Describe(Tolerance)
			.. "\nactual   " .. Describe(Actual), 2)
	end
end

function AssertContains(Text, Fragment, Message)
	if type(Text) ~= "string" or not string.find(Text, Fragment, 1, true) then
		error((Message or "expected text to contain " .. Describe(Fragment))
			.. ", got " .. Describe(Text), 2)
	end
end

--// Runner Entry Point
-- Called from Java with a one-based index. Results come back through globals.
function RunSingleTest(Index)
	local Entry = Tests.Registered[Index]
	if not Entry then
		TEST_NAME = "test #" .. tostring(Index)
		TEST_OK = false
		TEST_ERROR = "no test registered at that index"
		return
	end

	TEST_NAME = Entry.Name
	local Ok, Err = pcall(Entry.Body)
	TEST_OK = Ok
	TEST_ERROR = Ok and "" or tostring(Err)
end
