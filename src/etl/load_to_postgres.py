"""Loads the World Cup 2026 dataset CSVs (data/raw/) into the Postgres schema
defined in sql/schema.sql. Run after `docker compose up -d` and applying the
schema. historical_champions is intentionally not touched here — it's seeded
separately once its source data is verified.
"""
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw"

load_dotenv(ROOT / ".env")

# Source bug: squads_and_players.csv (and player_stats.csv, copied from it)
# truncates several Mc- surnames to literally "Mc". Identified by Daniel via
# manual research 2026-07-22 — see CHANGELOG.md.
PLAYER_NAME_CORRECTIONS = {
    290: "Scott McTominay",
    293: "John McGinn",
    309: "Kenny McLean",
    312: "Scott McKenna",
    320: "Weston McKennie",
    334: "Mark McKenzie",
    722: "Callum McCowatt",
}

DECIMAL_COLUMNS = {
    "market_value_eur",
    "avg_cards_per_game",
    "home_xg",
    "away_xg",
    "average_rating",
    "latitude",
    "longitude",
}


def make_engine():
    user = os.environ["POSTGRES_USER"]
    password = os.environ["POSTGRES_PASSWORD"]
    host = os.environ["POSTGRES_HOST"]
    port = os.environ["POSTGRES_PORT"]
    db = os.environ["POSTGRES_DB"]
    return create_engine(f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}")


def read_csv(name: str) -> pd.DataFrame:
    df = pd.read_csv(RAW_DIR / f"{name}.csv")
    # Nullable numeric columns are inferred as float64 by pandas when they
    # contain blanks (e.g. penalty scores, referee_id). Cast to the pandas
    # nullable Int64 dtype so missing values serialize as SQL NULL instead
    # of a literal like "3.0", which Postgres rejects for integer columns.
    for col in df.columns:
        if df[col].dtype == "float64" and col not in DECIMAL_COLUMNS:
            df[col] = df[col].astype("Int64")
    return df


def load_table(engine, df: pd.DataFrame, table: str) -> None:
    df.to_sql(table, engine, if_exists="append", index=False, method="multi", chunksize=500)
    print(f"  {table}: {len(df)} rows")


def main():
    engine = make_engine()

    print("Loading independent tables...")
    load_table(engine, read_csv("tournament_stages"), "tournament_stages")
    load_table(engine, read_csv("venues"), "venues")
    load_table(engine, read_csv("referees"), "referees")
    load_table(engine, read_csv("teams"), "teams")

    print("Loading players...")
    players = read_csv("squads_and_players").rename(columns={"goals": "pre_tournament_intl_goals"})
    players["player_name"] = players["player_id"].map(PLAYER_NAME_CORRECTIONS).fillna(players["player_name"])
    load_table(engine, players, "players")

    print("Loading matches...")
    matches = read_csv("matches").rename(columns={"date": "match_date"})
    load_table(engine, matches, "matches")

    print("Loading match_events...")
    events = read_csv("match_events")
    # Source notates stoppage time as "90+6" / "120+1" (base+stoppage).
    minute_str = events["minute"].astype(str)
    split = minute_str.str.split("+", n=1, expand=True)
    events["minute"] = split[0].astype("Int64")
    events["stoppage_minute"] = split[1].astype("Int64") if 1 in split.columns else pd.array([pd.NA] * len(events), dtype="Int64")
    load_table(engine, events, "match_events")

    print("Loading match_team_stats...")
    team_stats = read_csv("match_team_stats").drop(columns=["player_of_the_match"])
    load_table(engine, team_stats, "match_team_stats")

    print("Loading match_lineups...")
    lineups = read_csv("match_lineups")
    lineups["is_starting_xi"] = lineups["is_starting_xi"].astype(bool)
    load_table(engine, lineups, "match_lineups")

    print("Loading player_stats...")
    player_stats = read_csv("player_stats").drop(columns=["player_name", "team_id", "position"])
    load_table(engine, player_stats, "player_stats")

    print("Done.")


if __name__ == "__main__":
    main()
