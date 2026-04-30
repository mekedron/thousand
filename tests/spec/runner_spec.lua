-- Smoke test that proves the busted runner picks up tests/spec/*_spec.lua
-- and that the Lua interpreter wiring is sane. Real engine tests start in
-- Phase 1 under tests/spec/core/.

describe("test runner", function()
    it("executes a passing assertion", function()
        assert.is_true(true)
    end)

    it("compares values", function()
        assert.are.equal(1 + 1, 2)
    end)
end)
