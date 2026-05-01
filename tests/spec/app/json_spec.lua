-- Unit coverage for the tiny JSON encoder/decoder. Round-trips the value
-- shapes we actually persist (settings flags, schema versions, nested
-- objects) and pins the diagnostics returned for malformed input.

local json = require("app.json")

describe("app.json", function()
    describe("encode", function()
        it("encodes nil as null", function()
            assert.are.equal("null", json.encode(nil))
        end)

        it("encodes booleans", function()
            assert.are.equal("true", json.encode(true))
            assert.are.equal("false", json.encode(false))
        end)

        it("encodes integers without decimal points", function()
            assert.are.equal("0", json.encode(0))
            assert.are.equal("1", json.encode(1))
            assert.are.equal("-42", json.encode(-42))
        end)

        it("encodes floats with up to 14 significant digits", function()
            assert.are.equal("3.14", json.encode(3.14))
        end)

        it("escapes special characters in strings", function()
            assert.are.equal('"hello"', json.encode("hello"))
            assert.are.equal('"a\\nb"', json.encode("a\nb"))
            assert.are.equal('"\\""', json.encode('"'))
            assert.are.equal('"\\\\"', json.encode("\\"))
        end)

        it("encodes flat objects with sorted keys for stable output", function()
            local out = json.encode({ b = 2, a = 1, c = 3 })
            assert.are.equal('{"a":1,"b":2,"c":3}', out)
        end)

        it("encodes nested objects", function()
            local out = json.encode({ outer = { inner = true } })
            assert.are.equal('{"outer":{"inner":true}}', out)
        end)

        it("rejects non-finite numbers", function()
            assert.has_error(function()
                json.encode(1 / 0)
            end)
            assert.has_error(function()
                json.encode(-1 / 0)
            end)
            assert.has_error(function()
                json.encode(0 / 0)
            end)
        end)

        it("encodes a dense list as a JSON array", function()
            assert.are.equal('["a","b","c"]', json.encode({ "a", "b", "c" }))
        end)

        it("encodes an empty table as a JSON object for backward compat", function()
            assert.are.equal("{}", json.encode({}))
        end)

        it("encodes a nested array inside an object", function()
            local out = json.encode({ items = { 1, 2, 3 } })
            assert.are.equal('{"items":[1,2,3]}', out)
        end)

        it("encodes an array of objects", function()
            local out = json.encode({ { a = 1 }, { a = 2 } })
            assert.are.equal('[{"a":1},{"a":2}]', out)
        end)

        it("rejects mixed-key tables (string and integer keys)", function()
            assert.has_error(function()
                json.encode({ [1] = "a", name = "mixed" })
            end)
        end)
    end)

    describe("decode", function()
        it("decodes null, booleans and numbers", function()
            assert.are.equal(true, json.decode("true"))
            assert.are.equal(false, json.decode("false"))
            assert.are.equal(nil, json.decode("null"))
            assert.are.equal(42, json.decode("42"))
            assert.are.equal(-3.14, json.decode("-3.14"))
        end)

        it("decodes strings with escape sequences", function()
            assert.are.equal("hello", json.decode('"hello"'))
            assert.are.equal("a\nb", json.decode('"a\\nb"'))
            assert.are.equal('"', json.decode('"\\""'))
            assert.are.equal("\\", json.decode('"\\\\"'))
        end)

        it("decodes flat objects", function()
            local v = json.decode('{"a":1,"b":true,"c":"hello"}')
            assert.are.same({ a = 1, b = true, c = "hello" }, v)
        end)

        it("decodes nested objects", function()
            local v = json.decode('{"outer":{"inner":true}}')
            assert.are.same({ outer = { inner = true } }, v)
        end)

        it("tolerates whitespace between tokens", function()
            local v = json.decode('  { "a" : 1 ,   "b" :  true   }  ')
            assert.are.same({ a = 1, b = true }, v)
        end)

        it("returns a diagnostic for malformed input", function()
            local v, err = json.decode("{not json}")
            assert.is_nil(v)
            assert.is_string(err)
        end)

        it("returns a diagnostic for trailing characters", function()
            local v, err = json.decode("true junk")
            assert.is_nil(v)
            assert.is_string(err)
        end)

        it("returns a diagnostic for non-string input", function()
            local v, err = json.decode(nil)
            assert.is_nil(v)
            assert.is_string(err)
        end)
    end)

    describe("decode arrays", function()
        it("decodes an empty array", function()
            assert.are.same({}, json.decode("[]"))
        end)

        it("decodes a flat array of mixed primitives", function()
            assert.are.same({ 1, "two", true, nil }, json.decode('[1,"two",true,null]'))
        end)

        it("decodes a nested array inside an object", function()
            assert.are.same({ items = { 1, 2, 3 } }, json.decode('{"items":[1,2,3]}'))
        end)
    end)

    describe("round-trip", function()
        local cases = {
            { name = "empty object", value = {} },
            { name = "settings shape", value = { schemaVersion = 1, hot_seat_privacy = true } },
            { name = "nested mix", value = { a = { b = false, c = "x" }, d = 3.5 } },
            { name = "list of strings", value = { "a", "b", "c" } },
            { name = "array of objects", value = { { suit = "hearts", rank = "K" } } },
            {
                name = "auto-save-shaped record",
                value = {
                    schemaVersion = 1,
                    hands = { { { suit = "spades", rank = "A" } } },
                    running_totals = { 100, 200, 0 },
                },
            },
        }
        for _, case in ipairs(cases) do
            it("round-trips " .. case.name, function()
                local encoded = json.encode(case.value)
                local decoded = json.decode(encoded)
                assert.are.same(case.value, decoded)
            end)
        end
    end)
end)
