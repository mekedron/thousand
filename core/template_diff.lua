-- Pure-Lua diff utility for two RuleConfig blobs (post-`to_json` plain
-- tables). Walks the schema's section/field order so the diff list
-- matches the editor's declared rendering order. List and map fields
-- compare deep — any element difference flags the whole field as
-- modified.
--
-- Typical usage by the template editor:
--   local diff = template_diff.diff(parent_blob, working_blob)
--   for _, change in ipairs(diff.changes) do
--       modified[change.path] = change
--   end
--
-- and by the picker:
--   local summary = template_diff.summarise(parent_blob, working_blob)
--   "Modified: " .. tostring(summary.total_modified)

local rule_config = require("core.rule_config")

local M = {}

local function shallow_eq_list(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function key_set(t)
    local set = {}
    for k in pairs(t) do
        set[k] = true
    end
    return set
end

local function shallow_eq_map(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    local a_keys = key_set(a)
    local b_keys = key_set(b)
    for k in pairs(a_keys) do
        if not b_keys[k] then
            return false
        end
        if a[k] ~= b[k] then
            return false
        end
    end
    for k in pairs(b_keys) do
        if not a_keys[k] then
            return false
        end
    end
    return true
end

local function values_equal(kind, a, b)
    if kind == "list" then
        return shallow_eq_list(a, b)
    elseif kind == "map" then
        return shallow_eq_map(a, b)
    else
        return a == b
    end
end

local function copy_value(kind, v)
    if kind == "list" and type(v) == "table" then
        local out = {}
        for i = 1, #v do
            out[i] = v[i]
        end
        return out
    elseif kind == "map" and type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[k] = val
        end
        return out
    end
    return v
end

local function compare(parent_blob, child_blob, on_change)
    if type(parent_blob) ~= "table" or type(child_blob) ~= "table" then
        return
    end
    for _, section in ipairs(rule_config.sections()) do
        local section_desc = rule_config.schema_for(section)
        if section_desc and parent_blob[section] and child_blob[section] then
            for _, field in ipairs(section_desc.fields) do
                local field_desc = rule_config.schema_for(section .. "." .. field)
                if field_desc then
                    local old = parent_blob[section][field]
                    local new = child_blob[section][field]
                    if not values_equal(field_desc.kind, old, new) then
                        on_change({
                            path = section .. "." .. field,
                            section = section,
                            field = field,
                            kind = field_desc.kind,
                            old = copy_value(field_desc.kind, old),
                            new = copy_value(field_desc.kind, new),
                        })
                    end
                end
            end
        end
    end
end

function M.diff(parent_blob, child_blob)
    local changes = {}
    compare(parent_blob, child_blob, function(change)
        changes[#changes + 1] = change
    end)
    return { changes = changes }
end

function M.is_modified(parent_blob, child_blob, path)
    if type(path) ~= "string" then
        return false
    end
    local result = false
    compare(parent_blob, child_blob, function(change)
        if change.path == path then
            result = true
        end
    end)
    return result
end

function M.summarise(parent_blob, child_blob)
    local by_section = {}
    local total = 0
    compare(parent_blob, child_blob, function(change)
        total = total + 1
        by_section[change.section] = (by_section[change.section] or 0) + 1
    end)
    return { total_modified = total, by_section = by_section }
end

return M
