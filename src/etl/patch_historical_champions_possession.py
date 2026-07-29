"""Adds avg_possession_pct/pass_accuracy_pct to historical_champions, main
scope only (1994-2026) — same "own defensive style" spirit as avg_tackles/
avg_interceptions/avg_clearances/duel_win_pct, added later once the shots-vs-
goals analysis (Module A) surfaced the need for a ball-retention angle.

Source: the separate world_cup_db reference project (StatsBomb/Sofascore, no
live dependency in either direction, per CLAUDE.md) for 1994-2022. The 2026
row is copied from this project's own team_tournament_stats_fifa instead,
since it already exists here and is the more authoritative in-project source
for that year specifically (it also happens to match world_cup_db's own 2026
value almost exactly: 63.6%/0.895 vs 63.625%/0.895 — cross-validates both).
"""
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")

SOURCE_NOTE = "avg_possession_pct/pass_accuracy_pct: world_cup_db reference project (1994-2022), team_tournament_stats_fifa (2026)"

# year, team, avg_possession_pct, pass_accuracy_pct
PATCH = [
    (1994, "Brazil", 60.0, 0.8358),
    (1998, "France", 53.6, 0.7768),
    (2002, "Brazil", 48.3, 0.7920),
    (2006, "Italy", 48.0, 0.7904),
    (2010, "Spain", 65.7, 0.8645),
    (2014, "Germany", 60.3, 0.8525),
    (2018, "France", 48.3, 0.7894),
    (2022, "Argentina", 57.6, 0.8487),
    (2026, "Spain", 63.6, 0.8950),
]


def make_engine():
    user = os.environ["POSTGRES_USER"]
    password = os.environ["POSTGRES_PASSWORD"]
    host = os.environ["POSTGRES_HOST"]
    port = os.environ["POSTGRES_PORT"]
    db = os.environ["POSTGRES_DB"]
    return create_engine(f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}")


def main():
    engine = make_engine()
    with engine.begin() as conn:
        conn.execute(text("""
            ALTER TABLE historical_champions
                ADD COLUMN IF NOT EXISTS avg_possession_pct NUMERIC(4, 1),
                ADD COLUMN IF NOT EXISTS pass_accuracy_pct NUMERIC(5, 4)
        """))
        for year, team, possession, pass_acc in PATCH:
            result = conn.execute(
                text("""
                    UPDATE historical_champions
                    SET avg_possession_pct = :possession, pass_accuracy_pct = :pass_acc
                    WHERE world_cup_year = :year AND champion_team_name = :team
                """),
                {"year": year, "team": team, "possession": possession, "pass_acc": pass_acc},
            )
            if result.rowcount != 1:
                raise RuntimeError(f"Expected exactly 1 row for {year} {team}, matched {result.rowcount}")
    print(f"Patched {len(PATCH)} historical_champions rows with possession/pass-accuracy data.")


if __name__ == "__main__":
    main()
