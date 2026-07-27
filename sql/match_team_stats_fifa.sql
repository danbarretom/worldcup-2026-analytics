-- Per-match FIFA official stats (Gracenote, via fdh-api.fifa.com — no auth
-- needed, unlike the gameday tournament-aggregate API). 141 raw stats per
-- team per match, stored as-is (key/value) rather than reshaped into fixed
-- columns — the set is large, our own use of it is still exploratory, and
-- a few field names carry ambiguity worth resolving case-by-case before
-- ever normalizing them into their own columns (see CHANGELOG.md).
CREATE TABLE match_team_stats_fifa (
    match_id   SMALLINT NOT NULL REFERENCES matches (match_id),
    team_id    SMALLINT NOT NULL REFERENCES teams (team_id),
    stat_name  VARCHAR(60) NOT NULL,
    stat_value NUMERIC(14, 4),
    data_source  VARCHAR(50) NOT NULL DEFAULT 'FIFA official (fdh-api.fifa.com)',
    last_updated DATE,
    PRIMARY KEY (match_id, team_id, stat_name)
);
