-- ============================================================================
-- World Cup 2026 Analytics — PostgreSQL schema
--
-- Source: Kaggle dataset mominullptr/fifa-world-cup-2026-dataset (mirrored at
-- github.com/mominullptr/FIFA-World-Cup-2026-Dataset), inspected directly
-- (CSV headers + real rows, not just the published description) 2026-07-22.
-- Confirmed real/curated (fifa.com + sofascore.com sourced per match, not
-- simulated) and current through the Final (match 104, Spain 1-0 Argentina
-- AET) — see CHANGELOG.md for the full validation writeup.
--
-- Two tables in the source were deliberately NOT modeled here:
--   - match_prediction_features.csv (65 ML features) — this project tests
--     specific narrative theses against data, it doesn't build a predictor.
--   - matches_detailed.csv — a denormalized join of matches/teams/venues/
--     referees/players kept in the source for convenience. Recreated below
--     as a VIEW instead of a stored table, so it can't drift from the base
--     tables.
-- ============================================================================

CREATE TABLE tournament_stages (
    stage_id    SMALLINT PRIMARY KEY,
    stage_name  VARCHAR(50) NOT NULL,
    is_knockout BOOLEAN NOT NULL
);

CREATE TABLE venues (
    venue_id         SMALLINT PRIMARY KEY,
    stadium_name     VARCHAR(100) NOT NULL,
    city             VARCHAR(100) NOT NULL,
    country          VARCHAR(50) NOT NULL,
    capacity         INTEGER,
    latitude         NUMERIC(9, 6),
    longitude        NUMERIC(9, 6),
    elevation_meters INTEGER
);

CREATE TABLE referees (
    referee_id         SMALLINT PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    country             VARCHAR(50),
    avg_cards_per_game  NUMERIC(4, 2)
);

CREATE TABLE teams (
    team_id                     SMALLINT PRIMARY KEY,
    team_name                   VARCHAR(100) NOT NULL,
    fifa_code                   CHAR(3) NOT NULL,
    group_letter                CHAR(1) NOT NULL,
    confederation               VARCHAR(20) NOT NULL,
    fifa_ranking_pre_tournament SMALLINT,
    elo_rating                  SMALLINT,
    manager_name                VARCHAR(100)
);

CREATE TABLE players (
    player_id      INTEGER PRIMARY KEY,
    team_id        SMALLINT NOT NULL REFERENCES teams (team_id),
    -- Known source data-quality bug: 7 players (mostly Scotland/USA squads)
    -- have player_name truncated to literally "Mc" in the source CSV — see
    -- CHANGELOG.md for the full list and correction status.
    player_name    VARCHAR(100) NOT NULL,
    position        VARCHAR(10),
    club_team      VARCHAR(100),
    market_value_eur NUMERIC(12, 2),
    caps           SMALLINT,
    date_of_birth  DATE,
    height_cm      SMALLINT,
    -- Goals scored for the national team BEFORE the 2026 tournament (verified
    -- against Cristiano Ronaldo's real tally: 143 here + 3 in player_stats.goals
    -- = 146, matching his actual post-2026 total) — NOT a club+country career
    -- total. Distinct from player_stats.goals, which counts goals in this
    -- tournament only.
    pre_tournament_intl_goals SMALLINT
);

CREATE INDEX idx_players_team ON players (team_id);

CREATE TABLE matches (
    match_id                SMALLINT PRIMARY KEY,
    match_date              DATE NOT NULL,
    kickoff_time_utc        TIME,
    stage_id                SMALLINT NOT NULL REFERENCES tournament_stages (stage_id),
    venue_id                SMALLINT NOT NULL REFERENCES venues (venue_id),
    home_team_id            SMALLINT NOT NULL REFERENCES teams (team_id),
    away_team_id            SMALLINT NOT NULL REFERENCES teams (team_id),
    home_score              SMALLINT,
    away_score              SMALLINT,
    home_penalty_score      SMALLINT,
    away_penalty_score      SMALLINT,
    status                  VARCHAR(20) NOT NULL,
    -- 'Regular' / 'AET' / 'Penalties' once status = 'Completed'; NULL while 'Scheduled'.
    result_type             VARCHAR(20),
    home_xg                 NUMERIC(4, 2),
    away_xg                 NUMERIC(4, 2),
    referee_id              SMALLINT REFERENCES referees (referee_id),
    player_of_the_match_id  INTEGER REFERENCES players (player_id),
    CHECK (home_team_id <> away_team_id)
);

CREATE INDEX idx_matches_stage ON matches (stage_id);
CREATE INDEX idx_matches_home_team ON matches (home_team_id);
CREATE INDEX idx_matches_away_team ON matches (away_team_id);

CREATE TABLE match_events (
    event_id         INTEGER PRIMARY KEY,
    match_id         SMALLINT NOT NULL REFERENCES matches (match_id),
    -- Source minute is notated like "90+6" or "120+1" for stoppage time.
    -- Split into base minute (45/90/120 marks which period: 1st half, 2nd
    -- half or extra time) + nullable stoppage_minute, instead of collapsing
    -- to a single number, which would misrepresent elapsed match time.
    minute           SMALLINT NOT NULL,
    stoppage_minute  SMALLINT,
    -- 'Goal' / 'Assist' / 'Yellow Card' / 'Red Card' / 'VAR Review' /
    -- 'Penalty Shootout Goal' / 'Penalty Shootout Miss'.
    -- Goal-and-card level, not a shot-by-shot event stream — see Module C
    -- note in CHANGELOG.md before assuming per-shot timing is available here.
    event_type VARCHAR(30) NOT NULL,
    team_id    SMALLINT NOT NULL REFERENCES teams (team_id),
    player_id  INTEGER REFERENCES players (player_id)
);

CREATE INDEX idx_events_match ON match_events (match_id);
CREATE INDEX idx_events_type ON match_events (event_type);

CREATE TABLE match_team_stats (
    match_id         SMALLINT NOT NULL REFERENCES matches (match_id),
    team_id          SMALLINT NOT NULL REFERENCES teams (team_id),
    possession_pct   SMALLINT,
    total_shots      SMALLINT,
    shots_on_target  SMALLINT,
    corners          SMALLINT,
    fouls            SMALLINT,
    offsides         SMALLINT,
    saves            SMALLINT,
    data_source      VARCHAR(30),
    last_updated     DATE,
    PRIMARY KEY (match_id, team_id)
);

CREATE TABLE match_lineups (
    lineup_id          INTEGER PRIMARY KEY,
    match_id           SMALLINT NOT NULL REFERENCES matches (match_id),
    player_id          INTEGER NOT NULL REFERENCES players (player_id),
    team_id            SMALLINT NOT NULL REFERENCES teams (team_id),
    is_starting_xi     BOOLEAN NOT NULL,
    tactical_position  VARCHAR(10),
    minutes_played     SMALLINT
);

CREATE INDEX idx_lineups_match ON match_lineups (match_id);
CREATE INDEX idx_lineups_player ON match_lineups (player_id);

-- Cumulative tournament totals per player. Source CSV repeats player_name/
-- team_id/position (already on `players`) — dropped here to avoid a copy
-- that can drift from the roster table; join through player_id instead.
CREATE TABLE player_stats (
    player_id        INTEGER PRIMARY KEY REFERENCES players (player_id),
    matches_played    SMALLINT,
    matches_started   SMALLINT,
    minutes_played    SMALLINT,
    goals             SMALLINT,
    assists           SMALLINT,
    shots             SMALLINT,
    shots_on_target   SMALLINT,
    yellow_cards      SMALLINT,
    red_cards         SMALLINT,
    penalty_goals     SMALLINT,
    own_goals         SMALLINT,
    clean_sheets      SMALLINT,
    saves             SMALLINT,
    goals_conceded    SMALLINT,
    average_rating    NUMERIC(3, 1),
    data_source       VARCHAR(30),
    last_verified     DATE
);

-- ============================================================================
-- Team tournament-aggregate stats from FIFA's own official data (Gracenote-
-- powered "gameday" backend behind fifa.com's team-statistics page for 2026 —
-- reverse-engineered, no public docs; see CHANGELOG.md). One row per team,
-- whole-tournament totals/averages, NOT per-match — a different grain than
-- match_team_stats above. Loaded from a one-off local script, not part of
-- src/etl/ (this is FIFA-official enrichment, not the base Kaggle dataset).
-- Adds real official xG, passing/defending action counts, pressing proxies,
-- and physical tracking data (distance/speed/sprints) that the Kaggle
-- dataset doesn't have at all.
-- ============================================================================

CREATE TABLE team_tournament_stats_fifa (
    team_id       SMALLINT PRIMARY KEY REFERENCES teams (team_id),

    -- Attacking
    avg_shots               NUMERIC(4, 1),
    avg_shots_on_target     NUMERIC(4, 1),
    avg_shots_off_target    NUMERIC(4, 1),
    avg_shots_inside_box    NUMERIC(4, 1),
    avg_shots_outside_box   NUMERIC(4, 1),
    avg_headed_shots        NUMERIC(4, 1),
    avg_xg                  NUMERIC(4, 2),
    avg_assists             NUMERIC(4, 2),
    avg_big_chances_created NUMERIC(4, 2),
    avg_big_chances_missed  NUMERIC(4, 2),
    avg_possession_pct      NUMERIC(4, 1),
    avg_corners              NUMERIC(4, 1),
    penalties_scored         SMALLINT,
    total_own_goals          SMALLINT,

    -- Distribution
    avg_passes                    NUMERIC(6, 1),
    pass_accuracy_pct             NUMERIC(5, 4),
    avg_crosses                   NUMERIC(4, 1),
    crossing_accuracy_pct         NUMERIC(5, 4),
    avg_long_balls                NUMERIC(5, 1),
    avg_linebreaks_attempted      NUMERIC(5, 1),
    linebreak_accuracy_pct        NUMERIC(5, 4),
    avg_switches_of_play          NUMERIC(4, 1),
    switches_of_play_accuracy_pct NUMERIC(5, 4),

    -- Defending
    avg_tackles                            NUMERIC(4, 1),
    avg_interceptions                      NUMERIC(4, 1),
    avg_clearances                         NUMERIC(4, 1),
    duel_win_pct                           NUMERIC(5, 4),
    avg_fouls_committed                    NUMERIC(4, 1),
    avg_offsides                           NUMERIC(4, 1),
    avg_forced_turnovers                   NUMERIC(5, 1),
    avg_ball_recovery_time                 NUMERIC(5, 2), -- avg seconds, not per-game total
    avg_defensive_pressures_applied        NUMERIC(6, 1), -- pressing-intensity proxy
    avg_direct_defensive_pressures_applied NUMERIC(5, 1),

    -- Discipline
    total_yellow_cards       SMALLINT,
    total_red_cards          SMALLINT,
    total_indirect_red_cards SMALLINT, -- second-yellow dismissals, already included in total_red_cards

    -- Goalkeeping
    avg_saves NUMERIC(4, 1),

    -- Physical (2026+ only — GPS/tracking data didn't exist for older tournaments)
    avg_distance_covered_km NUMERIC(6, 2), -- whole-team total per match, not per-player
    avg_speed_kmh            NUMERIC(4, 2),
    avg_sprints              NUMERIC(6, 1),

    -- Movement (off-the-ball positioning/receiving)
    avg_offers_to_receive_total                        NUMERIC(6, 1),
    avg_offers_to_receive_in_behind                     NUMERIC(5, 1),
    avg_offers_to_receive_in_between                    NUMERIC(5, 1),
    avg_offers_to_receive_in_front                      NUMERIC(5, 1),
    avg_offers_to_receive_inside                        NUMERIC(5, 1),
    avg_offers_to_receive_outside                       NUMERIC(5, 1),
    avg_receptions_in_behind                            NUMERIC(4, 1),
    avg_receptions_between_midfield_and_defensive_line  NUMERIC(5, 1),
    avg_receptions_under_pressure                       NUMERIC(5, 1),

    data_source   VARCHAR(50) NOT NULL DEFAULT 'FIFA official (Gracenote gameday API)',
    last_updated  DATE
);

-- ============================================================================
-- Historical data — NOT in the Kaggle dataset (2026-only, confirmed in
-- CHANGELOG.md). Populated for Module A (Spain 2026's defensive record vs.
-- past champions). Scope fixed at 1958-2022 (17 tournaments) with Daniel
-- 2026-07-22 — pre-1958 excluded even from this baseline, too different an
-- era of football for a meaningful comparison. games_played/goals_conceded
-- sourced from thesoccerworldcups.com (cross-checked against FIFA's own
-- "fewest goals conceded" record citations), not Wikipedia as originally
-- planned — see CHANGELOG.md. Kept as a small standalone table rather than
-- forcing decades of loosely-structured historical box scores into the
-- match-level schema above.
-- ============================================================================

CREATE TABLE historical_champions (
    world_cup_year          SMALLINT PRIMARY KEY,
    champion_team_name      VARCHAR(100) NOT NULL,
    games_played            SMALLINT NOT NULL,
    goals_conceded          SMALLINT NOT NULL,
    goals_conceded_per_game NUMERIC(4, 2) GENERATED ALWAYS AS
        (ROUND(goals_conceded::numeric / NULLIF(games_played, 0), 2)) STORED,

    -- Deep layer, Module A "beyond raw goals conceded" — populated for the
    -- 1994-2022 main scope + 2026 (Spain, added as an 18th row here so the
    -- comparison is one query). 1958-1990 stay NULL on purpose (out of main
    -- scope; different football era makes the comparison itself weaker, not
    -- just a data-availability problem — see CHANGELOG.md).
    shots_conceded_total            SMALLINT,
    shots_conceded_per_game         NUMERIC(4, 2) GENERATED ALWAYS AS
        (ROUND(shots_conceded_total::numeric / NULLIF(games_played, 0), 2)) STORED,
    shots_on_target_conceded_total  SMALLINT,
    shots_on_target_conceded_per_game NUMERIC(4, 2) GENERATED ALWAYS AS
        (ROUND(shots_on_target_conceded_total::numeric / NULLIF(games_played, 0), 2)) STORED,
    -- Sofascore's own "big chance" tag (high-probability chances), not a
    -- model — a coarser, honestly-labeled stand-in for xG where no shot
    -- location data exists to compute real xG (pre-2014).
    big_chances_conceded_total      SMALLINT,
    big_chances_conceded_per_game   NUMERIC(4, 2) GENERATED ALWAYS AS
        (ROUND(big_chances_conceded_total::numeric / NULLIF(games_played, 0), 2)) STORED,
    -- Real xG against — only where a shot-location-based source exists:
    -- 2014 (whoscored), 2018/2022 (StatsBomb event data), 2026 (FIFA
    -- official, derived from the opponent's own XG in the same match).
    -- NULL elsewhere on purpose, not approximated (see CHANGELOG.md).
    xg_against_total        NUMERIC(5, 2),
    xg_against_per_game     NUMERIC(4, 2) GENERATED ALWAYS AS
        (ROUND(xg_against_total / NULLIF(games_played, 0), 2)) STORED,
    saves_total              SMALLINT,
    save_pct                 NUMERIC(5, 4) GENERATED ALWAYS AS
        (ROUND(saves_total::numeric / NULLIF(saves_total + goals_conceded, 0), 4)) STORED,
    -- Defensive work-rate/style profile (own actions, not conceded) —
    -- distinguishes a high-press/high-turnover team from a deep low-block
    -- one that just concedes little through structure.
    avg_tackles       NUMERIC(4, 1),
    avg_interceptions NUMERIC(4, 1),
    avg_clearances    NUMERIC(4, 1),
    duel_win_pct      NUMERIC(5, 4),
    -- Ball-retention profile — main scope (1994-2026) only, sourced from the
    -- separate world_cup_db reference project (StatsBomb/Sofascore, same
    -- technique documented there) for 1994-2022; 2026 copied from this
    -- project's own team_tournament_stats_fifa instead, since it already
    -- exists here and is the more authoritative in-project source.
    avg_possession_pct NUMERIC(4, 1),
    pass_accuracy_pct  NUMERIC(5, 4),

    source                  VARCHAR(100) NOT NULL
);

-- ============================================================================
-- Convenience view — mirrors the source's matches_detailed.csv without
-- storing a denormalized copy.
-- ============================================================================

CREATE VIEW matches_detailed AS
SELECT
    m.match_id,
    m.match_date,
    m.kickoff_time_utc,
    st.stage_name,
    v.stadium_name,
    v.city,
    v.country,
    ht.team_name AS home_team_name,
    ht.fifa_code AS home_fifa_code,
    at.team_name AS away_team_name,
    at.fifa_code AS away_fifa_code,
    m.home_score,
    m.away_score,
    m.home_penalty_score,
    m.away_penalty_score,
    m.status,
    m.result_type,
    m.home_xg,
    m.away_xg,
    potm.player_name AS player_of_the_match_name,
    r.name AS referee_name
FROM matches m
JOIN tournament_stages st ON st.stage_id = m.stage_id
JOIN venues v ON v.venue_id = m.venue_id
JOIN teams ht ON ht.team_id = m.home_team_id
JOIN teams at ON at.team_id = m.away_team_id
LEFT JOIN players potm ON potm.player_id = m.player_of_the_match_id
LEFT JOIN referees r ON r.referee_id = m.referee_id;
