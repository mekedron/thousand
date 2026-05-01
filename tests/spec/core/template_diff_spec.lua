local rule_config = require("core.rule_config")
local template_diff = require("core.template_diff")

-- Two convenience helpers: a fresh canonical blob (parent), and a blob
-- with a tiny mutation we can probe. We use real RuleConfig blobs so the
-- diff walks the same field shape the editor will hand it.
local function canonical_blob()
    local cfg = rule_config.canonical_russian
    local json = require("app.json")
    local serialised = rule_config.to_json(cfg)
    return json.decode(serialised)
end

describe("core.template_diff", function()
    describe("diff", function()
        it("returns no changes when blobs are identical", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            local result = template_diff.diff(parent, child)
            assert.is_table(result)
            assert.are.equal(0, #result.changes)
        end)

        it("detects a single scalar change", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.bidding.opening_min = 110
            local result = template_diff.diff(parent, child)
            assert.are.equal(1, #result.changes)
            local change = result.changes[1]
            assert.are.equal("bidding.opening_min", change.path)
            assert.are.equal(100, change.old)
            assert.are.equal(110, change.new)
            assert.are.equal("leaf", change.kind)
        end)

        it("detects a list-field change", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.cards.trick_rank_order = { "9", "Q", "J", "K", "10", "A" }
            local result = template_diff.diff(parent, child)
            local found = false
            for _, change in ipairs(result.changes) do
                if change.path == "cards.trick_rank_order" then
                    assert.are.equal("list", change.kind)
                    assert.are.same({ "9", "J", "Q", "K", "10", "A" }, change.old)
                    assert.are.same({ "9", "Q", "J", "K", "10", "A" }, change.new)
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("detects a map-field change", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.marriages.values.spades = 100
            local result = template_diff.diff(parent, child)
            local found = false
            for _, change in ipairs(result.changes) do
                if change.path == "marriages.values" then
                    assert.are.equal("map", change.kind)
                    assert.are.equal(40, change.old.spades)
                    assert.are.equal(100, change.new.spades)
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("detects multiple changes in the same diff", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.bidding.opening_min = 110
            child.bidding.pre_talon_max = 130
            child.barrel.threshold = 900
            local result = template_diff.diff(parent, child)
            assert.are.equal(3, #result.changes)
        end)

        it("walks fields in canonical declared order", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.barrel.threshold = 900
            child.bidding.opening_min = 110
            local result = template_diff.diff(parent, child)
            assert.are.equal("bidding.opening_min", result.changes[1].path)
            assert.are.equal("barrel.threshold", result.changes[2].path)
        end)

        it("treats missing parent or child sections as no-op", function()
            local parent = {}
            local child = {}
            local result = template_diff.diff(parent, child)
            assert.are.equal(0, #result.changes)
        end)
    end)

    describe("is_modified", function()
        it("returns true for a path whose values differ", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.bidding.opening_min = 110
            assert.is_true(template_diff.is_modified(parent, child, "bidding.opening_min"))
        end)

        it("returns false for an unchanged path", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            assert.is_false(template_diff.is_modified(parent, child, "bidding.opening_min"))
        end)

        it("returns false for an unknown path", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            assert.is_false(template_diff.is_modified(parent, child, "nope.unknown"))
        end)
    end)

    describe("summarise", function()
        it("counts modifications and groups them by section", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            child.bidding.opening_min = 110
            child.bidding.pre_talon_max = 130
            child.barrel.threshold = 900
            local summary = template_diff.summarise(parent, child)
            assert.are.equal(3, summary.total_modified)
            assert.are.equal(2, summary.by_section.bidding)
            assert.are.equal(1, summary.by_section.barrel)
        end)

        it("returns zero counts for identical blobs", function()
            local parent = canonical_blob()
            local child = canonical_blob()
            local summary = template_diff.summarise(parent, child)
            assert.are.equal(0, summary.total_modified)
            assert.are.same({}, summary.by_section)
        end)
    end)
end)
