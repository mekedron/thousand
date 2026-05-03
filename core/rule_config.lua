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
            "two_nines_in_talon_redeal",
            "misdeal_handling",
            "misdeal_flat_penalty",
            "all_pass_handling",
            "deck_size",
            "cut_deck_nine_jack_penalty",
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
            -- Book-rule: presence of exactly two 9s in the talon
            -- (widow / прикуп) entitles the declarer to demand a
            -- redeal after the talon is revealed. Distinct from the
            -- threshold-based `talon.bad_talon_redeal`: this fires
            -- on a 9-count predicate, not a card-point sum. The mode
            -- names mirror `talon.bad_talon_redeal`:
            --   "off":              never offered.
            --   "any_contract":     offered regardless of contract.
            --   "minimum_100_only": offered only when the contract
            --                       sits at or above 100. See
            -- docs/variations/house-rules.md "Two nines in the talon
            -- redeal".
            two_nines_in_talon_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "any_contract", "minimum_100_only" },
                default = "off",
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
            -- Book-rule, deferred: a 32-card deck (sixes through aces,
            -- with sevens worth 7 and eights worth 0) is the book's
            -- optional alternative to the canonical 24-card deck.
            -- Out of scope for v1; the field is here so saved
            -- templates round-trip cleanly. Only the schema's default
            -- ("24") is accepted today — `M.try_new` rejects "32"
            -- with `deferred_field_changed`.
            deck_size = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "24", "32" },
                default = "24",
                status = "deferred",
            },
            -- Book-rule, deferred: when the dealer cuts the deck and
            -- a 9 (or, in some agreements, a J) lands at the bottom,
            -- the deck is re-cut; the third occurrence assigns the
            -- standard penalty to the dealer. Procedural — not
            -- suitable for software simulation, where the cut is
            -- replaced by a deterministic shuffle. The field is here
            -- so saved templates round-trip cleanly. Only the
            -- schema's default ("off") is accepted today.
            cut_deck_nine_jack_penalty = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "redeal_after_three" },
                default = "off",
                status = "deferred",
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
            -- Allowed set {0, 2, 3}: 0 disables the talon entirely (some
            -- 4-player layouts), 2 is the Polish Tysiąc shape, 3 is
            -- canonical Russian / Ukrainian / 2-player B / 4-player B.
            -- Phase 3.6's Polish 2-card task wired the engine to read the
            -- value at runtime (dealer + talon module both branch on it),
            -- flipping this field to "implemented".
            size = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 0, 2, 3 },
                default = 3,
                status = "implemented",
            },
            -- How talon cards reach the players.
            -- Per-value status:
            --   * "declarer_takes_then_passes" — implemented; the standard
            --     3-card Russian flow (docs/rules/talon.md).
            --   * "pass_without_taking" — selectable; the Polish 2-card
            --     variant where the declarer never picks the talon up and
            --     instead passes one card face-down to each opponent
            --     (docs/variations/polish.md). Wired in Phase 3.6.
            --   * "stock_draw" — selectable; the 2-player Schnapsen-style
            --     closed-talon stock (docs/variations/two-player.md
            --     "Variant A"). Wired in Phase 3.6's 2-player
            --     stock-draw task. The stock-draw mechanic itself
            --     (deal, per-trick draw, phase=draw → strict transition)
            --     lives in core/dealing.lua and core/tricks.lua, keyed
            --     off `players.two_player_config = "closed_talon_draw_stock"`;
            --     the cross-field invariant
            --     `stock_draw_distribution_requires_variant_a` keeps the
            --     two settings consistent.
            -- Field-level status reflects the most-permissive value the
            -- picker may select; per-value gating is enforced by the
            -- engine and the cross-field invariants below.
            distribution = {
                kind = "leaf",
                lua_type = "string",
                allowed = {
                    "declarer_takes_then_passes",
                    "pass_without_taking",
                    "stock_draw",
                },
                default = "declarer_takes_then_passes",
                status = "selectable",
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
    -- docs/variations/house-rules.md "Bidding house rules". Phase 3.6's
    -- bidding-house-rules task flipped the nine toggles to "selectable"
    -- and added six sibling fields (multipliers + the preset-ratio split
    -- + the named-contract precedence list) plus four cross-field
    -- invariants tying everything together.
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
            "blind_bid_success_multiplier",
            "blind_bid_failure_multiplier",
            "re_entry_after_pass",
            "contra",
            "contra_multiplier",
            "redouble_multiplier",
            "forced_bid_concession",
            "forced_bid_concession_preset_ratio",
            "write_off",
            "write_off_split",
            "no_contract_without_marriage",
            "negative_score_restriction",
            "named_contracts",
            "named_contracts_precedence",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
            },
            -- Sibling of `blind_bid`. Multiplier applied to the
            -- declarer's deal score when a successful contract was
            -- declared in the dark. Defaults to 2 (the canonical
            -- "double on success") and is inert while
            -- `blind_bid = "off"`.
            blind_bid_success_multiplier = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 8,
                default = 2,
                status = "selectable",
            },
            -- Sibling of `blind_bid`. Multiplier applied to the
            -- declarer's penalty when a failed contract was declared
            -- in the dark. Defaults to 2 ("double on failure"); some
            -- house rules let success and failure use different
            -- multipliers, so the two siblings are independent.
            blind_bid_failure_multiplier = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 8,
                default = 2,
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
            },
            -- Sibling of `contra`. Multiplier applied to the contract
            -- value when defenders declare contra. Defaults to 2 (the
            -- canonical "doubled"); house rules occasionally use 3.
            -- Inert while `contra = "off"`.
            contra_multiplier = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 4,
                default = 2,
                status = "selectable",
            },
            -- Sibling of `contra`. Multiplier applied to the contract
            -- value when the declarer redoubles in response to contra.
            -- Composes multiplicatively with `contra_multiplier`, so the
            -- canonical 2 × 2 = 4 holds for the default. Inert unless
            -- `contra = "contra_and_redouble"`.
            redouble_multiplier = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 8,
                default = 2,
                status = "selectable",
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
                status = "selectable",
            },
            -- Sibling of `forced_bid_concession`. House-defined split
            -- when the concession mode is `preset_ratio`. Each entry is
            -- a non-negative weight in [0, 1]; the entries sum to 1
            -- (epsilon 1e-9), enforced by the
            -- `forced_bid_concession_ratio_sums_to_one` invariant. The
            -- list length must equal the active non-declarer seat count
            -- (player_count - 1, minus the sits-out seat in 4-player B),
            -- enforced by the `forced_bid_concession_ratio_length`
            -- invariant. Inert under any other concession mode.
            forced_bid_concession_preset_ratio = {
                kind = "list",
                element_type = "number",
                default = { 0.5, 0.5 },
                status = "selectable",
            },
            -- Phase 3.7 book toggle: declarer-initiated mid-deal
            -- concession (сдача / "write-off"). When `on`, the
            -- declarer may abandon the deal between tricks (any time
            -- before the last trick begins), subtracting the full
            -- contract bid from themselves and crediting opponents
            -- per `write_off_split`. The cross-deal counter that
            -- triggers the every-third-write-off penalty lives in
            -- `penalties.write_off_streak`. Distinct from
            -- `bidding.forced_bid_concession`, which fires only on a
            -- forced 100 contract at auction time. See
            -- docs/variations/house-rules.md "Write-off / Сдача"
            -- (added by the Phase 3.7 closing task).
            write_off = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `write_off`. Distribution of the conceded
            -- bid:
            --   * half_to_each — each opponent receives half the bid
            --     (book default; with 3+ opponents the credits
            --     intentionally exceed the debit).
            --   * equal_split — the bid value is divided equally
            --     across opponents, preserving conservation.
            -- Inert under `write_off = "off"`. Pools through
            -- `scoring.defender_contributions` for partnerships.
            write_off_split = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "half_to_each", "equal_split" },
                default = "half_to_each",
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
            },
            -- Sibling of `named_contracts`. Ordered list of named
            -- contract kinds the auction admits, weakest first. The
            -- canonical Russian default keeps the list populated so
            -- the schema is self-documenting; the auction enforces
            -- "first named bid wins; named-over-named is illegal" in
            -- this commit. The precedence order will be honoured once
            -- a follow-up task ("Implement named-contract scoring &
            -- play") wires the gameplay through. Entries must be one
            -- of {"mizere", "slam", "open_hand"}, with no duplicates,
            -- enforced by the `named_contracts_precedence_well_formed`
            -- invariant.
            named_contracts_precedence = {
                kind = "list",
                element_type = "string",
                default = { "mizere", "open_hand", "slam" },
                status = "selectable",
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
            "half_marriage_capture_bonus_value",
            "trump_activation_timing",
            "marriage_announcement_timing",
            "drowned_marriage",
            "ace_marriage",
            "ace_marriage_value",
            "one_trump_per_deal",
            "trick_required",
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
                status = "selectable",
            },
            -- Bonus credited per suit when a non-declarer captures
            -- both the K and Q of that suit. Inert under
            -- `half_marriage_capture_bonus = "off"`; carried in the
            -- schema so saved templates round-trip cleanly. Bounded
            -- in [0, 100] — a single capture bonus cannot exceed the
            -- canonical hearts marriage value.
            half_marriage_capture_bonus_value = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 100,
                default = 20,
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
            },
            -- Bonus credited when a player declares all four Aces.
            -- Inert under `ace_marriage = "off"`; carried in the
            -- schema so saved templates round-trip cleanly. Bounded
            -- in [0, 400] — at most twice the documented "+200"
            -- typical so unusual house rules can lift the cap.
            ace_marriage_value = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 400,
                default = 200,
                status = "selectable",
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
                status = "selectable",
            },
            -- Book-rule: a K-Q (trump) marriage and a four-aces ace
            -- marriage may only be declared once the seat has already
            -- captured at least one trick this deal. The book frames
            -- this as the standard rule and the trickless variant as
            -- the exception. The gate applies uniformly to every
            -- declaration path: lead-time `M.declare`, hand-time
            -- `M.announce_from_hand`, and `M.declare_ace_marriage`.
            -- Default `"on"` matches the book; tables that allow
            -- declaration without a trick pin this to `"off"`. See
            -- docs/variations/house-rules.md "Marriage trick required".
            trick_required = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "on", "off" },
                default = "on",
                status = "selectable",
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
            "last_trick_bonus_value",
            "slam_bonus",
            "slam_bonus_value",
            "slam_against_penalty",
            "slam_against_penalty_value",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
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
                status = "selectable",
            },
            -- House-rule: the winner of the final (8th) trick earns a
            -- small bonus added to that side's deal score. Common at
            -- many Russian and Polish tables. The bonus value lives in
            -- the sibling `last_trick_bonus_value` field. See
            -- docs/variations/house-rules.md "Last-trick bonus".
            last_trick_bonus = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Bonus credited to the seat that wins the eighth (final)
            -- trick. Inert under `last_trick_bonus = "off"`; carried in
            -- the schema so saved templates round-trip cleanly. Bounded
            -- in [0, 100] — the documented "+10 typical" sits well
            -- below the cap, leaving room for unusual house rules.
            last_trick_bonus_value = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 100,
                default = 10,
                status = "selectable",
            },
            -- House-rule: bonus for the declarer winning all 8 tricks.
            -- `fixed` adds a flat bonus (sibling
            -- `slam_bonus_value`); `doubled_bid` doubles the contract
            -- value on success — that mode reads no sibling, the bid
            -- doubling is realised in the scoring path. See
            -- docs/variations/house-rules.md "Slam bonus".
            slam_bonus = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "fixed", "doubled_bid" },
                default = "off",
                status = "selectable",
            },
            -- Fixed bonus credited to the declarer when they take all
            -- eight tricks under `slam_bonus = "fixed"`. Inert under
            -- `slam_bonus = "off"` and `slam_bonus = "doubled_bid"`;
            -- carried in the schema so saved templates round-trip
            -- cleanly. Bounded in [0, 240] — the documented range is
            -- "+60 or +120" and 240 mirrors the slam-contract value
            -- ceiling, leaving headroom for table-specific bumps.
            slam_bonus_value = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 60,
                status = "selectable",
            },
            -- House-rule: penalty levied on the declarer when they
            -- take zero tricks. Defender-side analogue of the slam
            -- bonus, mostly relevant for mizère contracts but
            -- supported for ordinary contracts too. The penalty value
            -- lives in the sibling `slam_against_penalty_value`. See
            -- docs/variations/house-rules.md "Slam bonus".
            slam_against_penalty = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Penalty deducted from the declarer's deal score when
            -- they take zero tricks under
            -- `slam_against_penalty = "on"`. Inert under
            -- `slam_against_penalty = "off"`; carried in the schema so
            -- saved templates round-trip cleanly. Bounded in [0, 240]
            -- — mirrors the canonical mizère contract value (120) by
            -- default, with headroom for stiffer table conventions.
            slam_against_penalty_value = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 120,
                status = "selectable",
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
                status = "selectable",
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
            -- success". Phase 3.6 wired: core/scoring.lua reads this
            -- and replaces the +bid success delta with the higher of
            -- the bid and the declarer's deal_score.
            actual_points_on_success = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- House-rule: how defender deal points reach defender
            -- running totals. `standard` credits each defender their
            -- own captured points; `pooled` sums and splits equally.
            -- Almost never used outside partnership variants. See
            -- docs/variations/house-rules.md "Defender contributions".
            -- Phase 3.6 wired: core/scoring.lua redistributes defender
            -- deltas under `pooled`. Inert under partnership_mode
            -- because the side accounting already pools.
            defender_contributions = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "pooled" },
                default = "standard",
                status = "selectable",
            },
            -- House-rule: where the bid value "goes" when the
            -- declarer fails. `lost` matches the canonical Russian
            -- rule (declarer's individual loss, defenders unaffected);
            -- the distribution variants split the bid among defenders
            -- with varying severity. `mirrors_forced_concession`
            -- reuses the bidding.forced_bid_concession setting for
            -- consistency. See docs/variations/house-rules.md
            -- "Failed-contract distribution". Phase 3.6 wired:
            -- core/scoring.lua adds the configured share to each
            -- defender's delta on failure.
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
                status = "selectable",
            },
            -- House-rule: round the declarer's captured points before
            -- comparing them to the bid. A captured 118 against a 120
            -- bid then rounds up to 120 and makes the contract.
            -- Forgiving to near-misses; reduces over-bidding caution.
            -- See docs/variations/house-rules.md "Declarer rounding
            -- before contract check". Phase 3.6 wired: default is
            -- `"on"` to preserve canonical Russian Phase 1.7 behaviour
            -- (`Declarer made contract when deal score is at least the
            -- bid`, where deal_score uses rounded card-points). The
            -- `"off"` mode flips to the strict tournament reading,
            -- comparing raw captured-points + exact bonuses to the
            -- bid.
            declarer_rounding_before_contract_check = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "on",
                status = "selectable",
            },
        },
    },
    -- Opening-game house rules. Golden deal is the only documented
    -- entry; its sub-flags (count, marriages-doubled, blind-allowed,
    -- penalty-doubled, failure-handling) live as sibling fields so
    -- saved templates round-trip cleanly even when the parent toggle
    -- is off. See docs/variations/house-rules.md "Opening-game house
    -- rules".
    opening_game = {
        kind = "section",
        field_order = {
            "golden_deal",
            "golden_deal_count",
            "golden_deal_marriages_doubled",
            "golden_deal_blind_allowed",
            "golden_deal_penalty_doubled",
            "golden_deal_failure_handling",
        },
        fields = {
            -- House-rule: during the first N deals (typically equal to
            -- the player count) every player in turn must play a
            -- mandatory 120 contract. The auction is bypassed for the
            -- duration. The detail toggles (marriages doubled, blind
            -- play allowed, penalties doubled, failure handling) live
            -- in the sibling fields below. See
            -- docs/variations/house-rules.md "Golden deal / Золотой
            -- кон".
            golden_deal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Number of opening deals played as forced 120 contracts
            -- under `golden_deal = "on"`. Conventionally equal to the
            -- player count (3 for canonical Russian, 2 for two-player,
            -- 4 for four-player). Inert under `golden_deal = "off"`;
            -- carried in the schema so saved templates round-trip
            -- cleanly. Bounded in [1, 8] — anything beyond a single
            -- round of golden deals is unheard of in practice.
            golden_deal_count = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 8,
                default = 3,
                status = "selectable",
            },
            -- Sibling of `golden_deal`. Doubles marriage values during
            -- the opening N deals when on. Most tables run with this
            -- on — see docs/variations/house-rules.md "Golden deal".
            -- Inert under `golden_deal = "off"`.
            golden_deal_marriages_doubled = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `golden_deal`. When on, declarers may opt
            -- into a blind 120 bid during the opening N deals (under
            -- `bidding.blind_bid` semantics). Most tables forbid this;
            -- defaults off accordingly. Inert under `golden_deal =
            -- "off"`.
            golden_deal_blind_allowed = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `golden_deal`. Doubles the −120 fall penalty
            -- (and any cross / bolt counters) for failed forced
            -- contracts during the opening N deals. Inert under
            -- `golden_deal = "off"`.
            golden_deal_penalty_doubled = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `golden_deal`. Resolves what happens when no
            -- declarer makes their 120 contract across the opening N
            -- deals. `continue` proceeds to normal play with the
            -- accumulated penalties. `replay_round` re-runs the
            -- opening sequence from the start. `reset` re-runs and
            -- also wipes accumulated penalties from those deals. Inert
            -- under `golden_deal = "off"`.
            golden_deal_failure_handling = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "continue", "replay_round", "reset" },
                default = "continue",
                status = "selectable",
            },
        },
    },
    -- Barrel rules and house-rule toggles. `threshold`, `deal_count`,
    -- and `fall_off_penalty` are "implemented" — core/scoring.lua's
    -- barrel state machine reads each one. The remaining fields are
    -- the barrel house-rule catalogue from
    -- docs/variations/house-rules.md "Barrel house rules". Phase 3.6
    -- wires every toggle into the engine so a built-in or saved
    -- template can opt into any combination.
    barrel = {
        kind = "section",
        field_order = {
            "threshold",
            "deal_count",
            "fall_off_penalty",
            "pit_lock_in",
            "pit_score",
            "collision_rule",
            "overshoot_penalty",
            "fall_count_resets_to_zero",
            "reverse_barrel",
            "reverse_barrel_fallback",
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
            -- House-rule: an intermediate "pit" score that players
            -- must clear before approaching the barrel. Crossing the
            -- pit from below caps the running total at exactly
            -- `pit_score`; the player must make a successful
            -- declarer contract to pass through. Defender points
            -- accumulate normally below the pit but cannot push the
            -- locked total higher. See docs/variations/house-rules.md
            -- "Alternative barrel threshold".
            pit_lock_in = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `pit_lock_in`. The exact running-total value
            -- the lock fires on. Conventionally 700 (the documented
            -- "at-700 lock-in"). Inert under `pit_lock_in = "off"`.
            -- Bounded in [100, threshold − 1] — must sit strictly
            -- below the barrel threshold to be meaningful.
            pit_score = {
                kind = "leaf",
                lua_type = "number",
                min = 100,
                max = 879,
                default = 700,
                status = "selectable",
            },
            -- House-rule: who survives when two or more units sit on
            -- the barrel simultaneously. `last_mounter` is the
            -- canonical Russian rule (latest mount survives, others
            -- fall off). `first_mounter` keeps the earliest mount on
            -- the barrel and falls the rest off. `all_collide_fall_off`
            -- knocks every colliding unit off, leaving the barrel
            -- empty. `coexist` is the relaxed book variant: every
            -- on-barrel unit stays mounted simultaneously, each
            -- running its own `deal_count` countdown. The book frames
            -- coexistence as an agreed-in-advance variant — see
            -- docs/variations/house-rules.md "Barrel collisions".
            collision_rule = {
                kind = "leaf",
                lua_type = "string",
                allowed = {
                    "last_mounter",
                    "first_mounter",
                    "all_collide_fall_off",
                    "coexist",
                },
                default = "last_mounter",
                status = "selectable",
            },
            -- House-rule: bidding strictly above the closing-gap
            -- (`target_score − threshold`, canonically 120) while on
            -- the barrel and failing incurs an extra penalty. The
            -- declarer falls off losing their bid amount instead of
            -- the standard `fall_off_penalty`. Discourages "hero"
            -- bids from the barrel. See
            -- docs/variations/house-rules.md "Barrel-jump penalty".
            overshoot_penalty = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Phase 3.7 book toggle: a unit that falls off the barrel
            -- three times has its running total reset to zero on the
            -- third fall, overriding `fall_off_penalty`. Counter is
            -- per-seat, persisted across deals, and survives auto-save
            -- / resume. The third-fall threshold is hard-coded per the
            -- book ("If a player sat on the barrel 3 times and then
            -- fell off it"); custom thresholds are out of scope. The
            -- reset takes precedence over `overshoot_penalty` on the
            -- triggering fall (book frames the reset as replacing
            -- `fall_off_penalty` regardless of bid). Inert under
            -- "off". See docs/variations/house-rules.md
            -- "Three-falls reset" (added by the Phase 3.7 closing
            -- task).
            fall_count_resets_to_zero = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- House-rule: a symmetric variant for failing players. At
            -- −threshold (canonically −880), a unit enters a reverse
            -- barrel: `deal_count` deals to reach −target (which loses
            -- the game outright); failing falls back to
            -- `reverse_barrel_fallback`. Rare; mostly a cruel add-on
            -- for long sessions. See docs/variations/house-rules.md
            -- "Reverse barrel".
            reverse_barrel = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `reverse_barrel`. Running total a unit lands
            -- on after failing the reverse-barrel sequence. Common
            -- conventions: −760 (mirror of canonical fall-off) or
            -- −500. Inert under `reverse_barrel = "off"`. No `min`:
            -- the value is intentionally negative.
            reverse_barrel_fallback = {
                kind = "leaf",
                lua_type = "number",
                default = -760,
                status = "selectable",
            },
        },
    },
    -- Endgame rules and house-rule toggles. `target_score` is
    -- "implemented" — core/scoring.lua reads it directly. Phase 3.6
    -- wires the remaining fields into the post-deal advancement so
    -- built-in templates and saved customs honour every documented
    -- variant from docs/variations/house-rules.md "Endgame house
    -- rules".
    endgame = {
        kind = "section",
        field_order = {
            "target_score",
            "going_over_target",
            "tiebreaker",
            "dump_truck",
            "dump_truck_threshold",
        },
        fields = {
            target_score = {
                kind = "leaf",
                lua_type = "number",
                default = 1000,
                status = "implemented",
            },
            -- House-rule: what happens when a unit exceeds the target
            -- in a single deal. `win_immediately` matches the
            -- canonical Russian rule (any total at or above the
            -- target wins). `exact_only` caps post-deal totals at
            -- `target_score - 1` until a unit lands exactly on the
            -- target — only an exact match wins. See
            -- docs/variations/house-rules.md "Going over the target".
            going_over_target = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "win_immediately", "exact_only" },
                default = "win_immediately",
                status = "selectable",
            },
            -- House-rule: how to break a tie when two or more units
            -- cross the target in the same deal. `declarer_wins`
            -- (canonical Russian) keeps the existing
            -- highest-wins-with-declarer-tiebreaker rule.
            -- `high_score` drops the declarer favouritism — the
            -- highest running total wins, with ties broken by lowest
            -- seat (or lowest side index) instead. `continuation`
            -- declares no winner and raises the effective target by
            -- +500 for the rest of the game; tied units sit at
            -- `target − 1` heading into the next deal. See
            -- docs/variations/house-rules.md "Tiebreakers".
            tiebreaker = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "declarer_wins", "high_score", "continuation" },
                default = "declarer_wins",
                status = "selectable",
            },
            -- House-rule: dump-truck / самосвал — landing on the
            -- threshold score (commonly +555) resets the unit's
            -- running total to zero. `positive_only` triggers on
            -- +threshold only; `both_signs` triggers on −threshold
            -- as well. The reset fires before the barrel/winner
            -- branch so a unit already on the barrel that lands on
            -- the threshold resets to 0 and dismounts. The exact
            -- threshold is the sibling field `dump_truck_threshold`.
            -- See docs/variations/house-rules.md "Dump truck /
            -- Самосвал".
            dump_truck = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "positive_only", "both_signs" },
                default = "off",
                status = "selectable",
            },
            -- Sibling of `dump_truck`. The exact running-total value
            -- the reset fires on (the book mentions both 555 and 550
            -- as agreed-upon variants). Inert under `dump_truck =
            -- "off"`; carried in the schema so saved templates round-
            -- trip cleanly. The trigger uses exact equality with
            -- ±threshold; because the scoring engine rounds totals to
            -- multiples of 5, threshold values not divisible by 5 will
            -- rarely fire in practice. Bounded in [100, 1000] —
            -- thresholds outside that range do not match the book's
            -- usage of the rule.
            dump_truck_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 100,
                max = 1000,
                default = 555,
                status = "selectable",
            },
        },
    },
    -- Special-contract toggles. Each named contract is a single
    -- on/off here; the bidding-section umbrella `named_contracts`
    -- gates whether any of them are admissible at the auction. The
    -- contract values for mizère and slam live in sibling
    -- `*_contract_value` fields below; open-hand carries no sibling
    -- because its `value = 200` is already doubled per the house-
    -- rules definition. See docs/variations/house-rules.md "Special
    -- contracts" and the bidding.named_contracts comment.
    specials = {
        kind = "section",
        field_order = {
            "mizere",
            "mizere_contract_value",
            "slam_contract",
            "slam_contract_value",
            "open_hand",
        },
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
                status = "selectable",
            },
            -- Score change applied to the declarer on a successful or
            -- failed mizère. Inert under `mizere = "off"`; carried in
            -- the schema so saved templates round-trip cleanly.
            -- Bounded in [1, 240] — the canonical 120 sits at the
            -- midpoint with headroom for stricter house conventions.
            mizere_contract_value = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 240,
                default = 120,
                status = "selectable",
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
                status = "selectable",
            },
            -- Score change applied to the declarer on a successful or
            -- failed slam. Inert under `slam_contract = "off"`;
            -- carried in the schema so saved templates round-trip
            -- cleanly. Bounded in [1, 600] — covers the documented
            -- "240 / 300 / double the highest numeric bid" range
            -- (max numeric bid is 300 today; 2× = 600).
            slam_contract_value = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                max = 600,
                default = 240,
                status = "selectable",
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
                status = "selectable",
            },
        },
    },
    -- Penalty house-rule toggles. Phase 3.6 wired: every toggle
    -- flips to "selectable" with engine + counter + scoreboard-row
    -- support. See docs/variations/house-rules.md "Penalty house
    -- rules".
    penalties = {
        kind = "section",
        field_order = {
            "revoke",
            "revoke_configurable_amount",
            "talon_look",
            "showing_hand",
            "zero_tricks",
            "zero_tricks_threshold",
            "zero_tricks_penalty_amount",
            "zero_tricks_declarer_exempt",
            "zero_tricks_golden_deal_doubled",
            "zero_tricks_dark_game_doubled",
            "write_off_streak",
            "write_off_streak_threshold",
            "write_off_streak_penalty_amount",
            "no_win_streak",
            "no_win_streak_threshold",
            "no_win_streak_penalty_amount",
            "cross",
            "cross_penalty_amount",
        },
        fields = {
            -- House-rule: penalty for revoking. `standard` awards
            -- the declarer's full bid to the opposing side; `flat`
            -- awards 120 regardless of bid; `configurable` lets the
            -- house pick a fixed amount (sibling
            -- `revoke_configurable_amount`). The engine triggers
            -- this penalty when `tricks.lazy_revoke = "on"` flags a
            -- violation in `completed_tricks.revoke_violations`. See
            -- docs/variations/house-rules.md "Revoke penalty".
            revoke = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "flat", "configurable" },
                default = "standard",
                status = "selectable",
            },
            -- Fixed penalty deducted from the offender under
            -- `revoke = "configurable"`. Inert under the other
            -- modes; carried in the schema so saved templates
            -- round-trip cleanly. Bounded in [0, 240] — the
            -- documented "120 typical" sits at the midpoint, with
            -- headroom for stiffer house conventions.
            revoke_configurable_amount = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 120,
                status = "selectable",
            },
            -- House-rule: penalty for looking at the talon before
            -- the auction ends. `standard` deducts 120 and redeals;
            -- `stricter` forfeits the deal and awards the bid to
            -- the opposing side. The engine fires this penalty when
            -- `Session:record_penalty_violation(seat, "talon_look")`
            -- is called — UI auto-trigger is deferred to a Phase 5
            -- polish task. See docs/variations/house-rules.md
            -- "Talon-look penalty".
            talon_look = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "stricter" },
                default = "standard",
                status = "selectable",
            },
            -- House-rule: penalty for showing one's hand to an
            -- opponent. `standard` is a small fixed penalty (20);
            -- `strict` deducts the full bid. Triggered via
            -- `Session:record_penalty_violation(seat, "showing_hand")`
            -- — UI auto-trigger is deferred to a Phase 5 polish
            -- task. See docs/variations/house-rules.md
            -- "Showing-hand penalty".
            showing_hand = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "strict" },
                default = "standard",
                status = "selectable",
            },
            -- House-rule: zero-tricks penalty / болт / палка.
            -- `consecutive_three` resets the bolt counter on any
            -- trick taken; `any_three` is cumulative across the
            -- game. The variant flags (declarer exempt, doubled in
            -- golden deal) live in sibling fields. See
            -- docs/variations/house-rules.md "Zero-tricks penalty
            -- (Болт / Палка)" — distinct from the bidding-section
            -- forced_dealer_bid (also called бовт/болт but a forced
            -- 100 contract, not a zero-tricks penalty).
            zero_tricks = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "consecutive_three", "any_three" },
                default = "off",
                status = "selectable",
            },
            -- Bolt count at which the zero-tricks penalty fires and
            -- the counter resets. Inert under `zero_tricks = "off"`.
            -- Bounded in [2, 5] — the spec's "commonly 3" sits at the
            -- midpoint, with room for stricter or laxer table rules.
            zero_tricks_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 2,
                max = 5,
                default = 3,
                status = "selectable",
            },
            -- Penalty deducted when a player's bolt count reaches
            -- `zero_tricks_threshold`. Inert under
            -- `zero_tricks = "off"`. Bounded in [0, 240] — the
            -- documented "−120 typical" sits at the midpoint.
            zero_tricks_penalty_amount = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 120,
                status = "selectable",
            },
            -- Sub-flag: when `on`, the declarer never accumulates a
            -- bolt — only defenders can earn them. Rare. Inert under
            -- `zero_tricks = "off"`.
            zero_tricks_declarer_exempt = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Sub-flag: when `on` and the deal is a golden deal, a
            -- zero-tricks seat earns 2 bolts instead of 1. Inert
            -- under `zero_tricks = "off"`.
            zero_tricks_golden_deal_doubled = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Phase 3.7 book toggle: when `on` AND the declarer's
            -- winning bid was blind (a "dark game" / тёмная), a
            -- zero-tricks seat earns 2 bolts instead of 1. Sister of
            -- `zero_tricks_golden_deal_doubled`. Stacks additively
            -- (i.e. doubling once — never more than 2 — even if both
            -- triggers fire in the same deal). Inert under
            -- `zero_tricks = "off"` or when no blind opening won the
            -- auction. See docs/variations/house-rules.md "Dark-game
            -- stick doubling" (added by the Phase 3.7 closing task).
            zero_tricks_dark_game_doubled = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Phase 3.7 book toggle: every-third-write-off penalty.
            -- When set to `any_three`, a per-seat counter increments
            -- on each `bidding.write_off` use; on the configured
            -- threshold the seat takes
            -- `write_off_streak_penalty_amount` and the counter
            -- resets to zero. Counter spans the whole game and
            -- survives auto-save / resume. Inert when
            -- `bidding.write_off = "off"` because the counter cannot
            -- advance. See docs/variations/house-rules.md
            -- "Every-third-write-off penalty" (added by the Phase
            -- 3.7 closing task).
            write_off_streak = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "any_three" },
                default = "off",
                status = "selectable",
            },
            -- Write-off count at which the every-third-write-off
            -- penalty fires and the counter resets. Inert under
            -- `write_off_streak = "off"`. Bounded in [2, 5] — the
            -- book's "every third" sits at 3.
            write_off_streak_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 2,
                max = 5,
                default = 3,
                status = "selectable",
            },
            -- Penalty deducted when a player's write-off count
            -- reaches `write_off_streak_threshold`. Inert under
            -- `write_off_streak = "off"`. Bounded in [0, 240] — the
            -- book's "−120 typical" sits at the midpoint.
            write_off_streak_penalty_amount = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 120,
                status = "selectable",
            },
            -- Phase 3.7 book toggle: no-win-streak penalty. The book
            -- frames this as "no win for 3 rounds in a row or in
            -- total" (lines 39–47): a seat that fails to win for
            -- `no_win_streak_threshold` deals takes the configured
            -- penalty and the counter resets. "Winning a deal" is
            -- the declarer making contract OR a defender capturing
            -- positive deal_scores; this is pinned in
            -- `app/session.lua` so the rule cannot drift downstream.
            -- Under `consecutive_three`, any winning deal resets the
            -- counter; under `any_three`, only the threshold trigger
            -- resets. Counter spans the whole game and survives
            -- auto-save / resume. Inert under "off". Shape mirrors
            -- the existing `zero_tricks` cluster. See
            -- docs/variations/house-rules.md "No-win streak penalty"
            -- (added by the Phase 3.7 closing task).
            no_win_streak = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "consecutive_three", "any_three" },
                default = "off",
                status = "selectable",
            },
            -- No-win count at which the no-win-streak penalty fires
            -- and the counter resets. Inert under
            -- `no_win_streak = "off"`. Bounded in [2, 5] — the book's
            -- "no win for 3 rounds" sits at 3.
            no_win_streak_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 2,
                max = 5,
                default = 3,
                status = "selectable",
            },
            -- Penalty deducted when a player's no-win count reaches
            -- `no_win_streak_threshold`. Inert under
            -- `no_win_streak = "off"`. Bounded in [0, 240] — the
            -- book's "−120 typical" sits at the midpoint.
            no_win_streak_penalty_amount = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 120,
                status = "selectable",
            },
            -- House-rule: cross / крест — alternative penalty path
            -- for failed contracts. When `on`, a failing declarer's
            -- bid deduction is suppressed; instead the declarer
            -- receives a cross. After two crosses the declarer takes
            -- a fixed penalty (sibling `cross_penalty_amount`) and
            -- the counter clears. Defender contributions still apply
            -- per `scoring.failed_contract_distribution`. See
            -- docs/variations/house-rules.md "Cross / Крест".
            cross = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "selectable",
            },
            -- Penalty deducted from the declarer when their cross
            -- counter reaches 2 under `cross = "on"`. Inert under
            -- `cross = "off"`. Bounded in [0, 240] — the documented
            -- "−120 typical" sits at the midpoint.
            cross_penalty_amount = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                max = 240,
                default = 120,
                status = "selectable",
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
    -- docs/variations/two-player.md "Variant A". Phase 3.6's 2-player
    -- stock-draw task also pins `talon.distribution = "stock_draw"`
    -- for this layout via `stock_draw_distribution_requires_variant_a`.
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
    -- Polish 2-card "pass_without_taking": the declarer never picks the
    -- talon up; the two talon cards go one each to the opponents. The
    -- distribution is meaningful only with a 2-card talon — anything
    -- else is a configuration error caught at validation time, not a
    -- runtime "unsupported_talon_size" surprise. See
    -- docs/variations/polish.md. Sibling of
    -- `stock_draw_distribution_requires_variant_a`, which gates the
    -- 2-player Schnapsen-style distribution against the same
    -- single-purpose pattern.
    {
        name = "pass_without_taking_requires_two_card_talon",
        predicate = function(blob)
            if blob.talon.distribution ~= "pass_without_taking" then
                return true
            end
            return blob.talon.size == 2
        end,
        context = function(blob)
            return {
                talon_distribution = blob.talon.distribution,
                talon_size = blob.talon.size,
            }
        end,
    },
    -- The 2-player Schnapsen-style "stock_draw" distribution is the
    -- 2-player Variant A flow (docs/variations/two-player.md). It is
    -- only meaningful when the layout is the closed-talon-with-draw-stock
    -- shape: 2 players, `players.two_player_config =
    -- "closed_talon_draw_stock"`. The `talon.size = 0` requirement for
    -- that layout is enforced by `two_player_a_requires_no_talon` above
    -- — each invariant stays single-purpose. Sibling of
    -- `pass_without_taking_requires_two_card_talon`.
    {
        name = "stock_draw_distribution_requires_variant_a",
        predicate = function(blob)
            if blob.talon.distribution ~= "stock_draw" then
                return true
            end
            return blob.players.count == 2
                and blob.players.two_player_config == "closed_talon_draw_stock"
        end,
        context = function(blob)
            return {
                talon_distribution = blob.talon.distribution,
                players_count = blob.players.count,
                two_player_config = blob.players.two_player_config,
            }
        end,
    },
    -- Phase 3.6 forced-bid concession: `preset_ratio` mode requires a
    -- per-defender split. The list length must equal the active
    -- non-declarer seat count: `players.count - 1` for 3-player and
    -- 2-player layouts, and `players.count - 2` (subtracting both
    -- declarer and sits-out seat) for 4-player Configuration B. Other
    -- modes ignore the ratio entirely. See
    -- docs/variations/house-rules.md "Forced-bid concession".
    {
        name = "forced_bid_concession_ratio_length",
        predicate = function(blob)
            if blob.bidding.forced_bid_concession ~= "preset_ratio" then
                return true
            end
            local expected = blob.players.count - 1
            if blob.players.count == 4 and blob.players.four_player_config == "dealer_sits_out" then
                expected = blob.players.count - 2
            end
            return #blob.bidding.forced_bid_concession_preset_ratio == expected
        end,
        context = function(blob)
            local expected = blob.players.count - 1
            if blob.players.count == 4 and blob.players.four_player_config == "dealer_sits_out" then
                expected = blob.players.count - 2
            end
            return {
                ratio_length = #blob.bidding.forced_bid_concession_preset_ratio,
                expected_length = expected,
                players_count = blob.players.count,
                four_player_config = blob.players.four_player_config,
            }
        end,
    },
    -- Phase 3.6 forced-bid concession: `preset_ratio` weights must sum
    -- to 1 (within an epsilon of 1e-9 to absorb the usual floating-
    -- point drift on round-trip serialisation). Inert under any other
    -- concession mode.
    {
        name = "forced_bid_concession_ratio_sums_to_one",
        predicate = function(blob)
            if blob.bidding.forced_bid_concession ~= "preset_ratio" then
                return true
            end
            local total = 0
            for _, weight in ipairs(blob.bidding.forced_bid_concession_preset_ratio) do
                total = total + weight
            end
            return math.abs(total - 1) <= 1e-9
        end,
        context = function(blob)
            local total = 0
            for _, weight in ipairs(blob.bidding.forced_bid_concession_preset_ratio) do
                total = total + weight
            end
            return {
                ratio_sum = total,
                expected_sum = 1,
            }
        end,
    },
    -- Phase 3.6 named-contracts wiring: the precedence list is the
    -- weakest-first ordering the auction will honour once a follow-up
    -- task implements named-contract scoring & play. For now the
    -- invariant only enforces that every entry is one of the three
    -- known kinds and that no kind appears twice. The on/off coupling
    -- between `named_contracts` and `specials.*` is left to the same
    -- follow-up task — the umbrella toggle wires the auction surface;
    -- the gameplay task wires the consequences.
    {
        name = "named_contracts_precedence_well_formed",
        predicate = function(blob)
            if blob.bidding.named_contracts ~= "on" then
                return true
            end
            local known = { mizere = true, slam = true, open_hand = true }
            local seen = {}
            for _, kind in ipairs(blob.bidding.named_contracts_precedence) do
                if not known[kind] then
                    return false
                end
                if seen[kind] then
                    return false
                end
                seen[kind] = true
            end
            return true
        end,
        context = function(blob)
            return {
                named_contracts = blob.bidding.named_contracts,
                precedence = table.concat(blob.bidding.named_contracts_precedence, ","),
            }
        end,
    },
    -- Phase 3.6 forced dealer bid: the rule presupposes a dealer who
    -- actually participates in the auction. In 4-player Configuration
    -- B the dealer sits out, so there is nobody to force into a
    -- minimum-100 contract — the toggle is structurally inert and the
    -- combination is rejected as a configuration error rather than a
    -- runtime surprise.
    {
        name = "forced_dealer_bid_requires_active_dealer",
        predicate = function(blob)
            if blob.bidding.forced_dealer_bid ~= "on" then
                return true
            end
            if blob.players.count ~= 4 then
                return true
            end
            return blob.players.four_player_config ~= "dealer_sits_out"
        end,
        context = function(blob)
            return {
                forced_dealer_bid = blob.bidding.forced_dealer_bid,
                players_count = blob.players.count,
                four_player_config = blob.players.four_player_config,
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
            two_nines_in_talon_redeal = "off",
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
            deck_size = "24",
            cut_deck_nine_jack_penalty = "off",
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
            blind_bid_success_multiplier = 2,
            blind_bid_failure_multiplier = 2,
            re_entry_after_pass = "off",
            contra = "off",
            contra_multiplier = 2,
            redouble_multiplier = 2,
            forced_bid_concession = "off",
            forced_bid_concession_preset_ratio = { 0.5, 0.5 },
            write_off = "off",
            write_off_split = "half_to_each",
            no_contract_without_marriage = "off",
            negative_score_restriction = "off",
            named_contracts = "off",
            named_contracts_precedence = { "mizere", "open_hand", "slam" },
        },
        marriages = {
            values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
            half_marriage_capture_bonus = "off",
            half_marriage_capture_bonus_value = 20,
            trump_activation_timing = "next_trick",
            marriage_announcement_timing = "on_lead",
            drowned_marriage = "off",
            ace_marriage = "off",
            ace_marriage_value = 200,
            one_trump_per_deal = "off",
            trick_required = "on",
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
            last_trick_bonus_value = 10,
            slam_bonus = "off",
            slam_bonus_value = 60,
            slam_against_penalty = "off",
            slam_against_penalty_value = 120,
            lead_trump_after_marriage = "off",
        },
        scoring = {
            round_to_nearest = 5,
            actual_points_on_success = "off",
            defender_contributions = "standard",
            failed_contract_distribution = "lost",
            declarer_rounding_before_contract_check = "on",
        },
        opening_game = {
            golden_deal = "off",
            golden_deal_count = 3,
            golden_deal_marriages_doubled = "off",
            golden_deal_blind_allowed = "off",
            golden_deal_penalty_doubled = "off",
            golden_deal_failure_handling = "continue",
        },
        barrel = {
            threshold = 880,
            deal_count = 3,
            fall_off_penalty = -120,
            pit_lock_in = "off",
            pit_score = 700,
            collision_rule = "last_mounter",
            overshoot_penalty = "off",
            fall_count_resets_to_zero = "off",
            reverse_barrel = "off",
            reverse_barrel_fallback = -760,
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
            dump_truck_threshold = 555,
        },
        specials = {
            mizere = "off",
            mizere_contract_value = 120,
            slam_contract = "off",
            slam_contract_value = 240,
            open_hand = "off",
        },
        penalties = {
            revoke = "standard",
            revoke_configurable_amount = 120,
            talon_look = "standard",
            showing_hand = "standard",
            zero_tricks = "off",
            zero_tricks_threshold = 3,
            zero_tricks_penalty_amount = 120,
            zero_tricks_declarer_exempt = "off",
            zero_tricks_golden_deal_doubled = "off",
            zero_tricks_dark_game_doubled = "off",
            write_off_streak = "off",
            write_off_streak_threshold = 3,
            write_off_streak_penalty_amount = 120,
            no_win_streak = "off",
            no_win_streak_threshold = 3,
            no_win_streak_penalty_amount = 120,
            cross = "off",
            cross_penalty_amount = 120,
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

    -- Polish Tysiąc (docs/variations/polish.md): 2-card talon, declarer
    -- never picks it up — one card goes face-down to each opponent
    -- (`distribution = "pass_without_taking"`). Bidding climbs in
    -- 10-step increments throughout the auction (no 5-step phase below
    -- 200). Polish *przebijanie* lifts the Russian must-beat / must-trump
    -- rules into "play your highest of the obligatory category", and
    -- defenders are required to overtrump declarer's trump when able —
    -- see docs/variations/polish.md lines 40–50 and house-rules.md
    -- "Trick-play house rules".
    polish = M.new(with_overrides(canonical_russian_blob(), {
        talon = {
            size = 2,
            distribution = "pass_without_taking",
        },
        bidding = {
            increment_below_200 = 10,
            increment_from_200 = 10,
        },
        tricks = {
            must_overtake_strictness = "polish_strict",
            must_trump_strictness = "polish_strict",
            defender_must_overtrump_declarer = "on",
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
    -- `players.two_player_config = "closed_talon_draw_stock"`. Phase
    -- 3.6's 2-player stock-draw task pins
    -- `talon.distribution = "stock_draw"` here so the wire-format
    -- name matches the engine path.
    two_player_a = M.new(with_overrides(canonical_russian_blob(), {
        players = {
            count = 2,
            two_player_config = "closed_talon_draw_stock",
        },
        talon = {
            size = 0,
            distribution = "stock_draw",
        },
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
