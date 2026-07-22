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
    player_name    VARCHAR(100) NOT NULL,
    position        VARCHAR(10),
    club_team      VARCHAR(100),
    market_value_eur NUMERIC(12, 2),
    caps           SMALLINT,
    date_of_birth  DATE,
    height_cm      SMALLINT,
    -- Pre-tournament career/international goals (roster bio stat) — distinct
    -- from player_stats.goals below, which counts goals in this tournament.
    career_goals   SMALLINT
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
    event_id   INTEGER PRIMARY KEY,
    match_id   SMALLINT NOT NULL REFERENCES matches (match_id),
    minute     SMALLINT NOT NULL,
    -- 'Goal' / 'Assist' / 'Yellow Card' / 'Red Card' / 'VAR Review'.
    -- Goal-and-card level, not a shot-by-shot event stream — see Module C
    -- note in CHANGELOG.md before assuming per-shot timing is available here.
    event_type VARCHAR(20) NOT NULL,
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
-- Historical data — NOT in the Kaggle dataset (2026-only, confirmed in
-- CHANGELOG.md). Populated from Wikipedia for Module A (Spain 2026's
-- defensive record vs. every past champion). Kept as a small standalone
-- table rather than trying to force decades of loosely-structured historical
-- box scores into the match-level schema above.
-- ============================================================================

CREATE TABLE historical_champions (
    world_cup_year          SMALLINT PRIMARY KEY,
    champion_team_name      VARCHAR(100) NOT NULL,
    games_played            SMALLINT NOT NULL,
    goals_conceded          SMALLINT NOT NULL,
    goals_conceded_per_game NUMERIC(4, 2) GENERATED ALWAYS AS
        (ROUND(goals_conceded::numeric / NULLIF(games_played, 0), 2)) STORED,
    source                  VARCHAR(100) NOT NULL DEFAULT 'Wikipedia'
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
