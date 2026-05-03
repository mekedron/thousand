-- Phase 4.2: difficulty enum + validator contract.

local difficulty = require("app.bot.difficulty")

describe("app.bot.difficulty", function()
    describe("VALUES", function()
        it("is the canonical Easy / Normal / Hard list in that order", function()
            assert.are.same({ "easy", "normal", "hard" }, difficulty.VALUES)
        end)
    end)

    describe("DEFAULT", function()
        it("is 'normal'", function()
            assert.are.equal("normal", difficulty.DEFAULT)
        end)

        it("is one of VALUES", function()
            local found = false
            for _, v in ipairs(difficulty.VALUES) do
                if v == difficulty.DEFAULT then
                    found = true
                end
            end
            assert.is_true(found)
        end)
    end)

    describe("validate", function()
        it("returns nil for nil input", function()
            assert.is_nil(difficulty.validate(nil, 3, "test"))
        end)

        it("returns a fresh copy of a valid array", function()
            local input = { "easy", "normal", "hard" }
            local out = difficulty.validate(input, 3, "test")
            assert.are.same(input, out)
            assert.are_not.equal(input, out)
        end)

        it("accepts every enum value at any seat index", function()
            local out = difficulty.validate({ "hard", "easy", "normal" }, 3, "test")
            assert.are.same({ "hard", "easy", "normal" }, out)
        end)

        it("accepts a 2-seat array under the 2-player template", function()
            local out = difficulty.validate({ "normal", "hard" }, 2, "test")
            assert.are.same({ "normal", "hard" }, out)
        end)

        it("rejects a non-table value", function()
            assert.error_matches(function()
                difficulty.validate("normal", 3, "ctx")
            end, "ctx: seat_difficulties must be a table or nil")
        end)

        it("rejects a length mismatch", function()
            assert.error_matches(function()
                difficulty.validate({ "easy", "normal" }, 3, "ctx")
            end, "ctx: seat_difficulties length 2 disagrees with players.count 3")
        end)

        it("rejects an unknown enum value", function()
            assert.error_matches(function()
                difficulty.validate({ "easy", "wizard", "hard" }, 3, "ctx")
            end, "ctx: seat_difficulties%[2%] must be one of 'easy' %| 'normal' %| 'hard'")
        end)

        it("rejects nil-valued slots inside the array", function()
            assert.error_matches(function()
                difficulty.validate({ "easy", nil, "hard" }, 3, "ctx")
            end, "seat_difficulties length")
        end)

        it("does not mutate the input on success", function()
            local input = { "easy", "normal", "hard" }
            difficulty.validate(input, 3, "test")
            assert.are.same({ "easy", "normal", "hard" }, input)
        end)
    end)
end)
