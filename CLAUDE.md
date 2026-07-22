# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

**Schema designed and validated, no ETL/analysis code yet.** Repo is live at
https://github.com/danbarretom/worldcup-2026-analytics (`main`/`dev` pushed), scaffolded
(`data/{raw,processed}`, `sql/`, `src/`, `app/`, `notebooks/`, `tests/`), with `.gitignore`, `requirements.txt`,
`CHANGELOG.md`, CI/CD (`.github/workflows/ci-cd.yml`), and `sql/schema.sql` (validated against the real
dataset, see below) in place. `project-scope.md` is the source of truth for scope, priorities, and decisions
already made (Portuguese, internal planning doc — not the public-facing README). Treat it the way you'd treat a
settled design doc: don't re-litigate its calls, but do update the changelog when a decision in it changes
during implementation.

Once real analysis/pipeline code exists, this file should be updated with actual lint/test commands (beyond
the bare `pytest`) and real architecture notes — don't leave this section stale once there's something to
document.

**Commands today**: `pip install -r requirements.txt`, `pytest` (currently collects zero tests — CI treats
that as success via exit-code 5, not a real pass signal).

## What this project is

A data portfolio project analyzing the 2026 World Cup, built for two hiring tracks: data analyst/scientist/
engineer (primary) and full-stack backend (secondary, via the pipeline + relational DB). It is explicitly
**not** a generic World Cup stats dashboard — every module tests a specific football thesis against data
(confirms, refines, or contradicts it), rather than just reporting top-N stats. Scope decisions throughout are
filtered by "does this strengthen the job application?" before "is this interesting?".

**Central narrative**: "Control isn't always the result — the 2026 World Cup told through the two paths to the
final." Spain: distinct playing philosophy, consistent dominance, early struggles converting possession into
goals, best defensive campaign in World Cup history. Argentina: more irregular campaign, efficient with less
possession, decided by details (experience, Dibu Martínez, Messi). The final embodies both arcs: Spain's
20-0 shot dominance in one stretch resolved by a 1-0 extra-time goal, with Argentina still creating a clear
equalizer chance afterward.

## Module priority (implementation order — follow this, not alphabetical)

**Priority 1 — MVP core** (data fully confirmed, high visual impact): built first.
- **Module A** — Is Spain's 2026 defense the statistically most efficient title-winning campaign in World Cup
  history (goals conceded per game)? Best "hero visual" candidate.
- **Module B** — Spain vs. Argentina campaign comparison (possession, xG, goal difference, comeback games).
- **Module C** — The final: is Spain's shot/xG volume consistent with a game normally decided by 3+ goals, and
  why did it end 1-0 in extra time? Emotional climax of the project, meant to open the README.

**Priority 2 — supporting chapters** (data confirmed, lower complexity): Module D (Spain's slow start —
conversion rate curve from group stage to knockouts, anchored on the 0-0 vs. Cape Verde opener), Module E
(England's offensive collapse after conceding in the semifinal vs. Argentina — reportedly 12% possession
between conceding and Argentina's winner), Module F (is the 6-4 third-place match a historical anomaly?).

**Priority 3 — stretch, conditional on source validation**: Module G (proving pressing is the mechanism behind
Module A's defensive record, via a PPDA-style metric) needs Squawka event data with coordinates, not yet
confirmed available for 2026. Explicitly **not** in MVP scope. If Squawka access is confirmed in Phase 1, it
becomes a bonus chapter; if not, the project stands fine without it — this is reinforcement, not a dependency.

Honorable mentions (short README paragraphs, not dedicated modules): Portugal/CR7 decline, the 48-team format
(Cape Verde, Colombia, US/Mexico home advantage), Brazil (deliberately kept brief — no new question to explore
there).

## Intended stack

Chosen to match the `SalesSystem`-style portfolio pattern the user already runs elsewhere, and because the
user already knows this flow — but the scope doc explicitly gives this Claude Code session latitude to revise
it if there's a better portfolio-fit call:

- Python (pandas, SQL via `psycopg2`/SQLAlchemy)
- PostgreSQL — own relational schema, populated from the Kaggle dataset + cross-validated against
  football-data.org
- `statsbombpy` (StatsBomb Open Data) for the 2022 historical comparison slice (Modules C/G only)
- Streamlit for the presentation front-end
- Stretch: a custom Squawka scraper — only after Phase 1 viability confirms the format is still accessible for
  2026; no code commitment before that check

## Data sources — validated in Phase 1 (see `CHANGELOG.md` for full detail)

| Source | Role | Status |
|---|---|---|
| Kaggle dataset `mominullptr/fifa-world-cup-2026-dataset` (relational, 12 tables, mirrored on GitHub) | Primary base | **Fully validated directly against the real CSVs** (not just the published description) — real/curated data (fifa.com/sofascore.com sourced per match, not simulated), tournament 100% complete (104/104 matches), zero FK violations. `match_events.csv` is goal/card/VAR-level w/ minute, **not** a shot-by-shot event stream; `match_team_stats.csv` carries the per-team-per-match aggregates (possession, shots, corners, fouls, offsides, saves) that Module C actually needs. The final's real numbers already validate the project's central thesis: Spain 1-0 Argentina AET, 65%/20 shots vs. 35%/2 shots. **Gotcha**: the GitHub mirror's `generate_dataset.py` bootstrap script is frozen at match 93 (stale) — later matches are patched directly into the CSVs by small dedicated scripts, so always read the CSVs (or the Kaggle API) directly, never trust that generator script's own hardcoded arrays for current state. Full detail in `CHANGELOG.md`. |
| football-data.org | Cross-validation for 2026 data only | **Confirmed**: free tier's historical data is limited to the current season — does **not** cover past World Cups. Not usable for Module A. |
| Wikipedia (or another dedicated historical dataset) | Historical champion defensive records (Module A) | Now the primary plan for Module A, since neither of the above covers past Cups. |
| FIFA Match Report Hub | Qualitative context | Available, format to check |
| StatsBomb Open Data (2022) | Event-level historical comparison | Confirmed available via `statsbombpy` |
| Squawka | Stretch goal (Module G) | **Confirmed not viable**: no public API — Squawka has publicly stated a previously-found API was internal and "shouldn't be public." Structured Opta access would require a commercial StatsPerform contract. Module G via Squawka is off the table; a StatsBomb-based pressing proxy for the 2022 slice is the only remaining option worth discussing, and that's a separate decision, not a Squawka scrape. |

`sql/schema.sql` implements the validated structure: `teams`, `venues`, `tournament_stages`, `referees`,
`players`, `matches`, `match_events`, `match_team_stats`, `match_lineups`, `player_stats`, plus a standalone
`historical_champions` table (for Module A, populated from Wikipedia — not in the Kaggle dataset) and a
`matches_detailed` view. Kaggle credentials still aren't configured in this environment — schema/FK validation
so far used the CSVs pulled from the dataset's public GitHub mirror, not the Kaggle API itself; loading real
data into Postgres will need either the mirror CSVs or Kaggle credentials, whichever is more convenient when
that ETL step happens.

## Execution phases

1. **Foundation (MVP)** — validate data sources, model + populate the PostgreSQL schema, build Modules A/B/C,
   first Streamlit deploy.
2. **Narrative body** — Modules D/E/F, StatsBomb 2022 historical integration, visual refinement.
3. **Polish & stretch** — final Squawka viability check → Module G if it clears, README to the same bar as the
   `SalesSystem` project (badges, screenshot/GIF, "why this project" section, live link), final deploy.

## Working conventions (mirrors the user's other portfolio repos, e.g. `SalesSystem`/`TrabalhoAV3Refatorado`)

- **Changelog**: maintain a `CHANGELOG.md` recording real technical decisions made during implementation (e.g.
  final table schema, whether Squawka made the cut) — not just a task list. This has proven a strong portfolio
  differentiator on prior projects; keep the habit here.
- **README**: the public `README.md` must be in **English**, matching the other repos under `danbarretom` on
  GitHub. `project-scope.md` (Portuguese) is internal planning only, never the public doc.
- **Repo name**: not yet decided — pick it in Phase 1 once the schema and first module are running and there's
  something tangible to name.
- **Git/CI-CD flow**: plan to follow the same shape used on `TrabalhoAV3Refatorado` — `main`/`dev` branches,
  GitHub Actions running the test suite on push/PR to both, a `release/*` branch merged into `main` triggering
  an automated GitHub Release whose version is read from the first `## [x.y.z]` line of `CHANGELOG.md`. Adapt
  the specifics to this project's Python/Streamlit/Postgres stack rather than copying the Java/Maven pipeline
  verbatim (e.g. `mvn test` → `pytest`), but keep the same overall pattern (dual-branch, changelog-driven
  release automation, tests gating merges).
