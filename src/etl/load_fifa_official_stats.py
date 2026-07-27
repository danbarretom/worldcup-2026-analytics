"""
One-off load of team_tournament_stats_fifa from the world_cup_db SQLite
database (a separate, independent personal project — see CHANGELOG.md).
team_id is identical between the two databases for the 2026 teams (verified
directly, zero mismatches across all 48), since world_cup_db's 2026 rows
were originally seeded from this same Postgres `teams` table — so no name
matching is needed, just a plain join on team_id.

Not part of the regular ETL pipeline (src/etl/load_to_postgres.py) — this
enriches with FIFA-official data on top of the base Kaggle dataset, run
once, not meant to be re-run automatically.
"""
import os
import sqlite3

import psycopg2
from dotenv import load_dotenv

load_dotenv()

WCDB = r"C:\Users\danie\Desktop\world_cup_db\world_cup.db"

COLUMNS = [
    "avg_shots", "avg_shots_on_target", "avg_shots_off_target", "avg_shots_inside_box",
    "avg_shots_outside_box", "avg_headed_shots", "avg_xg", "avg_assists",
    "avg_big_chances_created", "avg_big_chances_missed", "avg_possession_pct",
    "avg_corners", "penalties_scored", "total_own_goals",
    "avg_passes", "pass_accuracy_pct", "avg_crosses", "crossing_accuracy_pct",
    "avg_long_balls", "avg_linebreaks_attempted", "linebreak_accuracy_pct",
    "avg_switches_of_play", "switches_of_play_accuracy_pct",
    "avg_tackles", "avg_interceptions", "avg_clearances", "duel_win_pct",
    "avg_fouls_committed", "avg_offsides", "avg_forced_turnovers",
    "avg_ball_recovery_time", "avg_defensive_pressures_applied",
    "avg_direct_defensive_pressures_applied",
    "total_yellow_cards", "total_red_cards", "total_indirect_red_cards",
    "avg_saves",
    "avg_distance_covered_km", "avg_speed_kmh", "avg_sprints",
    "avg_offers_to_receive_total", "avg_offers_to_receive_in_behind",
    "avg_offers_to_receive_in_between", "avg_offers_to_receive_in_front",
    "avg_offers_to_receive_inside", "avg_offers_to_receive_outside",
    "avg_receptions_in_behind", "avg_receptions_between_midfield_and_defensive_line",
    "avg_receptions_under_pressure",
]


def main():
    wc = sqlite3.connect(WCDB)
    wc.row_factory = sqlite3.Row
    rows = wc.execute(
        f"SELECT team_id, {', '.join(COLUMNS)} FROM team_tournament_stats WHERE edition_id = 1"
    ).fetchall()

    pg = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST"), port=os.getenv("POSTGRES_PORT"),
        dbname=os.getenv("POSTGRES_DB"), user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )
    cur = pg.cursor()
    cur.execute("TRUNCATE team_tournament_stats_fifa")

    placeholders = ", ".join(["%s"] * (len(COLUMNS) + 1))
    col_list = ", ".join(["team_id"] + COLUMNS)
    for r in rows:
        values = [r["team_id"]] + [r[c] for c in COLUMNS]
        cur.execute(
            f"INSERT INTO team_tournament_stats_fifa ({col_list}, last_updated) "
            f"VALUES ({placeholders}, CURRENT_DATE)",
            values,
        )

    pg.commit()
    print(f"Loaded {len(rows)} teams into team_tournament_stats_fifa.")
    cur.close()
    pg.close()
    wc.close()


if __name__ == "__main__":
    main()
