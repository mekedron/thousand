-- Unit coverage for the love.filesystem wrapper. Drives the in-memory
-- storage hook so the spec stays independent of a Love2D runtime, in
-- the same shape as tests/spec/app/settings_spec.lua.

local function fresh_auto_save()
    package.loaded["app.auto_save"] = nil
    package.loaded["core.auto_save"] = nil
    package.loaded["app.json"] = nil
    return require("app.auto_save")
end

local function in_memory_storage()
    local store = {}
    local read_fn = function(path)
        return store[path]
    end
    local write_fn = function(path, content)
        store[path] = content
        return true
    end
    local remove_fn = function(path)
        store[path] = nil
        return true
    end
    return read_fn, write_fn, remove_fn, store
end

local Session = require("app.session")
local rule_config = require("core.rule_config")
local json = require("app.json")

local function find_safe_pass(hand, marriage_suit)
    for _, c in ipairs(hand) do
        if not (c.suit == marriage_suit and (c.rank == "K" or c.rank == "Q")) then
            return c
        end
    end
    error("no safe pass card available")
end

local function drive_to_talon(seed)
    local s = Session.new({ seed = seed, dealer = 1 })
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

local function drive_to_tricks(seed)
    local s = drive_to_talon(seed)
    assert(s:take_talon().ok)
    local hand = s:hands()[2]
    assert(s:pass_talon(1, find_safe_pass(hand, nil)).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, find_safe_pass(hand, nil)).ok)
    assert(s:skip_raise().ok)
    return s
end

describe("app.auto_save", function()
    local auto_save, store

    before_each(function()
        auto_save = fresh_auto_save()
        local read_fn, write_fn, remove_fn, s = in_memory_storage()
        store = s
        auto_save._set_storage(read_fn, write_fn, remove_fn)
    end)

    after_each(function()
        package.loaded["app.auto_save"] = nil
        package.loaded["core.auto_save"] = nil
        package.loaded["app.json"] = nil
    end)

    describe("save", function()
        it("returns false when no session is given", function()
            assert.is_false(auto_save.save(nil))
            assert.is_nil(store["auto_save.json"])
        end)

        it("writes a JSON document to auto_save.json", function()
            local s = Session.new({ seed = 7, dealer = 1 })
            assert.is_true(auto_save.save(s))
            local content = store["auto_save.json"]
            assert.is_string(content)
            local decoded = json.decode(content)
            assert.are.equal(1, decoded.schemaVersion)
            assert.are.equal("canonical_russian", decoded.templateName)
        end)
    end)

    describe("load", function()
        it("returns nil when no save file is present", function()
            assert.is_nil(auto_save.load())
        end)

        it("returns nil when the file is corrupt JSON", function()
            store["auto_save.json"] = "{not valid"
            assert.is_nil(auto_save.load())
        end)

        it("returns nil when the schemaVersion is wrong", function()
            store["auto_save.json"] = json.encode({
                schemaVersion = 99,
                templateName = "canonical_russian",
            })
            assert.is_nil(auto_save.load())
        end)

        it("returns nil when the templateName is unknown", function()
            store["auto_save.json"] = json.encode({
                schemaVersion = 1,
                templateName = "made_up_template",
            })
            assert.is_nil(auto_save.load())
        end)

        it("returns nil when the saved game already has a winner", function()
            local s = Session.from_state({
                config = rule_config.canonical_russian,
                dealer = 1,
                running_totals = { 1000, 540, 420 },
                winner = 1,
            })
            assert.is_true(auto_save.save(s))
            assert.is_nil(auto_save.load())
        end)
    end)

    describe("round-trip", function()
        it("preserves a Session at the auction phase", function()
            local s = Session.new({ seed = 7, dealer = 1 })
            assert.is_true(auto_save.save(s))
            local restored = auto_save.load()
            assert.is_table(restored)
            assert.are.equal("auction", restored:current_phase())
            assert.are.equal(s:current_turn(), restored:current_turn())
            assert.are.equal(s:dealer(), restored:dealer())
        end)

        it("preserves a Session mid-auction with a recorded bid", function()
            local s = Session.new({ seed = 7, dealer = 1 })
            assert(s:bid(2, 100).ok)
            assert.is_true(auto_save.save(s))
            local restored = auto_save.load()
            assert.are.equal(100, restored:current_bid())
            assert.are.equal(2, restored:current_leader())
        end)

        it("preserves a Session in the tricks phase", function()
            local s = drive_to_tricks(42)
            assert.is_true(auto_save.save(s))
            local restored = auto_save.load()
            assert.is_table(restored)
            assert.are.equal("tricks", restored:current_phase())
            assert.are.equal(s:current_turn(), restored:current_turn())
        end)
    end)

    describe("clear", function()
        it("removes the save file", function()
            local s = Session.new({ seed = 1, dealer = 1 })
            assert.is_true(auto_save.save(s))
            assert.is_string(store["auto_save.json"])
            auto_save.clear()
            assert.is_nil(store["auto_save.json"])
        end)

        it("is a no-op when no file exists", function()
            assert.has_no.errors(function()
                auto_save.clear()
            end)
        end)
    end)

    describe("exists", function()
        it("returns false when nothing has been saved", function()
            assert.is_false(auto_save.exists())
        end)

        it("returns true after a save", function()
            local s = Session.new({ seed = 1, dealer = 1 })
            auto_save.save(s)
            assert.is_true(auto_save.exists())
        end)

        it("returns false after clear", function()
            local s = Session.new({ seed = 1, dealer = 1 })
            auto_save.save(s)
            auto_save.clear()
            assert.is_false(auto_save.exists())
        end)
    end)
end)
