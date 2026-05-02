-- Unit coverage for core.templates: the pure-Lua wrapper around RuleConfig
-- that owns custom-template validation, single-template (de)serialization,
-- clone-from-builtin, reset-to-parent, id generation, and the default-sort
-- helper. No love.* — every assertion runs under plain busted.

local templates = require("core.templates")
local rule_config = require("core.rule_config")
local json = require("app.json")

-- The canonical Russian template's plain JSON blob, used as the inner
-- `ruleConfig` payload for valid wrappers. Going through to_json/decode
-- keeps the test in lockstep with whatever shape rule_config currently
-- emits, even as new sections land in 3.6.
local function builtin_blob(name)
    return json.decode(rule_config.to_json(rule_config.builtins[name]))
end

local function valid_wrapper()
    return {
        schemaVersion = 1,
        id = "deadbeefdeadbeef",
        name = "Test",
        parentTemplateId = "russian",
        starred = false,
        createdAt = 100,
        updatedAt = 100,
        ruleConfig = builtin_blob("russian"),
    }
end

describe("core.templates", function()
    describe("schema metadata", function()
        it("exposes a SCHEMA_VERSION", function()
            assert.are.equal(1, templates.SCHEMA_VERSION)
        end)
    end)

    describe("try_new", function()
        it("accepts a valid wrapper", function()
            local result = templates.try_new(valid_wrapper())
            assert.is_true(result.ok)
            assert.is_table(result.template)
            assert.are.equal("deadbeefdeadbeef", result.template.id)
            assert.are.equal("Test", result.template.name)
            assert.are.equal("russian", result.template.parentTemplateId)
            assert.are.equal(false, result.template.starred)
        end)

        it("rejects a non-table input", function()
            local r = templates.try_new(nil)
            assert.is_false(r.ok)
            assert.are.equal("not_a_table", r.error.code)
        end)

        it("rejects an unknown wrapper schemaVersion", function()
            local blob = valid_wrapper()
            blob.schemaVersion = 99
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("unsupported_schema_version", r.error.code)
            assert.are.equal(99, r.error.version)
            assert.are.equal(1, r.error.supported)
        end)

        it("rejects a missing id with field_required", function()
            local blob = valid_wrapper()
            blob.id = nil
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
            assert.are.equal("id", r.error.path)
        end)

        it("rejects an empty id with field_required", function()
            local blob = valid_wrapper()
            blob.id = ""
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
            assert.are.equal("id", r.error.path)
        end)

        it("rejects a missing name with field_required", function()
            local blob = valid_wrapper()
            blob.name = nil
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
            assert.are.equal("name", r.error.path)
        end)

        it("rejects a missing ruleConfig with field_required", function()
            local blob = valid_wrapper()
            blob.ruleConfig = nil
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
            assert.are.equal("ruleConfig", r.error.path)
        end)

        it("bubbles up an invalid inner ruleConfig under cause", function()
            local blob = valid_wrapper()
            blob.ruleConfig.cards.point_values["A"] = "not a number"
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("invalid_rule_config", r.error.code)
            assert.is_table(r.error.cause)
            assert.are.equal("type_mismatch", r.error.cause.code)
        end)

        it("bubbles up a deferred-field change as invalid_rule_config", function()
            local blob = valid_wrapper()
            -- half_marriage_capture_bonus is deferred while the Phase 3.6
            -- marriage-house-rules task is still pending.
            blob.ruleConfig.marriages.half_marriage_capture_bonus = "on"
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("invalid_rule_config", r.error.code)
            assert.are.equal("deferred_field_changed", r.error.cause.code)
        end)

        it("defaults starred to false when missing", function()
            local blob = valid_wrapper()
            blob.starred = nil
            local r = templates.try_new(blob)
            assert.is_true(r.ok)
            assert.are.equal(false, r.template.starred)
        end)

        it("rejects a non-boolean starred", function()
            local blob = valid_wrapper()
            blob.starred = "yes"
            local r = templates.try_new(blob)
            assert.is_false(r.ok)
            assert.are.equal("type_mismatch", r.error.code)
            assert.are.equal("starred", r.error.path)
        end)
    end)

    describe("dry_run", function()
        it("returns ok = true for a valid blob", function()
            local r = templates.dry_run(valid_wrapper())
            assert.is_true(r.ok)
            assert.is_nil(r.error)
        end)

        it("returns the same error envelope as try_new on failure", function()
            local blob = valid_wrapper()
            blob.id = ""
            local r = templates.dry_run(blob)
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
        end)
    end)

    describe("new_id", function()
        it("returns a 16-character hex string", function()
            templates._set_rng(nil) -- restore default
            local id = templates.new_id()
            assert.is_string(id)
            assert.are.equal(16, #id)
            assert.is_truthy(id:match("^[0-9a-f]+$"))
        end)

        it("returns distinct ids on consecutive calls", function()
            templates._set_rng(nil)
            local a = templates.new_id()
            local b = templates.new_id()
            assert.are_not.equal(a, b)
        end)

        it("is deterministic when the RNG is overridden", function()
            local n = 0
            templates._set_rng(function()
                n = n + 1
                return n
            end)
            local a = templates.new_id()
            n = 0
            local b = templates.new_id()
            assert.are.equal(a, b)
            templates._set_rng(nil)
        end)
    end)

    describe("clone_from_builtin", function()
        it("yields a template with parentTemplateId set to the source name", function()
            local r = templates.clone_from_builtin("russian", {
                name = "My Russian",
                id = "aaaaaaaaaaaaaaaa",
                now = 1234,
            })
            assert.is_true(r.ok)
            assert.are.equal("aaaaaaaaaaaaaaaa", r.template.id)
            assert.are.equal("My Russian", r.template.name)
            assert.are.equal("russian", r.template.parentTemplateId)
            assert.are.equal(1234, r.template.createdAt)
            assert.are.equal(1234, r.template.updatedAt)
            assert.are.equal(false, r.template.starred)
        end)

        it("clones the canonical blob byte-for-byte", function()
            local r = templates.clone_from_builtin("russian", {
                name = "Mine",
                id = "0000000000000001",
                now = 0,
            })
            local lhs = json.encode(r.template.ruleConfig)
            local rhs = rule_config.to_json(rule_config.builtins.russian)
            assert.are.equal(lhs, rhs)
        end)

        it("supports every built-in", function()
            for name, _ in pairs(rule_config.builtins) do
                local r = templates.clone_from_builtin(name, {
                    name = "Copy of " .. name,
                    id = "id" .. name,
                    now = 0,
                })
                assert.is_true(r.ok, "expected " .. name .. " to clone")
                assert.are.equal(name, r.template.parentTemplateId)
            end
        end)

        it("rejects an unknown built-in id with unknown_parent", function()
            local r = templates.clone_from_builtin("not_a_real_template", {
                name = "X",
                id = "00",
                now = 0,
            })
            assert.is_false(r.ok)
            assert.are.equal("unknown_parent", r.error.code)
            assert.are.equal("not_a_real_template", r.error.parentTemplateId)
        end)

        it("requires a non-empty name", function()
            local r = templates.clone_from_builtin("russian", {
                name = "",
                id = "00",
                now = 0,
            })
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
            assert.are.equal("name", r.error.path)
        end)

        it("uses the injected clock when now is omitted", function()
            templates._set_clock(function()
                return 7
            end)
            local r = templates.clone_from_builtin("russian", { name = "X", id = "id" })
            assert.are.equal(7, r.template.createdAt)
            assert.are.equal(7, r.template.updatedAt)
            templates._set_clock(nil)
        end)

        it("uses the injected RNG to mint an id when one is omitted", function()
            templates._set_rng(function()
                return 0xCAFE
            end)
            local r = templates.clone_from_builtin("russian", { name = "X", now = 0 })
            assert.is_true(r.ok)
            assert.are.equal("cafecafecafecafe", r.template.id)
            templates._set_rng(nil)
        end)
    end)

    describe("reset_to_parent", function()
        local builtins = rule_config.builtins

        it("replaces ruleConfig with the parent built-in's blob", function()
            local clone = templates.clone_from_builtin("polish", {
                name = "Edited Polish",
                id = "id",
                now = 0,
            }).template
            -- Mutate the clone, then reset.
            clone.ruleConfig.bidding.opening_min = 110
            local r = templates.reset_to_parent(clone, builtins, 99)
            assert.is_true(r.ok)
            assert.are.equal(99, r.template.updatedAt)
            local lhs = json.encode(r.template.ruleConfig)
            local rhs = rule_config.to_json(builtins.polish)
            assert.are.equal(lhs, rhs)
        end)

        it("returns a new table — original is not mutated", function()
            local clone = templates.clone_from_builtin("russian", {
                name = "Mine",
                id = "id",
                now = 0,
            }).template
            clone.ruleConfig.bidding.opening_min = 105
            local r = templates.reset_to_parent(clone, builtins, 50)
            assert.is_true(r.ok)
            assert.are.equal(105, clone.ruleConfig.bidding.opening_min)
            assert.are.equal(100, r.template.ruleConfig.bidding.opening_min)
        end)

        it("errors with parent_missing when parentTemplateId is nil", function()
            local clone = templates.clone_from_builtin("russian", {
                name = "Mine",
                id = "id",
                now = 0,
            }).template
            clone.parentTemplateId = nil
            local r = templates.reset_to_parent(clone, builtins, 0)
            assert.is_false(r.ok)
            assert.are.equal("parent_missing", r.error.code)
        end)

        it("errors with parent_missing when the parent is not in the builtins table", function()
            local clone = templates.clone_from_builtin("russian", {
                name = "Mine",
                id = "id",
                now = 0,
            }).template
            clone.parentTemplateId = "removed_in_a_future_release"
            local r = templates.reset_to_parent(clone, builtins, 0)
            assert.is_false(r.ok)
            assert.are.equal("parent_missing", r.error.code)
            assert.are.equal("removed_in_a_future_release", r.error.parentTemplateId)
        end)
    end)

    describe("with_rule_config", function()
        it("returns a new template with the updated ruleConfig and bumped updatedAt", function()
            local original = templates.clone_from_builtin("russian", {
                name = "Mine",
                id = "id",
                now = 100,
            }).template
            local edited = builtin_blob("russian")
            edited.bidding.opening_min = 105
            local next_template = templates.with_rule_config(original, edited, 200)
            assert.are.equal(200, next_template.updatedAt)
            assert.are.equal(100, next_template.createdAt)
            assert.are.equal(105, next_template.ruleConfig.bidding.opening_min)
            -- Original is untouched.
            assert.are.equal(100, original.ruleConfig.bidding.opening_min)
            assert.are.equal(100, original.updatedAt)
        end)
    end)

    describe("to_json / from_json round-trip", function()
        it("preserves every wrapper field exactly", function()
            local original = valid_wrapper()
            original.starred = true
            original.createdAt = 12345
            original.updatedAt = 67890
            local encoded = templates.to_json(original)
            assert.is_string(encoded)
            local r = templates.from_json(encoded)
            assert.is_true(r.ok)
            assert.are.equal(original.id, r.template.id)
            assert.are.equal(original.name, r.template.name)
            assert.are.equal(original.parentTemplateId, r.template.parentTemplateId)
            assert.are.equal(true, r.template.starred)
            assert.are.equal(12345, r.template.createdAt)
            assert.are.equal(67890, r.template.updatedAt)
            assert.are.equal(json.encode(original.ruleConfig), json.encode(r.template.ruleConfig))
        end)

        it("from_json reports json_decode_failed on malformed input", function()
            local r = templates.from_json("{not json")
            assert.is_false(r.ok)
            assert.are.equal("json_decode_failed", r.error.code)
        end)

        it("from_json bubbles up wrapper validation errors", function()
            local blob = valid_wrapper()
            blob.id = nil
            local r = templates.from_json(json.encode(blob))
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
        end)
    end)

    describe("default_sort", function()
        local function make(name, starred, id)
            return { name = name, starred = starred, id = id }
        end

        it("places starred templates before unstarred ones", function()
            local sorted = templates.default_sort({
                make("alpha", false, "a"),
                make("beta", true, "b"),
                make("gamma", false, "c"),
            })
            assert.are.equal("beta", sorted[1].name)
        end)

        it("sorts within each starred group by name ascending", function()
            local sorted = templates.default_sort({
                make("zulu", false, "z"),
                make("alpha", false, "a"),
                make("mike", true, "m"),
                make("bravo", true, "b"),
            })
            assert.are.equal("bravo", sorted[1].name)
            assert.are.equal("mike", sorted[2].name)
            assert.are.equal("alpha", sorted[3].name)
            assert.are.equal("zulu", sorted[4].name)
        end)

        it("breaks ties by id ascending", function()
            local sorted = templates.default_sort({
                make("alpha", false, "z"),
                make("alpha", false, "a"),
            })
            assert.are.equal("a", sorted[1].id)
            assert.are.equal("z", sorted[2].id)
        end)

        it("returns a fresh array — input is not mutated", function()
            local input = {
                make("zulu", false, "z"),
                make("alpha", false, "a"),
            }
            local sorted = templates.default_sort(input)
            assert.are_not.equal(input, sorted)
            assert.are.equal("zulu", input[1].name)
            assert.are.equal("alpha", sorted[1].name)
        end)
    end)
end)
