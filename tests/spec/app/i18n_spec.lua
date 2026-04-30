local i18n = require("app.i18n")

describe("app.i18n", function()
    before_each(function()
        i18n._reset()
    end)

    describe("get_locale / set_locale", function()
        it("defaults to English", function()
            assert.are.equal("en", i18n.get_locale())
        end)

        it("can switch between bundled locales", function()
            i18n.set_locale("ru")
            assert.are.equal("ru", i18n.get_locale())
            i18n.set_locale("pl")
            assert.are.equal("pl", i18n.get_locale())
            i18n.set_locale("uk")
            assert.are.equal("uk", i18n.get_locale())
        end)

        it("rejects an unknown locale", function()
            assert.has_error(function()
                i18n.set_locale("xx")
            end)
        end)

        it("rejects a non-string locale code", function()
            assert.has_error(function()
                i18n.set_locale(42)
            end)
        end)
    end)

    describe("t()", function()
        it("looks up a key in the active locale", function()
            assert.are.equal("Thousand", i18n.t("app.title"))
            assert.are.equal("New Game", i18n.t("menu.new_game"))
        end)

        it("looks up the same key under each bundled locale", function()
            for _, code in ipairs({ "en", "ru", "pl", "uk" }) do
                i18n.set_locale(code)
                assert.are.equal("Thousand", i18n.t("app.title"))
            end
        end)

        it("interpolates %{name} placeholders from a params table", function()
            assert.are.equal("Welcome, Alice!", i18n.t("greeting.welcome", { name = "Alice" }))
        end)

        it("preserves an unsubstituted placeholder when params omits the key", function()
            assert.are.equal("Welcome, %{name}!", i18n.t("greeting.welcome", {}))
        end)

        it("returns the raw string when params is nil", function()
            assert.are.equal("Welcome, %{name}!", i18n.t("greeting.welcome"))
        end)

        it("returns the key itself when missing in Phase 0 (no fallback yet)", function()
            assert.are.equal("does.not.exist", i18n.t("does.not.exist"))
        end)

        it("rejects a non-string key", function()
            assert.has_error(function()
                i18n.t(42)
            end)
        end)
    end)
end)
