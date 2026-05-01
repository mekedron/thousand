-- The Thousand session — a layer 2 in-memory wrapper around the engine state
-- a single game is composed of. Phase 2's first rendering pass needs a
-- single object the table scene can ask "what hands? what bid? whose turn?
-- what trump? what's on the scoreboard?" without ever touching engine
-- vocabulary.
--
-- Today the session is read-only: it builds a fresh post-deal state on
-- construction and exposes accessors. The next Phase 2 task ("Connect
-- hot-seat input to the rules engine") layers mutators on top — those will
-- thread auction.bid / talon.take / tricks.play through the same accessors
-- so the renderer's contract never changes.
--
-- Phase derivation:
--   "auction" — auction is in progress (default for a fresh session).
--   "talon"   — declarer has been chosen and the talon phase is live.
--   "tricks"  — tricks are being played.
--   "done"    — the game has produced a winner.
-- The session derives its current phase from which engine objects exist;
-- callers do not pass the phase in.
--
-- The session never mutates engine state and never imports love.* —
-- it lives in app/, which only uses love.filesystem / love.timer at the
-- module boundary, neither of which is needed here.

local deck_module = require("core.deck")
local dealing = require("core.dealing")
local auction_module = require("core.auction")
local marriages_module = require("core.marriages")
local scoring = require("core.scoring")
local rule_config = require("core.rule_config")

local Session = {}
Session.__index = Session

local M = {}

local function copy_list(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function copy_hands(hands)
    local copy = {}
    for i = 1, #hands do
        copy[i] = copy_list(hands[i])
    end
    return copy
end

local function zero_totals(player_count)
    local out = {}
    for i = 1, player_count do
        out[i] = 0
    end
    return out
end

-- Build a fresh session with a freshly shuffled deck, deal, opened auction,
-- empty marriage state and zero scores. `seed` is optional — if absent we
-- use os.time() so two consecutive launches don't replay the same hands.
-- `dealer` is optional — defaults to player 1, which makes player 2 (the
-- next seat clockwise) the forehand who acts first in the auction.
function M.new(opts)
    opts = opts or {}
    local config = opts.config or rule_config.canonical_russian
    if not rule_config.is_rule_config(config) then
        error("session.new: opts.config must be a RuleConfig", 2)
    end

    local dealer = opts.dealer or 1
    local seed = opts.seed or os.time()

    local deck = deck_module.shuffle(deck_module.build(), seed)
    local deal_result = dealing.deal(deck, config)
    if not deal_result.ok then
        error("session.new: deal failed: " .. tostring(deal_result.error.message), 2)
    end

    local auction_result = auction_module.new(config, dealer)
    if not auction_result.ok then
        error("session.new: auction.new failed: " .. tostring(auction_result.error.message), 2)
    end

    local marriages_result = marriages_module.new(config)
    if not marriages_result.ok then
        error("session.new: marriages.new failed: " .. tostring(marriages_result.error.message), 2)
    end

    local self = setmetatable({
        _config = config,
        _seed = seed,
        _dealer = dealer,
        _hands = deal_result.hands,
        _talon_cards = deal_result.talon,
        _auction = auction_result.auction,
        _talon = nil,
        _marriages = marriages_result.marriages,
        _tricks = nil,
        _scoring = nil,
        _running_totals = zero_totals(config.players.count),
        _barrel_state = scoring.initial_barrel_state(config),
        _winner = nil,
    }, Session)
    return self
end

-- Test-only factory. Production code calls M.new(opts). This lets a spec
-- (or e2e journey) construct a session in any phase — including a
-- finished game with a winner — without driving the engine through the
-- usual sequence of moves. Mirrors the `_reset` / `_set_logger` test-only
-- escape-hatch convention used in app/i18n.lua.
function M.from_state(state)
    assert(type(state) == "table", "session.from_state: state must be a table")
    local config = state.config or rule_config.canonical_russian
    if not rule_config.is_rule_config(config) then
        error("session.from_state: state.config must be a RuleConfig", 2)
    end
    local player_count = config.players.count
    local self = setmetatable({
        _config = config,
        _seed = state.seed,
        _dealer = state.dealer or 1,
        _hands = state.hands and copy_hands(state.hands) or {},
        _talon_cards = state.talon_cards and copy_list(state.talon_cards) or {},
        _auction = state.auction,
        _talon = state.talon,
        _marriages = state.marriages,
        _tricks = state.tricks,
        _scoring = state.scoring,
        _running_totals = state.running_totals and copy_list(state.running_totals)
            or zero_totals(player_count),
        _barrel_state = state.barrel_state or scoring.initial_barrel_state(config),
        _winner = state.winner,
    }, Session)
    return self
end

function Session:config()
    return self._config
end

function Session:dealer()
    return self._dealer
end

function Session:seed()
    return self._seed
end

-- The current hands as the engine sees them. Returns the active stage's
-- view: tricks.hands once tricks are in progress, else talon.hands once
-- the talon phase is live, else the deal's hands. Never returns nil.
function Session:hands()
    if self._tricks then
        return self._tricks.hands
    end
    if self._talon then
        return self._talon.hands
    end
    return self._hands
end

-- The 3 talon cards as the engine sees them. During the auction these are
-- face-down on the table; during the talon phase post-reveal they are
-- face-up; once the declarer takes them the engine's talon.talon list is
-- empty and so is the returned list.
function Session:talon_cards()
    if self._talon then
        return self._talon.talon
    end
    return self._talon_cards
end

-- True while the talon should be drawn face-down. The talon is hidden
-- during the auction and revealed for the talon phase. Once tricks begin
-- the talon is gone from the table and this returns false too — the
-- renderer will see talon_cards() as empty and draw nothing.
function Session:talon_face_down()
    return self._talon == nil and self._tricks == nil
end

-- "auction" / "talon" / "tricks" / "done". Derived from which engine
-- objects the session holds, so callers can't ask for a phase that
-- contradicts the underlying state.
function Session:current_phase()
    if self._winner then
        return "done"
    end
    if self._tricks then
        return "tricks"
    end
    if self._talon then
        return "talon"
    end
    return "auction"
end

-- The seat that should act next, or nil when the phase has no actor
-- (a finished game, or an auction that ended on all-pass).
function Session:current_turn()
    local phase = self:current_phase()
    if phase == "auction" then
        return self._auction and self._auction.turn or nil
    elseif phase == "talon" then
        return self._talon and self._talon.declarer or nil
    elseif phase == "tricks" then
        return self._tricks and self._tricks.next_to_play or nil
    end
    return nil
end

-- Highest bid currently on the table. nil pre-first-bid; non-nil through
-- talon and tricks (the contract holds for the deal once chosen).
function Session:current_bid()
    if self._talon then
        return self._talon.final_bid or self._talon.original_bid
    end
    if self._auction then
        if self._auction.status == "done" then
            return self._auction.final_bid
        end
        return self._auction.current_bid
    end
    return nil
end

-- The seat currently leading the auction (the prospective declarer).
-- During talon and tricks this is the declarer, since the auction is
-- finalised by then. nil if no bid has been made.
function Session:current_leader()
    if self._talon then
        return self._talon.declarer
    end
    if self._auction then
        if self._auction.status == "done" then
            return self._auction.declarer
        end
        return self._auction.current_leader
    end
    return nil
end

-- Active trump suit, or nil if no marriage has been declared yet. Reads
-- from the tricks layer when present (which captures the trump-flip
-- timing) and falls back to marriages otherwise.
function Session:trump()
    if self._tricks then
        return self._tricks.trump
    end
    if self._marriages then
        return self._marriages.trump
    end
    return nil
end

function Session:running_totals()
    return self._running_totals
end

function Session:barrel_state()
    return self._barrel_state
end

function Session:winner()
    return self._winner
end

-- Convenience accessor for the end-of-game scene: when a winner exists,
-- returns the running totals snapshot at game-end (which IS the final
-- scoreline). Returns nil otherwise so callers can branch on "is the
-- game over?" without inspecting two fields.
function Session:final_scores()
    if not self._winner then
        return nil
    end
    return self._running_totals
end

return M
