-- The Thousand RuleConfig value object.
--
-- A `RuleConfig` is the single source of truth for every variable rule in
-- the engine: card values, talon size, bid increments, marriage values,
-- trick-play strictness, scoring rounding, barrel rules, target score.
-- Phase 1 ships exactly one instance — `canonical_russian` — but the schema
-- is shaped so Phase 3 variants (Polish, Ukrainian, 2-/4-player, custom)
-- plug in as data only, with no engine code changes.
--
-- Schema. The private `SCHEMA` table is the contract: every field declares
-- its lua_type, default, status (implemented / selectable / deferred), and
-- where applicable, allowed values, min/max, or required nested keys. New
-- toggles in 3.2 land as new SCHEMA entries; the validator below adapts
-- automatically. `M.schema_for(path)` exposes a descriptor for the UI and
-- tests; `M.try_new` and `M.from_json` use the same descriptors to validate.
--
-- Status flags:
--   * "implemented" — the engine reads the field; UI may set any in-range
--     value.
--   * "selectable"  — same as "implemented" for validation; reserved as a
--     UI hint. Phase 3.2 starts using this for toggles whose UI affordances
--     are settled but whose engine behaviour is still landing.
--   * "deferred"    — only the schema's `default` value is accepted. The
--     framework's promise that the engine's reads remain backed by canonical
--     values until a future task flips the flag.
--
-- JSON. `M.to_json(config)` and `M.from_json(string)` round-trip a config
-- through JSON via app/json. The blob includes `schema_version`; mismatched
-- versions are rejected (Phase 9 owns forward migrations).
--
-- Errors. `M.try_new` and `M.from_json` return
--   { ok = true, config = <frozen> }
-- or
--   { ok = false, error = { code = "...", ...context } }
-- following the same envelope core/auction.lua, core/tricks.lua, etc. use.
-- Codes are stable strings; the UI maps them to "rule_config.error.<code>"
-- in the locale tables. `M.new` keeps its current contract and raises on
-- failure for backwards compatibility with the existing engine wiring.
--
-- Immutability: top-level configs and their section sub-tables are wrapped
-- in a write-blocking proxy. Reads pass through; assignments raise. List-
-- and dict-shaped values inside sections (e.g. `cards.trick_rank_order`,
-- `cards.point_values`, `marriages.values`) are plain tables so `#`, `pairs`
-- and `ipairs` work — engine code reads through them constantly. The
-- protection target is accidental writes to named fields like
-- `config.bidding.opening_min`, which the proxy catches loudly.

local json = require("app.json")

local M = {}

M.SCHEMA_VERSION = 1

local RULE_CONFIG_TYPE = "thousand.rule_config"
local SECTION_TYPE = "thousand.rule_config.section"

-- Schema -----------------------------------------------------------------
--
-- `_section_order` doubles as the section traversal order for validation
-- and serialisation, so error reports and JSON output are deterministic.
-- Inside each section, `field_order` plays the same role: cards lists
-- `trick_rank_order` before `point_values` because point_values's
-- `key_set_from` references trick_rank_order.

local SCHEMA = {
    _section_order = {
        "cards",
        "players",
        "dealing",
        "talon",
        "bidding",
        "marriages",
        "tricks",
        "scoring",
        "opening_game",
        "barrel",
        "endgame",
        "specials",
        "penalties",
    },
    schema_version = {
        kind = "leaf",
        lua_type = "number",
        allowed = { 1 },
        default = 1,
        status = "implemented",
    },
    cards = {
        kind = "section",
        field_order = { "trick_rank_order", "point_values" },
        fields = {
            trick_rank_order = {
                kind = "list",
                element_type = "string",
                default = { "9", "J", "Q", "K", "10", "A" },
                status = "implemented",
            },
            point_values = {
                kind = "map",
                value_type = "number",
                key_set_from = "cards.trick_rank_order",
                default = {
                    ["A"] = 11,
                    ["10"] = 10,
                    ["K"] = 4,
                    ["Q"] = 3,
                    ["J"] = 2,
                    ["9"] = 0,
                },
                status = "implemented",
            },
        },
    },
    players = {
        kind = "section",
        field_order = {
            "count",
            "partnership_mode",
            "four_player_config",
            "two_player_config",
        },
        fields = {
            -- Phase 3.2 narrowed this to {2, 3, 4} and flipped the status to
            -- "selectable": the picker can offer any of the three, but
            -- dealing/auction still gate runtime to count == 3 until 3.3
            -- ships built-in 2- and 4-player templates.
            count = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 2, 3, 4 },
                default = 3,
                status = "selectable",
            },
            -- Partnership applies only to the 4-player table (see
            -- docs/variations/four-player.md). Phase 3.6 flipped this to
            -- selectable: 4-player builtins set it to "fixed_across_table"
            -- and the engine pools partner scores.
            partnership_mode = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "none", "fixed_across_table" },
                default = "none",
                status = "selectable",
            },
            -- 4-player seating layout (see docs/variations/four-player.md).
            -- "dealer_plays_no_talon" is Configuration A, the docs' reference;
            -- "dealer_sits_out" is Configuration B. Phase 3.6 flipped this
            -- to selectable; both values run end-to-end.
            four_player_config = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "dealer_plays_no_talon", "dealer_sits_out" },
                default = "dealer_plays_no_talon",
                status = "selectable",
            },
            -- 2-player layout (see docs/variations/two-player.md).
            -- "closed_talon_draw_stock" is Variant A (Schnapsen-style draw);
            -- "fixed_deal_no_draw" is Variant B (8 tricks, identical pattern
            -- to the 3-player game). Phase 3.6 flipped this to selectable.
            two_player_config = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "closed_talon_draw_stock", "fixed_deal_no_draw" },
                default = "closed_talon_draw_stock",
                status = "selectable",
            },
        },
    },
    -- Dealing & redeal house rules. Phase 3.6's dealing-and-redeal
    -- gameplay task flipped each toggle here to "selectable" and added
    -- two sibling fields (`weak_hand_threshold`, `misdeal_flat_penalty`)
    -- the dependent variants reference. The locked-in default of every
    -- field is the value that matches the engine's pre-flip behaviour,
    -- so canonical_russian's gameplay is unchanged unless a custom
    -- template moves a field off its default. See
    -- docs/variations/house-rules.md "Dealing & redeal house rules" for
    -- the spec each toggle maps to.
    dealing = {
        kind = "section",
        field_order = {
            "four_nine_redeal",
            "three_nine_redeal",
            "four_jack_redeal",
            "weak_hand_redeal",
            "weak_hand_threshold",
            "misdeal_handling",
            "misdeal_flat_penalty",
            "all_pass_handling",
        },
        fields = {
            -- A player dealt all four 9s may demand a redeal. "mandatory"
            -- forces the dealer to redeal even if the player would prefer
            -- to play. See house-rules.md "4-nine mandatory redeal".
            four_nine_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "optional", "mandatory" },
                default = "off",
                status = "selectable",
            },
            -- A player dealt three 9s may request a redeal. "optional"
            -- offers the entitled player a choice; "mandatory" forces
            -- the table to redeal even if the player would prefer to
            -- play. See house-rules.md "3-nine optional redeal".
            three_nine_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "optional", "mandatory" },
                default = "off",
                status = "selectable",
            },
            -- A player dealt all four Jacks may request a redeal.
            -- "optional" offers the entitled player a choice;
            -- "mandatory" forces the table to redeal. See
            -- house-rules.md "Four-jack redeal".
            four_jack_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "optional", "mandatory" },
                default = "off",
                status = "selectable",
            },
            -- "Weak hand" entitles the player to request a redeal.
            --   "strict":  no marriage, no Ace, no card above 10.
            --   "loose":   no marriage and no Ace.
            --   "counted": card-point sum below `weak_hand_threshold`.
            -- See house-rules.md "Weak-hand redeal".
            weak_hand_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "strict", "loose", "counted" },
                default = "off",
                status = "selectable",
            },
            -- Card-point threshold for `weak_hand_redeal = "counted"`.
            -- A hand with strictly fewer card-points than this value
            -- is eligible for a redeal request. Inert under any other
            -- `weak_hand_redeal` value; carried in the schema so saved
            -- templates round-trip cleanly. The deck holds 120 card
            -- points, so the field is bounded in [0, 120].
            weak_hand_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 120,
                default = 14,
                status = "selectable",
            },
            -- Misdeal recovery branch.
            --   "standard":     same dealer redeals, no penalty.
            --   "soft_penalty": deal moves clockwise.
            --   "flat_penalty": dealer pays `misdeal_flat_penalty` and
            --                   redeals.
            -- See house-rules.md "Misdeal handling".
            misdeal_handling = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "soft_penalty", "flat_penalty" },
                default = "standard",
                status = "selectable",
            },
            -- Penalty applied when `misdeal_handling = "flat_penalty"`
            -- triggers. Subtracted from the offending dealer's running
            -- total. Inert under any other `misdeal_handling` value;
            -- carried in the schema so saved templates round-trip
            -- cleanly. Bounded in [0, 240] so a single misdeal cannot
            -- exceed the deal's maximum bid range.
            misdeal_flat_penalty = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 20,
                status = "selectable",
            },
            -- Behaviour when nobody bids and no forced-opening / bolt rule
            -- is in effect.
            --   "redeal":   same dealer redeals, no scoring (current UI
            --               flow's "All players passed" → "Next deal").
            --   "pass_out": deal moves clockwise without scoring.
            --   "raspassy": play the deal without trump or bidding, with
            --               the reverse-scoring rule from house-rules.md.
            -- See house-rules.md "All-pass handling".
            all_pass_handling = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "redeal", "pass_out", "raspassy" },
                default = "redeal",
                status = "selectable",
            },
        },
    },
    talon = {
        kind = "section",
        field_order = {
            "size",
            "distribution",
            "flip_after_first_round",
            "pass_the_talon",
            "buyback",
            "buyback_penalty",
            "hidden_on_minimum_100",
            "bad_talon_redeal",
            "bad_talon_threshold",
            "rebuy",
            "rebuy_contract_value",
            "open_discard",
        },
        fields = {
            -- Phase 3.2 narrowed the allowed set to {0, 2, 3} and flipped
            -- the status to "selectable": 0 disables the talon entirely
            -- (some 4-player layouts), 2 is the Polish Tysiąc shape, 3 is
            -- canonical Russian. The picker may surface all three; the
            -- engine still gates runtime to size == 3 until the 2- and
            -- 4-player paths land (see core/dealing.lua's
            -- unsupported_talon_size guard).
            size = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 0, 2, 3 },
                default = 3,
                status = "selectable",
            },
            -- How talon cards reach the players. "declarer_takes_then_passes"
            -- is the standard 3-card Russian flow (docs/rules/talon.md).
            -- "pass_without_taking" matches the Polish 2-card variant where
            -- the declarer never picks the talon up
            -- (docs/variations/polish.md). "stock_draw" is the 2-player
            -- Schnapsen-style closed-talon stock
            -- (docs/variations/two-player.md). Locked to the standard
            -- distribution until those engine paths land.
            distribution = {
                kind = "leaf",
                lua_type = "string",
                allowed = {
                    "declarer_takes_then_passes",
                    "pass_without_taking",
                    "stock_draw",
                },
                default = "declarer_takes_then_passes",
                status = "deferred",
            },
            -- House-rule: keep the talon closed during the first round of
            -- bidding and flip it only if the auction reaches a second
            -- round. Lets first-round bids stay sharp while preserving
            -- talon mystery for serious bids
            -- (docs/variations/house-rules.md).
            flip_after_first_round = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- House-rule: a declarer disgusted with the talon may concede
            -- the deal at the bid before play
            -- (docs/variations/house-rules.md, docs/rules/talon.md).
            pass_the_talon = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- House-rule: declarer may discard the entire hand for a fresh
            -- deal at the `buyback_penalty` cost
            -- (docs/variations/house-rules.md).
            buyback = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Penalty subtracted from the declarer's running total when
            -- `buyback = "on"` is exercised. Inert under `buyback = "off"`;
            -- carried in the schema so saved templates round-trip cleanly.
            -- Bounded in [0, 240] so a single buyback cannot exceed the
            -- deal's maximum bid range.
            buyback_penalty = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 50,
                status = "selectable",
            },
            -- House-rule: when the declarer wins at minimum 100 simply
            -- because everyone else passed, defenders do not see the
            -- talon. Some tables extend this to any forced-100 contract
            -- (bolt or forced opening); see
            -- docs/variations/house-rules.md.
            hidden_on_minimum_100 = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "minimum_100_only", "any_forced_100" },
                default = "off",
                status = "selectable",
            },
            -- House-rule: after the talon is revealed, a worthless talon
            -- triggers a redeal. Some tables allow this only on minimum-100
            -- contracts; others on any contract before the pass step.
            -- Distinct from the dealing-time 4-nine and 3-nine redeals
            -- catalogued in dealing.* — those fire before the auction;
            -- this one fires after the talon reveal. See
            -- docs/variations/house-rules.md.
            bad_talon_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "any_contract", "minimum_100_only" },
                default = "off",
                status = "selectable",
            },
            -- Card-point threshold for `bad_talon_redeal`. A talon with
            -- strictly fewer card-points than this value is eligible for
            -- the redeal offer. Inert under `bad_talon_redeal = "off"`;
            -- carried in the schema so saved templates round-trip cleanly.
            -- Bounded in [0, 30]: 30 is the maximum card-point sum a
            -- 3-card talon can hold (three aces).
            bad_talon_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 30,
                default = 5,
                status = "selectable",
            },
            -- House-rule: another player may "buy the talon away" by
            -- naming a higher fixed contract after seeing the talon,
            -- creating a second auction with full talon information
            -- (docs/variations/house-rules.md). Each non-declarer is
            -- offered the rebuy in clockwise order; the first claim
            -- wins and the claimant becomes the new declarer at the
            -- fixed `rebuy_contract_value`. If everyone passes, the
            -- original declarer keeps the contract.
            rebuy = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Fixed contract value charged to the player who buys the
            -- talon away under `rebuy = "on"`. Bounded in [100, 240]
            -- to match the post-talon bid range. Inert under
            -- `rebuy = "off"`; carried in the schema so saved
            -- templates round-trip cleanly.
            rebuy_contract_value = {
                kind = "leaf",
                lua_type = "number",
                min = 100,
                max = 240,
                default = 240,
                status = "selectable",
            },
            -- House-rule: declarer's discards to opponents are dealt
            -- face-up so defenders see what was thrown away. Mostly a
            -- tournament or analysis rule
            -- (docs/variations/house-rules.md).
            open_discard = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
        },
    },
    -- Bidding rules and house-rule toggles. The first five fields are
    -- "implemented" — the auction reads them. The remaining fields are
    -- the bidding house-rule catalogue from
    -- docs/variations/house-rules.md "Bidding house rules", landing here
    -- as deferred entries so built-in templates and saved customs can
    -- reference them by shape today and the auction can wire them up in
    -- a later task without another schema migration.
    bidding = {
        kind = "section",
        field_order = {
            "opening_min",
            "pre_talon_max",
            "increment_threshold",
            "increment_below_200",
            "increment_from_200",
            "forced_opening",
            "forced_dealer_bid",
            "blind_bid",
            "re_entry_after_pass",
            "contra",
            "forced_bid_concession",
            "no_contract_without_marriage",
            "negative_score_restriction",
            "named_contracts",
        },
        fields = {
            opening_min = {
                kind = "leaf",
                lua_type = "number",
                min = 10,
                default = 100,
                status = "implemented",
            },
            pre_talon_max = {
                kind = "leaf",
                lua_type = "number",
                min = 10,
                default = 120,
                status = "implemented",
            },
            -- The bid amount at which the increment switches from
            -- `increment_below_200` to `increment_from_200`. The field
            -- names keep their canonical-Russian shorthand so existing
            -- code stays readable; the threshold itself moves with the
            -- variant (e.g. 250 in some house-rule sets).
            increment_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 200,
                status = "implemented",
            },
            increment_below_200 = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 5,
                status = "implemented",
            },
            increment_from_200 = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 10,
                status = "implemented",
            },
            -- House-rule: forehand must open the auction at the
            -- minimum bid (cannot pass on the first turn). Speeds up
            -- the auction; eliminates the all-pass non-deal. See
            -- docs/variations/house-rules.md "Forced opening at 100".
            forced_opening = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: when every seat passes, the dealer is
            -- forced into the minimum-100 contract (Ukrainian *бовт*).
            -- Distinct from the zero-tricks penalty (also called
            -- *болт* / *палка*) catalogued under the special-contract
            -- and penalty section. See
            -- docs/variations/house-rules.md "Forced dealer bid (Бовт /
            -- Bolt)" and the warning in
            -- docs/variations/house-rules.md#zero-tricks-penalty-болт--палка.
            forced_dealer_bid = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: a player may make their first bid before
            -- looking at the hand (*в тёмную* / *ciemny*). Successful
            -- blind bids score double; failed blind bids cost double.
            -- The Russian "blind raise after winning the auction"
            -- variant is a separate rule and stays out of this toggle
            -- until a future task differentiates them. See
            -- docs/variations/house-rules.md "Dark / blind bid".
            blind_bid = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "first_bid_double" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: a player who passed in the first round may
            -- re-enter the auction once on a later round. Relaxes the
            -- standard permanent-pass rule. See
            -- docs/variations/house-rules.md "Re-entry after pass".
            re_entry_after_pass = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: defenders may double the declarer's bid
            -- (*contra*) before play; the declarer may redouble
            -- (*rekontra*) in response. `contra_only` permits the
            -- defender double; `contra_and_redouble` adds the
            -- declarer's response. See
            -- docs/variations/house-rules.md "Contra (defender
            -- doubling)".
            contra = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "contra_only", "contra_and_redouble" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: when a player has been forced into the
            -- minimum-100 contract (forced-opening, forced-dealer-bid,
            -- last-bidder-standing) and looks at a hopeless hand, some
            -- tables let them concede before play. The three on-states
            -- map to the documented distribution variants:
            --   "equal_split":  bid divided equally among non-conceders.
            --   "each_full":    every other player gets the full bid.
            --   "preset_ratio": house-defined split.
            -- Distinct from talon.pass_the_talon, which is available
            -- to any declarer after seeing the talon. See
            -- docs/variations/house-rules.md "Forced-bid concession".
            forced_bid_concession = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "equal_split", "each_full", "preset_ratio" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: forbid bidding 120 or higher without a
            -- marriage in the starting hand. The stricter
            -- `capped_by_marriages` variant caps the maximum bid at
            -- `120 + marriage values held`. See
            -- docs/variations/house-rules.md "No contract without
            -- marriage".
            no_contract_without_marriage = {
                kind = "leaf",
                lua_type = "string",
                allowed = {
                    "off",
                    "no_120_without_marriage",
                    "capped_by_marriages",
                },
                default = "off",
                status = "deferred",
            },
            -- House-rule: a player with a negative running score is
            -- barred from active bidding and may only receive the
            -- minimum forced 100 contract. Used at tables that don't
            -- want a falling player to escape the hole by gambling on
            -- big bids. See docs/variations/house-rules.md
            -- "Negative-score bidding restriction".
            negative_score_restriction = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- Umbrella toggle: are the named contract bids (mizère,
            -- slam, open-hand) admissible at the auction? Each
            -- individual contract is its own toggle in the
            -- special-contract-and-penalty section catalogued for a
            -- later Phase 3.2 task; this one exists so the bidding
            -- picker can grey out the umbrella when specials are off.
            -- See docs/variations/house-rules.md "Special contracts".
            named_contracts = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Marriage values and house-rule toggles. The `values` map is
    -- "implemented" — the engine reads each suit's bonus from it. The
    -- remaining fields are the marriage house-rule catalogue from
    -- docs/variations/house-rules.md "Marriage house rules", landing
    -- here as deferred entries so built-in templates and saved customs
    -- can reference them by shape today and the engine can wire them
    -- up in a later task without another schema migration.
    marriages = {
        kind = "section",
        field_order = {
            "values",
            "half_marriage_capture_bonus",
            "trump_activation_timing",
            "marriage_announcement_timing",
            "drowned_marriage",
            "ace_marriage",
            "one_trump_per_deal",
        },
        fields = {
            values = {
                kind = "map",
                value_type = "number",
                required_keys = { "hearts", "diamonds", "clubs", "spades" },
                default = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
                status = "implemented",
            },
            -- House-rule: a defender who captures both the K and the Q
            -- of the same suit in tricks scores a small bonus
            -- (typically ~20 points). Applies only to captured halves,
            -- not declared marriages. See
            -- docs/variations/house-rules.md "Half-marriage capture
            -- bonus".
            half_marriage_capture_bonus = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: when does the declared suit become trump?
            -- Standard `next_trick` defers the switch by one trick;
            -- the `immediate` variant applies trump on the very trick
            -- the K or Q was led, retroactively re-ranking cards
            -- already played to it. See
            -- docs/variations/house-rules.md "Trump activation
            -- timing".
            trump_activation_timing = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "next_trick", "immediate" },
                default = "next_trick",
                status = "deferred",
            },
            -- House-rule: how may a marriage be declared? Standard
            -- `on_lead` requires leading the K or Q while on lead.
            -- `hand_announcement` lets the leader announce from the
            -- hand and play a different card; trump still switches.
            -- `pre_first_trick` restricts declarations to the moment
            -- before the first trick. See
            -- docs/variations/house-rules.md "Marriage announcement
            -- timing".
            marriage_announcement_timing = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "on_lead", "hand_announcement", "pre_first_trick" },
                default = "on_lead",
                status = "deferred",
            },
            -- House-rule: a marriage is *drowned* when an opponent
            -- captures the other half before declaration. The
            -- `retroactive_cancel` variant goes further: a marriage
            -- already declared is retroactively cancelled if its
            -- K or Q is later captured. The `off` default leaves
            -- declared marriages standing once announced. See
            -- docs/variations/house-rules.md "Drowned marriage".
            drowned_marriage = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "retroactive_cancel" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: a player holding all four Aces declares an
            -- *ace marriage* (тузовый марьяж) for ~200 points. The
            -- `on` variant scores the bonus only; `sets_trump` makes
            -- the suit of the first Ace led after declaration the
            -- new trump, replacing the K-Q marriage as the trump
            -- trigger. See docs/variations/house-rules.md "Ace
            -- marriage / Тузовый марьяж".
            ace_marriage = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on", "sets_trump" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: only the first declared marriage in a deal
            -- sets trump; later marriages still score their bonus
            -- but the trump suit no longer flips. Used at tables
            -- that find mid-deal trump-flipping confusing. See
            -- docs/variations/house-rules.md "One trump per deal".
            one_trump_per_deal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Trick-play rules and house-rule toggles. The four `must_*` booleans
    -- are "implemented" — the engine reads them from
    -- core/tricks.lua's legality and required-action computation. The
    -- remaining fields are the trick-play house-rule catalogue from
    -- docs/variations/house-rules.md "Trick-play house rules", landing
    -- here as deferred entries so built-in templates and saved customs
    -- can reference them by shape today and the engine can wire them up
    -- in a later task without another schema migration.
    tricks = {
        kind = "section",
        field_order = {
            "must_follow",
            "must_beat",
            "must_trump",
            "must_overtrump",
            "must_overtake_strictness",
            "must_trump_strictness",
            "defender_must_overtrump_declarer",
            "lazy_revoke",
            "partial_trumping",
            "last_trick_bonus",
            "slam_bonus",
            "slam_against_penalty",
            "lead_trump_after_marriage",
        },
        fields = {
            -- Guarded constant: must-follow is the floor of every Thousand
            -- variant in v1, so the schema accepts only `true`. The field
            -- stays a boolean so the engine read site (core/tricks.lua)
            -- and existing JSON saves keep their shape; the narrower
            -- `allowed` set is the UI / template-editor contract that
            -- prevents anyone from saving a config the engine does not
            -- support.
            must_follow = {
                kind = "leaf",
                lua_type = "boolean",
                allowed = { true },
                default = true,
                status = "implemented",
            },
            must_beat = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
            must_trump = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
            must_overtrump = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
            -- House-rule: how strictly the must-overtake rule applies
            -- when following suit. `standard` is the canonical Russian
            -- read of must-beat; `polish_strict` matches Polish Tysiąc's
            -- *przebijanie*, which carries the obligation forward more
            -- aggressively (e.g. when discarding into a side-suit lead).
            -- See docs/variations/house-rules.md "Trick-play house rules"
            -- and docs/variations/polish.md.
            must_overtake_strictness = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "polish_strict" },
                default = "standard",
                status = "deferred",
            },
            -- House-rule: how strictly must-trump and must-overtrump
            -- apply when void in the led suit. `standard` matches the
            -- four canonical booleans; `polish_strict` enforces the
            -- Polish escalation. See docs/variations/house-rules.md
            -- "Trick-play house rules".
            must_trump_strictness = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "polish_strict" },
                default = "standard",
                status = "deferred",
            },
            -- House-rule: a defender who can overtrump the declarer's
            -- played trump must do so even when not strictly required by
            -- the must-overtrump rule. Used at tables that want
            -- defenders to push declarer harder. See
            -- docs/variations/house-rules.md "Trick-play house rules".
            defender_must_overtrump_declarer = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: misplays (failure to follow / overtake / trump)
            -- are punished only when caught and called before the next
            -- trick is led. After the next lead the misplay stands.
            -- Useful for casual play. See
            -- docs/variations/house-rules.md "Lazy revoke".
            lazy_revoke = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: a defender who cannot beat an existing trump
            -- but holds a lower trump may discard rather than play the
            -- lower trump. Standard Thousand requires playing the trump.
            -- See docs/variations/house-rules.md "Partial trumping".
            partial_trumping = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: the winner of the final (8th) trick earns a
            -- small bonus added to that side's deal score. Common at
            -- many Russian and Polish tables. The bonus value is a
            -- sibling field that lands with the gameplay task. See
            -- docs/variations/house-rules.md "Last-trick bonus".
            last_trick_bonus = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: bonus for the declarer winning all 8 tricks.
            -- `fixed` adds a flat bonus (commonly +60 or +120);
            -- `doubled_bid` doubles the contract value on success. The
            -- amount of the fixed bonus is a sibling field that lands
            -- with the gameplay task. See
            -- docs/variations/house-rules.md "Slam bonus".
            slam_bonus = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "fixed", "doubled_bid" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: defender-side analogue of the slam bonus —
            -- the declarer takes zero tricks and the defenders score a
            -- bonus. Mostly relevant for mizère contracts, but a few
            -- tables use it for ordinary contracts too. See
            -- docs/variations/house-rules.md "Slam bonus".
            slam_against_penalty = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: after declaring a marriage, the declarer must
            -- lead trump on the next trick (not just the K or Q of the
            -- marriage). Some tables enforce this as a strategy lock;
            -- most do not. See docs/variations/house-rules.md
            -- "Lead-trump-after-marriage".
            lead_trump_after_marriage = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Scoring rules and house-rule toggles. `round_to_nearest` is
    -- "implemented" — core/scoring.lua reads it directly. Phase 3.2
    -- widens its allowed set to { 5, 10 } and flips the status to
    -- "selectable" so the picker can offer the coarse-rounding variant
    -- (docs/variations/house-rules.md "Rounding granularity"); the
    -- engine math is generic over any positive integer divisor, so 10
    -- already works without further plumbing. The remaining fields are
    -- the scoring house-rule catalogue from
    -- docs/variations/house-rules.md "Scoring house rules", landing
    -- here as deferred entries so built-in templates and saved customs
    -- can reference them by shape today and the engine can wire them
    -- up in a later task without another schema migration.
    scoring = {
        kind = "section",
        field_order = {
            "round_to_nearest",
            "actual_points_on_success",
            "defender_contributions",
            "failed_contract_distribution",
            "declarer_rounding_before_contract_check",
        },
        fields = {
            round_to_nearest = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 5, 10 },
                default = 5,
                status = "selectable",
            },
            -- House-rule: declarer scores `max(bid, actual deal points)`
            -- on success rather than just the bid value. Reduces
            -- over-bidding pressure. See
            -- docs/variations/house-rules.md "Score actual points on
            -- success".
            actual_points_on_success = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: how defender deal points reach defender
            -- running totals. `standard` credits each defender their
            -- own captured points; `pooled` sums and splits equally.
            -- Almost never used outside partnership variants. See
            -- docs/variations/house-rules.md "Defender contributions".
            defender_contributions = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "pooled" },
                default = "standard",
                status = "deferred",
            },
            -- House-rule: where the bid value "goes" when the
            -- declarer fails. `lost` matches the canonical Russian
            -- rule (declarer's individual loss, defenders unaffected);
            -- the distribution variants split the bid among defenders
            -- with varying severity. `mirrors_forced_concession`
            -- reuses the bidding.forced_bid_concession setting for
            -- consistency. See docs/variations/house-rules.md
            -- "Failed-contract distribution".
            failed_contract_distribution = {
                kind = "leaf",
                lua_type = "string",
                allowed = {
                    "lost",
                    "split_among_defenders",
                    "each_defender_full",
                    "mirrors_forced_concession",
                },
                default = "lost",
                status = "deferred",
            },
            -- House-rule: round the declarer's captured points before
            -- comparing them to the bid. A captured 118 against a 120
            -- bid then rounds up to 120 and makes the contract.
            -- Forgiving to near-misses; reduces over-bidding caution.
            -- See docs/variations/house-rules.md "Declarer rounding
            -- before contract check".
            declarer_rounding_before_contract_check = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Opening-game house rules. The Phase 3.2 catalogue lands a single
    -- entry here — golden deal — leaving room for future opening-game
    -- variants without further section additions. See
    -- docs/variations/house-rules.md "Opening-game house rules".
    opening_game = {
        kind = "section",
        field_order = { "golden_deal" },
        fields = {
            -- House-rule: during the first N deals (typically equal to
            -- the player count) every player in turn must play a
            -- mandatory 120 contract. Penalties and bolts are commonly
            -- doubled. The detail toggles (marriages doubled, blind
            -- play allowed, etc.) are sibling fields that land with
            -- the gameplay task. See docs/variations/house-rules.md
            -- "Golden deal / Золотой кон".
            golden_deal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Barrel rules and house-rule toggles. The first three fields are
    -- "implemented" — core/scoring.lua's barrel state machine reads
    -- each one. The remaining fields are the barrel house-rule
    -- catalogue from docs/variations/house-rules.md "Barrel house
    -- rules", landing here as deferred entries so built-in templates
    -- and saved customs can reference them by shape today and the
    -- engine can wire them up in a later task without another schema
    -- migration.
    barrel = {
        kind = "section",
        field_order = {
            "threshold",
            "deal_count",
            "fall_off_penalty",
            "pit_lock_in",
            "collision_rule",
            "overshoot_penalty",
            "reverse_barrel",
        },
        fields = {
            -- `fall_off_penalty` intentionally omits `min`: -120 is canonical.
            threshold = {
                kind = "leaf",
                lua_type = "number",
                default = 880,
                status = "implemented",
            },
            deal_count = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 3,
                status = "implemented",
            },
            fall_off_penalty = {
                kind = "leaf",
                lua_type = "number",
                default = -120,
                status = "implemented",
            },
            -- House-rule: an intermediate "pit" score (e.g. an at-700
            -- lock-in) that players must clear before approaching the
            -- barrel. The exact pit score is a sibling field that
            -- lands with the gameplay task. See
            -- docs/variations/house-rules.md "Alternative barrel
            -- threshold".
            pit_lock_in = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: who survives when two or more players sit on
            -- the barrel simultaneously. `last_mounter` is the
            -- canonical Russian rule and the barrel state machine's
            -- current default; `first_mounter` and
            -- `all_collide_fall_off` are documented variants. A
            -- relaxed `coexist` mode (multiple players on the barrel
            -- without collision) is its own deferred catalogue entry
            -- in the bigger barrel-rules cluster and lands with the
            -- gameplay task. See docs/variations/house-rules.md
            -- "Barrel collisions".
            collision_rule = {
                kind = "leaf",
                lua_type = "string",
                allowed = {
                    "last_mounter",
                    "first_mounter",
                    "all_collide_fall_off",
                },
                default = "last_mounter",
                status = "deferred",
            },
            -- House-rule: bidding far above the 120 needed (e.g. 200)
            -- while on the barrel and failing incurs an extra
            -- penalty. Discourages "hero" bids. See
            -- docs/variations/house-rules.md "Barrel-jump penalty".
            overshoot_penalty = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: a symmetric variant for failing players. At
            -- -880, a player enters a reverse barrel: 3 deals to
            -- reach -1000 (which would lose the game outright);
            -- failing falls them back to a pre-agreed score. See
            -- docs/variations/house-rules.md "Reverse barrel".
            reverse_barrel = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Endgame rules and house-rule toggles. `target_score` is
    -- "implemented" — core/scoring.lua reads it directly. The
    -- remaining fields are the endgame house-rule catalogue from
    -- docs/variations/house-rules.md "Endgame house rules", landing
    -- here as deferred entries so built-in templates and saved
    -- customs can reference them by shape today and the engine can
    -- wire them up in a later task without another schema migration.
    endgame = {
        kind = "section",
        field_order = {
            "target_score",
            "going_over_target",
            "tiebreaker",
            "dump_truck",
        },
        fields = {
            target_score = {
                kind = "leaf",
                lua_type = "number",
                default = 1000,
                status = "implemented",
            },
            -- House-rule: what happens when a player exceeds the
            -- target in a single deal. `win_immediately` matches the
            -- canonical Russian rule; `exact_only` caps at
            -- `target_score - 1` and continues play until someone
            -- lands exactly on the target. See
            -- docs/variations/house-rules.md "Going over the target".
            going_over_target = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "win_immediately", "exact_only" },
                default = "win_immediately",
                status = "deferred",
            },
            -- House-rule: how to break a tie when two or more players
            -- cross the target in the same deal. `declarer_wins` is
            -- the canonical Russian rule; `high_score` awards the
            -- player with the highest running total; `continuation`
            -- raises the target by +500 and continues play. See
            -- docs/variations/house-rules.md "Tiebreakers".
            tiebreaker = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "declarer_wins", "high_score", "continuation" },
                default = "declarer_wins",
                status = "deferred",
            },
            -- House-rule: dump-truck / самосвал — landing on a
            -- specific score (commonly +555) resets the running total
            -- to zero. `positive_only` triggers on +555 only;
            -- `both_signs` triggers on -555 too. See
            -- docs/variations/house-rules.md "Dump truck / Самосвал".
            dump_truck = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "positive_only", "both_signs" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Special-contract toggles. Each named contract is a single
    -- on/off here; the bidding-section umbrella `named_contracts`
    -- gates whether any of them are admissible at the auction. The
    -- contract values (mizère = 120, slam = 240/300/double, etc.)
    -- are sibling fields that land with the gameplay task. See
    -- docs/variations/house-rules.md "Special contracts" and the
    -- bidding.named_contracts comment.
    specials = {
        kind = "section",
        field_order = { "mizere", "slam_contract", "open_hand" },
        fields = {
            -- Mizère / минимум: declarer commits to taking zero
            -- tricks in a no-trump deal. Fixed contract value
            -- (commonly 120). See docs/variations/house-rules.md
            -- "Mizère / Минимум".
            mizere = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- Slam: declarer commits to taking all 8 tricks. Common
            -- contract values are 240, 300, or simply double the
            -- highest numeric bid. See
            -- docs/variations/house-rules.md "Slam contract".
            slam_contract = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- Open hand: declarer plays the entire deal face-up.
            -- Scoring is doubled on both success and failure. Almost
            -- exclusively a tournament curiosity. See
            -- docs/variations/house-rules.md "Open hand".
            open_hand = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
    -- Penalty house-rule toggles. Phase 3.2 catalogues the shape;
    -- penalty amounts (e.g. flat 120 for revoke, 20 for showing
    -- hand) are sibling fields that land with the gameplay task.
    -- See docs/variations/house-rules.md "Penalty house rules".
    penalties = {
        kind = "section",
        field_order = {
            "revoke",
            "talon_look",
            "showing_hand",
            "zero_tricks",
            "cross",
        },
        fields = {
            -- House-rule: penalty for revoking. `standard` awards
            -- the declarer's full bid to the opposing side; `flat`
            -- awards 120 regardless of bid; `configurable` lets the
            -- house pick a fixed amount (the amount is a sibling
            -- field that lands with the gameplay task). See
            -- docs/variations/house-rules.md "Revoke penalty".
            revoke = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "flat", "configurable" },
                default = "standard",
                status = "deferred",
            },
            -- House-rule: penalty for looking at the talon before
            -- the auction ends. `standard` deducts 120 and redeals;
            -- `stricter` forfeits the deal and awards the bid to
            -- the opposing side. See
            -- docs/variations/house-rules.md "Talon-look penalty".
            talon_look = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "stricter" },
                default = "standard",
                status = "deferred",
            },
            -- House-rule: penalty for showing one's hand to an
            -- opponent. `standard` is a small fixed penalty
            -- (typically 20); `strict` deducts the full bid. See
            -- docs/variations/house-rules.md "Showing-hand penalty".
            showing_hand = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "strict" },
                default = "standard",
                status = "deferred",
            },
            -- House-rule: zero-tricks penalty / болт / палка.
            -- `consecutive_three` resets the bolt counter on any
            -- trick taken; `any_three` is cumulative across the
            -- game. The variant flags (declarer exempt, doubled in
            -- golden deal) are sibling fields that land with the
            -- gameplay task. See docs/variations/house-rules.md
            -- "Zero-tricks penalty (Болт / Палка)" — distinct from
            -- the bidding-section forced_dealer_bid (also called
            -- бовт/болт but a forced 100 contract, not a zero-tricks
            -- penalty).
            zero_tricks = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "consecutive_three", "any_three" },
                default = "off",
                status = "deferred",
            },
            -- House-rule: cross / крест — alternative penalty path
            -- for failed contracts. After accumulating two crosses,
            -- the declarer receives a fixed penalty and the cross
            -- counter clears. See docs/variations/house-rules.md
            -- "Cross / Крест".
            cross = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
        },
    },
}

-- Cross-field invariants. Each entry's `predicate` returns true when the
-- rule is satisfied; `context` returns a table of detail fields the UI
-- feeds into t("rule_config.invariant." .. name, context).

local INVARIANTS = {
    {
        name = "pre_talon_max_ge_opening_min",
        predicate = function(blob)
            return blob.bidding.pre_talon_max >= blob.bidding.opening_min
        end,
        context = function(blob)
            return {
                pre_talon_max = blob.bidding.pre_talon_max,
                opening_min = blob.bidding.opening_min,
            }
        end,
    },
    {
        name = "barrel_threshold_below_target",
        predicate = function(blob)
            return blob.barrel.threshold < blob.endgame.target_score
        end,
        context = function(blob)
            return {
                threshold = blob.barrel.threshold,
                target_score = blob.endgame.target_score,
            }
        end,
    },
    -- Phase 3.6 flipped partnership_mode to selectable; the invariant
    -- lives here so 4-player partnerships are the only legal place for
    -- "fixed_across_table". See docs/variations/four-player.md.
    {
        name = "partnership_mode_requires_four_players",
        predicate = function(blob)
            return blob.players.partnership_mode == "none" or blob.players.count == 4
        end,
        context = function(blob)
            return {
                partnership_mode = blob.players.partnership_mode,
                count = blob.players.count,
            }
        end,
    },
    -- Configuration A is "no talon, 6 cards each" by spec — flag a
    -- talon.size mismatch loudly rather than dealing nonsense at
    -- runtime. See docs/variations/four-player.md "Configuration A".
    {
        name = "four_player_a_requires_no_talon",
        predicate = function(blob)
            if blob.players.count ~= 4 then
                return true
            end
            if blob.players.four_player_config ~= "dealer_plays_no_talon" then
                return true
            end
            return blob.talon.size == 0
        end,
        context = function(blob)
            return {
                four_player_config = blob.players.four_player_config,
                talon_size = blob.talon.size,
            }
        end,
    },
    -- Configuration B is "dealer sits out, otherwise standard 3-player"
    -- — must keep the canonical 3-card talon. See
    -- docs/variations/four-player.md "Configuration B".
    {
        name = "four_player_b_requires_three_card_talon",
        predicate = function(blob)
            if blob.players.count ~= 4 then
                return true
            end
            if blob.players.four_player_config ~= "dealer_sits_out" then
                return true
            end
            return blob.talon.size == 3
        end,
        context = function(blob)
            return {
                four_player_config = blob.players.four_player_config,
                talon_size = blob.talon.size,
            }
        end,
    },
    -- Variant A's 6-card stock is dealt separately from any traditional
    -- talon — the schema's talon.size is 0 in this layout. The stock
    -- itself is fixed at 6 cards (24 - 9 - 9). See
    -- docs/variations/two-player.md "Variant A".
    {
        name = "two_player_a_requires_no_talon",
        predicate = function(blob)
            if blob.players.count ~= 2 then
                return true
            end
            if blob.players.two_player_config ~= "closed_talon_draw_stock" then
                return true
            end
            return blob.talon.size == 0
        end,
        context = function(blob)
            return {
                two_player_config = blob.players.two_player_config,
                talon_size = blob.talon.size,
            }
        end,
    },
    -- Variant B keeps the canonical 3-card talon (declarer takes, passes
    -- one to the opponent, discards one to the captured pile). See
    -- docs/variations/two-player.md "Variant B".
    {
        name = "two_player_b_requires_three_card_talon",
        predicate = function(blob)
            if blob.players.count ~= 2 then
                return true
            end
            if blob.players.two_player_config ~= "fixed_deal_no_draw" then
                return true
            end
            return blob.talon.size == 3
        end,
        context = function(blob)
            return {
                two_player_config = blob.players.two_player_config,
                talon_size = blob.talon.size,
            }
        end,
    },
}

-- Validation -------------------------------------------------------------

local function failure(code, extra)
    local err = { code = code }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function in_set(value, allowed)
    if not allowed then
        return true
    end
    for _, candidate in ipairs(allowed) do
        if value == candidate then
            return true
        end
    end
    return false
end

local function set_from_list(t)
    local out = {}
    for _, v in ipairs(t) do
        out[v] = true
    end
    return out
end

local function format_path(parts)
    return table.concat(parts, ".")
end

local function describe_value_short(v)
    local tv = type(v)
    if tv == "string" then
        return string.format("%q", v)
    elseif tv == "table" then
        return "<table>"
    end
    return tostring(v)
end

local function format_allowed(allowed)
    if not allowed then
        return "[]"
    end
    local parts = {}
    for i, v in ipairs(allowed) do
        parts[i] = describe_value_short(v)
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function lookup_path(blob, path)
    local current = blob
    for segment in tostring(path):gmatch("[^.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[segment]
    end
    return current
end

local function child_path(path, segment)
    local out = {}
    for i = 1, #path do
        out[i] = path[i]
    end
    out[#out + 1] = tostring(segment)
    return out
end

local function validate_leaf(value, descriptor, path)
    if type(value) ~= descriptor.lua_type then
        return failure("type_mismatch", {
            path = format_path(path),
            expected = descriptor.lua_type,
            actual = type(value),
        })
    end
    if descriptor.status == "deferred" and not deep_equal(value, descriptor.default) then
        return failure("deferred_field_changed", { path = format_path(path) })
    end
    if not in_set(value, descriptor.allowed) then
        return failure("value_not_allowed", {
            path = format_path(path),
            value = value,
            allowed = format_allowed(descriptor.allowed),
        })
    end
    if descriptor.min and value < descriptor.min then
        return failure("value_out_of_range", {
            path = format_path(path),
            value = value,
        })
    end
    if descriptor.max and value > descriptor.max then
        return failure("value_out_of_range", {
            path = format_path(path),
            value = value,
        })
    end
    return { ok = true }
end

local function is_dense_array(t)
    local n = #t
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 or k > n then
            return false
        end
        count = count + 1
    end
    return count == n
end

local function validate_list(value, descriptor, path)
    if type(value) ~= "table" or not is_dense_array(value) then
        return failure("type_mismatch", {
            path = format_path(path),
            expected = "list",
            actual = type(value) == "table" and "non-list table" or type(value),
        })
    end
    if descriptor.status == "deferred" and not deep_equal(value, descriptor.default) then
        return failure("deferred_field_changed", { path = format_path(path) })
    end
    if descriptor.element_type then
        for i = 1, #value do
            if type(value[i]) ~= descriptor.element_type then
                return failure("type_mismatch", {
                    path = format_path(child_path(path, i)),
                    expected = descriptor.element_type,
                    actual = type(value[i]),
                })
            end
        end
    end
    return { ok = true }
end

local function validate_map(value, descriptor, path, full_blob)
    if type(value) ~= "table" then
        return failure("type_mismatch", {
            path = format_path(path),
            expected = "table",
            actual = type(value),
        })
    end
    if descriptor.status == "deferred" and not deep_equal(value, descriptor.default) then
        return failure("deferred_field_changed", { path = format_path(path) })
    end
    local required
    if descriptor.required_keys then
        required = descriptor.required_keys
    elseif descriptor.key_set_from then
        local resolved = lookup_path(full_blob, descriptor.key_set_from)
        if type(resolved) ~= "table" then
            return failure("missing_field", { path = descriptor.key_set_from })
        end
        required = resolved
    end
    if required then
        for _, key in ipairs(required) do
            local entry = value[key]
            if entry == nil then
                return failure("missing_field", {
                    path = format_path(child_path(path, key)),
                })
            end
            if descriptor.value_type and type(entry) ~= descriptor.value_type then
                return failure("type_mismatch", {
                    path = format_path(child_path(path, key)),
                    expected = descriptor.value_type,
                    actual = type(entry),
                })
            end
        end
    end
    return { ok = true }
end

local function dispatch_validate(value, descriptor, path, full_blob)
    if descriptor.kind == "leaf" then
        return validate_leaf(value, descriptor, path)
    elseif descriptor.kind == "list" then
        return validate_list(value, descriptor, path)
    elseif descriptor.kind == "map" then
        return validate_map(value, descriptor, path, full_blob)
    end
    error("rule_config: bad schema descriptor at " .. format_path(path), 2)
end

local function validate_section(blob, name, section_schema)
    local section = blob[name]
    if section == nil then
        return failure("missing_field", { path = name })
    end
    if type(section) ~= "table" then
        return failure("type_mismatch", {
            path = name,
            expected = "table",
            actual = type(section),
        })
    end
    local known = set_from_list(section_schema.field_order)
    for k in pairs(section) do
        if not known[k] then
            return failure("unknown_field", { path = name .. "." .. tostring(k) })
        end
    end
    for _, field_name in ipairs(section_schema.field_order) do
        local descriptor = section_schema.fields[field_name]
        local value = section[field_name]
        if value == nil then
            return failure("missing_field", { path = name .. "." .. field_name })
        end
        local res = dispatch_validate(value, descriptor, { name, field_name }, blob)
        if not res.ok then
            return res
        end
    end
    return { ok = true }
end

local function validate_blob(blob, schema, invariants)
    schema = schema or SCHEMA
    if type(blob) ~= "table" then
        return failure("not_a_table", { actual = type(blob) })
    end

    local section_order = schema._section_order
    if type(section_order) ~= "table" then
        error("rule_config: schema is missing _section_order", 2)
    end

    -- Schema version. All failures funnel into one code so the UI can
    -- distinguish "save from a different build" from generic validation.
    local sv_descriptor = schema.schema_version
    local sv = blob.schema_version
    if type(sv) ~= sv_descriptor.lua_type or not in_set(sv, sv_descriptor.allowed) then
        return failure("unsupported_schema_version", {
            version = sv,
            supported = format_allowed(sv_descriptor.allowed),
        })
    end

    -- Top-level unknown-key rejection.
    local known_top = { schema_version = true }
    for _, name in ipairs(section_order) do
        known_top[name] = true
    end
    for k in pairs(blob) do
        if not known_top[k] then
            return failure("unknown_field", { path = tostring(k) })
        end
    end

    -- Sections in declared order.
    for _, name in ipairs(section_order) do
        local section_schema = schema[name]
        if section_schema and section_schema.kind == "section" then
            local section_res = validate_section(blob, name, section_schema)
            if not section_res.ok then
                return section_res
            end
        end
    end

    -- Cross-field invariants. Default-on for the production schema only;
    -- a custom test schema opts in by passing its own list (or `nil` for
    -- "no invariants" — the default for any non-production schema).
    local effective
    if invariants ~= nil then
        effective = invariants
    elseif schema == SCHEMA then
        effective = INVARIANTS
    else
        effective = {}
    end
    for _, invariant in ipairs(effective) do
        if not invariant.predicate(blob) then
            local context = invariant.context(blob)
            context.invariant = invariant.name
            return failure("incompatible_combination", context)
        end
    end

    return { ok = true }
end

-- Construction -----------------------------------------------------------

local function freeze(data, type_marker)
    return setmetatable({}, {
        __index = data,
        __newindex = function(_, key)
            error("rule_config is frozen: cannot set key " .. tostring(key), 2)
        end,
        __metatable = type_marker,
    })
end

local function build_frozen(blob)
    local data = { schema_version = blob.schema_version }
    for _, name in ipairs(SCHEMA._section_order) do
        data[name] = freeze(blob[name], SECTION_TYPE)
    end
    return freeze(data, RULE_CONFIG_TYPE)
end

function M.try_new(blob)
    local res = validate_blob(blob)
    if not res.ok then
        return res
    end
    return { ok = true, config = build_frozen(blob) }
end

function M.new(blob)
    local res = M.try_new(blob)
    if res.ok then
        return res.config
    end
    -- Render a developer-facing summary. Existing tests use `assert.has_error`,
    -- so the exact text is not pinned; the error code is the contract for
    -- anyone inspecting structured diagnostics.
    local err = res.error
    local parts = { "rule_config: " .. tostring(err.code) }
    for k, v in pairs(err) do
        if k ~= "code" then
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    error(table.concat(parts, " "), 2)
end

function M.is_rule_config(v)
    if type(v) ~= "table" then
        return false
    end
    return getmetatable(v) == RULE_CONFIG_TYPE
end

-- Schema reflection ------------------------------------------------------

local function clone_descriptor(node)
    local out = {}
    for k, v in pairs(node) do
        if type(v) == "table" then
            local copy = {}
            for ki, vi in pairs(v) do
                copy[ki] = vi
            end
            out[k] = copy
        else
            out[k] = v
        end
    end
    return out
end

function M.sections()
    local out = {}
    for i, name in ipairs(SCHEMA._section_order) do
        out[i] = name
    end
    return out
end

function M.schema_for(path)
    if type(path) ~= "string" then
        return nil
    end
    local segments = {}
    for s in path:gmatch("[^.]+") do
        segments[#segments + 1] = s
    end
    if #segments == 0 then
        return nil
    end
    local first = segments[1]
    if first == "schema_version" and #segments == 1 then
        return clone_descriptor(SCHEMA.schema_version)
    end
    local section = SCHEMA[first]
    if not section or section.kind ~= "section" then
        return nil
    end
    if #segments == 1 then
        local fields = {}
        for i, name in ipairs(section.field_order) do
            fields[i] = name
        end
        return { kind = "section", fields = fields }
    end
    if #segments ~= 2 then
        return nil
    end
    local descriptor = section.fields[segments[2]]
    if not descriptor then
        return nil
    end
    return clone_descriptor(descriptor)
end

-- JSON round-trip --------------------------------------------------------

local function plain_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = plain_copy(v)
    end
    return out
end

function M.to_json(config)
    if not M.is_rule_config(config) then
        error("rule_config.to_json expects a RuleConfig, got " .. type(config), 2)
    end
    local data = { schema_version = config.schema_version }
    for _, name in ipairs(SCHEMA._section_order) do
        local section_schema = SCHEMA[name]
        local section_out = {}
        for _, field_name in ipairs(section_schema.field_order) do
            section_out[field_name] = plain_copy(config[name][field_name])
        end
        data[name] = section_out
    end
    return json.encode(data)
end

function M.from_json(s)
    if type(s) ~= "string" then
        return failure("type_mismatch", {
            path = "json",
            expected = "string",
            actual = type(s),
        })
    end
    local decoded, err = json.decode(s)
    if decoded == nil then
        return failure("json_decode_failed", { details = tostring(err) })
    end
    return M.try_new(decoded)
end

-- Test hook: run validation only, optionally against a custom schema and
-- a custom invariants list. Mirrors app/i18n.lua's `_set_locale_table` /
-- `_reset` convention. Used by specs to exercise the deferred-field path,
-- alternative schema shapes, and invariants whose target field is still
-- deferred in production (so try_new can't reach the predicate).
function M._validate(blob, schema_override, invariants_override)
    return validate_blob(blob, schema_override, invariants_override)
end

-- Test hook: returns a shallow copy of the production INVARIANTS list so
-- specs can assert wiring without reaching into the module's locals.
function M._invariants()
    local copy = {}
    for i, inv in ipairs(INVARIANTS) do
        copy[i] = inv
    end
    return copy
end

-- Canonical instance -----------------------------------------------------
--
-- The canonical-Russian blob lives in a builder function so each Phase 3.3
-- regional / player-count variant can start from a fresh copy and overlay
-- the handful of fields that distinguish it. Variants must never mutate the
-- canonical instance: it is frozen, and shared sub-tables would alias the
-- canonical config's sections.

local function canonical_russian_blob()
    return {
        schema_version = 1,
        cards = {
            point_values = {
                ["A"] = 11,
                ["10"] = 10,
                ["K"] = 4,
                ["Q"] = 3,
                ["J"] = 2,
                ["9"] = 0,
            },
            trick_rank_order = { "9", "J", "Q", "K", "10", "A" },
        },
        players = {
            count = 3,
            partnership_mode = "none",
            four_player_config = "dealer_plays_no_talon",
            two_player_config = "closed_talon_draw_stock",
        },
        dealing = {
            four_nine_redeal = "off",
            three_nine_redeal = "off",
            four_jack_redeal = "off",
            weak_hand_redeal = "off",
            weak_hand_threshold = 14,
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
        },
        talon = {
            size = 3,
            distribution = "declarer_takes_then_passes",
            flip_after_first_round = "off",
            pass_the_talon = "off",
            buyback = "off",
            buyback_penalty = 50,
            hidden_on_minimum_100 = "off",
            bad_talon_redeal = "off",
            bad_talon_threshold = 5,
            rebuy = "off",
            rebuy_contract_value = 240,
            open_discard = "off",
        },
        bidding = {
            opening_min = 100,
            pre_talon_max = 120,
            increment_threshold = 200,
            increment_below_200 = 5,
            increment_from_200 = 10,
            forced_opening = "off",
            forced_dealer_bid = "off",
            blind_bid = "off",
            re_entry_after_pass = "off",
            contra = "off",
            forced_bid_concession = "off",
            no_contract_without_marriage = "off",
            negative_score_restriction = "off",
            named_contracts = "off",
        },
        marriages = {
            values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
            half_marriage_capture_bonus = "off",
            trump_activation_timing = "next_trick",
            marriage_announcement_timing = "on_lead",
            drowned_marriage = "off",
            ace_marriage = "off",
            one_trump_per_deal = "off",
        },
        tricks = {
            must_follow = true,
            must_beat = true,
            must_trump = true,
            must_overtrump = true,
            must_overtake_strictness = "standard",
            must_trump_strictness = "standard",
            defender_must_overtrump_declarer = "off",
            lazy_revoke = "off",
            partial_trumping = "off",
            last_trick_bonus = "off",
            slam_bonus = "off",
            slam_against_penalty = "off",
            lead_trump_after_marriage = "off",
        },
        scoring = {
            round_to_nearest = 5,
            actual_points_on_success = "off",
            defender_contributions = "standard",
            failed_contract_distribution = "lost",
            declarer_rounding_before_contract_check = "off",
        },
        opening_game = { golden_deal = "off" },
        barrel = {
            threshold = 880,
            deal_count = 3,
            fall_off_penalty = -120,
            pit_lock_in = "off",
            collision_rule = "last_mounter",
            overshoot_penalty = "off",
            reverse_barrel = "off",
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
        },
        specials = {
            mizere = "off",
            slam_contract = "off",
            open_hand = "off",
        },
        penalties = {
            revoke = "standard",
            talon_look = "standard",
            showing_hand = "standard",
            zero_tricks = "off",
            cross = "off",
        },
    }
end

local function with_overrides(blob, overrides)
    for section, fields in pairs(overrides) do
        local target = blob[section]
        if type(target) ~= "table" then
            error("rule_config builtins: unknown section '" .. tostring(section) .. "'", 2)
        end
        for key, value in pairs(fields) do
            target[key] = value
        end
    end
    return blob
end

M.canonical_russian = M.new(canonical_russian_blob())

-- Built-in templates -----------------------------------------------------
--
-- Each entry is a constant `RuleConfig` value. Phase 3.3 ships these as
-- data only — no engine code per variant. Where a variant's documented
-- "characteristic" rule maps to a toggle still flagged `deferred` in
-- Phase 3.2's schema (e.g. Polish strict *przebijanie*, Ukrainian *bolt*),
-- the template stays at the schema's locked-in default and a comment
-- names the Phase 3.6 task that flips the toggle to selectable. Engine
-- support for the non-Russian shapes (dealing.lua's
-- `unsupported_player_count` / `unsupported_talon_size` guards, the
-- per-variant trick-play / barrel / bidding behaviour) also lands in
-- Phase 3.6; see docs/development/task-list.md "3.6 Toggle gameplay".
--
-- The `russian` entry is an alias for `canonical_russian` so the picker
-- and template registry can treat it like every other built-in without
-- breaking the existing `canonical_russian` callsites (auto-save, the
-- session bootstrap, every `core/` spec).

M.builtins = {
    russian = M.canonical_russian,

    -- Polish Tysiąc (docs/variations/polish.md): 2-card talon (declarer
    -- never picks it up; one card goes face-down to each opponent),
    -- bidding climbs in 10-step increments throughout the auction (no
    -- 5-step phase below 200). The schema-deferred Polish tells —
    -- `talon.distribution = "pass_without_taking"` and
    -- `tricks.must_overtake_strictness = "polish_strict"` — flip to
    -- selectable in Phase 3.6.
    polish = M.new(with_overrides(canonical_russian_blob(), {
        talon = { size = 2 },
        bidding = {
            increment_below_200 = 10,
            increment_from_200 = 10,
        },
    })),

    -- Ukrainian Тисяча (docs/variations/ukrainian.md): tighter
    -- two-deal barrel rather than the canonical three. The bolt rule
    -- (`bidding.forced_dealer_bid = "on"`) is the other defining
    -- Ukrainian house rule but still deferred in Phase 3.2's schema;
    -- it lands in Phase 3.6's bidding-house-rules task.
    ukrainian = M.new(with_overrides(canonical_russian_blob(), {
        barrel = { deal_count = 2 },
    })),

    -- Two-player Variant A — closed talon, draw stock
    -- (docs/variations/two-player.md). The 6-card stock is dealt
    -- separately from any traditional talon, so `talon.size = 0`; the
    -- draw mechanic and trump-from-stock-bottom rule live in the
    -- engine's two-player path keyed off
    -- `players.two_player_config = "closed_talon_draw_stock"`.
    two_player_a = M.new(with_overrides(canonical_russian_blob(), {
        players = {
            count = 2,
            two_player_config = "closed_talon_draw_stock",
        },
        talon = { size = 0 },
    })),

    -- Two-player Variant B — fixed deal, no draw, 7-card hands and the
    -- standard 3-card talon (docs/variations/two-player.md). Declarer
    -- takes the 3-card talon, passes 1 to the opponent face-down, and
    -- discards 1 to the captured pile to reach 8/8 before the first
    -- trick.
    two_player_b = M.new(with_overrides(canonical_russian_blob(), {
        players = {
            count = 2,
            two_player_config = "fixed_deal_no_draw",
        },
    })),

    -- Four-player Variant A — dealer plays, no talon, 6 cards each;
    -- played in fixed across-the-table partnerships
    -- (docs/variations/four-player.md). `talon.size = 0` reflects the
    -- no-talon shape; `partnership_mode = "fixed_across_table"` pools
    -- partner scores at deal-end.
    four_player_a = M.new(with_overrides(canonical_russian_blob(), {
        players = {
            count = 4,
            four_player_config = "dealer_plays_no_talon",
            partnership_mode = "fixed_across_table",
        },
        talon = { size = 0 },
    })),

    -- Four-player Variant B — dealer sits out, otherwise standard
    -- 3-player rules; played in fixed across-the-table partnerships
    -- (docs/variations/four-player.md). The dealer's seat is inactive
    -- for the deal; the three remaining seats run the canonical 3-card
    -- talon flow but the dealer's partner still pools captured points.
    four_player_b = M.new(with_overrides(canonical_russian_blob(), {
        players = {
            count = 4,
            four_player_config = "dealer_sits_out",
            partnership_mode = "fixed_across_table",
        },
    })),
}

return M
