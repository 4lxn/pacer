# Pacer — product thesis and go/no-go (2026-09-21)

Written after builds 1–20: the app works, but it is a list of features, not a product. This
document says who it is for, what it should become, and the numbers that decide whether it
lives. Code map: `ARCHITECTURE.md`. Section plan that got us here: `PLAN-v2.md`.

## One sentence

**Pacer runs your day so you don't have to: it tells you what's now, asks whether it
happened, and moves what didn't — travel time included, no guilt.**

Tagline candidates: "Days on pace." · "Your day, on pace."

## Who it is for

**Primary: the person whose routine collapses by 2 pm.** 25–38, ADHD or "ADHD-ish"
(self-identified counts), has a routine on paper — gym, work, study, meals — that fails
silently. Has tried Structured, Tiimo or Notion and quit because they require opening the
app and *planning*; the failure happens at 14:05 when the block did not happen and nobody
noticed. iPhone, often a watch. Lives in a city where getting anywhere takes 30+ minutes.
Pays $10–40/year for an app that works.

Evidence the segment exists and pays:

- Tiimo (ADHD visual planner): 500k+ users, 50k+ paying, 75% of payers neurodivergent;
  $4.8M raised; iPhone App of the Year 2025.
- Structured (daily planner): 1.5M monthly users, 4.9★; top complaint is recurring tasks
  behind the paywall, i.e. the basics still sell.
- Finch (self-care pet): $30–40M ARR, bootstrapped, 75% women 25–35, built on *no shame,
  no penalties* — the tone this segment rewards.
- Routinery: App of the Day 2025; top complaints are a hard paywall and routines locked to
  a fixed start time (exactly what Pacer's replanner removes).

What the segment asks for that planners do badly (Tiimo's own feedback board, ADDitude,
review roundups): "skip a task or mark it incomplete", "move unfinished tasks to the next
day", "remind me at the end of the day to reschedule", "make time feel concrete", "capture
in seconds". Tiimo shipped an evening *Review Today*; Motion and Reclaim reshuffle
calendars for $19–34/month and are built for knowledge workers with meetings, not for
someone trying to get to the gym after work.

**Secondary (later):** anyone with a fixed weekly routine and places — shift workers,
students, new parents. Same loop, different templates.

## Why Pacer, why now

Every competitor builds the planning canvas. Pacer's wedge is the **execution loop**: a
notification with real actions (Done · Move it later · Skip), a replan that respects travel
time and the rest of the day, gym blocks that close themselves from Apple Health, and a Live
Activity that shows what's now. iOS 26 Live Activities, interactive notifications and
tool-using models make a "day runner" feasible on a phone for the first time.

Nobody in the category asks *did it happen?* at the moment it matters and fixes the day
without a trip to the app. That is the product. Everything else is a block type.

## What is wrong today (Alan's words, then the audit)

> "No tiene forma, tampoco encanto… solo son features… tampoco es placentero de usar."

- **Seven sections** (Today, Train, Food, Focus, Money, Closet, Coach). Money and Closet have
  nothing to do with a day on pace; they turn the pitch into "an app with stuff".
- **No character.** Screens are competent lists. Nothing happens when you close a block.
  Nothing accumulates that you would show a friend.
- **"Coach"** is a tab and a chat. The word says fitness app; the surface says "type to me".
  The model should *act* (brief, replan, capture), not hold a conversation.
- **Onboarding sells features** (section toggles) instead of a result.
- **Dopamine is absent** — and the wrong kind would be worse. The segment punishes
  streak-shame (Finch's whole business is the opposite).

## The shape: three surfaces, one loop

### 1. Now
One card: what's now, what's next, one big action. Timeline below. The morning brief sits
on top until the first block ends; in the evening the card becomes the review, and the
review shows what went right *first*. Travel hints stay ("leave by 18:40 · 25 min").

### 2. Pace
The good dopamine, all certain rewards, no slot machine:

- Closing a block: haptic + a short, satisfying fill animation. Immediate and certain.
- The day ring closes → "Day on pace" with a one-line summary. Daily and certain.
- Days on pace accumulate into a month grid and a weekly pace %. Streak with **forgiveness**:
  one free miss per week (Duolingo's freeze, Finch's no-penalty), never a red zero.
- Blocks Health closed on their own are marked "closed itself" — the magic moment, shown.
- Surprise only in the review: "third Thursday in a row you made the gym."

Train, Focus and Food stop being tabs and become **block types** with their own detail:
a gym block opens HR, bests and readiness; a study block starts the focus timer and Live
Activity; water and meals are small blocks. Same code, moved behind the block.

### 3. Ask
The assistant is **Pacer itself**, not a coach. A sheet from anywhere ("Ask Pacer"), voice
first, built for capture and change: "gym tomorrow at 7 at Smart Fit", "move dinner, I'm
late", "what did I miss this week?". Chips fit the moment. No tab, no chat history as the
main surface (history stays reachable).

**Cut:** Money and Closet leave the default product (keep the code behind a "Labs" toggle
or delete it; my vote is delete — dead weight in the binary and the pitch). The section
registry stays; the default is Now · Pace · Ask.

### Character without a mascot
Finch proves a character sells, but a bird is wrong for this user. Pacer's face is the
**pace line**: a single animated line across the Now card that stays calm and green while
the day is on pace, drifts amber when behind, and settles when a replan lands. It is the
same object in the widget and the Live Activity. Cheap to build, on thesis, ownable.

Voice: short, warm, no exclamation marks, never "you failed". "Moved to 19:30." "Closed
itself — nice run." "Two left. Plenty of day."

## Onboarding = a running day in 60 seconds

1. "What does a good day look like?" — pick three blocks from templates with times.
2. Where — home, work, gym pins via Maps search → "we'll tell you when to leave".
3. Health → "gym blocks close themselves".
4. Notifications → "one question per block, one tap answers".
5. Screen five *is* today, already running, Live Activity visible.

Pricing: free 7 days, then $4.99/month or $29.99/year (hard paywall after the trial —
RevenueCat 2026: 10.7% download-to-paid vs 2.1% freemium, same year-one retention).
Cheaper than Tiimo, pricier than Structured, priced as a utility not a game.

## Fail-fast gates

- **Gate 1 — 4 weeks after v3 hits TestFlight:** 30 external testers from ADHD
  communities and Alan's network. D7 ≥ 25%, D30 ≥ 20%, DAU/MAU ≥ 20%, and ≥ 50% of days
  with at least one check-in answered from the notification (the loop, not the app).
- **Gate 2 — 8 weeks:** 5+ payers at $29.99/year, 30% of new users from a referral.
- Miss gate 1 → stop, write it up, next project.

## YC-lens evaluation (honest)

| Axis | 1–5 | Why |
|---|---|---|
| Problem real and painful | 4 | Validated by Tiimo, Structured, Finch, Routinery revenue; still "nice to have" for many. |
| Differentiation | 3 | The execution loop is distinct today; Tiimo shipped Review Today + Live Activities, Motion auto-reschedules. Parity within 12 months is plausible. |
| Market size | 3 | ~15M diagnosed ADHD adults in the US alone, self-identified far more; Tiimo's 50k payers show willingness. A winner is a Finch-sized business ($30–50M ARR), not a venture-scale platform. |
| Founder–market fit | 4 | Alan is the user; iOS build/CI engineer; shipped 20 builds in 6 days. Solo, no design or growth co-founder. |
| Traction | 1 | Zero external users, no retention data. |
| Distribution | 2 | No channel yet. ADHD TikTok/Reddit works for Tiimo and Finch but needs content or ad spend. |
| Defensibility | 2 | Apple could ship this in Reminders; the model is a commodity; the data moat is small. |
| Why now | 3 | Live Activities, Health, tool-using models. Real but not unique to Pacer. |

**Verdict today: not YC-ready, and the reason is not the product.** YC's own bar for
consumer apps is retention that survives without notifications (D7 > 25%, D30 > 20%,
DAU/MAU > 20%, 30%+ of new users from word of mouth). Pacer has none of those numbers
because nobody outside Alan has used it. A YC application filed now would be judged on
"10,000 downloads and no retention data" — theirs, not ours.

There is one structural tension to name: YC treats notification-driven retention as an
incomplete loop, and Pacer *is* notification-first. The answer has to be that the
notification is the product (Duolingo's reminders are, too) and that people come back to
see their pace on their own. That is exactly what gate 1 measures.

**Recommendation:** six weeks, not six months. Rebuild to the three surfaces, get thirty
real users, measure the gates. Pass → apply with numbers. Miss → next project.

## Status (2026-09-21, build 22)

Shipped the same day as this document: Now · Pace · Ask (#44), onboarding with goal chips and
templates (#45), anonymous usage counts + privacy promises (#46), "ends in 5 min" nudges and the
per-block quiet switch (#47). Research behind the order: `USERS.md`; surface-by-surface gaps:
`APP-MAP.md`. Next: voice capture in Ask, block types opening Train/Focus from a block, calendar
events as replanner obstacles, then the 30-tester TestFlight post.
