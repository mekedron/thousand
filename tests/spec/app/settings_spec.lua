-- Unit coverage for the settings module. Drives the in-memory storage
-- hook so we don't depend on Love2D's filesystem.

local function fresh_settings()
    package.loaded["app.settings"] = nil
    package.loaded["app.json"] = nil
    return require("app.settings")
end

local function in_memory_storage()
    local store = {}
    return function(path)
        return store[path]
    end,
        function(path, content)
            store[path] = content
            return true
        end,
        store
end

describe("app.settings", function()
    local settings, store

    before_each(function()
        settings = fresh_settings()
        local read_fn, write_fn, s = in_memory_storage()
        store = s
        settings._set_storage(read_fn, write_fn)
    end)

    after_each(function()
        package.loaded["app.settings"] = nil
        package.loaded["app.json"] = nil
    end)

    it("returns defaults when no settings file exists", function()
        assert.are.equal(true, settings.get("hot_seat_privacy"))
    end)

    it("set persists the new value via the storage hook", function()
        settings.set("hot_seat_privacy", false)
        assert.are.equal(false, settings.get("hot_seat_privacy"))
        assert.is_string(store["settings.json"])
    end)

    it("survives a reload by reading back from storage", function()
        settings.set("hot_seat_privacy", false)
        settings.reload()
        assert.are.equal(false, settings.get("hot_seat_privacy"))
    end)

    it("rejects an unknown key", function()
        assert.has_error(function()
            settings.set("not_a_real_key", true)
        end)
    end)

    it("falls back to defaults when the file is malformed JSON", function()
        store["settings.json"] = "{not json"
        settings.reload()
        assert.are.equal(true, settings.get("hot_seat_privacy"))
    end)

    it("falls back to defaults when schemaVersion is missing", function()
        store["settings.json"] = '{"hot_seat_privacy":false}'
        settings.reload()
        assert.are.equal(true, settings.get("hot_seat_privacy"))
    end)

    it("falls back to defaults when schemaVersion is wrong", function()
        store["settings.json"] = '{"schemaVersion":99,"hot_seat_privacy":false}'
        settings.reload()
        assert.are.equal(true, settings.get("hot_seat_privacy"))
    end)

    it("preserves valid settings under the current schemaVersion", function()
        store["settings.json"] = '{"schemaVersion":1,"hot_seat_privacy":false}'
        settings.reload()
        assert.are.equal(false, settings.get("hot_seat_privacy"))
    end)

    it("ignores fields with the wrong type", function()
        store["settings.json"] = '{"schemaVersion":1,"hot_seat_privacy":"yes"}'
        settings.reload()
        -- Falls back to the default for that key, not the malformed value.
        assert.are.equal(true, settings.get("hot_seat_privacy"))
    end)

    it("reset writes the defaults back to storage", function()
        settings.set("hot_seat_privacy", false)
        settings.reset()
        assert.are.equal(true, settings.get("hot_seat_privacy"))
        assert.is_truthy(store["settings.json"]:find("true", 1, true))
    end)

    it("encodes the persisted file with the current schemaVersion", function()
        settings.set("hot_seat_privacy", false)
        local content = store["settings.json"]
        assert.is_truthy(content:find('"schemaVersion":1', 1, true))
        assert.is_truthy(content:find('"hot_seat_privacy":false', 1, true))
    end)

    describe("active_template_id", function()
        it("defaults to russian", function()
            assert.are.equal("russian", settings.get("active_template_id"))
        end)

        it("persists a custom id and survives reload", function()
            settings.set("active_template_id", "polish")
            settings.reload()
            assert.are.equal("polish", settings.get("active_template_id"))
        end)

        it("ignores a non-string active_template_id from disk", function()
            store["settings.json"] = '{"schemaVersion":1,"active_template_id":42}'
            settings.reload()
            assert.are.equal("russian", settings.get("active_template_id"))
        end)

        it("preserves a valid active_template_id from disk", function()
            store["settings.json"] = '{"schemaVersion":1,"active_template_id":"ukrainian"}'
            settings.reload()
            assert.are.equal("ukrainian", settings.get("active_template_id"))
        end)

        it("reset returns active_template_id to the canonical default", function()
            settings.set("active_template_id", "polish")
            settings.reset()
            assert.are.equal("russian", settings.get("active_template_id"))
        end)
    end)
end)
