-- English — the source locale. Every key the game ships must exist here;
-- ru/pl/uk are populated against this same set in Phase 9.
--
-- Note on suit and rank glyphs: card.suit.* and card.rank.* are intentionally
-- identical across en/ru/pl/uk. They are universal symbols, not translated
-- words; resist a translator's instinct to "fix" them. A future
-- accessibility skin (e.g. high-contrast text-only deck) is the kind of
-- change that would override them, not a locale change.

return {
    ["app.title"] = "Thousand",
    ["app.subtitle"] = "A digital implementation of the Russian card game",

    ["scene.menu.title"] = "Thousand",
    ["scene.menu.subtitle"] = "A digital implementation of the Russian card game",
    ["scene.menu.new_game"] = "New Game",
    ["scene.menu.continue"] = "Continue",
    ["scene.menu.abandon"] = "Abandon Game",
    ["scene.menu.quit"] = "Quit",
    ["scene.menu.confirm_abandon.prompt"] = "Abandon the current game?",
    ["scene.menu.confirm_abandon.yes"] = "Yes, abandon",
    ["scene.menu.confirm_abandon.no"] = "Cancel",

    ["scene.table.back_to_menu"] = "Menu",
    ["scene.table.player_label.you"] = "Your hand",
    ["scene.table.player_label.other"] = "Player %{n}",
    ["scene.table.dealer_badge"] = "D",
    ["scene.table.deck.size"] = "%{n} cards",
    ["scene.table.scoreboard.title"] = "Score",
    ["scene.table.scoreboard.barrel"] = "Barrel: %{n} left",
    ["scene.table.bid.label"] = "Bid",
    ["scene.table.bid.none"] = "—",
    ["scene.table.turn.label"] = "Turn",
    ["scene.table.talon.label"] = "Talon",
    ["scene.table.trump.label"] = "Trump",
    ["scene.table.phase.label"] = "Phase",
    ["scene.table.phase.auction"] = "Auction",
    ["scene.table.phase.talon"] = "Talon",
    ["scene.table.phase.tricks"] = "Tricks",
    ["scene.table.phase.done"] = "Game Over",

    ["scene.table.auction.bid_button"] = "Bid %{amount}",
    ["scene.table.auction.pass_button"] = "Pass",
    ["scene.table.auction.your_turn"] = "Your turn — bid or pass",
    ["scene.table.auction.history_entry_bid"] = "Player %{n}: bid %{amount}",
    ["scene.table.auction.history_entry_pass"] = "Player %{n}: pass",

    ["scene.table.talon.take_button"] = "Take talon",
    ["scene.table.talon.pass_to"] = "Pass card to Player %{n}",
    ["scene.table.talon.raise_button"] = "Raise to %{amount}",
    ["scene.table.talon.skip_raise_button"] = "Keep bid at %{amount}",

    ["scene.table.tricks.your_turn"] = "Your turn — play a card",
    ["scene.table.tricks.led"] = "Led:",

    ["scene.table.marriage.prompt"] = "Declare marriage in:",
    ["scene.table.marriage.yes"] = "Declare",
    ["scene.table.marriage.no"] = "Just play",

    ["scene.table.privacy.prompt"] = "Pass the device to Player %{n}.",
    ["scene.table.privacy.subtitle"] = "Tap when ready.",
    ["scene.table.privacy.ready_button"] = "Ready",

    ["scene.table.deal_done.scored"] = "Deal complete",
    ["scene.table.deal_done.all_pass"] = "All players passed",
    ["scene.table.deal_done.next_deal"] = "Next deal",

    ["scene.table.toast.illegal_play"] = "Illegal play: %{reason}",
    ["scene.table.toast.not_your_turn"] = "Not your turn",

    ["scene.end_of_game.title"] = "Game Over",
    ["scene.end_of_game.placeholder"] = "Final scores will appear here.",
    ["scene.end_of_game.winner"] = "Winner: Player %{n}",
    ["scene.end_of_game.scores_title"] = "Final scores",
    ["scene.end_of_game.back_to_menu"] = "Back to Menu",

    ["card.suit.spades"] = "♠",
    ["card.suit.clubs"] = "♣",
    ["card.suit.diamonds"] = "♦",
    ["card.suit.hearts"] = "♥",

    ["card.rank.9"] = "9",
    ["card.rank.J"] = "J",
    ["card.rank.Q"] = "Q",
    ["card.rank.K"] = "K",
    ["card.rank.10"] = "10",
    ["card.rank.A"] = "A",

    ["greeting.welcome"] = "Welcome, %{name}!",
}
