"""
Module A: is Spain's 2026 defensive campaign the most statistically
efficient title-winning campaign in World Cup history?

Reads historical_champions (18 rows: 1958-2022 + 2026). The shallow layer
(goals_conceded_per_game) covers all 18; the deep layer (shots/big-chances/
xG conceded, defensive style) covers the 1994-2026 main scope (9 rows) —
see CLAUDE.md for why 1958-1990 were narrowed out of the deep comparison.
"""
import os

import pandas as pd
import psycopg2
from dotenv import load_dotenv

load_dotenv()

MAIN_SCOPE_START_YEAR = 1994


def load_historical_champions() -> pd.DataFrame:
    conn = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST"), port=os.getenv("POSTGRES_PORT"),
        dbname=os.getenv("POSTGRES_DB"), user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )
    df = pd.read_sql("SELECT * FROM historical_champions ORDER BY world_cup_year", conn)
    conn.close()
    return df


def main():
    df = load_historical_champions()

    print("=" * 80)
    print("1) FULL HISTORICAL RANKING — goals conceded per game (all 18, 1958-2026)")
    print("=" * 80)
    ranked = df.sort_values("goals_conceded_per_game").reset_index(drop=True)
    print(ranked[["world_cup_year", "champion_team_name", "games_played",
                  "goals_conceded", "goals_conceded_per_game"]].to_string(index=False))
    spain_rank = ranked[ranked.world_cup_year == 2026].index[0] + 1
    print(f"\n>>> Spain 2026 rank: {spain_rank} of {len(df)}")

    main_scope = df[df.world_cup_year >= MAIN_SCOPE_START_YEAR].copy()

    print("\n" + "=" * 80)
    print(f"2) DEEP COMPARISON — main scope ({MAIN_SCOPE_START_YEAR}-2026, {len(main_scope)} champions)")
    print("=" * 80)
    cols = ["world_cup_year", "champion_team_name", "goals_conceded_per_game",
            "shots_conceded_per_game", "shots_on_target_conceded_per_game",
            "big_chances_conceded_per_game", "xg_against_per_game", "save_pct"]
    print(main_scope.sort_values("shots_conceded_per_game")[cols].to_string(index=False))

    print("\n" + "=" * 80)
    print("3) DEFENSIVE STYLE PROFILE — own defensive actions + possession, main scope")
    print("=" * 80)
    style_cols = ["world_cup_year", "champion_team_name",
                  "avg_tackles", "avg_interceptions", "avg_clearances", "duel_win_pct"]
    print(main_scope.sort_values("world_cup_year")[style_cols].to_string(index=False))

    print("\n" + "=" * 80)
    print("4) xG OVER/UNDER-PERFORMANCE — xG conceded vs actual goals conceded (only where xG exists)")
    print("=" * 80)
    xg_df = main_scope.dropna(subset=["xg_against_per_game"]).copy()
    xg_df["overperformance"] = xg_df["xg_against_per_game"] - xg_df["goals_conceded_per_game"]
    print(xg_df.sort_values("world_cup_year")[
        ["world_cup_year", "champion_team_name", "xg_against_per_game",
         "goals_conceded_per_game", "overperformance"]
    ].to_string(index=False))
    print("\n(positive overperformance = conceded FEWER goals than the chances faced would predict —")
    print(" i.e. keeper/luck did some of the work, not pure structural defense)")


if __name__ == "__main__":
    main()
