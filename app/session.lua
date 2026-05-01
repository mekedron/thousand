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
local card_module = require("core.card")
local redeal = require("core.redeal")

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
    local deal_result = dealing.deal(deck, config, { dealer = dealer })
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

-- Replace the session's deal-time state with a fresh shuffle/deal/auction
-- against the active config. Used by accept_redeal, report_misdeal, the
-- forced-redeal loop and start_next_deal — every code path that needs to
-- restart the deal in place. Bumps the seed by `seed_bump` so each
-- successive call produces a different shuffle.
local function reset_deal_state(self, dealer, seed_bump)
    self._dealer = dealer or self._dealer
    self._seed = (self._seed or os.time()) + (seed_bump or 0)
    local deal_result, auction, marriages =
        build_initial_state(self._config, self._dealer, self._seed)
    self._hands = deal_result.hands
    self._talon_cards = deal_result.talon
    self._stock = deal_result.stock
    self._trump_indicator = deal_result.trump_indicator
    self._sits_out = deal_result.sits_out
    self._leftover_for_declarer = deal_result.leftover_for_declarer
    self._auction = auction
    self._marriages = marriages
    self._talon = nil
    self._tricks = nil
    self._scoring = nil
    self._raspassy_active = false
    self._pending_trump_apply = nil
end

-- Compute the clockwise queue of non-declarer seats eligible to claim
-- the rebuy at this point in the talon phase. Drops the current
-- declarer and the sits-out seat (4-player B). Returns an ordered list
-- starting from `(declarer % count) + 1` and wrapping clockwise. Used
-- by `maybe_open_rebuy_offer` only — relies on `_talon` being live.
local function compute_rebuy_pending_seats(self)
    local count = self._config.players.count
    local declarer = self._talon.declarer
    local sits_out = self._talon.sits_out
    local seats = {}
    local seat = (declarer % count) + 1
    for _ = 1, count do
        if seat ~= declarer and seat ~= sits_out then
            seats[#seats + 1] = seat
        end
        seat = (seat % count) + 1
    end
    return seats
end

-- Open the rebuy offer when the rule fires and the queue is non-empty.
-- Called from `on_auction_end` (after the bad-talon block clears) and
-- from `decline_bad_talon_redeal`. Refuses to open when:
--   * `talon.rebuy ~= "on"`,
--   * no live talon at status "revealed",
--   * the rebuy contract isn't strictly higher than the current bid,
--   * the queue would be empty (every other seat sits out).
local function maybe_open_rebuy_offer(self)
    if self._config.talon.rebuy ~= "on" then
        return
    end
    if not self._talon or self._talon.status ~= "revealed" then
        return
    end
    local contract = self._config.talon.rebuy_contract_value
    if contract <= self._talon.final_bid then
        return
    end
    local seats = compute_rebuy_pending_seats(self)
    if #seats == 0 then
        return
    end
    self._rebuy_pending = {
        seats = seats,
        contract = contract,
        original_declarer = self._talon.declarer,
    }
end

-- Walk the entitlement detector and, for forced redeals, re-deal in
-- place. Stops on the first non-forced offer (recorded as
-- `_redeal_offer`) or when no offer is found. The 16-iteration cap is
-- a safety belt against a configuration that would loop forever — in
-- practice a forced 4-nine redeal fires once per ~1300 deals, so two
-- iterations is already pathological.
local function evaluate_entitlement_with_forced_loop(self)
    for _ = 1, 16 do
        local offer = redeal.entitled_offer(self._hands, self._config)
        if offer == nil then
            self._redeal_offer = nil
            return
        end
        if not offer.forced then
            self._redeal_offer = offer
            return
        end
        self._redeal_log[#self._redeal_log + 1] = {
            kind = offer.kind,
            seat = offer.seat,
            forced = true,
            dealer = self._dealer,
        }
        reset_deal_state(self, self._dealer, 1)
    end
    self._redeal_offer = nil
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
        _stock = deal_result.stock,
        _trump_indicator = deal_result.trump_indicator,
        _sits_out = deal_result.sits_out,
        _leftover_for_declarer = deal_result.leftover_for_declarer,
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
        -- Phase 3.6 dealing-and-redeal state.
        --   _redeal_offer: nil when no entitlement is open, otherwise
        --       { seat, kind, forced }. Forced offers are applied
        --       automatically by `evaluate_entitlement_with_forced_loop`;
        --       optional offers wait on accept_redeal/decline_redeal.
        --   _redeal_log:   list of every redeal that fired in this
        --       game, including forced auto-applies. Surfaced to the
        --       table view-model for "Redeal — four 9s" banners.
        --   _misdeal_log:  list of every misdeal report routed by
        --       report_misdeal. Banners are taken from the latest
        --       entry.
        --   _raspassy_active: true when the deal is being played out
        --       under all_pass_handling = "raspassy". Drives the
        --       raspassy_play phase, the score_raspassy hand-off,
        --       and the marriage-rejection guard.
        _redeal_offer = nil,
        _redeal_log = {},
        _misdeal_log = {},
        _raspassy_active = false,
        -- Phase 3.6 talon-variants state.
        --   _bad_talon_offer: nil unless `talon.bad_talon_redeal` fired
        --       at reveal and the declarer has not yet
        --       accepted/declined. Mirrors `_redeal_offer`'s shape
        --       ({ kind = "bad_talon", points, declarer }).
        --   _bad_talon_log:   list of bad-talon decisions in this deal
        --       (entry per accept/decline) for the table banner.
        --   _buyback_log:     list of buyback events in this deal
        --       (entry per `buyback_hand` call) for the table banner.
        --   _rebuy_pending:   nil unless `talon.rebuy = "on"` and a
        --       defender's rebuy decision is open. Shape:
        --       { seats = { ... }, contract, original_declarer }; the
        --       head of `seats` is the seat to act next.
        --   _rebuy_log:       list of rebuy decisions in this deal
        --       (entry per accept/decline) for audit and the banner.
        _bad_talon_offer = nil,
        _bad_talon_log = {},
        _buyback_log = {},
        _rebuy_pending = nil,
        _rebuy_log = {},
    }, Session)
    evaluate_entitlement_with_forced_loop(self)
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
        _stock = state.stock and copy_list(state.stock) or nil,
        _trump_indicator = state.trump_indicator,
        _sits_out = state.sits_out,
        _leftover_for_declarer = state.leftover_for_declarer and copy_list(
            state.leftover_for_declarer
        ) or nil,
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
        _redeal_offer = state.redeal_offer,
        _redeal_log = state.redeal_log or {},
        _misdeal_log = state.misdeal_log or {},
        _raspassy_active = state.raspassy_active or false,
        _bad_talon_offer = state.bad_talon_offer,
        _bad_talon_log = state.bad_talon_log or {},
        _buyback_log = state.buyback_log or {},
        _rebuy_pending = state.rebuy_pending,
        _rebuy_log = state.rebuy_log or {},
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
--
-- Phase 3.6: with `talon.flip_after_first_round = "on"`, the talon
-- stays closed during the first round of bidding and flips only when
-- the auction reaches a second round.
function Session:talon_face_down()
    if self._talon ~= nil or self._tricks ~= nil then
        return false
    end
    if self._auction and self._config.talon.flip_after_first_round == "on" then
        local rn = auction_module.round_number(self._auction)
        if rn.ok and rn.round < 2 then
            return true
        end
        if rn.ok then
            return false
        end
    end
    return true
end

-- True when `talon.hidden_on_minimum_100` is active and the current
-- contract qualifies, regardless of the viewer. The declarer-vs-seat
-- check is left to `talon_face_down_to_seat` so callers that need a
-- single boolean (the view-model's `talon.hidden_to_defenders`) can
-- read this directly.
function Session:talon_hidden_rule_active()
    if self._auction == nil then
        return false
    end
    local mode = self._config.talon.hidden_on_minimum_100
    if mode == "off" then
        return false
    end
    local final_bid = self._auction.final_bid
    if final_bid == nil then
        return false
    end
    -- "minimum_100_only" and "any_forced_100" both currently key on the
    -- declarer winning at the opening minimum — the forced-opening /
    -- forced-dealer-bid toggles that distinguish the two are still
    -- deferred. The hide condition will tighten when those land.
    return final_bid == self._config.bidding.opening_min
end

-- Per-seat talon visibility post-reveal. Honors
-- `talon.hidden_on_minimum_100`: when active and the contract is at
-- the forced floor, defenders see the talon face-down. The declarer
-- always sees their own talon. Returns false (i.e. visible) by
-- default.
function Session:talon_face_down_to_seat(seat)
    if not self:talon_hidden_rule_active() then
        return false
    end
    local declarer = self._talon and self._talon.declarer or self._auction.declarer
    if declarer == nil or seat == declarer then
        return false
    end
    return true
end

-- Whether the declarer's talon discards (passes) should render face-up
-- to defenders. Driven by `talon.open_discard`.
function Session:talon_passes_face_up()
    return self._config.talon.open_discard == "on"
end

-- "auction" / "awaiting_redeal_decision" / "talon" /
-- "awaiting_bad_talon_decision" / "awaiting_rebuy_decision" /
-- "tricks" / "raspassy_play" / "deal_done" / "done". Derived from
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
        if self._raspassy_active then
            return "raspassy_play"
        end
        return "tricks"
    end
    if self._talon then
        if self._bad_talon_offer then
            return "awaiting_bad_talon_decision"
        end
        if self._rebuy_pending then
            return "awaiting_rebuy_decision"
        end
        return "talon"
    end
    if self._redeal_offer then
        return "awaiting_redeal_decision"
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
    elseif phase == "awaiting_rebuy_decision" then -- i18n-ok: phase enum
        return self._rebuy_pending and self._rebuy_pending.seats[1] or nil
    elseif phase == "tricks" or phase == "raspassy_play" then -- i18n-ok: phase enums
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

-- The 2-player A draw stock. Returns nil for layouts without a stock,
-- otherwise a list of cards with the bottom-most entry exposed as the
-- trump indicator. The list shrinks as tricks resolve during the
-- draw-phase.
function Session:stock()
    if self._tricks then
        return self._tricks.stock
    end
    return self._stock
end

-- The face-up bottom card of the draw stock (the Schnapsen-style trump
-- indicator). Set at deal time for 2-player A and never changes — the
-- trump suit may flip on a marriage but the indicator card itself
-- stays exposed as a record.
function Session:trump_indicator()
    return self._trump_indicator
end

-- "draw" or "strict" — only meaningful while the tricks phase is
-- live and the layout uses a stock. Returns nil otherwise.
function Session:tricks_phase()
    if self._tricks then
        return self._tricks.phase
    end
    return nil
end

-- The seat that sits out this deal (4-player B), or nil if every seat
-- is active. Surfaced for the table-scene's sits-out indicator.
function Session:sits_out()
    if self._tricks and self._tricks.sits_out then
        return self._tricks.sits_out
    end
    if self._auction and self._auction.sits_out then
        return self._auction.sits_out
    end
    return self._sits_out
end

-- Mapping of seat → side (1 or 2) when partnership_mode is
-- "fixed_across_table"; nil otherwise. The table-scene reads this to
-- render partner badges and the pooled-side scoreboard row.
function Session:partnership_sides()
    if self._tricks and self._tricks.partnership_sides then
        return self._tricks.partnership_sides
    end
    if
        self._config.players.partnership_mode == "fixed_across_table"
        and self._config.players.count == 4
    then
        return { 1, 2, 1, 2 }
    end
    return nil
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

-- Build the tricks state directly. Used by both the auction → tricks
-- short-circuit (no-talon layouts) and the talon → tricks transition
-- (talon-bearing layouts). Both call sites wrap the same options.
local function start_tricks(self, hands, declarer, opts)
    opts = opts or {}
    opts.dealer = self._dealer
    if self._stock then
        opts.stock = self._stock
        opts.trump_indicator = self._trump_indicator
        if self._trump_indicator then
            opts.trump = self._trump_indicator.suit
        end
    end
    local tricks_result = tricks_module.new(self._config, hands, declarer, opts)
    if not tricks_result.ok then
        local msg = "session: tricks construction failed: " -- i18n-ok
            .. tostring(tricks_result.error.message)
        error(msg, 2)
    end
    self._tricks = tricks_result.tricks
end

-- Auction → talon (or auction → tricks for layouts with no traditional
-- talon). When the auction terminates with a declarer the session either
-- constructs the talon state for the standard flow, or — for talon.size
-- == 0 layouts (4-player A no-talon, 2-player A closed-talon stock-draw)
-- — bypasses the talon phase and goes straight to tricks. An all-pass
-- auction routes via `dealing.all_pass_handling`:
--   * "redeal":   stop the deal so the next-deal hand-off keeps the same
--                 dealer (per house-rules.md "Standard").
--   * "pass_out": stop the deal; start_next_deal rotates the dealer.
--   * "raspassy": play out the deal under reverse-scoring with no
--                 trump and no marriages.
local function on_auction_end(self)
    local a = self._auction
    if not a or a.status == "in_progress" then
        return
    end
    if a.status == "all_pass" then
        local mode = self._config.dealing.all_pass_handling
        if mode == "raspassy" then
            -- Raspassy turns the all-pass deal into a no-trump
            -- no-marriage trick-play deal. The trick engine expects
            -- 8-card hands under the canonical 3-player layout, so the
            -- 3 talon cards are distributed one each to the active
            -- seats (forehand first). Layouts where the talon doesn't
            -- divide evenly into the active-seat count are not yet
            -- supported and fall back to the redeal banner.
            local count = self._config.players.count
            local forehand = (self._dealer % count) + 1
            local sits_out = self._sits_out
            local active = {}
            local seat = forehand
            for _ = 1, count do
                if seat ~= sits_out then
                    active[#active + 1] = seat
                end
                seat = (seat % count) + 1
            end
            local talon_cards = self._talon_cards or {}
            local active_count = #active
            if active_count == 0 or (#talon_cards > 0 and #talon_cards % active_count ~= 0) then
                -- Layout cannot host raspassy under this distribution
                -- rule; fall back to the standard all-pass redeal so
                -- the deal_done banner still has a meaningful reason.
                self._deal_done = { reason = "all_pass" }
                return
            end
            if #talon_cards > 0 then
                local hands = self._hands
                local cursor = 1
                for i = 1, #talon_cards do
                    local target = active[cursor]
                    local hand = hands[target]
                    hand[#hand + 1] = talon_cards[i]
                    cursor = (cursor % active_count) + 1
                end
                self._talon_cards = {}
            end
            self._raspassy_active = true
            local tricks_result = tricks_module.new(self._config, self._hands, forehand, {
                dealer = self._dealer,
            })
            if not tricks_result.ok then
                local msg = "session: raspassy tricks construction failed: " -- i18n-ok
                    .. tostring(tricks_result.error.message)
                error(msg, 2)
            end
            self._tricks = tricks_result.tricks
            return
        end
        if mode == "pass_out" then
            self._deal_done = { reason = "all_pass_pass_out" }
            return
        end
        -- "redeal" (default).
        self._deal_done = { reason = "all_pass" }
        return
    end
    if a.status ~= "done" then
        return
    end
    if self._config.talon.size == 0 then
        -- No traditional talon: skip directly to tricks. The declarer
        -- leads the first trick (canonical Russian rule); 2-player A
        -- additionally seeds tricks with the stock and the trump
        -- indicator's suit as the initial trump.
        start_tricks(self, self._hands, a.declarer)
        return
    end

    local talon_result = talon_module.new(self._config, a, self._hands, self._talon_cards, {
        leftover_for_declarer = self._leftover_for_declarer,
    })
    if not talon_result.ok then
        local msg = "session: talon construction failed after auction: " -- i18n-ok
            .. tostring(talon_result.error.message)
        error(msg, 2)
    end
    self._talon = talon_result.talon

    -- Phase 3.6 talon-variants: bad-talon redeal eligibility check.
    -- The talon module exposes `is_bad_talon`; we evaluate it here so
    -- the offer is in place by the time the player can act on it.
    local bad_mode = self._config.talon.bad_talon_redeal
    if bad_mode ~= "off" then
        local eligible
        if bad_mode == "any_contract" then
            eligible = true
        else -- "minimum_100_only"
            -- Forced minimum-100 contract: declarer's only bid was the
            -- opening minimum and no one else bid. Forced-opening /
            -- forced-dealer-bid toggles still deferred so we approximate
            -- with the floor-bid heuristic.
            eligible = a.final_bid == self._config.bidding.opening_min
        end
        if eligible then
            local threshold = self._config.talon.bad_talon_threshold
            if talon_module.is_bad_talon(self._talon_cards, threshold, self._config) then
                local total = 0
                for _, c in ipairs(self._talon_cards) do
                    total = total + card_module.point_value(c, self._config)
                end
                self._bad_talon_offer = {
                    kind = "bad_talon",
                    declarer = a.declarer,
                    points = total,
                }
            end
        end
    end

    -- Phase 3.6 talon-variants: rebuy offer. Sequenced after the
    -- bad-talon offer so a pending bad-talon decision blocks rebuy
    -- until the declarer accepts (redeal, no rebuy) or declines
    -- (rebuy opens — see decline_bad_talon_redeal).
    if not self._bad_talon_offer then
        maybe_open_rebuy_offer(self)
    end
end

-- Talon → tricks transition. The declarer leads the first trick (the
-- canonical Russian rule); future variants will read this from
-- RuleConfig once Phase 3 wires it. 2-player B's discard credits its
-- point value to the declarer's captured pile via
-- `initial_captured_points`.
local function on_talon_end(self)
    local t = self._talon
    if not t or t.status ~= "done" then
        return
    end
    local opts = {}
    if t.discards and #t.discards > 0 then
        local seeded = {}
        for i = 1, self._config.players.count do
            seeded[i] = 0
        end
        local total = 0
        for _, c in ipairs(t.discards) do
            total = total + card_module.point_value(c, self._config)
        end
        seeded[t.declarer] = total
        opts.initial_captured_points = seeded
    end
    start_tricks(self, t.hands, t.declarer, opts)
end

-- Raspassy tricks → scoring transition. Runs scoring.score_raspassy
-- (negate captured card-points) + scoring.advance_game with synthetic
-- declarer = forehand seat (the tiebreaker case it guards never fires
-- under raspassy because every delta is non-positive). Sets the
-- deal_done sentinel with reason "raspassy_scored" so start_next_deal
-- knows to rotate the dealer.
local function on_raspassy_end(self)
    local t = self._tricks
    if not t or t.status ~= "done" then
        return
    end
    local player_count = self._config.players.count
    local forehand = (self._dealer % player_count) + 1

    local sr = scoring.score_raspassy(self._config, {
        captured_points = t.captured_points,
        running_totals = self._running_totals,
    })
    if not sr.ok then
        error("session: score_raspassy failed: " .. tostring(sr.error.message), 2)
    end
    self._scoring = sr.scoring

    local g = scoring.advance_game(self._config, {
        declarer = forehand,
        deal_index = self._deal_index,
        deltas = sr.scoring.deltas,
        running_totals_before = self._running_totals,
        barrel_state_before = self._barrel_state,
    })
    if not g.ok then
        error("session: advance_game failed (raspassy): " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    if g.game.winner then
        self._winner = g.game.winner
    else
        self._deal_done = {
            reason = "raspassy_scored",
            deal_scores = sr.scoring.deal_scores,
        }
    end
    self._raspassy_active = false
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
    if self._redeal_offer then
        return failure("awaiting_redeal_decision", "resolve the pending redeal offer first", {
            kind = self._redeal_offer.kind,
            seat = self._redeal_offer.seat,
        })
    end
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
    if self._redeal_offer then
        return failure("awaiting_redeal_decision", "resolve the pending redeal offer first", {
            kind = self._redeal_offer.kind,
            seat = self._redeal_offer.seat,
        })
    end
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

local function bad_talon_guard(self, action)
    if self._bad_talon_offer then
        local msg = "resolve the pending bad-talon offer first" -- i18n-ok
        return failure("awaiting_bad_talon_decision", msg, {
            action = action,
            kind = self._bad_talon_offer.kind,
        })
    end
    return nil
end

local function rebuy_guard(self, action)
    if self._rebuy_pending then
        local msg = "resolve the pending rebuy offer first" -- i18n-ok
        return failure("awaiting_rebuy_decision", msg, {
            action = action,
            seat = self._rebuy_pending.seats[1],
        })
    end
    return nil
end

function Session:take_talon()
    if not self._talon then
        return failure("wrong_phase", "take_talon requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local g = bad_talon_guard(self, "take_talon") -- i18n-ok: action enum
        or rebuy_guard(self, "take_talon") -- i18n-ok: action enum
    if g then
        return g
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
    local g = bad_talon_guard(self, "pass_talon") -- i18n-ok: action enum
        or rebuy_guard(self, "pass_talon") -- i18n-ok: action enum
    if g then
        return g
    end
    local result = talon_module.pass(self._talon, target_player, card)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    return { ok = true }
end

-- Polish Tysiąc 2-card direct pass. Each call pushes one talon card to
-- one opponent without the declarer ever picking the talon up. After
-- both opponents have received a card (`talon.opponent_count` calls)
-- the talon module flips status to `done` directly — there is no
-- post-talon raise — so this wrapper invokes `on_talon_end` to advance
-- into the trick-play phase.
function Session:pass_polish_talon(target_player, talon_index)
    if not self._talon then
        return failure("wrong_phase", "pass_polish_talon requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local g = bad_talon_guard(self, "pass_polish_talon") -- i18n-ok: action enum
        or rebuy_guard(self, "pass_polish_talon") -- i18n-ok: action enum
    if g then
        return g
    end
    local result = talon_module.pass_from_talon(self._talon, target_player, talon_index)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    if self._talon.status == "done" then
        on_talon_end(self)
    end
    return { ok = true }
end

-- 2-player Variant B: after the declarer takes the talon and passes one
-- card to the opponent, they must discard one face-down card to the
-- captured pile to reach 8/8. The discard's point value credits the
-- declarer's captured-points total via core.tricks's
-- initial_captured_points opt at on_talon_end.
function Session:discard_talon(card)
    if not self._talon then
        return failure("wrong_phase", "discard_talon requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local g = bad_talon_guard(self, "discard_talon") -- i18n-ok: action enum
        or rebuy_guard(self, "discard_talon") -- i18n-ok: action enum
    if g then
        return g
    end
    local result = talon_module.discard(self._talon, card)
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
    local g = bad_talon_guard(self, "raise") -- i18n-ok: action enum
        or rebuy_guard(self, "raise") -- i18n-ok: action enum
    if g then
        return g
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
    local g = bad_talon_guard(self, "skip_raise") -- i18n-ok: action enum
        or rebuy_guard(self, "skip_raise") -- i18n-ok: action enum
    if g then
        return g
    end
    local result = talon_module.skip_raise(self._talon)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    on_talon_end(self)
    return { ok = true }
end

-- Phase 3.6 talon-variants: pass-the-talon. The declarer concedes the
-- deal at the bid before play. Available only when
-- `talon.pass_the_talon = "on"`. The bid is deducted from the
-- declarer's running total; defenders score zero. Closes the deal with
-- `reason = "talon_conceded"`; `start_next_deal` rotates the dealer.
function Session:concede_deal()
    if not self._talon then
        return failure("wrong_phase", "concede_deal requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local rebuy_block = rebuy_guard(self, "concede_deal")
    if rebuy_block then
        return rebuy_block
    end
    if self._config.talon.pass_the_talon ~= "on" then
        local msg = "concede_deal requires talon.pass_the_talon = 'on'" -- i18n-ok
        return failure("concede_disabled", msg, {
            rule = self._config.talon.pass_the_talon,
        })
    end
    if self._talon.status ~= "revealed" then
        return failure("wrong_talon_phase", "concede_deal must be called before take", {
            status = self._talon.status,
        })
    end

    local declarer = self._talon.declarer
    local bid = self._talon.original_bid
    local player_count = self._config.players.count
    local deltas = {}
    for i = 1, player_count do
        deltas[i] = 0
    end
    deltas[declarer] = -bid

    local g = scoring.advance_game(self._config, {
        declarer = declarer,
        deal_index = self._deal_index,
        deltas = deltas,
        running_totals_before = self._running_totals,
        barrel_state_before = self._barrel_state,
    })
    if not g.ok then
        error("session: advance_game failed (concede): " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    if g.game.winner then
        self._winner = g.game.winner
    else
        self._deal_done = {
            reason = "talon_conceded",
            declarer = declarer,
            deal_scores = deltas,
        }
    end
    -- Drop the live talon and any open bad-talon offer; the deal is over.
    self._talon = nil
    self._bad_talon_offer = nil
    return { ok = true }
end

-- Phase 3.6 talon-variants: buyback. The declarer discards their entire
-- hand for a fresh deal at a configurable penalty. Available only when
-- `talon.buyback = "on"`. The penalty is deducted from the declarer's
-- running total directly (the deal hasn't ended — it restarts). Same
-- dealer redeals; the auction reopens.
function Session:buyback_hand()
    if not self._talon then
        return failure("wrong_phase", "buyback_hand requires the talon phase", {
            phase = self:current_phase(),
        })
    end
    local rebuy_block = rebuy_guard(self, "buyback_hand")
    if rebuy_block then
        return rebuy_block
    end
    if self._config.talon.buyback ~= "on" then
        return failure("buyback_disabled", "buyback_hand requires talon.buyback = 'on'", {
            rule = self._config.talon.buyback,
        })
    end
    if self._talon.status ~= "revealed" then
        return failure("wrong_talon_phase", "buyback_hand must be called before take", {
            status = self._talon.status,
        })
    end

    local declarer = self._talon.declarer
    local penalty = self._config.talon.buyback_penalty or 0
    local player_count = self._config.players.count
    local totals = {}
    for i = 1, player_count do
        totals[i] = self._running_totals[i]
    end
    totals[declarer] = totals[declarer] - penalty
    self._running_totals = totals
    self._buyback_log[#self._buyback_log + 1] = {
        declarer = declarer,
        dealer = self._dealer,
        penalty = penalty,
    }
    -- Restart the deal in place: same dealer, fresh shuffle, fresh
    -- auction. The bad-talon offer (if any) is naturally cleared by
    -- reset_deal_state.
    self._bad_talon_offer = nil
    self._redeal_offer = nil
    reset_deal_state(self, self._dealer, 1)
    evaluate_entitlement_with_forced_loop(self)
    return { ok = true }
end

-- Phase 3.6 talon-variants: bad-talon redeal accept/decline mutators.
-- The session never auto-decides the offer on the player's behalf; the
-- table scene drives them through the bad-talon modal. Mirrors
-- accept_redeal / decline_redeal.
function Session:bad_talon_offer_state()
    return self._bad_talon_offer
end

function Session:bad_talon_log()
    return self._bad_talon_log
end

function Session:buyback_log()
    return self._buyback_log
end

function Session:accept_bad_talon_redeal()
    if not self._bad_talon_offer then
        return failure("no_bad_talon_pending", "accept_bad_talon_redeal needs an open offer", {
            phase = self:current_phase(),
        })
    end
    self._bad_talon_log[#self._bad_talon_log + 1] = {
        kind = self._bad_talon_offer.kind,
        declarer = self._bad_talon_offer.declarer,
        points = self._bad_talon_offer.points,
        accepted = true,
        dealer = self._dealer,
    }
    self._bad_talon_offer = nil
    -- Same dealer redeals. reset_deal_state clears _talon for free.
    reset_deal_state(self, self._dealer, 1)
    evaluate_entitlement_with_forced_loop(self)
    return { ok = true }
end

function Session:decline_bad_talon_redeal()
    if not self._bad_talon_offer then
        return failure("no_bad_talon_pending", "decline_bad_talon_redeal needs an open offer", {
            phase = self:current_phase(),
        })
    end
    self._bad_talon_log[#self._bad_talon_log + 1] = {
        kind = self._bad_talon_offer.kind,
        declarer = self._bad_talon_offer.declarer,
        points = self._bad_talon_offer.points,
        accepted = false,
        dealer = self._dealer,
    }
    self._bad_talon_offer = nil
    -- Rebuy is sequenced after the bad-talon decision: a decline lets
    -- the rebuy offer fire, mirroring what happens at the end of
    -- `on_auction_end` when no bad-talon offer was ever opened.
    maybe_open_rebuy_offer(self)
    return { ok = true }
end

-- Phase 3.6 rebuy: defenders may "buy the talon away" at the fixed
-- `talon.rebuy_contract_value` after the talon is revealed. The
-- session iterates over non-declarer seats clockwise; the first
-- claimant wins. If everyone passes, control returns to the original
-- declarer's pre-take menu.

function Session:rebuy_offer_state()
    return self._rebuy_pending
end

function Session:rebuy_log()
    return self._rebuy_log
end

function Session:claim_rebuy(seat)
    if not self._rebuy_pending then
        return failure("no_rebuy_pending", "claim_rebuy needs an open offer", {
            phase = self:current_phase(),
        })
    end
    local head = self._rebuy_pending.seats[1]
    if seat ~= head then
        return failure("not_your_turn", "the rebuy offer is open for a different seat", {
            seat = seat,
            expected = head,
        })
    end
    local contract = self._rebuy_pending.contract
    local original_declarer = self._rebuy_pending.original_declarer
    local result = talon_module.rebuy(self._talon, seat, contract)
    if not result.ok then
        return result
    end
    self._talon = result.talon
    self._rebuy_log[#self._rebuy_log + 1] = {
        seat = seat,
        accepted = true,
        contract = contract,
        from_declarer = original_declarer,
        dealer = self._dealer,
    }
    self._rebuy_pending = nil
    return { ok = true }
end

function Session:decline_rebuy(seat)
    if not self._rebuy_pending then
        return failure("no_rebuy_pending", "decline_rebuy needs an open offer", {
            phase = self:current_phase(),
        })
    end
    local head = self._rebuy_pending.seats[1]
    if seat ~= head then
        return failure("not_your_turn", "the rebuy offer is open for a different seat", {
            seat = seat,
            expected = head,
        })
    end
    self._rebuy_log[#self._rebuy_log + 1] = {
        seat = seat,
        accepted = false,
        contract = self._rebuy_pending.contract,
        from_declarer = self._rebuy_pending.original_declarer,
        dealer = self._dealer,
    }
    table.remove(self._rebuy_pending.seats, 1)
    if #self._rebuy_pending.seats == 0 then
        self._rebuy_pending = nil
    end
    return { ok = true }
end

-- Marriage + trick mutators --------------------------------------------

function Session:declare_marriage(player, suit)
    if self._raspassy_active then
        return failure("marriages_disabled_in_raspassy", "raspassy plays without marriages", {
            phase = self:current_phase(),
        })
    end
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
            if self._raspassy_active then
                on_raspassy_end(self)
            else
                on_tricks_end(self)
            end
        end
    end
    return { ok = true }
end

-- Redeal / misdeal API -------------------------------------------------
--
-- The session never auto-decides an optional redeal offer on the
-- player's behalf — accept_redeal / decline_redeal are caller-driven.
-- The Phase 2 hot-seat scene drives them through the redeal modal in
-- `ui/scenes/table.lua`; the future Phase 4 AI player layer
-- (`app/ai/`) will call them from its decision routine when an AI
-- seat is the entitled player. The decision heuristic ("hold this
-- weak hand or take the redeal?") belongs to `app/ai/`, not here.
-- Mandatory entitlements (e.g. four_nine_redeal = "mandatory") are
-- already auto-applied by `evaluate_entitlement_with_forced_loop`
-- and never reach a decision routine — they show up in
-- `redeal_log()` after the fact for the banner.

-- The current open redeal offer. nil unless an optional 4-nine /
-- 4-jack / 3-nine / weak-hand entitlement is waiting on the player's
-- accept-or-decline call. Mandatory entitlements are auto-applied and
-- recorded in `redeal_log()` instead of being surfaced here.
function Session:redeal_offer()
    return self._redeal_offer
end

-- Apply the current redeal offer. Re-shuffles the deck (with a bumped
-- seed) and re-deals at the same dealer, then re-evaluates entitlement
-- so the player can chain optional offers if a follow-up condition
-- fires. Records the acceptance in `_redeal_log` for the banner.
function Session:accept_redeal()
    if not self._redeal_offer then
        return failure("no_redeal_pending", "accept_redeal needs an open offer", {
            phase = self:current_phase(),
        })
    end
    self._redeal_log[#self._redeal_log + 1] = {
        kind = self._redeal_offer.kind,
        seat = self._redeal_offer.seat,
        forced = false,
        accepted = true,
        dealer = self._dealer,
    }
    self._redeal_offer = nil
    reset_deal_state(self, self._dealer, 1)
    evaluate_entitlement_with_forced_loop(self)
    return { ok = true }
end

-- Decline the current redeal offer. Clears `_redeal_offer` and leaves
-- the auction in place; the player can now bid or pass as normal.
-- Recorded in `_redeal_log` so the UI's "Optional redeal: declined"
-- banner has a hook.
function Session:decline_redeal()
    if not self._redeal_offer then
        return failure("no_redeal_pending", "decline_redeal needs an open offer", {
            phase = self:current_phase(),
        })
    end
    self._redeal_log[#self._redeal_log + 1] = {
        kind = self._redeal_offer.kind,
        seat = self._redeal_offer.seat,
        forced = false,
        accepted = false,
        dealer = self._dealer,
    }
    self._redeal_offer = nil
    return { ok = true }
end

-- Report a misdeal. Routed by `dealing.misdeal_handling`:
--   * "standard":     same dealer redeals, no penalty.
--   * "soft_penalty": rotate dealer, redeal.
--   * "flat_penalty": deduct `dealing.misdeal_flat_penalty` from the
--                     current dealer's running total, redeal with the
--                     same dealer.
-- Records the event in `_misdeal_log` for the banner.
function Session:report_misdeal()
    if self._winner then
        return failure("game_over", "cannot report a misdeal once the game is won", {
            winner = self._winner,
        })
    end
    if self._tricks or self._talon then
        return failure("wrong_phase", "report_misdeal must run before the auction resolves", {
            phase = self:current_phase(),
        })
    end
    local mode = self._config.dealing.misdeal_handling
    local player_count = self._config.players.count
    local entry = {
        handling = mode,
        dealer = self._dealer,
        penalty = 0,
    }
    local new_dealer = self._dealer
    if mode == "soft_penalty" then
        new_dealer = (self._dealer % player_count) + 1
    elseif mode == "flat_penalty" then
        local penalty = self._config.dealing.misdeal_flat_penalty
        local totals = {}
        for i = 1, player_count do
            totals[i] = self._running_totals[i]
        end
        totals[self._dealer] = totals[self._dealer] - penalty
        self._running_totals = totals
        entry.penalty = penalty
    end
    self._misdeal_log[#self._misdeal_log + 1] = entry
    -- Drop any pending redeal offer; the dealer just changed (or the
    -- penalty just landed) and the about-to-fire deal will produce a
    -- fresh entitlement evaluation anyway.
    self._redeal_offer = nil
    reset_deal_state(self, new_dealer, 1)
    evaluate_entitlement_with_forced_loop(self)
    return { ok = true }
end

-- Read-only access to the running redeal log. The table view-model
-- consumes this to render the latest banner (auto-applied forced
-- redeals appear here; optional accept/decline events too). Each
-- entry: { kind, seat, forced, accepted?, dealer }.
function Session:redeal_log()
    return self._redeal_log
end

-- Read-only access to the misdeal log. Each entry:
-- { handling, dealer, penalty }. The banner derives from the latest
-- entry until the next deal starts.
function Session:misdeal_log()
    return self._misdeal_log
end

-- True while the deal is being played out under
-- `all_pass_handling = "raspassy"`. The table view-model uses this to
-- hide bid/contract/trump indicators and the table scene to render the
-- raspassy banner.
function Session:raspassy_active()
    return self._raspassy_active
end

-- Game-loop hand-off ----------------------------------------------------

-- Construct a fresh deal under the same rules, with the dealer rotated
-- per `dealing.all_pass_handling` and running totals carried forward.
-- Used by the deal-done banner's "Next deal" button. Refuses once a
-- winner exists — the game is over and the table scene should hand off
-- to the end-of-game scene instead.
--
-- Dealer rotation:
--   * reason "all_pass" (i.e. all_pass_handling = "redeal")  → keep
--     same dealer (per house-rules.md "Standard").
--   * reasons "all_pass_pass_out" / "raspassy_scored" / "scored" →
--     rotate dealer clockwise.
function Session:start_next_deal()
    if self._winner then
        return failure("game_over", "cannot start a new deal once the game is won", {
            winner = self._winner,
        })
    end
    local player_count = self._config.players.count
    -- "all_pass" means dealing.all_pass_handling = "redeal": same
    -- dealer redeals (per house-rules.md "Standard"). Every other
    -- reason rotates clockwise.
    local prev_reason = self._deal_done and self._deal_done.reason or "scored"
    local next_dealer
    if prev_reason == "all_pass" then
        next_dealer = self._dealer
    else
        next_dealer = (self._dealer % player_count) + 1
    end

    self._deal_done = nil
    self._deal_index = self._deal_index + 1
    -- The redeal/misdeal banners are per-deal; clear them before the
    -- next deal so a previous deal's events don't leak into the new
    -- one's view-model.
    self._redeal_log = {}
    self._misdeal_log = {}
    self._bad_talon_log = {}
    self._buyback_log = {}
    self._rebuy_log = {}
    self._bad_talon_offer = nil
    self._rebuy_pending = nil
    reset_deal_state(self, next_dealer, self._deal_index)
    evaluate_entitlement_with_forced_loop(self)
    return { ok = true }
end

return M
