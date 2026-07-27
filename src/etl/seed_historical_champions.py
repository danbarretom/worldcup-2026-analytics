"""Seeds historical_champions (1958-2022) — not part of the Kaggle dataset
(2026-only), sourced separately. Scope fixed at 1958-2022 with Daniel
2026-07-22: pre-1958 tournaments excluded even from this baseline layer
(too different an era of football to draw a meaningful comparison), see
CHANGELOG.md. games_played/goals_conceded verified against
thesoccerworldcups.com, cross-checked against FIFA's own "fewest goals
conceded" record citation (France 1998/Italy 2006/Spain 2010 = 2 each) and
against Spain 2026's already-loaded real campaign (1 conceded/8 games).
Deeper metrics (shots conceded, possession, saves) are added in a later
pass — see historical_champions_research.xlsx (outside the repo) and the
statsbombpy-covered tournaments noted in CHANGELOG.md.
"""
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")

SOURCE = "thesoccerworldcups.com (cross-checked vs FIFA record citations), 2026-07-22"

CHAMPIONS = [
    (1958, "Brazil", 6, 4),
    (1962, "Brazil", 6, 5),
    (1966, "England", 6, 3),
    (1970, "Brazil", 6, 7),
    (1974, "West Germany", 7, 4),
    (1978, "Argentina", 7, 4),
    (1982, "Italy", 7, 6),
    (1986, "Argentina", 7, 5),
    (1990, "West Germany", 7, 5),
    (1994, "Brazil", 7, 3),
    (1998, "France", 7, 2),
    (2002, "Brazil", 7, 4),
    (2006, "Italy", 7, 2),
    (2010, "Spain", 7, 2),
    (2014, "Germany", 7, 4),
    (2018, "France", 7, 6),
    (2022, "Argentina", 7, 8),
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
        for year, team, games, conceded in CHAMPIONS:
            conn.execute(
                text(
                    """
                    INSERT INTO historical_champions
                        (world_cup_year, champion_team_name, games_played, goals_conceded, source)
                    VALUES (:year, :team, :games, :conceded, :source)
                    ON CONFLICT (world_cup_year) DO UPDATE SET
                        champion_team_name = EXCLUDED.champion_team_name,
                        games_played = EXCLUDED.games_played,
                        goals_conceded = EXCLUDED.goals_conceded,
                        source = EXCLUDED.source
                    """
                ),
                {"year": year, "team": team, "games": games, "conceded": conceded, "source": SOURCE},
            )
    print(f"Seeded {len(CHAMPIONS)} historical champions (1958-2022).")


if __name__ == "__main__":
    main()
