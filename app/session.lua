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

-- Phase 4.2 seat composition: per-seat human/bot binding. The session
-- carries the array so the auto-save round-trips it and the bot driver
-- has a single source of truth at tick time. Validation happens at
-- both `Session.new` and `Session.from_state` so a bad save or test
-- fixture surfaces the failure right at the entrypoint, not later when
-- the driver tries to dispatch a chooser.
local SEAT_KIND_VALUES = { human = true, bot = true }

local function validate_seat_kinds(value, count, where)
    if value == nil then
        return nil
    end
    if type(value) ~= "table" then
        error(where .. ": seat_kinds must be a table or nil", 3)
    end
    if #value ~= count then
        error(
            where
                .. ": seat_kinds length " -- i18n-ok: developer assertion
                .. tostring(#value)
                .. " disagrees with players.count " -- i18n-ok: developer assertion
                .. tostring(count),
            3
        )
    end
    local out = {}
    for i = 1, count do
        local kind = value[i]
        if not SEAT_KIND_VALUES[kind] then
            error(where .. ": seat_kinds[" .. tostring(i) .. "] must be 'human' or 'bot'", 3)
        end
        out[i] = kind
    end
    return out
end

local function zero_totals(player_count)
    local out = {}
    for i = 1, player_count do
        out[i] = 0
    end
    return out
end

-- Phase 3.6 bidding-house-rules: compute the per-seat marriage holdings
-- from `hands` so the auction's `no_contract_without_marriage` rule
-- can cap bids accurately. Returns a map { [seat] = { marriage_total
-- = N } } where the total is the sum of `config.marriages.values`
-- for every suit the seat holds both K and Q of. Empty hands yield
-- marriage_total = 0.
local function compute_holdings(hands, config)
    local holdings = {}
    for seat = 1, #hands do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (config.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end
    return holdings
end

-- Forward-declare on_auction_end so reset_deal_state can fire it
-- immediately when the deal opens with a synthetic golden-deal auction
-- already in `done` status. The full body lives a few hundred lines
-- down, after the various deal-time helpers.
local on_auction_end

local function build_initial_state(config, dealer, seed, running_totals, deal_index)
    local guard_bottom = config.dealing.cut_deck_safety == "on"
    local deck = deck_module.shuffle(deck_module.build(), seed, {
        ensure_bottom_safe = guard_bottom,
    })
    -- Phase 3.8: snapshot the bottom card before dealing consumes the
    -- deck so the cut-phase ritual can validate it without re-running
    -- the shuffle. The cut phase is opt-in via
    -- `dealing.cut_deck_nine_jack_penalty = "on"`; when off, callers
    -- ignore this value.
    local bottom_card = deck[#deck]
    local deal_result = dealing.deal(deck, config, { dealer = dealer })
    if not deal_result.ok then
        error("session: deal failed: " .. tostring(deal_result.error.message), 2)
    end

    local marriages_result = marriages_module.new(config)
    if not marriages_result.ok then
        error("session: marriages.new failed: " .. tostring(marriages_result.error.message), 2)
    end

    -- Phase 3.6 opening-game: bypass the auction during the opening N
    -- golden deals. Each player in turn becomes the forced-120
    -- declarer; the talon (or no-talon) flow runs as if a normal
    -- auction had ended at that bid.
    local golden_active, golden_seat = auction_module.is_golden_deal_active(config, deal_index or 1)
    if golden_active then
        local auction = auction_module.golden_deal_state(config, dealer, golden_seat)
        return deal_result, auction, marriages_result.marriages, true, bottom_card
    end

    local holdings = compute_holdings(deal_result.hands, config)
    local auction_result = auction_module.new(config, dealer, {
        holdings = holdings,
        running_totals = running_totals,
    })
    if not auction_result.ok then
        error("session: auction.new failed: " .. tostring(auction_result.error.message), 2)
    end

    return deal_result, auction_result.auction, marriages_result.marriages, false, bottom_card
end

-- Phase 3.8: counter-clockwise seat lookup for the cut-deck ritual.
-- 1-indexed Lua arithmetic. The codebase uses (seat % count) + 1 for
-- clockwise; the inverse is ((seat - 2) % count) + 1.
local function ccw_of(seat, count)
    return ((seat - 2) % count) + 1
end

-- Phase 3.8: open the pre-auction cut phase if the toggle is on.
-- Stash the bottom card on `_cut_phase` so `Session:cut_deck()` can
-- validate it without re-running anything. Initial cutter is the
-- seat counter-clockwise of the dealer.
local function maybe_open_cut_phase(self, bottom_card)
    if self._config.dealing.cut_deck_nine_jack_penalty ~= "on" then
        self._cut_phase = nil
        return
    end
    self._cut_phase = {
        active_cutter = ccw_of(self._dealer, self._config.players.count),
        bad_cut_count = 0,
        bottom_card = bottom_card,
    }
end

-- Replace the session's deal-time state with a fresh shuffle/deal/auction
-- against the active config. Used by accept_redeal, report_misdeal, the
-- forced-redeal loop and start_next_deal — every code path that needs to
-- restart the deal in place. Bumps the seed by `seed_bump` so each
-- successive call produces a different shuffle.
local function reset_deal_state(self, dealer, seed_bump)
    self._dealer = dealer or self._dealer
    self._seed = (self._seed or os.time()) + (seed_bump or 0)
    local deal_result, auction, marriages, golden_active, bottom_card = build_initial_state(
        self._config,
        self._dealer,
        self._seed,
        self._running_totals,
        self._deal_index
    )
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
    self._pending_lead_trump_after_marriage = nil
    -- Phase 3.6 bidding-house-rules per-deal state.
    self._revealed_hands = {}
    self._re_entry_used = {}
    self._blind_bidders = {}
    self._contra_declared = false
    self._redouble_declared = false
    self._contra_declarer = nil
    self._forced_concession_offer = nil
    self._forced_concession_resolved = false
    self._awaiting_write_off_decision = nil
    self._write_off_decision_resolved = false
    self._first_trick_played = false
    -- Phase 3.6 opening-game: track whether this deal is a forced
    -- golden deal so on_tricks_end can attribute failures and the
    -- view-model can render the banner.
    self._in_golden_deal = golden_active and true or false
    -- Phase 3.6 special contracts: cleared on every deal start; set by
    -- on_auction_end when a winning bid is structured. Read by the
    -- marriage-block guard, the open-hand visibility flag, and the
    -- named-contract scoring path.
    self._active_named_contract = nil
    -- Phase 3.6 penalty house-rules: cleared on every deal start.
    -- Bolt and cross counters span deals (per-game state) and stay
    -- intact; only the per-deal recorded_penalties log resets.
    self._recorded_penalties = {}
    -- Phase 3.8 cut-deck ritual: open the cut phase if the toggle is
    -- on. The phase blocks any auction-side transition (forced
    -- redeals, golden-deal `on_auction_end`) until the cutter clears
    -- it through `Session:cut_deck()`.
    maybe_open_cut_phase(self, bottom_card)
    if not self._cut_phase and golden_active then
        -- Drive the auction-end transition immediately so the talon
        -- (or no-talon trick start, under templates with `talon.size =
        -- 0`) is in place from the first frame.
        on_auction_end(self)
    end
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

-- Phase 3.9: open the pre-tricks write-off / сдача prompt. The book
-- frames write-off as a one-shot decision the declarer makes after
-- seeing the widow — between talon take and the pass step in the
-- standard 3-card layout, or between talon reveal and the two opponent
-- passes in the Polish 2-card `pass_without_taking` distribution.
-- Refuses to open when:
--   * `bidding.write_off ~= "on"` (toggle off);
--   * the declarer has already chosen this deal
--     (`_write_off_decision_resolved`);
--   * an offer is already pending (`_awaiting_write_off_decision`);
--   * no live talon, or a bad-talon / rebuy decision is still open;
--   * the talon is not at the right transition point — `awaiting_pass`
--     for the take-then-pass distributions, or `revealed` with
--     `pass_without_taking` for the Polish direct-pass path;
--   * the active bid is structured (named contract): write-off is
--     numeric-only per the 3.7 scoring contract.
local function maybe_open_write_off_prompt(self)
    if self._awaiting_write_off_decision then
        return
    end
    if self._write_off_decision_resolved then
        return
    end
    if self._config.bidding.write_off ~= "on" then
        return
    end
    local t = self._talon
    if not t then
        return
    end
    if self._bad_talon_offer or self._rebuy_pending then
        return
    end
    local ready = false
    local status = t.status
    if status == "awaiting_pass" then -- i18n-ok: talon status enum
        ready = true
    elseif status == "awaiting_discard" then -- i18n-ok: talon status enum
        ready = true
    elseif status == "revealed" then -- i18n-ok: talon status enum
        if t.distribution == "pass_without_taking" then -- i18n-ok: talon distribution enum
            ready = true
        end
    end
    if not ready then
        return
    end
    local declarer = t.declarer
    if declarer == nil then
        return
    end
    local bid = t.final_bid or t.original_bid
    if type(bid) ~= "number" then
        return
    end
    self._awaiting_write_off_decision = {
        declarer = declarer,
        bid = bid,
        split_mode = self._config.bidding.write_off_split,
    }
end

-- Walk the entitlement detector and, for forced redeals, re-deal in
-- place. Stops on the first non-forced offer (recorded as
-- `_redeal_offer`) or when no offer is found. The 16-iteration cap is
-- a safety belt against a configuration that would loop forever — in
-- practice a forced 4-nine redeal fires once per ~1300 deals, so two
-- iterations is already pathological.
--
-- Phase 3.8: while a cut phase is open, the forced-redeal sweep is
-- deferred until the cutter clears it (re-shuffling under the
-- player's nose would invalidate the bottom-card check the ritual
-- relies on). `Session:cut_deck()` runs this loop after the phase
-- clears, so the entitlement check still happens on the final deck.
local function evaluate_entitlement_with_forced_loop(self)
    if self._cut_phase then
        return
    end
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
        -- A forced redeal that re-opens the cut phase (toggle on)
        -- must defer too. The cut clears it before any further
        -- entitlement re-check, so break here.
        if self._cut_phase then
            return
        end
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
    local seat_kinds = validate_seat_kinds(opts.seat_kinds, config.players.count, "session.new")

    local initial_running_totals = zero_totals(config.players.count)
    local deal_result, auction, marriages, golden_active, bottom_card =
        build_initial_state(config, dealer, seed, initial_running_totals, 1)

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
        _running_totals = initial_running_totals,
        _barrel_state = scoring.initial_barrel_state(config),
        _winner = nil,
        _deal_done = nil,
        _deal_index = 1,
        -- Phase 3.6 endgame house-rules. `_effective_target` carries
        -- the elevated target produced by `tiebreaker = "continuation"`
        -- across deals: it starts at the canonical target_score and
        -- jumps +500 each time the continuation event fires. Saved
        -- games round-trip this so a continuation that happened in deal
        -- 5 still applies to deal 6.
        _effective_target = config.endgame.target_score,
        -- `_in_golden_deal` and `_golden_deal_failures` track the
        -- opening-game forced-contract sequence. The flag is true while
        -- the current deal is one of the opening N golden deals;
        -- failures accumulates across the round so
        -- `golden_deal_failure_handling` can decide what to do at the
        -- end of the sequence.
        _in_golden_deal = golden_active and true or false,
        _golden_deal_failures = 0,
        -- Set when declare_marriage runs and cleared once the
        -- consequent trick resolves. Drives the "trump engages from
        -- the next trick" timing rule from core/marriages.lua.
        _pending_trump_apply = nil,
        -- Phase 3.6 lead_trump_after_marriage = "on": set on
        -- declare_marriage, applied to tricks state at the next trick
        -- boundary so the trick AFTER the marriage trick is restricted
        -- to a trump lead.
        _pending_lead_trump_after_marriage = nil,
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
        -- Phase 3.6 bidding-house-rules per-deal state.
        --   _revealed_hands: per-seat boolean — whether the player has
        --       dismissed their privacy curtain at least once this deal.
        --       Drives the `blind_bid` window: once revealed the seat
        --       can no longer declare blind.
        --   _re_entry_used:   per-seat boolean — whether the player has
        --       exercised their single `re_entry_after_pass` claim this
        --       deal.
        --   _contra_declared / _redouble_declared / _contra_declarer:
        --       track the doubling sub-phase the contra toggle gates.
        --       Read by `contract_multiplier()` and the view-model.
        --   _forced_concession_offer: nil or a record set by
        --       `on_auction_end` when `forced_bid_concession` fires
        --       under the dealer-forced-bid path. The session enters
        --       the `awaiting_forced_concession_decision` phase until
        --       the declarer accepts (`concede_forced_bid`) or
        --       declines (`decline_forced_bid`).
        --   _first_trick_played: gate for the contra-window accessor;
        --       flipped on the first `Session:play` invocation that
        --       resolves a card into a trick.
        _revealed_hands = {},
        _re_entry_used = {},
        _blind_bidders = {},
        _contra_declared = false,
        _redouble_declared = false,
        _contra_declarer = nil,
        _forced_concession_offer = nil,
        -- Phase 3.9 write-off prompt. `_awaiting_write_off_decision` is
        -- nil unless the declarer is currently being prompted between
        -- talon take and the pass step (or between talon reveal and the
        -- Polish opponent passes). Shape: { declarer, bid, split_mode }.
        -- `_write_off_decision_resolved` flips true once the declarer
        -- chooses (accept_play / write_off) so the helper does not
        -- re-prompt later in the same deal — e.g. after a bad-talon
        -- decline or a defender's rebuy declines reopens the talon.
        _awaiting_write_off_decision = nil,
        _write_off_decision_resolved = false,
        _first_trick_played = false,
        -- Phase 3.6 marriage-house-rules per-deal state.
        --   _pre_first_trick_marriage_queue: nil unless
        --       `marriage_announcement_timing = "pre_first_trick"` is
        --       active and at least one seat holds a marriage at the
        --       start of the tricks phase. Shape: { seats = { ... },
        --       current_index = 1 }; the head of seats is the seat
        --       to act next.
        --   _half_marriage_captures: per-seat per-suit map tracking
        --       captured K/Q halves in tricks. Awarded once per suit
        --       per non-declarer when both K and Q have been
        --       captured by the same seat under
        --       `half_marriage_capture_bonus = "on"`.
        --   _half_marriage_capture_bonuses: per-seat awarded total
        --       for the deal, fed to scoring.score_deal.
        --   _drowned_marriage_log: per-deal record of cancellations
        --       under `drowned_marriage = "retroactive_cancel"`.
        _pre_first_trick_marriage_queue = nil,
        _half_marriage_captures = {},
        _half_marriage_capture_bonuses = {},
        _drowned_marriage_log = {},
        -- Phase 3.6 special contracts: nil unless the auction
        -- terminated with a structured named bid this deal. Carries
        -- `{ kind = "mizere"|"slam"|"open_hand", value }` for the
        -- marriage-block guard, the open-hand visibility flag, and
        -- the named-contract scoring path.
        _active_named_contract = nil,
        -- Phase 3.6 penalty house-rules state.
        --   _zero_tricks_bolts: per-seat persistent bolt counter.
        --       Incremented when a seat takes zero tricks under
        --       `penalties.zero_tricks ~= "off"`; reset on threshold
        --       hit and (under `consecutive_three`) on any trick
        --       taken. Persisted across deals.
        --   _cross_count: per-seat persistent cross counter.
        --       Incremented when the declarer fails a contract under
        --       `penalties.cross = "on"`; reset on threshold hit
        --       (2 crosses). Persisted across deals.
        --   _recorded_penalties: list of per-deal violation records
        --       fed by Session:record_penalty_violation (talon-look
        --       and showing-hand). Cleared at deal start; consumed
        --       by on_tricks_end when computing the per-deal
        --       talon_look_penalty / showing_hand_penalty arrays.
        _zero_tricks_bolts = zero_totals(config.players.count),
        _cross_count = zero_totals(config.players.count),
        _recorded_penalties = {},
        -- Phase 3.7 write-off counter: per-seat persistent count of
        -- mid-deal write-offs (Session:write_off). Threshold-hit fires
        -- the configured penalty and resets the seat's counter to 0.
        -- Persisted across deals.
        _write_off_counts = zero_totals(config.players.count),
        -- Phase 3.7 no-win-streak counter: per-seat persistent count of
        -- consecutive (or total, depending on `penalties.no_win_streak`)
        -- deals where the seat did not win. "Won the deal" = declarer
        -- made contract OR defender captured positive deal_scores.
        -- Threshold-hit fires the configured penalty and resets the
        -- seat's counter to 0. Persisted across deals.
        _no_win_streak_counts = zero_totals(config.players.count),
        -- Phase 3.7 barrel-fall counter: per-seat persistent count of
        -- forward-barrel fall-offs. When `barrel.fall_count_resets_to_zero
        -- == "on"`, the third fall zeros the running total and the
        -- counter resets to 0. Persisted across deals.
        _barrel_fall_counts = zero_totals(config.players.count),
        -- Phase 3.8 cut-deck ritual state.
        --   _cut_phase: nil unless `dealing.cut_deck_nine_jack_penalty
        --       == "on"`. Otherwise { active_cutter, bad_cut_count,
        --       bottom_card }. Cleared on a good cut or on the third
        --       bad cut (which fires the −120 dealer penalty).
        --   _cut_deck_log: list of cut-phase events surfaced to the
        --       table banner. Cleared at start_next_deal so the next
        --       deal opens cleanly.
        _cut_phase = nil,
        _cut_deck_log = {},
        -- Phase 4.2 seat composition: per-seat "human"/"bot" binding.
        -- Optional — Session.new without `seat_kinds` produces a session
        -- the bot driver treats as all-human (no chooser dispatch). The
        -- new-game flow and Single Player menu entry both supply it;
        -- the auto-save round-trips it.
        _seat_kinds = seat_kinds,
    }, Session)
    -- Phase 3.8: open the cut phase before any auction-side
    -- transition. Forced redeals and the golden-deal auction-end hook
    -- defer until the cutter clears the phase, so the cut ritual is
    -- always the first interactive moment of the deal.
    maybe_open_cut_phase(self, bottom_card)
    if not self._cut_phase then
        evaluate_entitlement_with_forced_loop(self)
        -- Phase 3.6 opening-game: drive the auction-end transition so the
        -- talon (or no-talon trick start) is in place from the first frame
        -- when the deal opens with a synthetic golden-deal auction.
        if self._in_golden_deal and self._auction and self._auction.status == "done" then
            on_auction_end(self)
        end
    end
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
        _effective_target = state.effective_target or config.endgame.target_score,
        _in_golden_deal = state.in_golden_deal or false,
        _golden_deal_failures = state.golden_deal_failures or 0,
        _pending_trump_apply = nil,
        _pending_lead_trump_after_marriage = nil,
        _redeal_offer = state.redeal_offer,
        _redeal_log = state.redeal_log or {},
        _misdeal_log = state.misdeal_log or {},
        _raspassy_active = state.raspassy_active or false,
        _bad_talon_offer = state.bad_talon_offer,
        _bad_talon_log = state.bad_talon_log or {},
        _buyback_log = state.buyback_log or {},
        _rebuy_pending = state.rebuy_pending,
        _rebuy_log = state.rebuy_log or {},
        _revealed_hands = state.revealed_hands or {},
        _re_entry_used = state.re_entry_used or {},
        _blind_bidders = state.blind_bidders or {},
        _contra_declared = state.contra_declared or false,
        _redouble_declared = state.redouble_declared or false,
        _contra_declarer = state.contra_declarer,
        _forced_concession_offer = state.forced_concession_offer,
        _awaiting_write_off_decision = state.awaiting_write_off_decision,
        _write_off_decision_resolved = state.write_off_decision_resolved or false,
        _first_trick_played = state.first_trick_played or false,
        _pre_first_trick_marriage_queue = state.pre_first_trick_marriage_queue,
        _half_marriage_captures = state.half_marriage_captures or {},
        _half_marriage_capture_bonuses = state.half_marriage_capture_bonuses or {},
        _drowned_marriage_log = state.drowned_marriage_log or {},
        _active_named_contract = state.active_named_contract,
        _zero_tricks_bolts = state.zero_tricks_bolts or zero_totals(player_count),
        _cross_count = state.cross_count or zero_totals(player_count),
        _recorded_penalties = state.recorded_penalties or {},
        _write_off_counts = state.write_off_counts or zero_totals(player_count),
        _no_win_streak_counts = state.no_win_streak_counts or zero_totals(player_count),
        _barrel_fall_counts = state.barrel_fall_counts or zero_totals(player_count),
        -- Phase 3.8 cut-deck ritual: nil for old saves and saves
        -- where the toggle is off; otherwise carries the in-progress
        -- ritual state. The log is empty for old saves so the banner
        -- has nothing to render.
        _cut_phase = state.cut_phase,
        _cut_deck_log = state.cut_deck_log or {},
        -- Phase 4.2 seat composition. Validated against the active
        -- player count so a tampered save or stale test fixture fails
        -- at restore time rather than mid-deal.
        _seat_kinds = validate_seat_kinds(state.seat_kinds, player_count, "session.from_state"),
    }, Session)
    -- Phase 3.6: when from_state restores a tricks-phase session and
    -- the active variant is pre_first_trick, re-open the queue from
    -- the held hands. Tests and saved-game restoration both rely on
    -- this hook.
    if
        self._tricks
        and self._tricks.status == "in_progress"
        and not self._pre_first_trick_marriage_queue
    then
        self:_open_pre_first_trick_window(self._tricks.hands)
    end
    return self
end

function Session:config()
    return self._config
end

-- Phase 4.2 seat composition accessors. `seat_kinds` returns nil when
-- the session was constructed without a binding (legacy Phase 2/3 paths,
-- pre-4.2 saves), and a defensive copy of the array otherwise so callers
-- cannot mutate engine state via the returned table. `set_seat_kinds`
-- replaces the binding wholesale and validates against the active player
-- count.
function Session:seat_kinds()
    if self._seat_kinds == nil then
        return nil
    end
    return copy_list(self._seat_kinds)
end

function Session:set_seat_kinds(value)
    self._seat_kinds =
        validate_seat_kinds(value, self._config.players.count, "session.set_seat_kinds")
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
        if self._pre_first_trick_marriage_queue then
            return "awaiting_pre_first_trick_marriages"
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
        if self._awaiting_write_off_decision then
            return "awaiting_write_off_decision"
        end
        return "talon"
    end
    if self._forced_concession_offer then
        return "awaiting_forced_concession_decision"
    end
    if self._redeal_offer then
        return "awaiting_redeal_decision"
    end
    -- Phase 3.8: the cut ritual fires before forced redeals and the
    -- golden-deal auction-end hook (the engine defers them until the
    -- cutter clears the phase), so the cut precedes "auction" but
    -- never overlaps the deal-done / tricks / talon stages.
    if self._cut_phase then
        return "cut"
    end
    return "auction"
end

-- Phase 4.1: classify the talon sub-step so the bot driver can route a
-- single phase ("talon") to one of the three choosers without poking
-- private fields.
--
--   * "action"      — declarer chooses take_talon | concede_deal | buyback_hand
--                     (status "revealed", non-Polish distribution).
--   * "pass"        — declarer must pass a card to an opponent
--                     (status "awaiting_pass").
--   * "polish_pass" — Polish 2-card direct pass (status "revealed",
--                     distribution "pass_without_taking").
--   * "discard"     — 2-player Variant B face-down discard
--                     (status "awaiting_discard").
--   * "raise"       — declarer chooses raise | skip_raise
--                     (status "awaiting_raise").
--   * nil           — outside the talon phase, or status "done".
function Session:talon_substate()
    if not self._talon then
        return nil
    end
    local status = self._talon.status
    if status == "revealed" then
        if self._talon.distribution == "pass_without_taking" then
            return "polish_pass" -- i18n-ok: substate enum
        end
        return "action" -- i18n-ok: substate enum
    end
    if status == "awaiting_pass" then
        return "pass" -- i18n-ok: substate enum
    end
    if status == "awaiting_discard" then
        return "discard" -- i18n-ok: substate enum
    end
    if status == "awaiting_raise" then
        return "raise" -- i18n-ok: substate enum
    end
    return nil
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
    elseif phase == "awaiting_write_off_decision" then -- i18n-ok: phase enum
        return self._awaiting_write_off_decision and self._awaiting_write_off_decision.declarer
            or nil
    elseif phase == "awaiting_pre_first_trick_marriages" then -- i18n-ok: phase enum
        local q = self._pre_first_trick_marriage_queue
        return q and q.seats[q.current_index] or nil
    elseif phase == "tricks" or phase == "raspassy_play" then -- i18n-ok: phase enums
        return self._tricks and self._tricks.next_to_play or nil
    elseif phase == "cut" then -- i18n-ok: phase enum
        return self._cut_phase and self._cut_phase.active_cutter or nil
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

-- Per-seat persistent bolt counter under
-- `penalties.zero_tricks ~= "off"`. Returns a copy so callers (the
-- table view-model in particular) cannot mutate session state.
function Session:zero_tricks_bolts()
    return copy_list(self._zero_tricks_bolts)
end

-- Per-seat persistent cross counter under `penalties.cross = "on"`.
-- Returns a copy.
function Session:cross_count()
    return copy_list(self._cross_count)
end

-- Per-seat persistent write-off counter under
-- `bidding.write_off = "on"`. Counts the number of times each seat
-- has invoked `Session:write_off`. Threshold-hit (under
-- `penalties.write_off_streak ~= "off"`) fires the configured
-- penalty and resets that seat's counter. Returns a copy so callers
-- cannot mutate session state.
function Session:write_off_counts()
    return copy_list(self._write_off_counts)
end

-- Phase 3.7 per-seat persistent no-win-streak counter under
-- `penalties.no_win_streak ~= "off"`. Counts deals where the seat
-- did not win (declarer failed contract; defender captured no deal
-- points). Threshold-hit fires the configured penalty and resets
-- the seat's counter. Returns a copy.
function Session:no_win_streak_counts()
    return copy_list(self._no_win_streak_counts)
end

-- Phase 3.7 per-seat persistent barrel-fall counter under
-- `barrel.fall_count_resets_to_zero = "on"`. Counts forward-barrel
-- fall-offs; the third fall zeros the seat's running total and
-- resets the counter. Returns a copy.
function Session:barrel_fall_counts()
    return copy_list(self._barrel_fall_counts)
end

-- Record a penalty violation for the current deal. The session
-- accumulates these and emits the matching per-seat penalty array at
-- `on_tricks_end`. Used by tests today; UI auto-trigger lands in a
-- later polish task. `kind` must be `"talon_look"` or
-- `"showing_hand"`; `seat` is a seat index in `[1, player_count]`.
function Session:record_penalty_violation(seat, kind)
    local count = self._config.players.count
    if type(seat) ~= "number" or seat < 1 or seat > count or seat ~= math.floor(seat) then
        local msg = "seat must be an integer in 1.." -- i18n-ok: internal error
        return {
            ok = false,
            error = {
                code = "bad_seat",
                message = msg .. count,
                actual = seat,
                player_count = count,
            },
        }
    end
    if kind ~= "talon_look" and kind ~= "showing_hand" then -- i18n-ok: kind enum
        local msg = "kind must be 'talon_look' or 'showing_hand'" -- i18n-ok: internal error
        return {
            ok = false,
            error = {
                code = "bad_kind",
                message = msg,
                actual = kind,
            },
        }
    end
    local pen_rules = self._config.penalties
    local amount
    if kind == "talon_look" then
        amount = 120
        if pen_rules.talon_look == "stricter" then
            -- Forfeit the deal at the active bid; fall back to 120
            -- when the auction has not produced one yet.
            local fb = self._talon and self._talon.final_bid
            if type(fb) == "number" and fb > 0 then
                amount = fb
            elseif self._auction and type(self._auction.current_bid) == "number" then
                amount = self._auction.current_bid
            end
        end
    else
        amount = 20
        if pen_rules.showing_hand == "strict" then
            local fb = self._talon and self._talon.final_bid
            if type(fb) == "number" and fb > 0 then
                amount = fb
            elseif self._auction and type(self._auction.current_bid) == "number" then
                amount = self._auction.current_bid
            else
                amount = self._config.bidding.opening_min
            end
        end
    end
    self._recorded_penalties[#self._recorded_penalties + 1] = {
        seat = seat,
        kind = kind,
        amount = amount,
    }
    return { ok = true, seat = seat, kind = kind, amount = amount }
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

-- Phase 3.6 endgame house-rules accessors.
--
-- `effective_target` carries the active winning total for the game,
-- which equals `config.endgame.target_score` until a
-- `tiebreaker == "continuation"` event fires; each event lifts it by
-- +500. Saved games round-trip this value so the next deal continues
-- against the elevated target.
function Session:effective_target()
    return self._effective_target
end

-- `in_golden_deal` is true while the current deal is one of the
-- forced-120 opening deals under `opening_game.golden_deal = "on"`.
-- The view-model renders the banner; AI seats also key off this flag
-- when the matching Phase 4.5 task lands.
function Session:in_golden_deal()
    return self._in_golden_deal == true
end

-- `golden_deal_failures` accumulates declarer-failed contracts across
-- the opening sequence. `start_next_deal` reads it to apply
-- `golden_deal_failure_handling` (`continue` is the canonical default;
-- `replay_round` and `reset` re-run the sequence).
function Session:golden_deal_failures()
    return self._golden_deal_failures or 0
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
    opts.declarer = declarer
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

    self:_open_pre_first_trick_window(hands)
end

-- Phase 3.6 marriage_announcement_timing = "pre_first_trick": open the
-- announcement window in dealer-clockwise order starting at the
-- leader. Only seats currently holding a K-Q marriage (or four aces
-- under ace_marriage ~= "off") queue up; everyone else is skipped
-- silently. Exposed as a method so `Session.from_state` can reproduce
-- the same window for tests + saved-game restoration.
function Session:_open_pre_first_trick_window(hands)
    if self._config.marriages.marriage_announcement_timing ~= "pre_first_trick" then
        return
    end
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return
    end
    local pc = self._config.players.count
    local leader = self._tricks.next_to_play
    local seats = {}
    for offset = 0, pc - 1 do
        local seat = ((leader - 1 + offset) % pc) + 1
        local has_kq = #marriages_module.detect(hands[seat]) > 0
        local has_aces = false
        if self._config.marriages.ace_marriage ~= "off" then
            local seen = {}
            for _, c in ipairs(hands[seat]) do
                if c.rank == "A" then
                    seen[c.suit] = true
                end
            end
            has_aces = seen.hearts and seen.diamonds and seen.clubs and seen.spades
        end
        if has_kq or has_aces then
            seats[#seats + 1] = seat
        end
    end
    if #seats > 0 then
        self._pre_first_trick_marriage_queue = {
            seats = seats,
            current_index = 1,
        }
    end
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
function on_auction_end(self)
    local a = self._auction
    if not a or a.status == "in_progress" then
        return
    end
    -- Phase 3.6 contra/redouble: the engine's auction state machine
    -- exposes a `doubling` sub-phase for unit-test coverage of
    -- `M.contra` / `M.redouble` / `M.skip_contra`. The session does
    -- not drive those engine mutators — it tracks doubling via the
    -- per-deal `_contra_declared` / `_redouble_declared` flags so
    -- the talon can construct immediately and the contra window
    -- spans both talon and tricks-pre-play. Treat `doubling` as
    -- `done` for downstream session transitions.
    local effective_status = a.status
    if effective_status == "doubling" then
        effective_status = "done"
    end
    -- Phase 3.6 named-contracts wiring: a winning structured (named)
    -- bid records the active contract on the session so downstream
    -- play (marriage block under mizère, open-hand visibility,
    -- named-contract scoring) can branch on it. The talon, tricks,
    -- and scoring flows continue through the same code paths a
    -- numeric bid uses.
    if effective_status == "done" and type(a.final_bid) == "table" then -- i18n-ok: status enums
        self._active_named_contract = {
            kind = a.final_bid.contract,
            value = a.final_bid.value,
        }
    end
    -- Phase 3.6 forced-bid concession: the dealer-forced-bid path
    -- (the only path that triggers concession) leaves a flag on the
    -- auction state. When the forced_bid_concession toggle is on, the
    -- session enters an awaiting-decision phase before constructing
    -- the talon — declarer can concede the deal up-front per the
    -- configured split or decline and continue into the talon.
    -- `_forced_concession_resolved` blocks re-opening once the
    -- declarer has already chosen.
    if
        effective_status == "done"
        and a.dealer_forced
        and self._config.bidding.forced_bid_concession ~= "off"
        and not self._forced_concession_resolved
    then
        self._forced_concession_offer = {
            declarer = a.declarer,
            bid = a.final_bid,
            split_mode = self._config.bidding.forced_bid_concession,
        }
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
    if effective_status ~= "done" then
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
    -- Phase 3.7 adds a parallel two-nines-in-talon trigger that
    -- shares the same offer machinery but fires on a 9-count
    -- predicate instead of a card-point sum. If both triggers
    -- evaluate true on the same talon they collapse into a single
    -- offer (the bad-talon trigger wins for breadcrumb purposes —
    -- it carries a card-point payload).
    local function eligibility_for(mode)
        if mode == "off" then
            return false
        elseif mode == "any_contract" then
            return true
        else -- "minimum_100_only"
            -- Forced minimum-100 contract: declarer's only bid was the
            -- opening minimum and no one else bid. Forced-opening /
            -- forced-dealer-bid toggles still deferred so we approximate
            -- with the floor-bid heuristic.
            return a.final_bid == self._config.bidding.opening_min
        end
    end

    local function nine_count(cards)
        local n = 0
        for _, c in ipairs(cards) do
            if c.rank == "9" then
                n = n + 1
            end
        end
        return n
    end

    local bad_mode = self._config.talon.bad_talon_redeal
    if eligibility_for(bad_mode) then
        local threshold = self._config.talon.bad_talon_threshold
        if talon_module.is_bad_talon(self._talon_cards, threshold, self._config) then
            local total = 0
            for _, c in ipairs(self._talon_cards) do
                total = total + card_module.point_value(c, self._config)
            end
            self._bad_talon_offer = {
                kind = "bad_talon",
                trigger = "bad_talon",
                declarer = a.declarer,
                points = total,
            }
        end
    end

    if not self._bad_talon_offer then
        local nines_mode = self._config.dealing.two_nines_in_talon_redeal
        if eligibility_for(nines_mode) and nine_count(self._talon_cards) == 2 then
            self._bad_talon_offer = {
                kind = "bad_talon",
                trigger = "two_nines",
                declarer = a.declarer,
            }
        end
    end

    -- Phase 3.6 talon-variants: rebuy offer. Sequenced after the
    -- bad-talon offer so a pending bad-talon decision blocks rebuy
    -- until the declarer accepts (redeal, no rebuy) or declines
    -- (rebuy opens — see decline_bad_talon_redeal).
    if not self._bad_talon_offer then
        maybe_open_rebuy_offer(self)
    end
    -- Phase 3.9: the Polish 2-card `pass_without_taking` distribution
    -- has no take step — the declarer passes directly off the revealed
    -- talon. Open the write-off prompt at the end of the auction-end
    -- block (after bad_talon / rebuy guards clear); the helper no-ops
    -- for take-then-pass distributions because the talon is still at
    -- status "revealed" without `pass_without_taking`.
    maybe_open_write_off_prompt(self)
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
        bid = nil,
        declarer_made_contract = false,
        effective_target_before = self._effective_target,
    })
    if not g.ok then
        error("session: advance_game failed (raspassy): " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    self._effective_target = g.game.effective_target_after
    if g.game.tiebreaker_continuation_event then
        self._winner = nil
    end
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
    local is_named = type(bid) == "table"

    local player_count = self._config.players.count

    -- Phase 3.6 named-contract dispatch. Structured bids
    -- (`{ kind = "named", contract, value }`) reach scoring through the
    -- dedicated named-contract path: declarer +/-value, defenders 0,
    -- bonus arrays zeroed. Success criteria are contract-specific:
    -- mizère = took zero tricks; slam = took every trick; open_hand =
    -- captured points cleared the contract value (rounded per
    -- `scoring.round_to_nearest`). The numeric-bid bonus pipeline below
    -- is skipped for named contracts.
    local sd_opts
    if is_named then
        local declarer_tricks_won = t.tricks_won[declarer] or 0
        local named_contract_made
        if bid.contract == "mizere" then
            named_contract_made = declarer_tricks_won == 0
        elseif bid.contract == "slam" then
            named_contract_made = declarer_tricks_won == t.tricks_per_deal
        elseif bid.contract == "open_hand" then
            -- Open-hand is a face-up numeric contract with doubled
            -- scoring: declarer must clear `bidding.opening_min`
            -- (canonically 100) in captured points, and the score
            -- change applied is the doubled-effective `bid.value`
            -- carried in the structured bid (200 by default).
            local opening_min = self._config.bidding.opening_min
            local nearest = self._config.scoring.round_to_nearest
            local rounded = math.floor((t.captured_points[declarer] + nearest / 2) / nearest)
                * nearest
            named_contract_made = rounded >= opening_min
        else
            local msg = "session: unknown named-contract kind: " -- i18n-ok
                .. tostring(bid.contract)
            error(msg, 2)
        end
        sd_opts = {
            declarer = declarer,
            bid = bid,
            named_contract_made = named_contract_made,
            captured_points = t.captured_points,
            running_totals = self._running_totals,
        }
    end

    local half_capture_bonuses = {}
    local ace_marriage_bonuses = {}
    for i = 1, player_count do
        half_capture_bonuses[i] = self._half_marriage_capture_bonuses[i] or 0
        ace_marriage_bonuses[i] = 0
    end
    for _, decl in ipairs(self._marriages.declarations) do
        if decl.kind == "ace_marriage" and not decl.cancelled then
            ace_marriage_bonuses[decl.player] = (ace_marriage_bonuses[decl.player] or 0)
                + decl.value
        end
    end
    -- The marriages module already credits ace-marriage values into
    -- `bonuses` on declaration. To avoid double counting, build the
    -- K-Q-only marriage_bonuses array by subtracting the ace-marriage
    -- contributions; the deal scoreboard surfaces them separately.
    local kq_bonuses = {}
    for i = 1, player_count do
        kq_bonuses[i] = self._marriages.bonuses[i] - (ace_marriage_bonuses[i] or 0)
        if kq_bonuses[i] < 0 then
            kq_bonuses[i] = 0
        end
    end
    -- Phase 3.6 trick-play house-rule bonuses. Computed from the
    -- finalised tricks state — last-trick winner, declarer trick count
    -- — and the active toggles. Each bonus array is per-seat to fit
    -- the partnership-mode pooling that score_deal already does.
    local trick_rules = self._config.tricks
    local last_trick_bonus = {}
    local slam_bonus = {}
    local slam_against_penalty = {}
    for i = 1, player_count do
        last_trick_bonus[i] = 0
        slam_bonus[i] = 0
        slam_against_penalty[i] = 0
    end
    if trick_rules.last_trick_bonus == "on" and #t.completed_tricks > 0 then
        local last_winner = t.completed_tricks[#t.completed_tricks].winner
        last_trick_bonus[last_winner] = trick_rules.last_trick_bonus_value
    end
    local declarer_tricks_won = t.tricks_won[declarer] or 0
    local bid_multiplier = 1
    if declarer_tricks_won == t.tricks_per_deal then
        if trick_rules.slam_bonus == "fixed" then
            slam_bonus[declarer] = trick_rules.slam_bonus_value
        elseif trick_rules.slam_bonus == "doubled_bid" then
            bid_multiplier = 2
        end
    end
    if trick_rules.slam_against_penalty == "on" and declarer_tricks_won == 0 then
        slam_against_penalty[declarer] = -trick_rules.slam_against_penalty_value
    end

    -- Phase 3.6 opening-game / golden_deal sub-flag effects on
    -- scoring. `_in_golden_deal` is true only during the opening N
    -- forced-120 deals. Marriage doubling multiplies the K/Q +
    -- half-capture + ace-marriage arrays before they are passed to
    -- score_deal; penalty doubling stacks onto the existing
    -- `bid_multiplier` so a failed forced contract loses 2× the bid.
    -- Non-canonical templates inherit the same behaviour by reading
    -- the sub-flags from `opening_game`.
    if self._in_golden_deal then
        local opening = self._config.opening_game
        if opening.golden_deal_marriages_doubled == "on" then
            for i = 1, player_count do
                kq_bonuses[i] = kq_bonuses[i] * 2
                half_capture_bonuses[i] = half_capture_bonuses[i] * 2
                ace_marriage_bonuses[i] = ace_marriage_bonuses[i] * 2
            end
        end
        if opening.golden_deal_penalty_doubled == "on" then
            bid_multiplier = bid_multiplier * 2
        end
    end

    -- Phase 3.6 penalty house-rules. Build five signed per-seat
    -- arrays the engine adds straight to deltas. Each array is
    -- pre-computed before score_deal so the contract check stays
    -- clean — penalties are running-total adjustments, not bonus
    -- contributions to deal_scores.
    local pen_rules = self._config.penalties
    local revoke_penalty = {}
    local talon_look_penalty = {}
    local showing_hand_penalty = {}
    local zero_tricks_penalty = {}
    local cross_penalty = {}
    for i = 1, player_count do
        revoke_penalty[i] = 0
        talon_look_penalty[i] = 0
        showing_hand_penalty[i] = 0
        zero_tricks_penalty[i] = 0
        cross_penalty[i] = 0
    end

    -- Revoke: walk the completed tricks for any tagged violations
    -- (engine flags them only under tricks.lazy_revoke = "on"). For
    -- each violation deduct the active amount from the offender and
    -- credit the opposing side. A defender revoke awards the full
    -- amount to the declarer; a declarer revoke splits it across
    -- the defenders.
    local revoke_violations = {}
    for _, completed in ipairs(t.completed_tricks or {}) do
        for _, v in ipairs(completed.revoke_violations or {}) do
            revoke_violations[#revoke_violations + 1] = v
        end
    end
    if #revoke_violations > 0 and type(bid) == "number" then
        local amount
        if pen_rules.revoke == "flat" then
            amount = 120
        elseif pen_rules.revoke == "configurable" then
            amount = pen_rules.revoke_configurable_amount
        else
            amount = bid
        end
        for _, v in ipairs(revoke_violations) do
            local offender = v.player
            revoke_penalty[offender] = revoke_penalty[offender] - amount
            if offender == declarer then
                local defenders = {}
                for i = 1, player_count do
                    if i ~= declarer then
                        defenders[#defenders + 1] = i
                    end
                end
                if #defenders > 0 then
                    local share = math.floor(amount / #defenders)
                    local rem = amount - share * #defenders
                    for k, i in ipairs(defenders) do
                        revoke_penalty[i] = revoke_penalty[i] + share + (k == 1 and rem or 0)
                    end
                end
            else
                revoke_penalty[declarer] = revoke_penalty[declarer] + amount
            end
        end
    end

    -- Zero-tricks bolts. Iterate seats; under any_three the counter
    -- accumulates without a trick-taken reset; under consecutive_three
    -- a seat that took a trick this deal resets to 0. A zero-trick
    -- seat earns one bolt (two if golden_deal_doubled is on and the
    -- deal is a golden deal). On threshold hit emit the penalty and
    -- reset.
    local new_bolts = {}
    for i = 1, player_count do
        new_bolts[i] = self._zero_tricks_bolts[i] or 0
    end
    if pen_rules.zero_tricks ~= "off" then
        local threshold = pen_rules.zero_tricks_threshold
        local penalty_amount = pen_rules.zero_tricks_penalty_amount
        local exempt_declarer = pen_rules.zero_tricks_declarer_exempt == "on"
        -- Phase 3.7 stick doubling. Either the golden-deal sub-flag or
        -- the dark-game sub-flag (or both) bumps a zero-trick seat's
        -- bolt earn from 1 to 2; doubling does not stack to 4 even
        -- when both fire — the book's wording is "doubled" per
        -- condition.
        local declarer_was_blind = self._auction and self._auction.blind_at_win == true or false
        local doubled = (pen_rules.zero_tricks_golden_deal_doubled == "on" and self._in_golden_deal)
            or (pen_rules.zero_tricks_dark_game_doubled == "on" and declarer_was_blind)
        for seat = 1, player_count do
            local won = t.tricks_won[seat] or 0
            local exempt = exempt_declarer and seat == declarer
            if won == 0 and not exempt then
                new_bolts[seat] = new_bolts[seat] + (doubled and 2 or 1)
            elseif won >= 1 and pen_rules.zero_tricks == "consecutive_three" then
                new_bolts[seat] = 0
            end
            if new_bolts[seat] >= threshold then
                zero_tricks_penalty[seat] = zero_tricks_penalty[seat] - penalty_amount
                new_bolts[seat] = 0
            end
        end
    end

    -- Talon-look / showing-hand recorded violations. Each record
    -- carries a pre-computed amount captured at API-call time.
    -- Talon-look "stricter" awards the offender's amount to the
    -- opposing side (split across defenders if offender is declarer);
    -- standard talon-look and any showing-hand mode just deduct.
    for _, rec in ipairs(self._recorded_penalties or {}) do
        local seat = rec.seat
        local amount = rec.amount
        if rec.kind == "talon_look" then
            talon_look_penalty[seat] = talon_look_penalty[seat] - amount
            if pen_rules.talon_look == "stricter" then
                if seat == declarer then
                    local defenders = {}
                    for i = 1, player_count do
                        if i ~= declarer then
                            defenders[#defenders + 1] = i
                        end
                    end
                    if #defenders > 0 then
                        local share = math.floor(amount / #defenders)
                        local rem = amount - share * #defenders
                        for k, i in ipairs(defenders) do
                            talon_look_penalty[i] = talon_look_penalty[i]
                                + share
                                + (k == 1 and rem or 0)
                        end
                    end
                else
                    talon_look_penalty[declarer] = talon_look_penalty[declarer] + amount
                end
            end
        elseif rec.kind == "showing_hand" then
            showing_hand_penalty[seat] = showing_hand_penalty[seat] - amount
        end
    end

    local cross_active = pen_rules.cross == "on"

    if not is_named then
        sd_opts = {
            declarer = declarer,
            bid = bid,
            bid_multiplier = bid_multiplier,
            captured_points = t.captured_points,
            marriage_bonuses = kq_bonuses,
            half_marriage_capture_bonuses = half_capture_bonuses,
            ace_marriage_bonuses = ace_marriage_bonuses,
            last_trick_bonus = last_trick_bonus,
            slam_bonus = slam_bonus,
            slam_against_penalty = slam_against_penalty,
            running_totals = self._running_totals,
            revoke_penalty = revoke_penalty,
            talon_look_penalty = talon_look_penalty,
            showing_hand_penalty = showing_hand_penalty,
            zero_tricks_penalty = zero_tricks_penalty,
            cross_penalty = cross_penalty,
            suppress_declarer_failed_bid_deduction = cross_active,
        }
    else
        sd_opts.revoke_penalty = revoke_penalty
        sd_opts.talon_look_penalty = talon_look_penalty
        sd_opts.showing_hand_penalty = showing_hand_penalty
        sd_opts.zero_tricks_penalty = zero_tricks_penalty
        sd_opts.cross_penalty = cross_penalty
    end
    local sd = scoring.score_deal(self._config, sd_opts)
    if not sd.ok then
        error("session: score_deal failed: " .. tostring(sd.error.message), 2)
    end

    -- Cross post-processing. The declarer's failed-bid deduction was
    -- already suppressed in the engine; here we increment the cross
    -- counter, fire the threshold penalty (mutating sd.scoring's
    -- cross_penalty + deltas in place so the deal_done payload and
    -- advance_game both see the final figures), and reset on hit.
    if cross_active and sd.scoring.made_contract == false then
        self._cross_count[declarer] = (self._cross_count[declarer] or 0) + 1
        if self._cross_count[declarer] >= 2 then
            local pen = pen_rules.cross_penalty_amount
            sd.scoring.cross_penalty[declarer] = sd.scoring.cross_penalty[declarer] - pen
            sd.scoring.deltas[declarer] = sd.scoring.deltas[declarer] - pen
            sd.scoring.running_totals[declarer] = sd.scoring.running_totals[declarer] - pen
            self._cross_count[declarer] = 0
        end
    end

    -- Phase 3.7 no-win-streak penalty. "Won the deal" = declarer made
    -- contract OR defender captured positive deal_scores. Mutates
    -- `sd.scoring` in place (mirroring the cross-counter pattern
    -- above) so the deal_done payload and advance_game both see the
    -- final figures. The counter spans the whole game, persisted
    -- across deals; threshold-hit fires `-penalty_amount` and resets
    -- the seat's counter to 0.
    local new_no_win = {}
    for i = 1, player_count do
        new_no_win[i] = self._no_win_streak_counts[i] or 0
    end
    local no_win_streak_penalty = {}
    for i = 1, player_count do
        no_win_streak_penalty[i] = 0
    end
    if pen_rules.no_win_streak ~= "off" then
        local nws_threshold = pen_rules.no_win_streak_threshold
        local nws_amount = pen_rules.no_win_streak_penalty_amount
        local made = sd.scoring.made_contract and true or false
        for seat = 1, player_count do
            local won_this_deal
            if seat == declarer then
                won_this_deal = made
            else
                won_this_deal = (sd.scoring.deal_scores[seat] or 0) > 0
            end
            if won_this_deal then
                if pen_rules.no_win_streak == "consecutive_three" then
                    new_no_win[seat] = 0
                end
                -- under any_three: no reset on a winning deal; only
                -- the threshold-hit reset clears the counter.
            else
                new_no_win[seat] = new_no_win[seat] + 1
            end
            if new_no_win[seat] >= nws_threshold then
                no_win_streak_penalty[seat] = no_win_streak_penalty[seat] - nws_amount
                sd.scoring.deltas[seat] = sd.scoring.deltas[seat] - nws_amount
                sd.scoring.running_totals[seat] = sd.scoring.running_totals[seat] - nws_amount
                new_no_win[seat] = 0
            end
        end
    end
    sd.scoring.no_win_streak_penalty = no_win_streak_penalty
    self._no_win_streak_counts = new_no_win

    -- Commit zero-tricks counter updates after score_deal returns. The
    -- engine has already applied the threshold deductions through the
    -- penalty array; this just persists the new counters.
    self._zero_tricks_bolts = new_bolts

    self._scoring = sd.scoring

    local g = scoring.advance_game(self._config, {
        declarer = declarer,
        deal_index = self._deal_index,
        deltas = sd.scoring.deltas,
        running_totals_before = self._running_totals,
        barrel_state_before = self._barrel_state,
        bid = type(bid) == "number" and bid or nil,
        declarer_made_contract = sd.scoring.made_contract and true or false,
        effective_target_before = self._effective_target,
        barrel_fall_counts_before = self._barrel_fall_counts,
    })
    if not g.ok then
        error("session: advance_game failed: " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    self._effective_target = g.game.effective_target_after
    self._barrel_fall_counts = g.game.barrel_fall_counts_after
    if g.game.tiebreaker_continuation_event then
        -- The deal ended with a tiebreaker_continuation event:
        -- effective_target jumped +500. Carry the elevated target into
        -- the next deal but never seal a winner this deal.
        self._winner = nil
    end
    if self._in_golden_deal and not sd.scoring.made_contract then
        self._golden_deal_failures = self._golden_deal_failures + 1
    end
    if g.game.winner then
        self._winner = g.game.winner
    else
        self._deal_done = {
            reason = "scored",
            declarer = declarer,
            made_contract = sd.scoring.made_contract,
            deal_scores = sd.scoring.deal_scores,
            -- Phase 3.6 score-breakdown inputs. Per-seat arrays for
            -- every bonus / penalty that contributed to deal_scores so
            -- the view-model can surface a row per non-zero kind.
            marriage_bonuses = sd.scoring.marriage_bonuses,
            half_marriage_capture_bonuses = sd.scoring.half_marriage_capture_bonuses,
            ace_marriage_bonuses = sd.scoring.ace_marriage_bonuses,
            last_trick_bonus = sd.scoring.last_trick_bonus,
            slam_bonus = sd.scoring.slam_bonus,
            slam_against_penalty = sd.scoring.slam_against_penalty,
            -- Phase 3.6 scoring house-rule outputs surfaced for the
            -- table view-model: contract-check value (raw vs. rounded
            -- under declarer_rounding_before_contract_check),
            -- success_payout (actual_points_on_success override),
            -- defender_pool_total (defender_contributions = pooled),
            -- and per-seat failed-contract distribution extras.
            contract_check_value = sd.scoring.contract_check_value,
            success_payout = sd.scoring.success_payout,
            effective_bid = sd.scoring.effective_bid,
            defender_pool_total = sd.scoring.defender_pool_total,
            failed_contract_distribution_extras = sd.scoring.failed_contract_distribution_extras,
            -- Phase 3.6 opening-game / barrel / endgame house-rule
            -- outputs. Per-seat arrays surface the matching scoreboard
            -- rows; effective_target_after captures continuation bumps;
            -- tiebreaker_continuation_event drives the banner row.
            dump_truck_events = g.game.dump_truck_events,
            pit_lock_in_state = g.game.pit_lock_in_state,
            overshoot_penalty_applied = g.game.overshoot_penalty_applied,
            eliminated = g.game.eliminated,
            going_over_target_capped = g.game.going_over_target_capped,
            effective_target_before = g.game.effective_target_before,
            effective_target_after = g.game.effective_target_after,
            tiebreaker_continuation_event = g.game.tiebreaker_continuation_event,
            in_golden_deal = self._in_golden_deal,
            -- Phase 3.6 named-contract output. Surfaces the kind /
            -- value pair so the deal-done scoreboard renders the
            -- right contract row (mizère / slam / open hand) instead
            -- of the standard captured-points + bonuses breakdown.
            named_contract = sd.scoring.named_contract,
            -- Phase 3.6 penalty house-rules. Per-seat signed arrays
            -- and post-deal counter snapshots so the view-model can
            -- render the deal-scoreboard penalty rows and the running
            -- bolt / cross counters.
            revoke_penalty = sd.scoring.revoke_penalty,
            talon_look_penalty = sd.scoring.talon_look_penalty,
            showing_hand_penalty = sd.scoring.showing_hand_penalty,
            zero_tricks_penalty = sd.scoring.zero_tricks_penalty,
            cross_penalty = sd.scoring.cross_penalty,
            zero_tricks_bolts = copy_list(self._zero_tricks_bolts),
            cross_count = copy_list(self._cross_count),
            -- Phase 3.7 cross-deal counter outputs. Per-seat signed
            -- penalty array, post-deal counter snapshots, and the
            -- per-seat fall event / reset flags from advance_game.
            no_win_streak_penalty = no_win_streak_penalty,
            no_win_streak_counts = copy_list(self._no_win_streak_counts),
            barrel_fall_events = g.game.barrel_fall_events,
            barrel_fall_resets = g.game.barrel_fall_resets,
            barrel_fall_counts = copy_list(self._barrel_fall_counts),
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
    -- A normal (non-blind) bid implies the seat has consulted their
    -- hand. Once revealed they can no longer declare blind. Phase 3.6
    -- bidding-house-rules.
    self._revealed_hands[player] = true
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
    self._revealed_hands[player] = true
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

-- Phase 3.9 follow-up: the pre-tricks write-off prompt is no longer a
-- blocking gate. Pass / discard / raise mutators auto-clear the offer
-- (equivalent to a silent `accept_play()`) before applying — the user
-- gives away their first card and the inline Write-off button vanishes
-- without them having had to dismiss a modal. The explicit
-- `Session:accept_play()` and `Session:write_off()` APIs stay for
-- callers (bot / scripted tests / future LLM player) that want to
-- resolve the offer without coupling it to a card move.
local function auto_resolve_write_off_offer(self)
    if self._awaiting_write_off_decision then
        self._awaiting_write_off_decision = nil
        self._write_off_decision_resolved = true
    end
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
    -- Phase 3.9: now that the declarer holds the full hand, surface the
    -- pre-tricks write-off prompt before any pass / discard ceremony.
    -- The helper no-ops when the toggle is off, the declarer has
    -- already chosen this deal, or the bid is structured.
    maybe_open_write_off_prompt(self)
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
    auto_resolve_write_off_offer(self)
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
    auto_resolve_write_off_offer(self)
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
    auto_resolve_write_off_offer(self)
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
    auto_resolve_write_off_offer(self)
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
    auto_resolve_write_off_offer(self)
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
        bid = type(bid) == "number" and bid or nil,
        declarer_made_contract = false,
        effective_target_before = self._effective_target,
    })
    if not g.ok then
        error("session: advance_game failed (concede): " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    self._effective_target = g.game.effective_target_after
    if g.game.tiebreaker_continuation_event then
        self._winner = nil
    end
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
    -- Phase 3.9: a Polish declarer who declined the bad-talon redeal
    -- now reaches the same pre-pass moment the auction-end hook would
    -- otherwise have caught. The helper no-ops if rebuy fired or if
    -- this is a take-then-pass distribution.
    maybe_open_write_off_prompt(self)
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
    -- Phase 3.9: a successful rebuy installs a new declarer; the
    -- write-off prompt opens for them at the next pre-pass moment.
    -- The helper no-ops for take-then-pass distributions because the
    -- talon is still at status "revealed" without `pass_without_taking`.
    maybe_open_write_off_prompt(self)
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
    -- Phase 3.9: the last decline restores control to the original
    -- declarer's pre-pass menu. Same helper, same no-op rules as the
    -- accept path.
    maybe_open_write_off_prompt(self)
    return { ok = true }
end

-- Marriage + trick mutators --------------------------------------------

-- Apply the marriage trump rule after a successful K-Q declaration:
--   * If `_marriages.trump` did not advance to `suit`, the
--     `one_trump_per_deal` rule suppressed the flip — do nothing.
--   * Otherwise: under `trump_activation_timing = "immediate"` flip
--     trump now via `tricks_module.set_trump_in_trick`; under the
--     standard `next_trick` schedule the flip for the next trick
--     boundary via `_pending_trump_apply`.
local function apply_marriage_trump_rule(self, suit)
    if self._marriages.trump ~= suit then
        -- one_trump_per_deal kept the trump suit unchanged.
        self._pending_trump_apply = nil
        return
    end
    if self._config.marriages.trump_activation_timing == "immediate" then
        if self._tricks and self._tricks.status == "in_progress" then
            local r = tricks_module.set_trump_in_trick(self._tricks, suit)
            if not r.ok then
                error(
                    "session: set_trump_in_trick failed: " -- i18n-ok
                        .. tostring(r.error.message),
                    2
                )
            end
            self._tricks = r.tricks
        end
        self._pending_trump_apply = nil
    else
        self._pending_trump_apply = suit
    end
    -- Phase 3.6 lead_trump_after_marriage: the flag should engage on
    -- the lead of the trick AFTER the marriage trick (not on the
    -- declaration trick itself, where the K/Q is led under on_lead).
    -- For pre_first_trick mode there is no marriage trick — the
    -- announcement happens before any trick — so engage immediately
    -- on trick 1's lead.
    if self._config.tricks.lead_trump_after_marriage == "on" then
        local timing = self._config.marriages.marriage_announcement_timing
        if
            timing == "pre_first_trick"
            and self._tricks
            and self._tricks.status == "in_progress"
            and self._tricks.tricks_played == 0
        then
            local r = tricks_module.mark_lead_trump_after_marriage(self._tricks)
            if r.ok then
                self._tricks = r.tricks
            end
        else
            self._pending_lead_trump_after_marriage = true
        end
    end
end

function Session:declare_marriage(player, suit)
    if self._raspassy_active then
        return failure("marriages_disabled_in_raspassy", "raspassy plays without marriages", {
            phase = self:current_phase(),
        })
    end
    if self._active_named_contract and self._active_named_contract.kind == "mizere" then
        return failure(
            "marriages_disabled_in_mizere",
            "mizere plays without trump or marriages", -- i18n-ok: internal error message
            { phase = self:current_phase() }
        )
    end
    if self._config.marriages.marriage_announcement_timing == "pre_first_trick" then
        return failure(
            "marriage_announcement_phase_closed",
            "declare_marriage_blocked",
            { mode = "pre_first_trick" }
        )
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
    local tricks_won = (self._tricks.tricks_won and self._tricks.tricks_won[player]) or 0
    local result = marriages_module.declare(self._marriages, player, suit, hand, tricks_won)
    if not result.ok then
        return result
    end
    self._marriages = result.marriages
    apply_marriage_trump_rule(self, suit)
    return { ok = true }
end

-- Phase 3.6: declare a marriage under
-- `marriage_announcement_timing in {"hand_announcement","pre_first_trick"}`.
-- The seat keeps the K and Q in hand and need not lead either; the
-- bonus posts and trump flips per the active timing.
function Session:announce_marriage(player, suit)
    if self._raspassy_active then
        return failure("marriages_disabled_in_raspassy", "raspassy plays without marriages", {
            phase = self:current_phase(),
        })
    end
    if self._active_named_contract and self._active_named_contract.kind == "mizere" then
        return failure(
            "marriages_disabled_in_mizere",
            "mizere plays without trump or marriages", -- i18n-ok: internal error message
            { phase = self:current_phase() }
        )
    end
    local mode = self._config.marriages.marriage_announcement_timing
    if mode == "on_lead" then
        return failure("wrong_announcement_mode", "announce_marriage_disabled", { mode = mode })
    end

    local hand
    if mode == "pre_first_trick" then
        if not self._pre_first_trick_marriage_queue then
            return failure("marriage_announcement_phase_closed", "window_closed", { mode = mode })
        end
        local q = self._pre_first_trick_marriage_queue
        local current = q.seats[q.current_index]
        if current ~= player then
            return failure("not_your_turn", "wrong_seat", {
                player = player,
                turn = current,
            })
        end
        hand = self._tricks and self._tricks.hands[player] or self._hands[player]
    else
        -- hand_announcement: leader on an empty trick.
        if not self._tricks or self._tricks.status ~= "in_progress" then
            return failure("wrong_phase", "announce_marriage requires the tricks phase", {
                phase = self:current_phase(),
            })
        end
        if self._tricks.next_to_play ~= player then
            return failure("not_your_turn", "announce_marriage requires the seat on lead", {
                player = player,
                turn = self._tricks.next_to_play,
            })
        end
        if #self._tricks.current_trick.plays ~= 0 then
            return failure("not_on_lead", "announce_marriage requires an empty trick", {
                plays = #self._tricks.current_trick.plays,
            })
        end
        hand = self._tricks.hands[player]
    end

    local tricks_won = 0
    if self._tricks and self._tricks.tricks_won then
        tricks_won = self._tricks.tricks_won[player] or 0
    end
    local result =
        marriages_module.announce_from_hand(self._marriages, player, suit, hand, tricks_won)
    if not result.ok then
        return result
    end
    self._marriages = result.marriages
    apply_marriage_trump_rule(self, suit)

    if mode == "pre_first_trick" then
        local q = self._pre_first_trick_marriage_queue
        q.current_index = q.current_index + 1
        if q.current_index > #q.seats then
            self._pre_first_trick_marriage_queue = nil
        end
    end
    return { ok = true }
end

-- Phase 3.6: pass a seat's pre-first-trick announcement window. Only
-- valid under `marriage_announcement_timing = "pre_first_trick"` and
-- only for the seat the queue is currently asking.
function Session:skip_pre_first_trick_marriage(player)
    if self._config.marriages.marriage_announcement_timing ~= "pre_first_trick" then
        return failure("wrong_announcement_mode", "skip_disabled", {
            mode = self._config.marriages.marriage_announcement_timing,
        })
    end
    if not self._pre_first_trick_marriage_queue then
        return failure("marriage_announcement_phase_closed", "window_closed", {})
    end
    local q = self._pre_first_trick_marriage_queue
    local current = q.seats[q.current_index]
    if current ~= player then
        return failure("not_your_turn", "wrong_seat", {
            player = player,
            turn = current,
        })
    end
    q.current_index = q.current_index + 1
    if q.current_index > #q.seats then
        self._pre_first_trick_marriage_queue = nil
    end
    return { ok = true }
end

-- Phase 3.6: declare the four-Aces (тузовый марьяж) bonus. Valid only
-- under `marriages.ace_marriage in {"on","sets_trump"}` for the seat
-- on lead at an empty trick. Under `sets_trump` the engine records a
-- pending ace-trump activation; the orchestrator flips trump when the
-- declaring seat next leads an Ace.
function Session:declare_ace_marriage(player)
    if self._raspassy_active then
        return failure("marriages_disabled_in_raspassy", "raspassy plays without marriages", {
            phase = self:current_phase(),
        })
    end
    if self._config.marriages.ace_marriage == "off" then
        return failure("ace_marriage_disabled", "ace_marriage_off", { mode = "off" })
    end
    -- Allow during the pre-first-trick window or on lead at an empty
    -- trick.
    local hand
    if self._pre_first_trick_marriage_queue then
        local q = self._pre_first_trick_marriage_queue
        local current = q.seats[q.current_index]
        if current ~= player then
            return failure("not_your_turn", "wrong_seat", {
                player = player,
                turn = current,
            })
        end
        hand = self._tricks and self._tricks.hands[player] or self._hands[player]
    else
        if not self._tricks or self._tricks.status ~= "in_progress" then
            return failure("wrong_phase", "declare_ace_marriage requires the tricks phase", {
                phase = self:current_phase(),
            })
        end
        if self._tricks.next_to_play ~= player then
            return failure("not_your_turn", "declare_ace_marriage requires the seat on lead", {
                player = player,
                turn = self._tricks.next_to_play,
            })
        end
        if #self._tricks.current_trick.plays ~= 0 then
            return failure("not_on_lead", "declare_ace_marriage requires an empty trick", {
                plays = #self._tricks.current_trick.plays,
            })
        end
        hand = self._tricks.hands[player]
    end

    local tricks_won = 0
    if self._tricks and self._tricks.tricks_won then
        tricks_won = self._tricks.tricks_won[player] or 0
    end
    local result = marriages_module.declare_ace_marriage(self._marriages, player, hand, tricks_won)
    if not result.ok then
        return result
    end
    self._marriages = result.marriages
    return { ok = true }
end

-- Read-only accessor for the pre-first-trick announcement window.
-- Returns nil when the window is closed; otherwise `{ seat,
-- pending_seats, eligible_suits }` where `seat` is the seat to act
-- next, `pending_seats` is the remaining queue (including `seat`),
-- and `eligible_suits` is the list of suits the active seat may
-- declare.
function Session:pre_first_trick_announcement_state()
    local q = self._pre_first_trick_marriage_queue
    if not q then
        return nil
    end
    local seat = q.seats[q.current_index]
    local pending = {}
    for i = q.current_index, #q.seats do
        pending[#pending + 1] = q.seats[i]
    end
    local hand = self._tricks and self._tricks.hands[seat] or self._hands[seat]
    local suits = marriages_module.detect(hand)
    return { seat = seat, pending_seats = pending, eligible_suits = suits }
end

-- Read-only accessor for the drowned-marriage banner. Returns the
-- full per-deal log; the most recent entry feeds the table-scene
-- banner.
function Session:drowned_marriage_log()
    return self._drowned_marriage_log or {}
end

-- Read-only accessor for the pending ace-trump activation under
-- `ace_marriage = "sets_trump"`. Returns the seat that must next
-- lead an Ace, or nil.
function Session:pending_ace_trump_seat()
    return self._marriages and self._marriages.pending_ace_trump or nil
end

-- Test-only accessor for the marriages engine state. Production
-- code reads marriage outcomes through the higher-level helpers
-- (`trump`, `available_marriages`, `drowned_marriage_log`,
-- `pending_ace_trump_seat`). Tests sometimes need the raw bonuses
-- and declarations to assert specific values.
function Session:_marriages_state_for_test()
    return self._marriages
end

-- Test-only accessor for the per-seat half-marriage capture bonus
-- accumulator. The same array is fed into scoring.score_deal at
-- end-of-deal; tests can observe it before that to validate the
-- per-trick award path.
function Session:_half_marriage_capture_bonuses_for_test()
    return self._half_marriage_capture_bonuses
end

-- Phase 3.6 marriage trick-side effects:
--   * `half_marriage_capture_bonus = "on"` — if a non-declarer captures
--     both the K and Q of the same suit in tricks, award the bonus
--     once.
--   * `drowned_marriage = "retroactive_cancel"` — if a previously
--     declared K-Q marriage's K or Q is captured by a seat other
--     than the declarer, reverse the bonus.
local function record_trick_marriage_effects(self, _resolved_trick, _trick_plays_before)
    local completed = self._tricks and self._tricks.completed_tricks
    if not completed then
        return
    end
    local last = completed[#completed]
    if not last then
        return
    end
    local declarer = self._talon and self._talon.declarer
    local config = self._config

    -- Half-marriage capture bonus.
    if config.marriages.half_marriage_capture_bonus == "on" then
        local bonus_value = config.marriages.half_marriage_capture_bonus_value
        for _, play in ipairs(last.plays) do
            local c = play.card
            local r = c.rank
            if (r == "K" or r == "Q") and last.winner ~= declarer then -- i18n-ok: rank enums
                local seat_caps = self._half_marriage_captures[last.winner]
                if not seat_caps then
                    seat_caps = {}
                    self._half_marriage_captures[last.winner] = seat_caps
                end
                local suit_caps = seat_caps[c.suit]
                if not suit_caps then
                    suit_caps = { K = false, Q = false, awarded = false }
                    seat_caps[c.suit] = suit_caps
                end
                suit_caps[c.rank] = true
                if suit_caps.K and suit_caps.Q and not suit_caps.awarded then
                    suit_caps.awarded = true
                    self._half_marriage_capture_bonuses[last.winner] = (
                        self._half_marriage_capture_bonuses[last.winner] or 0
                    ) + bonus_value
                end
            end
        end
    end

    -- Drowned marriage cancellation.
    if config.marriages.drowned_marriage == "retroactive_cancel" then
        for _, play in ipairs(last.plays) do
            local c = play.card
            local rk = c.rank
            if rk == "K" or rk == "Q" then -- i18n-ok: rank enums
                local declarations = self._marriages.declarations
                for _, decl in ipairs(declarations) do
                    if
                        (decl.kind == nil or decl.kind == "kq")
                        and not decl.cancelled
                        and decl.suit == c.suit
                        and decl.player ~= last.winner
                        and last.winner ~= decl.player
                    then
                        local cancel_result =
                            marriages_module.cancel_drowned(self._marriages, c.suit)
                        if cancel_result.ok then
                            self._marriages = cancel_result.marriages
                            self._drowned_marriage_log = self._drowned_marriage_log or {}
                            self._drowned_marriage_log[#self._drowned_marriage_log + 1] = {
                                suit = c.suit,
                                declarer = decl.player,
                                value = decl.value,
                                trick_index = #completed,
                            }
                        end
                        break
                    end
                end
            end
        end
    end
end

function Session:play(player, card)
    if not self._tricks or self._tricks.status ~= "in_progress" then
        return failure("wrong_phase", "play requires the tricks phase", {
            phase = self:current_phase(),
        })
    end
    if self._pre_first_trick_marriage_queue then
        return failure(
            "awaiting_pre_first_trick_marriages",
            "play_blocked_pre_first_trick",
            { phase = self:current_phase() }
        )
    end

    -- Phase 3.6 ace_marriage = "sets_trump": if the declaring seat is
    -- about to lead an Ace, flip trump immediately on this lead.
    -- Ranking is read at the resolver per play, so set_trump_in_trick
    -- before the play is recorded is sufficient.
    local pending_ace_seat = self._marriages and self._marriages.pending_ace_trump
    if
        pending_ace_seat == player
        and #self._tricks.current_trick.plays == 0
        and type(card) == "table"
        and card.rank == "A"
    then
        local r = marriages_module.activate_ace_trump(self._marriages, card.suit)
        if r.ok then
            self._marriages = r.marriages
            local sr = tricks_module.set_trump_in_trick(self._tricks, card.suit)
            if not sr.ok then
                error(
                    "session: set_trump_in_trick failed (ace marriage): " -- i18n-ok
                        .. tostring(sr.error.message),
                    2
                )
            end
            self._tricks = sr.tricks
        end
    end

    local before_played = self._tricks.tricks_played
    local trick_plays_before = self._tricks.current_trick.plays
    local result = tricks_module.play(self._tricks, player, card)
    if not result.ok then
        return result
    end
    self._tricks = result.tricks

    -- Trick boundary reached — apply any pending trump and check for
    -- end-of-deal. set_trump is only legal between tricks, which is
    -- exactly the window we land in when tricks_played increments.
    if self._tricks.tricks_played > before_played then
        local resolved_trick = self._tricks.history[#self._tricks.history]
        record_trick_marriage_effects(self, resolved_trick, trick_plays_before)
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
        if self._pending_lead_trump_after_marriage and self._tricks.status == "in_progress" then
            local r = tricks_module.mark_lead_trump_after_marriage(self._tricks)
            if r.ok then
                self._tricks = r.tricks
            end
            self._pending_lead_trump_after_marriage = nil
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

-- Cut-deck ritual API (Phase 3.8) --------------------------------------
--
-- When `dealing.cut_deck_nine_jack_penalty = "on"` the engine opens a
-- pre-auction `cut` phase. The seat counter-clockwise of the dealer
-- cuts the deck via `Session:cut_deck()`. A 9 or J at the bottom is a
-- bad cut: the cutter rotates one seat counter-clockwise, the bad-cut
-- counter increments, and the deck is re-shuffled with a bumped seed.
-- After three bad cuts the dealer takes a fixed −120 penalty applied
-- immediately to the running total, the cut phase clears, and the
-- deal proceeds with the current deck. Counter resets per deal.
--
-- The cut phase also blocks the forced-redeal sweep and the
-- golden-deal `on_auction_end` hook until the cutter clears it, so
-- the ritual is always the first interactive moment of the deal.
--
-- The Phase 4 bot driver (`app/bot/`) will call `cut_deck()` directly
-- from its decision routine — the action carries no decision so
-- latency is bounded only by the existing minimum thinking delay.

local CUT_DECK_THRESHOLD = 3
local CUT_DECK_PENALTY_AMOUNT = 120

-- Drive any auction-side transitions deferred while the cut phase was
-- open. Mirrors the tail of Session.new and reset_deal_state — the
-- forced-redeal sweep first (entitlements may chain), then the
-- golden-deal `on_auction_end` hook if applicable.
local function run_post_cut_transitions(self)
    evaluate_entitlement_with_forced_loop(self)
    if self._in_golden_deal and self._auction and self._auction.status == "done" then
        on_auction_end(self)
    end
end

-- Re-shuffle and re-deal in place, keeping the dealer fixed. Bumps the
-- seed so the new shuffle differs from the previous one, refreshes
-- every deal-time field, and returns the fresh bottom card so the
-- caller can update `_cut_phase.bottom_card`. Used only by
-- `Session:cut_deck()` on a bad cut — `reset_deal_state` is the wrong
-- shape because it would re-open the cut phase from scratch and lose
-- the running counter.
local function reshuffle_for_cut(self)
    self._seed = (self._seed or os.time()) + 1
    local deal_result, auction, marriages, golden_active, bottom_card = build_initial_state(
        self._config,
        self._dealer,
        self._seed,
        self._running_totals,
        self._deal_index
    )
    self._hands = deal_result.hands
    self._talon_cards = deal_result.talon
    self._stock = deal_result.stock
    self._trump_indicator = deal_result.trump_indicator
    self._sits_out = deal_result.sits_out
    self._leftover_for_declarer = deal_result.leftover_for_declarer
    self._auction = auction
    self._marriages = marriages
    self._in_golden_deal = golden_active and true or false
    return bottom_card
end

-- The current cut-phase state, or nil. Surfaced as a single read so
-- the table view-model and the Phase 4 bot driver can branch on
-- presence without poking at a private field.
function Session:cut_phase()
    return self._cut_phase
end

-- The seat that should call `cut_deck()` next, or nil when no cut
-- phase is open. Distinct from `current_turn()` (which derives the
-- value from the current phase) so callers that want the cutter's
-- identity directly don't need to compare phase strings.
function Session:active_cutter()
    return self._cut_phase and self._cut_phase.active_cutter or nil
end

-- Number of bad cuts in the current deal. Returns 0 when no cut
-- phase is open or when the toggle is off, so the running scoreboard
-- can surface "Bad cuts: %{count} / 3" unconditionally.
function Session:bad_cut_count()
    return self._cut_phase and self._cut_phase.bad_cut_count or 0
end

-- The cut-deck event log for the current deal. Latest entry feeds
-- the threshold-penalty banner. Cleared at start_next_deal.
function Session:cut_deck_log()
    return self._cut_deck_log or {}
end

-- Cut the deck on behalf of the active cutter. Returns the typical
-- `{ ok | error }` envelope; on success, `result` is one of:
--   "good_cut"          — bottom is safe; phase clears and the deal
--                         advances to forced redeals / auction.
--   "bad_cut"           — bottom is 9 or J; cutter rotates ccw, the
--                         deck is re-shuffled, the counter increments.
--   "threshold_penalty" — third bad cut; dealer is debited 120
--                         immediately, phase clears, deal proceeds
--                         with the current ordering. `penalty` is
--                         set to the amount in this case.
function Session:cut_deck()
    if not self._cut_phase then
        return failure("wrong_phase", "cut_deck has no open cut phase", {
            phase = self:current_phase(),
        })
    end
    if not deck_module.is_bottom_disallowed(self._cut_phase.bottom_card) then
        local cutter = self._cut_phase.active_cutter
        self._cut_deck_log[#self._cut_deck_log + 1] = {
            kind = "good_cut",
            seat = cutter,
            dealer = self._dealer,
            bad_cut_count = self._cut_phase.bad_cut_count,
        }
        self._cut_phase = nil
        run_post_cut_transitions(self)
        return { ok = true, result = "good_cut" }
    end
    local count = self._config.players.count
    self._cut_phase.bad_cut_count = self._cut_phase.bad_cut_count + 1
    if self._cut_phase.bad_cut_count >= CUT_DECK_THRESHOLD then
        local cutter = self._cut_phase.active_cutter
        self._running_totals[self._dealer] = self._running_totals[self._dealer]
            - CUT_DECK_PENALTY_AMOUNT
        self._cut_deck_log[#self._cut_deck_log + 1] = {
            kind = "threshold_penalty",
            seat = cutter,
            dealer = self._dealer,
            amount = CUT_DECK_PENALTY_AMOUNT,
            bad_cut_count = self._cut_phase.bad_cut_count,
        }
        self._cut_phase = nil
        run_post_cut_transitions(self)
        return { ok = true, result = "threshold_penalty", penalty = CUT_DECK_PENALTY_AMOUNT }
    end
    local previous = self._cut_phase.active_cutter
    local rotated = ccw_of(previous, count)
    local new_bottom = reshuffle_for_cut(self)
    self._cut_phase.active_cutter = rotated
    self._cut_phase.bottom_card = new_bottom
    self._cut_deck_log[#self._cut_deck_log + 1] = {
        kind = "bad_cut",
        seat = previous,
        dealer = self._dealer,
        bad_cut_count = self._cut_phase.bad_cut_count,
        next_cutter = rotated,
    }
    return { ok = true, result = "bad_cut" }
end

-- Redeal / misdeal API -------------------------------------------------
--
-- The session never auto-decides an optional redeal offer on the
-- player's behalf — accept_redeal / decline_redeal are caller-driven.
-- The Phase 2 hot-seat scene drives them through the redeal modal in
-- `ui/scenes/table.lua`; the future Phase 4 bot player layer
-- (`app/bot/`) will call them from its decision routine when a bot
-- seat is the entitled player. The decision heuristic ("hold this
-- weak hand or take the redeal?") belongs to `app/bot/`, not here.
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

    -- Phase 3.6 opening-game / golden_deal_failure_handling. When the
    -- just-completed deal closed the opening sequence and every
    -- declarer in it failed their forced contract,
    -- `replay_round` restarts the sequence; `reset` additionally
    -- zeroes the running totals and barrel state. `continue` is the
    -- canonical default and proceeds to normal play with whatever
    -- penalties the round produced.
    local opening = self._config.opening_game
    local golden_count = opening.golden_deal_count
    local was_last_golden = self._in_golden_deal and self._deal_index == golden_count
    local handling = opening.golden_deal_failure_handling
    if
        was_last_golden
        and self._golden_deal_failures >= golden_count
        and handling ~= "continue"
    then
        if handling == "reset" then
            self._running_totals = zero_totals(player_count)
            self._barrel_state = scoring.initial_barrel_state(self._config)
            self._effective_target = self._config.endgame.target_score
        end
        self._deal_index = 1
        self._golden_deal_failures = 0
        next_dealer = (self._dealer - golden_count) % player_count
        if next_dealer == 0 then
            next_dealer = player_count
        end
    else
        self._deal_index = self._deal_index + 1
    end

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
    -- Phase 3.8: per-deal cut events also clear before the next deal.
    self._cut_deck_log = {}
    reset_deal_state(self, next_dealer, self._deal_index)
    if not self._cut_phase then
        evaluate_entitlement_with_forced_loop(self)
    end
    return { ok = true }
end

-- Phase 3.6 bidding-house-rules ------------------------------------------
--
-- Read-only accessors and mutators for the nine bidding toggles wired
-- in this commit. Mutators forward to core.auction (or apply a session-
-- only effect for forced-bid concession) and return the same
-- { ok | error={code, message, ...} } envelope used elsewhere.

function Session:auction_status()
    if not self._auction then
        return nil
    end
    if self._auction.status == "done" and self._auction.dealer_forced then
        return "forced_dealer_bid"
    end
    return self._auction.status
end

function Session:has_revealed_hand(seat)
    return self._revealed_hands[seat] == true
end

-- Test / view-model hook to record a curtain dismissal. The table
-- scene calls this when its privacy curtain leaves the on-screen
-- queue for `seat`. Once true the seat can no longer declare a blind
-- bid.
function Session:mark_hand_revealed(seat)
    self._revealed_hands[seat] = true
end

function Session:has_used_re_entry(seat)
    return self._re_entry_used[seat] == true
end

function Session:contra_declared()
    return self._contra_declared
end

function Session:redouble_declared()
    return self._redouble_declared
end

-- The active "self" defenders (every non-declarer non-sits-out seat).
-- Used by the view-model to render contra buttons and by the contra
-- mutator to validate the actor.
function Session:defender_seats()
    if not self._auction or self._auction.declarer == nil then
        return {}
    end
    local count = self._config.players.count
    local sits_out = self._auction.sits_out or self._sits_out
    local declarer = self._auction.declarer
    local out = {}
    for seat = 1, count do
        if seat ~= declarer and seat ~= sits_out then
            out[#out + 1] = seat
        end
    end
    return out
end

-- The contra/redouble window opens once the talon has been revealed
-- and closes when the first trick lands. Both edges are necessary so
-- declarer can see their full hand before deciding to redouble while
-- defenders cannot contra mid-trick.
function Session:contra_window_open()
    if self._config.bidding.contra == "off" then
        return false
    end
    -- Window opens once the auction has settled on a declarer and
    -- closes the moment the tricks phase begins (so the declarer can
    -- redouble after seeing the talon but no defender can contra
    -- once a card is led).
    if self._tricks then
        return false
    end
    if self._auction then
        local s = self._auction.status
        if s == "done" or s == "doubling" then -- i18n-ok: status enums
            return true
        end
    end
    if self._talon and self._talon.status == "revealed" then
        return true
    end
    return false
end

-- True when the active declarer arrived at the contract via either
-- the forced-dealer-bid path (toggle 2) or the forced-opening path
-- (toggle 1) where forehand was the lone bidder at opening_min.
function Session:was_forced_into_minimum_contract()
    if not self._auction or self._auction.declarer == nil then
        return false
    end
    if self._auction.dealer_forced then
        return true
    end
    local opening_min = self._config.bidding.opening_min
    if self._auction.final_bid ~= opening_min then
        return false
    end
    if self._config.bidding.forced_opening ~= "on" then
        return false
    end
    -- Forced-opening path: forehand was the only bidder at opening_min
    -- and every other active seat passed.
    if self._auction.declarer ~= self._auction.forehand then
        return false
    end
    return true
end

-- Composite multiplier applied to the contract value: blind
-- (success/failure picked by the scoring module), then contra, then
-- redouble. Default 1 when no toggle fires.
function Session:contract_multiplier()
    local mult = 1
    -- Honour both the engine's blind_at_win flag (set when the
    -- declarer's winning bid was blind) and the in-flight blind flag
    -- on the current leader (so the badge surfaces the moment the
    -- blind bid lands, before the auction has terminated).
    if self._auction then
        local declarer_blind = self._auction.blind_at_win
        local leader = self._auction.current_leader
        local leader_blind = leader and self._auction.blind and self._auction.blind[leader]
        if declarer_blind or leader_blind then
            mult = mult * (self._config.bidding.blind_bid_success_multiplier or 2)
        end
    end
    if self._contra_declared then
        mult = mult * (self._config.bidding.contra_multiplier or 2)
    end
    if self._redouble_declared then
        mult = mult * (self._config.bidding.redouble_multiplier or 2)
    end
    return mult
end

-- The slam contract value resolved from the
-- `specials.slam_contract_value` sibling field. Defaults to 240
-- (the canonical Russian value); house-rule templates can pick any
-- positive integer in [1, 600] per the schema.
function Session:slam_contract_value()
    return self._config.specials.slam_contract_value
end

-- The mizère contract value resolved from the
-- `specials.mizere_contract_value` sibling field. Defaults to 120
-- per the canonical Russian / Polish wording.
function Session:mizere_contract_value()
    return self._config.specials.mizere_contract_value
end

-- The active named contract record `{ kind, value }`, or nil when
-- the current deal is not a special-contract deal. Set by
-- on_auction_end when a structured bid wins; consumed by the
-- marriage-block guard, the open-hand visibility flag, and the
-- named-contract scoring path. Cleared on every fresh deal.
function Session:active_named_contract()
    if not self._active_named_contract then
        return nil
    end
    return {
        kind = self._active_named_contract.kind,
        value = self._active_named_contract.value,
    }
end

-- Forced-bid concession state for the view-model.
function Session:forced_concession_offer_state()
    return self._forced_concession_offer
end

-- Bidding-house-rules mutators below reuse the file-scope `failure`
-- helper defined above.

-- Pre-reveal blind action by the seat on turn. Records the blind flag
-- and bids the opening minimum via auction.bid with opts.blind. The
-- engine's blind validator catches every failure (toggle off, seat
-- already revealed, seat already acted) and the envelope is returned
-- verbatim.
function Session:declare_blind(player)
    if not self._auction or self._auction.status ~= "in_progress" then
        return failure("auction_already_done", "auction has already terminated", {
            status = self._auction and self._auction.status or "unknown",
        })
    end
    if self._config.bidding.blind_bid == "off" then
        return failure("blind_disabled", "blind bidding is not enabled", {})
    end
    if self._revealed_hands[player] then
        return failure("already_revealed", "hand already revealed; too late to bid blind", {
            player = player,
        })
    end
    local opening_min = self._config.bidding.opening_min
    local result = auction_module.bid(self._auction, player, opening_min, { blind = true })
    if not result.ok then
        return result
    end
    self._auction = result.auction
    self._blind_bidders[player] = true
    on_auction_end(self)
    return { ok = true }
end

-- Out-of-turn re-entry by a passed seat. Wraps auction.bid_re_entry
-- and records the per-deal use so a second attempt fails fast.
function Session:bid_re_entry(player, amount)
    -- Toggle check fires first so the "rule disabled" message reaches
    -- the UI even when the auction has already terminated; the engine
    -- itself returns the same code via core.auction.bid_re_entry.
    if self._config.bidding.re_entry_after_pass ~= "on" then
        return failure("re_entry_disabled", "re-entry after pass is not enabled", {})
    end
    if not self._auction or self._auction.status ~= "in_progress" then
        return failure("auction_already_done", "auction has already terminated", {
            status = self._auction and self._auction.status or "unknown",
        })
    end
    local result = auction_module.bid_re_entry(self._auction, player, amount)
    if not result.ok then
        return result
    end
    self._auction = result.auction
    self._re_entry_used[player] = true
    on_auction_end(self)
    return { ok = true }
end

-- Bid a named special contract. Wraps auction.bid with a structured
-- amount; the engine validates `bidding.named_contracts` and the
-- per-contract `specials.<contract>` toggle. Resolves the contract
-- value through the slam_contract_value helper for slam.
function Session:bid_named_contract(player, kind)
    if not self._auction or self._auction.status ~= "in_progress" then
        return failure("auction_already_done", "auction has already terminated", {
            status = self._auction and self._auction.status or "unknown",
        })
    end
    if self._config.bidding.named_contracts ~= "on" then
        return failure("named_contracts_disabled", "named contracts not enabled", {})
    end
    local value
    if kind == "mizere" then
        value = self:mizere_contract_value()
    elseif kind == "slam" then
        value = self:slam_contract_value()
    elseif kind == "open_hand" then
        -- Open-hand keeps the doubled-effective default at 200
        -- (= 2 × the canonical 100 base) per the house-rules
        -- definition. No sibling field — the value is pre-doubled
        -- so the scoring path applies no further multiplier.
        value = 200
    else
        return failure("unknown_kind", "unknown named contract kind", { kind = kind })
    end
    local result = auction_module.bid(self._auction, player, {
        kind = "named",
        contract = kind,
        value = value,
    })
    if not result.ok then
        return result
    end
    self._auction = result.auction
    on_auction_end(self)
    return { ok = true }
end

local function ensure_contra_window(self)
    if not self:contra_window_open() then
        return failure("wrong_phase", "contra window is closed", {
            phase = self:current_phase(),
        })
    end
    return nil
end

-- Defender doubles the contract. Updates the session's flags so
-- `contract_multiplier()` reflects the change; the engine's auction
-- state is unaffected because doubling lives on the session under
-- this commit's design (the auction module's `doubling` sub-phase is
-- only consulted at finalize-time, not during talon).
function Session:declare_contra(defender)
    if self._config.bidding.contra == "off" then
        return failure("contra_disabled", "contra is not enabled", {})
    end
    local err = ensure_contra_window(self)
    if err then
        return err
    end
    if self._contra_declared then
        return failure("already_contra", "contra already declared", {})
    end
    local defenders = self:defender_seats()
    local found = false
    for _, s in ipairs(defenders) do
        if s == defender then
            found = true
            break
        end
    end
    if not found then
        return failure("not_a_defender", "this seat is not a defender", {
            player = defender,
            declarer = self._auction.declarer,
        })
    end
    self._contra_declared = true
    self._contra_declarer = defender
    return { ok = true }
end

-- Declarer responds to a contra. Only legal under
-- `bidding.contra = "contra_and_redouble"`.
function Session:declare_redouble(declarer)
    local err = ensure_contra_window(self)
    if err then
        return err
    end
    if self._config.bidding.contra ~= "contra_and_redouble" then
        return failure("redouble_disabled", "redouble is not enabled", {
            contra = self._config.bidding.contra,
        })
    end
    if not self._contra_declared then
        return failure("no_contra", "redouble requires a prior contra", {})
    end
    if self._redouble_declared then
        return failure("already_redoubled", "redouble already declared", {})
    end
    if declarer ~= self._auction.declarer then
        return failure("not_declarer", "only the declarer may redouble", {
            player = declarer,
            declarer = self._auction.declarer,
        })
    end
    self._redouble_declared = true
    return { ok = true }
end

-- Defender declines to declare contra. Currently a noop on session
-- state — the contra window simply remains closed for that seat.
-- Provided so the UI button has a callable target; engine semantics
-- are identical to "no contra".
function Session:skip_contra(defender)
    if self._config.bidding.contra == "off" then
        return failure("contra_disabled", "contra is not enabled", {})
    end
    local _ = defender
    local err = ensure_contra_window(self)
    if err then
        return err
    end
    if self._contra_declared then
        return failure("already_contra", "contra already declared", {})
    end
    return { ok = true }
end

-- Declarer concedes the forced minimum-100 contract before the talon
-- is revealed. Distribution depends on `bidding.forced_bid_concession`:
--   * equal_split — bid divided equally among non-conceders.
--   * each_full   — every other active player gets the full bid.
--   * preset_ratio — the configured ratio applies.
-- Sets _deal_done so start_next_deal rotates the dealer normally.
function Session:concede_forced_bid()
    if not self._forced_concession_offer then
        if self._config.bidding.forced_bid_concession == "off" then
            return failure("concession_disabled", "forced-bid concession is not enabled", {})
        end
        return failure("not_forced", "concession is not currently offered", {})
    end
    local offer = self._forced_concession_offer
    local declarer = offer.declarer
    local bid = offer.bid
    local mode = offer.split_mode
    local count = self._config.players.count
    local sits_out = self._auction.sits_out

    local recipients = {}
    for seat = 1, count do
        if seat ~= declarer and seat ~= sits_out then
            recipients[#recipients + 1] = seat
        end
    end

    local deltas = {}
    for seat = 1, count do
        deltas[seat] = 0
    end
    deltas[declarer] = -bid
    if mode == "equal_split" then
        local share = math.floor(bid / #recipients)
        for _, seat in ipairs(recipients) do
            deltas[seat] = share
        end
    elseif mode == "each_full" then
        for _, seat in ipairs(recipients) do
            deltas[seat] = bid
        end
    elseif mode == "preset_ratio" then
        local ratio = self._config.bidding.forced_bid_concession_preset_ratio
        for i, seat in ipairs(recipients) do
            local weight = ratio[i] or 0
            deltas[seat] = math.floor(bid * weight + 0.5)
        end
    end

    local g = scoring.advance_game(self._config, {
        declarer = declarer,
        deal_index = self._deal_index,
        deltas = deltas,
        running_totals_before = self._running_totals,
        barrel_state_before = self._barrel_state,
        bid = type(bid) == "number" and bid or nil,
        declarer_made_contract = false,
        effective_target_before = self._effective_target,
    })
    if not g.ok then
        return failure("scoring_failed", g.error.message or "advance_game failed", {
            cause = g.error,
        })
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    self._effective_target = g.game.effective_target_after
    if g.game.tiebreaker_continuation_event then
        self._winner = nil
    elseif g.game.winner then
        self._winner = g.game.winner
    end
    self._deal_done = {
        reason = "forced_bid_conceded",
        declarer = declarer,
        deal_scores = deltas,
    }
    self._forced_concession_offer = nil
    self._forced_concession_resolved = true
    return { ok = true }
end

-- Declarer declines the forced-bid concession; the deal proceeds
-- through the talon path normally. Re-enters the talon construction
-- block from `on_auction_end` against the same auction state.
function Session:decline_forced_bid()
    if not self._forced_concession_offer then
        return failure("not_forced", "no concession offer to decline", {})
    end
    self._forced_concession_offer = nil
    self._forced_concession_resolved = true
    -- Run the post-finalize path that was deferred when the offer
    -- opened. The auction state is unchanged so the talon-construction
    -- branch runs normally now.
    on_auction_end(self)
    return { ok = true }
end

-- Phase 3.9 write-off offer accessor for the table view-model.
function Session:write_off_offer_state()
    return self._awaiting_write_off_decision
end

-- Phase 3.9: declarer chooses to play this hand instead of writing off.
-- Clears the prompt and lets the existing pass / discard / Polish-pass
-- methods proceed. The "resolved" flag prevents the helper from
-- re-prompting this deal.
function Session:accept_play()
    if not self._awaiting_write_off_decision then
        return failure("no_write_off_pending", "no write-off prompt to accept", {
            phase = self:current_phase(),
        })
    end
    self._awaiting_write_off_decision = nil
    self._write_off_decision_resolved = true
    return { ok = true }
end

-- Phase 3.9 write-off / сдача. The book frames the decision as a
-- one-shot pre-tricks prompt the declarer answers after seeing the
-- widow — between talon take and the pass step (Russian, 2-player B)
-- or between talon reveal and the two opponent passes (Polish 2-card
-- `pass_without_taking`). On accept, pays out the contract per
-- `bidding.write_off_split`:
--   * half_to_each — every active opponent gets half the bid.
--     Book default; with 3+ opponents the credits intentionally
--     exceed the debit.
--   * equal_split — the bid value is divided equally across the
--     opponents.
-- Sits-out seats (4-player B) are excluded from recipients, mirroring
-- `concede_forced_bid`. The declarer's per-seat counter advances; on
-- threshold (under `penalties.write_off_streak = "any_three"`) the
-- configured penalty is folded into the declarer's delta and the
-- counter resets. The deal closes with `reason = "write_off"` so
-- `start_next_deal` rotates the dealer normally.
function Session:write_off()
    if self._config.bidding.write_off ~= "on" then
        local msg = "bidding.write_off is not enabled" -- i18n-ok: internal error
        return failure("write_off_disabled", msg, { rule = self._config.bidding.write_off })
    end
    if self:current_phase() ~= "awaiting_write_off_decision" then
        return failure("wrong_phase", "write_off requires the awaiting_write_off_decision phase", {
            phase = self:current_phase(),
        })
    end
    local offer = self._awaiting_write_off_decision
    local declarer = offer.declarer
    if declarer == nil then
        return failure("no_declarer", "write_off has no declarer to charge", {})
    end
    local bid = offer.bid
    if type(bid) ~= "number" then
        return failure("no_numeric_bid", "write_off requires a numeric contract bid", { bid = bid })
    end

    local count = self._config.players.count
    local sits_out = self._auction and self._auction.sits_out or nil
    local recipients = {}
    for seat = 1, count do
        if seat ~= declarer and seat ~= sits_out then
            recipients[#recipients + 1] = seat
        end
    end

    local deltas = {}
    for seat = 1, count do
        deltas[seat] = 0
    end
    deltas[declarer] = -bid
    local split_mode = self._config.bidding.write_off_split
    if split_mode == "half_to_each" then
        local share = math.floor(bid / 2)
        for _, seat in ipairs(recipients) do
            deltas[seat] = share
        end
    elseif split_mode == "equal_split" then
        if #recipients > 0 then
            local share = math.floor(bid / #recipients)
            for _, seat in ipairs(recipients) do
                deltas[seat] = share
            end
        end
    end

    -- Streak counter. Increment unconditionally so a UI scoreboard can
    -- display progress even when `write_off_streak = "off"`. The
    -- threshold-fire branch only fires when the streak rule is on.
    local pen_rules = self._config.penalties
    local new_count = (self._write_off_counts[declarer] or 0) + 1
    local streak_active = pen_rules.write_off_streak == "any_three"
    if streak_active and new_count >= (pen_rules.write_off_streak_threshold or 3) then
        deltas[declarer] = deltas[declarer] - (pen_rules.write_off_streak_penalty_amount or 120)
        new_count = 0
    end
    self._write_off_counts[declarer] = new_count

    local g = scoring.advance_game(self._config, {
        declarer = declarer,
        deal_index = self._deal_index,
        deltas = deltas,
        running_totals_before = self._running_totals,
        barrel_state_before = self._barrel_state,
        bid = bid,
        declarer_made_contract = false,
        effective_target_before = self._effective_target,
    })
    if not g.ok then
        error("session: advance_game failed (write_off): " .. tostring(g.error.message), 2)
    end
    self._running_totals = g.game.running_totals
    self._barrel_state = g.game.barrel_state
    self._effective_target = g.game.effective_target_after
    if g.game.tiebreaker_continuation_event then
        self._winner = nil
    elseif g.game.winner then
        self._winner = g.game.winner
    end
    if not self._winner then
        self._deal_done = {
            reason = "write_off",
            declarer = declarer,
            deal_scores = deltas,
        }
    end
    -- Drop the live tricks/talon state; the deal is over.
    self._tricks = nil
    self._talon = nil
    self._marriages = nil
    self._pre_first_trick_marriage_queue = nil
    self._raspassy_active = false
    self._awaiting_write_off_decision = nil
    self._write_off_decision_resolved = true
    return { ok = true }
end

return M
