-- Unit coverage for the love.filesystem wrapper around core.templates.
-- Drives the in-memory storage hook so the spec stays independent of a
-- Love2D runtime, in the same shape as tests/spec/app/auto_save_spec.lua.

local function fresh_templates()
    package.loaded["app.templates"] = nil
    package.loaded["core.templates"] = nil
    package.loaded["app.json"] = nil
    return require("app.templates")
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
    return read_fn, write_fn, store
end

local rule_config = require("core.rule_config")
local json = require("app.json")

local function builtin_blob(name)
    return json.decode(rule_config.to_json(rule_config.builtins[name]))
end

describe("app.templates", function()
    local templates, store

    before_each(function()
        templates = fresh_templates()
        local read_fn, write_fn, s = in_memory_storage()
        store = s
        templates._set_storage(read_fn, write_fn)
        -- Deterministic clock and id generator for the whole test run.
        local time_now = 1000
        templates._set_clock(function()
            return time_now
        end)
        templates._tick_clock = function(dt)
            time_now = time_now + (dt or 1)
        end
        local n = 0
        templates._set_rng(function()
            n = n + 1
            return n
        end)
    end)

    after_each(function()
        package.loaded["app.templates"] = nil
        package.loaded["core.templates"] = nil
        package.loaded["app.json"] = nil
    end)

    describe("list", function()
        it("starts with no custom templates and all the built-ins", function()
            local listing = templates.list()
            assert.are.same({}, listing.templates)
            assert.is_table(listing.builtins)
            -- Every key in rule_config.builtins should appear by id.
            local seen = {}
            for _, b in ipairs(listing.builtins) do
                seen[b.id] = true
            end
            for name, _ in pairs(rule_config.builtins) do
                assert.is_true(seen[name], "missing built-in: " .. name)
            end
        end)
    end)

    describe("create", function()
        it("clones a built-in into a new custom template", function()
            local r = templates.create({ fromBuiltin = "russian", name = "Mine" })
            assert.is_true(r.ok)
            assert.are.equal("Mine", r.template.name)
            assert.are.equal("russian", r.template.parentTemplateId)
            assert.is_string(r.template.id)
            -- Persists.
            assert.is_string(store["templates.json"])
            -- Visible via list().
            local listing = templates.list()
            assert.are.equal(1, #listing.templates)
            assert.are.equal(r.template.id, listing.templates[1].id)
        end)

        it("rejects an unknown built-in id", function()
            local r = templates.create({ fromBuiltin = "no_such", name = "X" })
            assert.is_false(r.ok)
            assert.are.equal("unknown_parent", r.error.code)
            assert.is_nil(store["templates.json"])
        end)

        it("rejects an empty name", function()
            local r = templates.create({ fromBuiltin = "russian", name = "" })
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
        end)

        it("mints a fresh id even when called repeatedly with the same args", function()
            local a = templates.create({ fromBuiltin = "russian", name = "A" })
            local b = templates.create({ fromBuiltin = "russian", name = "A" })
            assert.is_true(a.ok)
            assert.is_true(b.ok)
            assert.are_not.equal(a.template.id, b.template.id)
        end)
    end)

    describe("get", function()
        it("returns a custom template by id", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local got = templates.get(created.id)
            assert.is_table(got)
            assert.are.equal(created.id, got.id)
            assert.are.equal("Mine", got.name)
        end)

        it("returns nil for an unknown id", function()
            assert.is_nil(templates.get("not_a_real_id"))
        end)
    end)

    describe("update", function()
        it("replaces the ruleConfig blob and bumps updatedAt", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            templates._tick_clock(50)
            local edited = builtin_blob("russian")
            edited.bidding.opening_min = 105
            local r = templates.update(created.id, edited)
            assert.is_true(r.ok)
            assert.are.equal(105, r.template.ruleConfig.bidding.opening_min)
            assert.is_true(r.template.updatedAt > created.updatedAt)
        end)

        it("rejects an invalid blob and leaves storage unchanged", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local snapshot = store["templates.json"]
            local bad = builtin_blob("russian")
            bad.cards.point_values["A"] = "not a number"
            local r = templates.update(created.id, bad)
            assert.is_false(r.ok)
            assert.are.equal("invalid_rule_config", r.error.code)
            assert.are.equal(snapshot, store["templates.json"])
        end)

        it("rejects a deferred-toggle change and leaves storage unchanged", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local snapshot = store["templates.json"]
            local bad = builtin_blob("russian")
            -- penalties.zero_tricks stays deferred until Phase 3.6's
            -- penalties task lands.
            bad.penalties.zero_tricks = "consecutive_three"
            local r = templates.update(created.id, bad)
            assert.is_false(r.ok)
            assert.are.equal("invalid_rule_config", r.error.code)
            assert.are.equal("deferred_field_changed", r.error.cause.code)
            assert.are.equal(snapshot, store["templates.json"])
        end)

        it("returns unknown_template when the id does not exist", function()
            local r = templates.update("not_real", builtin_blob("russian"))
            assert.is_false(r.ok)
            assert.are.equal("unknown_template", r.error.code)
        end)
    end)

    describe("rename", function()
        it("changes the name and persists", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            templates._tick_clock()
            local r = templates.rename(created.id, "Yours")
            assert.is_true(r.ok)
            assert.are.equal("Yours", r.template.name)
            assert.are.equal("Yours", templates.get(created.id).name)
        end)

        it("rejects an empty name", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local r = templates.rename(created.id, "")
            assert.is_false(r.ok)
            assert.are.equal("field_required", r.error.code)
        end)

        it("returns unknown_template when the id does not exist", function()
            local r = templates.rename("not_real", "X")
            assert.is_false(r.ok)
            assert.are.equal("unknown_template", r.error.code)
        end)
    end)

    describe("delete", function()
        it("removes the template and persists the new state", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local r = templates.delete(created.id)
            assert.is_true(r.ok)
            assert.is_nil(templates.get(created.id))
            local listing = templates.list()
            assert.are.equal(0, #listing.templates)
        end)

        it("returns unknown_template for an unknown id", function()
            local r = templates.delete("nope")
            assert.is_false(r.ok)
            assert.are.equal("unknown_template", r.error.code)
        end)
    end)

    describe("duplicate", function()
        it("produces a new id and a name suffixed with ' copy'", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local r = templates.duplicate(created.id)
            assert.is_true(r.ok)
            assert.are_not.equal(created.id, r.template.id)
            assert.are.equal("Mine copy", r.template.name)
            assert.are.equal("russian", r.template.parentTemplateId)
        end)

        it("preserves starred and ruleConfig from the source", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            templates.set_starred(created.id, true)
            local r = templates.duplicate(created.id)
            assert.is_true(r.ok)
            assert.are.equal(true, r.template.starred)
            assert.are.equal(
                json.encode(templates.get(created.id).ruleConfig),
                json.encode(r.template.ruleConfig)
            )
        end)

        it("returns unknown_template for an unknown id", function()
            local r = templates.duplicate("nope")
            assert.is_false(r.ok)
            assert.are.equal("unknown_template", r.error.code)
        end)
    end)

    describe("set_starred", function()
        it("flips the starred flag and persists", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local r = templates.set_starred(created.id, true)
            assert.is_true(r.ok)
            assert.are.equal(true, templates.get(created.id).starred)
            templates.set_starred(created.id, false)
            assert.are.equal(false, templates.get(created.id).starred)
        end)

        it("returns unknown_template for an unknown id", function()
            local r = templates.set_starred("nope", true)
            assert.is_false(r.ok)
            assert.are.equal("unknown_template", r.error.code)
        end)
    end)

    describe("reset", function()
        it("restores the parent built-in's ruleConfig", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Mine" }).template
            local edited = builtin_blob("russian")
            edited.bidding.opening_min = 105
            assert.is_true(templates.update(created.id, edited).ok)
            local r = templates.reset(created.id)
            assert.is_true(r.ok)
            assert.are.equal(
                rule_config.to_json(rule_config.builtins.russian),
                json.encode(r.template.ruleConfig)
            )
        end)

        it("errors with parent_missing when the template is parentless", function()
            -- Persist a template with a known id but parentTemplateId = nil
            -- by importing a hand-crafted JSON.
            local blob = {
                schemaVersion = 1,
                id = "abc",
                name = "Free",
                starred = false,
                createdAt = 0,
                updatedAt = 0,
                ruleConfig = builtin_blob("russian"),
            }
            local r = templates.import(json.encode(blob))
            assert.is_true(r.ok)
            local reset = templates.reset(r.template.id)
            assert.is_false(reset.ok)
            assert.are.equal("parent_missing", reset.error.code)
        end)

        it("errors with parent_missing when parent built-in is unknown to this build", function()
            local blob = {
                schemaVersion = 1,
                id = "abc",
                name = "Imported",
                parentTemplateId = "future_variant",
                starred = false,
                createdAt = 0,
                updatedAt = 0,
                ruleConfig = builtin_blob("russian"),
            }
            local r = templates.import(json.encode(blob))
            assert.is_true(r.ok)
            local reset = templates.reset(r.template.id)
            assert.is_false(reset.ok)
            assert.are.equal("parent_missing", reset.error.code)
        end)
    end)

    describe("export and import", function()
        it("export round-trips through import as a brand-new template", function()
            local created = templates.create({ fromBuiltin = "polish", name = "MyPolish" }).template
            local exported = templates.export(created.id)
            assert.is_true(exported.ok)
            assert.is_string(exported.json)

            -- Strip the original from storage so the import path doesn't
            -- look at the source.
            templates.delete(created.id)

            local imported = templates.import(exported.json)
            assert.is_true(imported.ok)
            assert.are.equal("MyPolish", imported.template.name)
            assert.are.equal("polish", imported.template.parentTemplateId)
            -- Import always mints a new id so re-importing into the same
            -- library doesn't collide.
            assert.are_not.equal(created.id, imported.template.id)
        end)

        it("import rejects malformed JSON", function()
            local r = templates.import("{not json")
            assert.is_false(r.ok)
            assert.are.equal("json_decode_failed", r.error.code)
        end)

        it("import rejects a wrapper that fails validation", function()
            local blob = {
                schemaVersion = 1,
                name = "Missing id",
                parentTemplateId = "russian",
                ruleConfig = builtin_blob("russian"),
            }
            local r = templates.import(json.encode(blob))
            assert.is_false(r.ok)
            -- The id is regenerated by import, so the blob is salvageable
            -- when only the id is missing — but the rejection path here
            -- uses a more egregious flaw: bad ruleConfig.
            local bad_inner = {
                schemaVersion = 1,
                id = "x",
                name = "Bad",
                parentTemplateId = "russian",
                ruleConfig = { schema_version = 1 },
            }
            local r2 = templates.import(json.encode(bad_inner))
            assert.is_false(r2.ok)
            assert.are.equal("invalid_rule_config", r2.error.code)
        end)

        it("export returns unknown_template for an unknown id", function()
            local r = templates.export("nope")
            assert.is_false(r.ok)
            assert.are.equal("unknown_template", r.error.code)
        end)
    end)

    describe("load fall-back", function()
        it("returns an empty list when the file is corrupt JSON", function()
            store["templates.json"] = "{not json"
            templates._reload()
            assert.are.equal(0, #templates.list().templates)
            local err = templates.last_load_error()
            assert.is_table(err)
            assert.are.equal("json_decode_failed", err.code)
        end)

        it("returns an empty list when schemaVersion is wrong", function()
            store["templates.json"] = json.encode({ schemaVersion = 99, templates = {} })
            templates._reload()
            assert.are.equal(0, #templates.list().templates)
            local err = templates.last_load_error()
            assert.is_table(err)
            assert.are.equal("unsupported_schema_version", err.code)
        end)

        it("drops a corrupt per-template entry but keeps the good ones", function()
            local good = {
                schemaVersion = 1,
                id = "good",
                name = "Good",
                parentTemplateId = "russian",
                starred = false,
                createdAt = 0,
                updatedAt = 0,
                ruleConfig = builtin_blob("russian"),
            }
            local bad = {
                schemaVersion = 1,
                id = "bad",
                name = "Bad",
                parentTemplateId = "russian",
                starred = false,
                createdAt = 0,
                updatedAt = 0,
                -- Missing ruleConfig — invalid wrapper.
            }
            store["templates.json"] = json.encode({
                schemaVersion = 1,
                templates = { good, bad },
            })
            templates._reload()
            local listing = templates.list()
            assert.are.equal(1, #listing.templates)
            assert.are.equal("good", listing.templates[1].id)
            local err = templates.last_load_error()
            assert.is_table(err)
            assert.are.equal("per_template_invalid", err.code)
            assert.are.equal(1, err.dropped_count)
        end)
    end)

    describe("persistence round-trip", function()
        it("reloads three created templates in the same order", function()
            local a = templates.create({ fromBuiltin = "russian", name = "A" }).template
            local b = templates.create({ fromBuiltin = "polish", name = "B" }).template
            local c = templates.create({ fromBuiltin = "ukrainian", name = "C" }).template
            templates._reload()
            local listing = templates.list()
            assert.are.equal(3, #listing.templates)
            assert.are.equal(a.id, listing.templates[1].id)
            assert.are.equal(b.id, listing.templates[2].id)
            assert.are.equal(c.id, listing.templates[3].id)
        end)
    end)

    describe("active template id", function()
        local function fresh_settings()
            package.loaded["app.settings"] = nil
            local s = require("app.settings")
            local read_fn, write_fn, _ = in_memory_storage()
            s._set_storage(read_fn, write_fn)
            return s
        end

        before_each(function()
            -- The settings module is the storage backing for the active id.
            -- Reset it per-test so default lookups stay deterministic.
            fresh_settings()
        end)

        after_each(function()
            package.loaded["app.settings"] = nil
        end)

        it("get_active_id defaults to russian", function()
            assert.are.equal("russian", templates.get_active_id())
        end)

        it("set_active_id round-trips through settings", function()
            templates.set_active_id("polish")
            assert.are.equal("polish", templates.get_active_id())
        end)

        it("resolve_active_config returns the canonical built-in by default", function()
            local cfg = templates.resolve_active_config()
            assert.is_true(rule_config.is_rule_config(cfg))
            assert.are.equal(rule_config.canonical_russian, cfg)
        end)

        it("resolve_active_config returns a built-in when the id matches", function()
            templates.set_active_id("polish")
            local cfg = templates.resolve_active_config()
            assert.is_true(rule_config.is_rule_config(cfg))
            assert.are.equal(rule_config.builtins.polish, cfg)
        end)

        it("resolve_active_config returns a frozen RuleConfig from a custom template", function()
            local created = templates.create({ fromBuiltin = "russian", name = "Custom" })
            assert.is_true(created.ok)
            templates.set_active_id(created.template.id)
            local cfg = templates.resolve_active_config()
            assert.is_true(rule_config.is_rule_config(cfg))
        end)

        it("resolve_active_config falls back to canonical when the id is unknown", function()
            templates.set_active_id("does-not-exist")
            local cfg = templates.resolve_active_config()
            assert.are.equal(rule_config.canonical_russian, cfg)
        end)

        it("resolve_active_config falls back to canonical when blob invalid", function()
            -- Plant a row that survives outer-envelope validation but fails
            -- inner rule_config.try_new (set bidding to a wrong type).
            local good = builtin_blob("russian")
            good.bidding.opening_min = "not-a-number"
            local bad_template = {
                schemaVersion = 1,
                id = "broken",
                name = "Broken",
                parentTemplateId = "russian",
                starred = false,
                createdAt = 1,
                updatedAt = 1,
                ruleConfig = good,
            }
            -- Inject directly via the storage to bypass M.update validation.
            store["templates.json"] = json.encode({
                schemaVersion = 1,
                templates = { bad_template },
            })
            templates._reload()
            templates.set_active_id("broken")
            local cfg = templates.resolve_active_config()
            assert.are.equal(rule_config.canonical_russian, cfg)
        end)
    end)
end)
