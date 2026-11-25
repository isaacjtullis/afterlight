# Combat: design notes (deferred)

Combat is not in chapter 3. These notes record how it should fit the systems Mara's chapter introduced, so that
nothing built now has to be torn out later.

## Principles

- **Conflict is about things in the world first.** Water, parts, routes and promises are what people fight over.
  Fights should start from a broken agreement, a taken part or a blocked route, never at random.
- **Evidence gates hostility.** An NPC only turns on Max when they hold an `Evidence` record against him.
  Suspicion without evidence stays as dialogue ("I'm not saying it was you").
- **Every fight has an exit.** Mirrors the rule that every lockable space has a way out: Max can back off,
  return what he took, or offer a part, and the standoff ends without anyone hurt.
- **Short and legible.** A standoff is a few seconds at most, readable on a phone with one thumb.

## Shape of a standoff

1. **Trigger:** an NPC with evidence meets Max at a contested place (the line valve, a shelf, a hatch).
2. **Stances:** three choices in the same small panel used for deals. *Back off* (leave the area),
   *Make it right* (return or replace, using `settleHolding`), or *Hold your ground*.
3. **Holding your ground** starts a short shove-and-grab exchange. The outcome changes the world, for example
   who controls the valve, never just a health number. Nobody dies.
4. **Aftermath** is recorded like any agreement: the log keeps what happened, and trust moves.

## Hooks that already exist

- `Coop.evidence`, `Coop.holdings`, `Coop.trust`: who knows what, who holds what, how they feel.
- `Agreement.log` and term states: every breach and repair is kept.
- `SharedJob` blockers: an NPC refusing to work ("won't finish your lift while her tap's dry") is the
  non-violent end of the same scale.
- Panels with confirmations: the UI for choosing a stance.

## Open questions

- Should tunnel collapses (digging into someone's route) count as sabotage evidence automatically?
- How much should trust recover over time versus only through actions?
- Do allied NPCs ever step in for Max, and does that cost them trust with others?
