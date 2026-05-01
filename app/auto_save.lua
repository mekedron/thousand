-- Auto-save: one slot, JSON via love.filesystem, written on app suspend,
-- graceful quit, and after every scored deal.
--
-- Mirrors app.settings: separate read_fn / write_fn / remove_fn closures
-- that default to love.filesystem and can be swapped for in-memory
-- storage by tests. The serialization protocol lives in core.auto_save
-- (no love.* there) — this module is the engine-side wrapper that owns
-- the filesystem I/O.
--
-- API
--   M.save(session)   → boolean    -- write the current session, or
--                                     return false on missing session.
--   M.load()          → Session?   -- restore a saved session if one is
--                                     present and valid; nil otherwise.
--                                     A finished game (winner != nil)
--                                     is treated as "no save".
--   M.clear()         → ()         -- delete the on-disk save.
--   M.exists()        → boolean    -- has a save file present?
--
-- Test hook: M._set_storage(read_fn, write_fn, remove_fn).

local json = require("app.json")
local core_auto_save = require("core.auto_save")
local session_module = require("app.session")

local M = {}

local AUTO_SAVE_PATH = "auto_save.json"

local read_fn
local write_fn
local remove_fn

local function install_default_storage()
    if read_fn and write_fn and remove_fn then
        return
    end
    if love and love.filesystem then
        read_fn = function(path)
            local info = love.filesystem.getInfo and love.filesystem.getInfo(path)
            if not info then
                return nil
            end
            local content, err = love.filesystem.read(path)
            if not content then
                return nil, err
            end
            return content
        end
        write_fn = function(path, content)
            return love.filesystem.write(path, content)
        end
        remove_fn = function(path)
            local info = love.filesystem.getInfo and love.filesystem.getInfo(path)
            if not info then
                return true
            end
            return love.filesystem.remove(path)
        end
    else
        -- No engine, no test override → in-memory transient storage so a
        -- stray require from outside a test doesn't blow up.
        local memory
        read_fn = function()
            return memory
        end
        write_fn = function(_, content)
            memory = content
            return true
        end
        remove_fn = function()
            memory = nil
            return true
        end
    end
end

-- Public API ------------------------------------------------------------

function M.save(session)
    install_default_storage()
    if session == nil then
        return false
    end
    local blob = core_auto_save.serialize(session)
    if blob == nil then
        return false
    end
    local encoded = json.encode(blob)
    return write_fn(AUTO_SAVE_PATH, encoded) and true or false
end

-- Returns a restored Session, or nil if no save is present, the file is
-- corrupt, the schema version doesn't match, the rule template is
-- unknown, or the saved game is already finished.
function M.load()
    install_default_storage()
    local content = read_fn(AUTO_SAVE_PATH)
    if not content then
        return nil
    end
    local decoded, err = json.decode(content)
    if err or type(decoded) ~= "table" then
        return nil
    end
    local state = core_auto_save.deserialize(decoded)
    if state == nil then
        return nil
    end
    -- Refuse to restore a finished game — Continue should land the user
    -- in the menu's idle state, not in a freshly-finished end-of-game
    -- scene from the previous run.
    if state.winner ~= nil then
        return nil
    end
    return session_module.from_state(state)
end

function M.clear()
    install_default_storage()
    remove_fn(AUTO_SAVE_PATH)
end

function M.exists()
    install_default_storage()
    return read_fn(AUTO_SAVE_PATH) ~= nil
end

function M.path()
    return AUTO_SAVE_PATH
end

-- Test-only: replace the love.filesystem hooks with in-memory closures
-- so a spec can drive save/load/clear without a Love2D runtime. Pass a
-- third argument if the test cares about the remove path.
function M._set_storage(reader, writer, remover)
    read_fn = reader
    write_fn = writer
    remove_fn = remover or function()
        return true
    end
end

-- Test-only: drop module state without touching storage.
function M._reset()
    read_fn = nil
    write_fn = nil
    remove_fn = nil
end

return M
