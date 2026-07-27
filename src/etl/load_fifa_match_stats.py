"""
One-off load of match_team_stats_fifa: per-match, per-team stats (141 raw
fields) from FIFA's Gracenote-powered "Data Hub" API — no auth needed,
unlike the tournament-aggregate gameday API used for team_tournament_stats_fifa.

Pipeline (all reverse-engineered, no public docs — see CHANGELOG.md):
  1. api.fifa.com/api/v3/calendar/matches?idSeason=285023 -> all 104 matches,
     each with FIFA's own long match id (IdMatch) and each team's IdCountry
     (maps directly to our teams.fifa_code).
  2. api.fifa.com/api/v3/calendar/{IdMatch} -> Properties.IdIFES, a short
     internal id that a different backend (fdh-api) actually uses.
  3. fdh-api.fifa.com/v1/stats/match/{IdIFES}/teams.json -> the real stats,
     keyed by FIFA's numeric team id.

Our own match_id is resolved by matching FIFA's (home team, away team, date)
triple against the `matches` table — reliable since this is the same real
tournament our Kaggle dataset already covers exactly (cross-validated
earlier: scores match exactly for every checked match).
"""
import os
import time

import psycopg2
import requests
from dotenv import load_dotenv

load_dotenv()

SEASON_ID = "285023"
HEADERS = {"User-Agent": "Mozilla/5.0"}


def pg_conn():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST"), port=os.getenv("POSTGRES_PORT"),
        dbname=os.getenv("POSTGRES_DB"), user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )


def main():
    conn = pg_conn()
    cur = conn.cursor()
    cur.execute("SELECT team_id, fifa_code FROM teams")
    team_by_code = {code: tid for tid, code in cur.fetchall()}

    # keyed by the unordered pair of teams — no two teams meet twice in this
    # tournament (verified), so this is safe and avoids fragile date-matching
    # (FIFA's calendar date doesn't always agree with ours by a day, likely
    # a timezone-of-record difference, not worth chasing further)
    cur.execute("SELECT match_id, home_team_id, away_team_id FROM matches")
    match_lookup = {frozenset((r[1], r[2])): r[0] for r in cur.fetchall()}

    cal = requests.get(
        "https://api.fifa.com/api/v3/calendar/matches",
        params={"language": "en", "count": 500, "idSeason": SEASON_ID}, headers=HEADERS,
    ).json()
    fifa_matches = cal["Results"]
    print(f"{len(fifa_matches)} matches in FIFA calendar")

    cur.execute("TRUNCATE match_team_stats_fifa")

    inserted_matches, skipped = 0, []
    for fm in fifa_matches:
        id_match = fm["IdMatch"]
        home_code, away_code = fm["Home"]["IdCountry"], fm["Away"]["IdCountry"]
        home_team_id, away_team_id = team_by_code.get(home_code), team_by_code.get(away_code)

        our_match_id = None
        if home_team_id and away_team_id:
            our_match_id = match_lookup.get(frozenset((home_team_id, away_team_id)))
        if not our_match_id:
            skipped.append((id_match, home_code, away_code))
            continue

        detail = requests.get(f"https://api.fifa.com/api/v3/calendar/{id_match}",
                               params={"language": "en"}, headers=HEADERS).json()
        id_ifes = detail.get("Properties", {}).get("IdIFES")
        if not id_ifes:
            skipped.append((id_match, home_code, away_code, "no IdIFES"))
            continue

        stats = requests.get(f"https://fdh-api.fifa.com/v1/stats/match/{id_ifes}/teams.json",
                              headers=HEADERS).json()

        fifa_team_id_by_code = {home_code: fm["Home"]["IdTeam"], away_code: fm["Away"]["IdTeam"]}
        code_by_fifa_team_id = {v: k for k, v in fifa_team_id_by_code.items()}

        rows = []
        for fifa_team_id, stat_list in stats.items():
            code = code_by_fifa_team_id.get(fifa_team_id)
            our_team_id = team_by_code.get(code)
            if not our_team_id:
                continue
            for stat_name, value, _flag in stat_list:
                if isinstance(value, (int, float)):
                    rows.append((our_match_id, our_team_id, stat_name, value))

        cur.executemany(
            "INSERT INTO match_team_stats_fifa (match_id, team_id, stat_name, stat_value, last_updated) "
            "VALUES (%s, %s, %s, %s, CURRENT_DATE) ON CONFLICT DO NOTHING",
            rows,
        )
        conn.commit()
        inserted_matches += 1
        print(f"  match {our_match_id} ({home_code} vs {away_code}): {len(rows)} stat rows")
        time.sleep(0.3)

    print(f"\nDone. {inserted_matches}/{len(fifa_matches)} matches loaded.")
    if skipped:
        print("Skipped:", skipped)

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
