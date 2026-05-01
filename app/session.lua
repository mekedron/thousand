-- The Thousand session — a layer 2 in-memory wrapper around the engine state
-- a single game is composed of. Phase 2's first rendering pass needs a
-- single object the table scene can ask "what hands? what bid? whose turn?
-- what trump? what's on the scoreboard?" without ever touching engine
-- vocabulary.
--
-- This layer also owns the *transitions* between phases — it is the only
-- place that builds a `core.talon` from a finalised auction, builds a
-- `core.tricks` from a finalised talon, and runs scoring on the eighth
-- trick. The scene calls high-level mutators (Session:bid, take_talon,
-- play, …) and the session forwards each call to the appropriate
-- engine module, replaces its private state, and re-derives
-- current_phase() from which engine objects exist. Every mutator returns
-- the engine's `{ ok, error }` envelope verbatim — no rewording — so
-- callers can match on engine error codes.
--
-- Phase derivation:
--   "auction"   — auction is in progress (default for a fresh session).
--   "talon"     — declarer has been chosen and the talon phase is live.
--   "tricks"    — tricks are being played.
--   "deal_done" — the deal ended (all-pass, or eight tricks scored) but
--                 nobody has crossed the target score yet — call
--                 start_next_deal to resume play.
--   "done"      — the game has produced a winner.
-- The session derives its current phase from which engine objects exist;
-- callers do not pass the phase in.
--
-- Marriage timing rule. core/marriages.lua hands the "trump effective
-- from the next trick" timing to the orchestrator. The session captures
-- this here: declare_marriage records a pending-trump-apply flag, and
-- the next trick that resolves picks up the flag and runs
-- tricks.set_trump on the trick boundary.
--
-- The session never mutates engine state and never imports love.* —
-- it lives in app/, which only uses love.filesystem / love.timer at the
-- module boundary, neither of which is needed here.

local deck_module = require("core.deck")
local dealing = require("core.dealing")
local auction_module = require("core.auction")
local talon_module = require("core.talon")
local tricks_module = require("core.tricks")
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

local function build_initial_state(config, dealer, seed)
    local deck = deck_module.shuffle(deck_module.build(), seed)
    local deal_result = dealing.deal(deck, config)
    if not deal_result.ok then
        error("session: deal failed: " .. tostring(deal_result.error.message), 2)
    end

    local auction_result = auction_module.new(config, dealer)
    if not auction_result.ok then
        error("session: auction.new failed: " .. tostring(auction_result.error.message), 2)
    end

    local marriages_result = marriages_module.new(config)
    if not marriages_result.ok then
        error("session: marriages.new failed: " .. tostring(marriages_result.error.message), 2)
    end

    return deal_result, auction_result.auction, marriages_result.marriages
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

    local deal_result, auction, marriages = build_initial_state(config, dealer, seed)

    local self = setmetatable({
        _config = config,
        _seed = seed,
        _dealer = dealer,
        _hands = deal_result.hands,
        _talon_cards = deal_result.talon,
        _auction = auction,
        _talon = nil,
        _marriages = marriages,
        _tricks = nil,
        _scoring = nil,
        _running_totals = zero_totals(config.players.count),
        _barrel_state = scoring.initial_barrel_state(config),
        _winner = nil,
        _deal_done = nil,
        _deal_index = 1,
        -- Set when declare_marriage runs and cleared once the
        -- consequent trick resolves. Drives the "trump engages from
        -- the next trick" timing rule from core/marriages.lua.
        _pending_trump_apply = nil,
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
        _deal_done = state.deal_done,
        _deal_index = state.deal_index or 1,
        _pending_trump_apply = nil,
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

-- "auction" / "talon" / "tricks" / "deal_done" / "done". Derived from
-- which engine objects the session holds, so callers can't ask for a
-- phase that contradicts the underlying state.
function Session:current_phase()
    if self._winner then
        return "done"
    end
    if self._deal_done then
        return "deal_done"
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
-- (a finished game, a deal that ended on all-pass, or the gap between
-- the eighth trick and the next-deal hand-off).
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

-- The plays in the current trick (player + card pairs in order), or nil
-- when no trick is in progress. Surfaces engine state to the table-scene
-- centre band so the renderer can show what's been played without
-- learning engine vocabulary.
function Session:current_trick()
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return nil
    end
    local plays = self._tricks.current_trick.plays
    local copy = {}
    for i = 1, #plays do
        copy[i] = { player = plays[i].player, card = plays[i].card }
    end
    local lead_suit
    if #copy >= 1 then
        lead_suit = copy[1].card.suit
    end
    return {
        plays = copy,
        lead_suit = lead_suit,
        next_to_play = self._tricks.next_to_play,
    }
end

-- The set of suits the given player can declare a marriage in right
-- now. Empty unless: the tricks phase is live, the player is on lead
-- (no plays yet on the current trick), the hand still holds K and Q of
-- the suit, and that suit hasn't been declared yet this deal. Used by
-- the table scene to decide when to surface the marriage prompt.
function Session:available_marriages(player)
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return {}
    end
    if self._tricks.next_to_play ~= player then
        return {}
    end
    if #self._tricks.current_trick.plays ~= 0 then
        return {}
    end
    local hand = self._tricks.hands[player]
    if not hand then
        return {}
    end
    local available = {}
    local detected = marriages_module.detect(hand)
    local declarations = self._marriages and self._marriages.declarations or {}
    for _, suit in ipairs(detected) do
        local already = false
        for _, d in ipairs(declarations) do
            if d.suit == suit then
                already = true
                break
            end
        end
        if not already then
            available[#available + 1] = suit
        end
    end
    return available
end

-- Return the engine's permitted plays for the player on turn. Returns
-- an empty list when not in the tricks phase or when the engine errors;
-- the caller is expected to never call this off the tricks phase.
-- Surfaced on the session so the legal-action affordances task (the
-- next Phase 2 task on the roadmap) can use the same accessor as tests.
function Session:legal_cards(player)
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return {}
    end
    local result = tricks_module.legal_cards(self._tricks, player)
    if not result.ok then
        return {}
    end
    return result.cards
end

-- A non-nil return means the deal has finished without reaching the
-- target score. The shape mirrors the table-scene "deal complete"
-- banner: `reason = "scored" | "all_pass"`, plus a snapshot of the
-- per-player deal scores when scoring ran. nil while a deal is still
-- in progress.
function Session:deal_done()
    return self._deal_done
end

-- Engine error envelopes ------------------------------------------------

local function failure(code, message, extra)
    local err = { code = code, message = message }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

-- Auction → talon transition. When the auction terminates with a
-- declarer the session immediately constructs the talon state so the
-- next mutator call (typically take_talon) finds the right shape. An
-- all-pass auction stops the deal: there is no contract to play.
local function on_auction_end(self)
    local a = self._auction
    if not a or a.status == "in_progress" then
        return
    end
    if a.status == "all_pass" then
        self._deal_done = { reason = "all_pass" }
        return
    end
    if a.status == "done" then
        local talon_result = talon_module.new(self._config, a, self._hands, self._talon_cards)
        if not talon_result.ok then
            local msg = "session: talon construction failed after auction: " -- i18n-ok
                .. tostring(talon_result.error.message)
            error(msg, 2)
        end
        self._talon = talon_result.talon
    end
end

-- Talon → tricks transition. The declarer leads the first trick (the
-- canonical Russian rule); future variants will read this from
-- RuleConfig once Phase 3 wires it.
local function on_talon_end(self)
    local t = self._talon
    if not t or t.status ~= "done" then
        return
    end
    local tricks_result = tricks_module.new(self._config, t.hands, t.declarer)
    if not tricks_result.ok then
        local msg = "session: tricks construction failed after talon: " -- i18n-ok
            .. tostring(tricks_result.error.message)
        error(msg, 2)
    end
    self._tricks = tricks_result.tricks
end

-- Tricks → scoring transition. Runs scoring.score_deal +
-- scoring.advance_game with the captured points + marriage bonuses
-- captured by the engine, then either records the winner (game ends)
-- or marks the deal_done sentinel (next deal pending).
local function on_tricks_end(self)
    local t = self._tricks
    if not t or t.status ~= "done" then
        return
    end
    local declarer = self._talon.declarer
    local bid = self._talon.final_bid

    local sd = scoring.score_deal(self._config, {
        declarer = declarer,
        bid = bid,
        captured_points = t.captured_points,
        marriage_bonuses = self._marriages.bonuses,
        running_totals = self._running_totals,
    })
    if not sd.ok then
        error("session: score_deal failed: " .. tostring(sd.error.message), 2)
    end
    self._scoring = sd.scoring

    local g = scoring.advance_game(self._config, {
        declarer = declarer,
        deal_index = self._deal_index,
        deltas = sd.scoring.deltas,
        running_totals_before = self._running_totals,
        barrel_state_before = self._barrel_state,
    })
    if not g.ok then
        error("session: advance_game failed: " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    if g.game.winner then
        self._winner = g.game.winner
    else
        self._deal_done = {
            reason = "scored",
            declarer = declarer,
            made_contract = sd.scoring.made_contract,
            deal_scores = sd.scoring.deal_scores,
        }
    end
end

-- Auction mutators ------------------------------------------------------

function Session:bid(player, amount)
    if not self._auction or self._auction.status ~= "in_progress" then
        return failure("auction_already_done", "auction has already terminated", {
            status = self._auction and self._auction.status or "unknown",
        })
    end
    local result = auction_module.bid(self._auction, player, amount)
    if not result.ok then
        return result
    end
    self._auction = result.auction
    on_auction_end(self)
    return { ok = true }
end

function Session:pass(player)
    if not self._auction or self._auction.status ~= "in_progress" then
        return failure("auction_already_done", "auction has already terminated", {
            status = self._auction and self._auction.status or "unknown",
        })
    end
    local result = auction_module.pass(self._auction, player)
    if not result.ok then
        return result
    end
    self._auction = result.auction
    on_auction_end(self)
    return { ok = true }
end

-- Talon mutators --------------------------------------------------------

function Session:take_talon()
    if not self._talon then
        return failure("wrong_phase", "take_talon requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local result = talon_module.take(self._talon)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    return { ok = true }
end

function Session:pass_talon(target_player, card)
    if not self._talon then
        return failure("wrong_phase", "pass_talon requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local result = talon_module.pass(self._talon, target_player, card)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    return { ok = true }
end

function Session:raise(amount)
    if not self._talon then
        return failure("wrong_phase", "raise requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local result = talon_module.raise(self._talon, amount)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    on_talon_end(self)
    return { ok = true }
end

function Session:skip_raise()
    if not self._talon then
        return failure("wrong_phase", "skip_raise requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local result = talon_module.skip_raise(self._talon)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    on_talon_end(self)
    return { ok = true }
end

-- Marriage + trick mutators --------------------------------------------

function Session:declare_marriage(player, suit)
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return failure("wrong_phase", "declare_marriage requires the tricks phase", {
            phase = self:current_phase(),
        })
    end
    if self._tricks.next_to_play ~= player then
        return failure("not_your_turn", "marriage requires the seat on lead", {
            player = player,
            turn = self._tricks.next_to_play,
        })
    end
    if #self._tricks.current_trick.plays ~= 0 then
        return failure("not_on_lead", "marriage declarations require an empty trick", {
            plays = #self._tricks.current_trick.plays,
        })
    end
    local hand = self._tricks.hands[player]
    local result = marriages_module.declare(self._marriages, player, suit, hand)
    if not result.ok then
        return result
    end
    self._marriages = result.marriages
    -- Schedule the trump flip for the next trick boundary; the engine
    -- enforces "set_trump only between tricks" so the application of
    -- the new trump waits for the trick to resolve.
    self._pending_trump_apply = suit
    return { ok = true }
end

function Session:play(player, card)
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return failure("wrong_phase", "play requires the tricks phase", {
            phase = self:current_phase(),
        })
    end
    local before_played = self._tricks.tricks_played
    local result = tricks_module.play(self._tricks, player, card)
    if not result.ok then
        return result
    end
    self._tricks = result.tricks

    -- Trick boundary reached — apply any pending trump and check for
    -- end-of-deal. set_trump is only legal between tricks, which is
    -- exactly the window we land in when tricks_played increments.
    if self._tricks.tricks_played > before_played then
        if self._pending_trump_apply and self._tricks.status == "in_progress" then
            local set_result = tricks_module.set_trump(self._tricks, self._pending_trump_apply)
            if not set_result.ok then
                local msg = "session: set_trump failed at trick boundary: " -- i18n-ok
                    .. tostring(set_result.error.message)
                error(msg, 2)
            end
            self._tricks = set_result.tricks
            self._pending_trump_apply = nil
        end
        if self._tricks.status == "done" then
            on_tricks_end(self)
        end
    end
    return { ok = true }
end

-- Game-loop hand-off ----------------------------------------------------

-- Construct a fresh deal under the same rules, with the dealer rotated
-- clockwise and running totals carried forward. Used by the deal-done
-- banner's "Next deal" button. Refuses once a winner exists — the game
-- is over and the table scene should hand off to the end-of-game scene
-- instead.
function Session:start_next_deal()
    if self._winner then
        return failure("game_over", "cannot start a new deal once the game is won", {
            winner = self._winner,
        })
    end
    local config = self._config
    local player_count = config.players.count
    local next_dealer = (self._dealer % player_count) + 1
    local seed = (self._seed or os.time()) + self._deal_index

    local deal_result, auction, marriages = build_initial_state(config, next_dealer, seed)

    self._dealer = next_dealer
    self._seed = seed
    self._hands = deal_result.hands
    self._talon_cards = deal_result.talon
    self._auction = auction
    self._talon = nil
    self._marriages = marriages
    self._tricks = nil
    self._scoring = nil
    self._deal_done = nil
    self._deal_index = self._deal_index + 1
    self._pending_trump_apply = nil
    return { ok = true }
end

return M
