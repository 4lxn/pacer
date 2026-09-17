# Pacer v2 — sections that stand on their own

_Written 2026-09-17 after builds 4–11. Goal: every section is a complete, attractive product of its
own, the menu is the user's, and the whole still reads as one idea: **your day, on pace**._

## 1. The idea, restated

Pacer runs the day: a plan of blocks, notifications that ask "did it happen?", a planner that
repairs misses, a coach that knows everything and can change anything. The other sections exist
because the day is made of them — training, food, focus, money, clothes. Each one must:

1. answer **"what now?"** at the top (a hero card, like Today's Now card);
2. show **progress** toward a goal the user chose (bar, ring, streak);
3. offer **one-tap actions** that feed the day (log, start, cook, done);
4. keep **history** that makes the goal feel real (charts, calendar, PRs);
5. be **usable by the coach** (tools + snapshot) and **feed Today** (auto-close, hints).

A section that can't do all five is a widget, not a section.

## 2. Modular menu

- **Registry** — `AppSection` enum: `today, train, food, focus, money, closet, coach`, each with
  title, symbol, tint, one-line pitch, `isCore` (Today always on). Order + enabled set live in
  `sections.json` (`SectionStore`). The tab bar renders the enabled sections in order; iOS shows a
  *More* tab past five.
- **Settings → Sections** — toggles and drag-to-reorder; a disabled section keeps its data.
- **Onboarding** — a "What should Pacer run?" step with the same list (Today + Coach preselected).
- **Coach** — tools and snapshot are filtered to enabled sections (fewer tokens, no talk about
  closets the user turned off).
- **Life** splits into **Focus**, **Money**, **Closet** — each earns its own tab and its own hero.

## 3. Design language

- One card grammar: 16 pt radius, `secondarySystemGroupedBackground`, 16 pt padding; section
  headers = headline + count capsule; every list row = leading glyph · time/amount · title ·
  trailing chip.
- Each section owns a **tint** (Today accent blue, Train orange, Food green, Focus indigo, Money
  teal, Closet pink, Coach purple) used for its hero eyebrow, progress and chart; everything else
  stays neutral so the day, not the chrome, is the colour.
- Motion: `.snappy` for state, `.blurReplace` for hero swaps, `numericText` for numbers, symbol
  bounce on completion, `.sensoryFeedback(.success)` when a goal advances.
- Empty states are invitations with one button, never a paragraph.
- Liquid Glass for chrome (toolbars, floating bars, chips); content stays flat.

## 4. Section plans

### Today (core) — done in v1; v2 adds
- **Evening review** card after the last block: what got done, what slipped, "carry to tomorrow"
  per miss (moves it with one tap, using the calendar + places).
- **Day streak** (days ≥ 80 %) next to the 14-day strip.
- **Siri / Shortcuts**: "What's next in Pacer", "Mark the current block done", "Move it later".

### Train
- Hero: today's session (Run / Gym) with status and the *leave by* time; readiness line
  (sleep · resting HR · yesterday's load) in plain words.
- Goals: runs / lifts / minutes per week with progress; PRs from Health (fastest 5 k / 10 k,
  longest run); 8-week chart stays; weight + goal stays.
- Coach: `get_training_week`, `set_training_goals`.

### Food
- Hero: what's left today (kcal, protein) and the next planned meal.
- **Water** (glasses, target, quick +1); **Plan my meals** (one tap: coach fills the day from pantry
  + targets + recipes, logs nothing until tapped); weekly averages; recipes + cook stay.

### Focus (was Study) — the polished one
- Hero: a **full-screen timer** with a ring, subject, focus / break phases, Live Activity in the
  Dynamic Island (countdown + Stop), end sound.
- Subjects with weekly goals; heat map of the last 12 weeks; streak; sessions grouped by day.
- Coach: `start_focus`, `stop_focus`, `add_subject`.

### Money (was Income)
- Income **and expenses** with categories; monthly budget per category; savings rate;
  6-month chart; "this month vs last".
- Coach: `add_expense`, `get_money_month`, `set_budget`.

### Closet
- Hero: today's outfit suggestion with weather when WeatherKit is enabled; laundry due; scan stays.

### Coach
- Entry points from every section ("Ask about this"), suggestions per section, morning brief
  (push) later.

## 5. Order of work (each a PR + TestFlight build)

1. Sections registry, Settings → Sections, onboarding step, Life split, coach filtering.
2. Focus: full-screen timer + Live Activity + subjects + heat map (the showcase).
3. Money: expenses, budgets, savings.
4. Food: water, plan my meals, weekly averages.
5. App Intents / Siri for Today and Focus.
6. Today: evening review + streak. Train: goals, readiness, PRs.
7. Closet: weather (WeatherKit) if the entitlement is granted.
