# Afterlight

A cinematic 2D survival game about digging your way back to the surface. Max lives in a small facility 214 miles down. The power just failed. His shovel cuts sideways and down; every tool, room and friendship he builds is part of figuring out how to go up.

Native Swift + SpriteKit for iPhone. Cloud saves and offline jobs on Supabase.

## What's in chapters 1–3

1. **The Blackout.** Candle, dirt wall, the violet glint, the flashlight, the buried lift shaft.
2. **First Ascent.** Dig east into the great cavern, salvage the fallen lift car for a lift tooth, make a short pick, build a ladder, climb the shaft, pick open the seam into the maintenance room.
3. **A Place to Come Back To.** Follow the warm pipe to Odi's outpost, fix the pump and decide where the water goes, wake the battery bank, plant and harvest, and light the passage so Odi can use it.

Max takes jobs: hold on a dirt wall to give him a dig order, or pick a **daily job** from the bed. Jobs keep running with the game closed. The server owns the clock and resolves them when you come back.

## Layout

```
Packages/AfterlightCore   game logic: world, digging, physics, items, story, jobs, saves (pure Swift, tested on Linux + macOS)
App/Sources               SpriteKit rendering, SwiftUI HUD and sheets, audio, Supabase sync
supabase/migrations       saves, jobs, RLS, and the job-claim functions
docs/                     design notes, including the NPC combat and collaboration plan
```

## Running it

1. `brew install xcodegen`
2. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and fill in your Supabase host, anon key and Apple team ID. (Leave it blank to play fully offline.)
3. `xcodegen generate && open Afterlight.xcodeproj`
4. Run on your iPhone.

### Supabase

```
supabase link --project-ref <ref>
supabase db push
```

Turn on **Anonymous sign-ins** in Authentication → Providers. The app signs in anonymously on first launch.

## How jobs can't pay out twice

- A job plan is computed in full on the phone (every step's seconds, stamina cost and effect) and stored on the server with the server's start time.
- `claim_job` counts finished steps with the server clock, marks the job `claimed` in the same transaction, and returns the same count on any later claim.
- The save records applied job ids, so replaying a claim after a crash does nothing.
- `JobResolver.completedSteps` (Swift) and `public.job_steps_done` (SQL) use the same arithmetic. Change both together.

## Tests

```
cd Packages/AfterlightCore && swift test
```

The tests play chapter 1 with the game's own controls, then run the ladder → pick → seam climb and the chapter 3 choices. They also cover exactly-once job payouts and save round-trips.
