# Module A: is Spain's 2026 defensive campaign the most statistically
# efficient title-winning campaign in World Cup history?
#
# R port of src/analysis/module_a.py, extended with the advanced statistical
# layer worked out interactively with Daniel: a standardized-bisector analysis
# for the shots-vs-goals scatter (section 2) instead of a raw xG-vs-goals
# "overperformance" table (dropped — too noisy over a 7-8 game sample, and
# unusable for Spain specifically since FIFA doesn't expose shot-level xG for
# 2026), and a PCA + nearest-neighbor gap analysis for the 2026-only pressing
# pillar (section 5).
#
# Required packages: DBI, RPostgres, dplyr, ggplot2, dotenv. Install with:
#   install.packages(c("DBI", "RPostgres", "dplyr", "ggplot2", "dotenv"))
# Run from the repo root: Rscript analysis/r/module_a_stats.R

library(DBI)
library(RPostgres)
library(dplyr)
library(ggplot2)
library(dotenv)

dotenv::load_dot_env()

MAIN_SCOPE_START_YEAR <- 1994
OUTPUT_DIR <- "analysis/r/output"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

accent <- "#2a78d6"
gray_mark <- "#c9c7bf"
theme_module_a <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(), plot.title.position = "plot")

con <- dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("POSTGRES_HOST"),
  port = as.integer(Sys.getenv("POSTGRES_PORT")),
  dbname = Sys.getenv("POSTGRES_DB"),
  user = Sys.getenv("POSTGRES_USER"),
  password = Sys.getenv("POSTGRES_PASSWORD")
)

hr <- function() cat(strrep("=", 80), "\n")

# ---------------------------------------------------------------------------
# 1) Full historical ranking — goals conceded per game (all 18, 1958-2026),
#    plus the games-played and xGA framing that leads the module
# ---------------------------------------------------------------------------
champions <- dbGetQuery(con, "SELECT * FROM historical_champions ORDER BY world_cup_year")

hr()
cat("1) FULL HISTORICAL RANKING — goals conceded per game (all 18, 1958-2026)\n")
hr()
ranked <- champions %>% arrange(goals_conceded_per_game)
print(ranked %>% select(world_cup_year, champion_team_name, games_played,
                         goals_conceded, goals_conceded_per_game))

spain <- champions %>% filter(world_cup_year == 2026)
xg_df_all <- champions %>% filter(!is.na(xg_against_per_game))
cat(sprintf(
  "\n>>> Spain 2026: %.2f goals/game in %d games (the longest path of any champion in the sample)\n",
  spain$goals_conceded_per_game, spain$games_played
))
cat(sprintf(
  ">>> Among the %d tournaments with real xG data (2014-2026), Spain also has the lowest xGA: %.2f/game\n",
  nrow(xg_df_all), spain$xg_against_per_game
))

main_scope <- champions %>% filter(world_cup_year >= MAIN_SCOPE_START_YEAR)

# ---------------------------------------------------------------------------
# 2) Process vs. result — shots conceded x goals conceded, main scope
#    (1994-2026). A raw regression line is nearly flat here (r ~ -0.07 between
#    shots and goals conceded across these 9 elite campaigns) so it adds
#    nothing over a mean line. The standardized bisector (z-score both axes,
#    slope-1 diagonal) is the meaningful reference: distance from it measures
#    how far a campaign's *result* deviated from what its *shot exposure*
#    alone would proportionally predict.
# ---------------------------------------------------------------------------
cat("\n"); hr()
cat(sprintf("2) PROCESS VS. RESULT — main scope (%d-2026, %d champions)\n",
            MAIN_SCOPE_START_YEAR, nrow(main_scope)))
hr()

ms <- main_scope %>% mutate(label = paste(world_cup_year, champion_team_name))
x_shots <- ms$shots_conceded_per_game
y_goals <- ms$goals_conceded_per_game

x_mean <- mean(x_shots); x_sd <- sd(x_shots)
y_mean <- mean(y_goals); y_sd <- sd(y_goals)
bisector_slope <- y_sd / x_sd
bisector_intercept <- y_mean - bisector_slope * x_mean

xz <- (x_shots - x_mean) / x_sd
yz <- (y_goals - y_mean) / y_sd
ms$bisector_distance <- (yz - xz) / sqrt(2)

print(ms %>% arrange(bisector_distance) %>%
  select(world_cup_year, champion_team_name, shots_conceded_per_game,
         goals_conceded_per_game, bisector_distance))
cat("\n(negative = took more shots than its goal count would suggest, i.e. overperformed the\n")
cat(" proportional expectation; positive = the opposite. Spain sits near zero — its result IS\n")
cat(" what its shot exposure predicted, at the most dominant extreme of the sample.)\n")

# ---------------------------------------------------------------------------
# 3) Defensive profile: ball retention first, own defensive actions second.
#    Spain leads possession AND pass accuracy in both title-winning campaigns,
#    while having the LOWEST total defensive-action volume of the 9 — the
#    dominance is preventive (keep the ball, deny the game), not reactive.
#    A duel_win_pct-vs-bisector_distance correlation (r ~ -0.87) was explored
#    and DROPPED: it collapses to r ~ -0.42 once the two low-duel outliers
#    (Argentina 2022, France 2018) are excluded, and Italy — the sample's most
#    extreme overperformer — has an unremarkable duel-win rate (tied for
#    highest, not uniquely so), so it doesn't explain Italy's case either.
#    With n=9 (and only champions, a highly selected group), this isn't a
#    real relationship — see CLAUDE.md for the full discussion with Daniel.
# ---------------------------------------------------------------------------
cat("\n"); hr()
cat("3) DEFENSIVE PROFILE — possession/pass accuracy + own defensive actions, main scope\n")
hr()
style_df <- main_scope %>% arrange(world_cup_year) %>%
  mutate(total_actions = avg_tackles + avg_interceptions + avg_clearances)
print(style_df %>%
  select(world_cup_year, champion_team_name, avg_possession_pct, pass_accuracy_pct,
         total_actions, duel_win_pct))

spain_style <- style_df %>% filter(world_cup_year == 2026)
cat(sprintf("\n>>> Spain 2026: highest possession (%.1f%%) AND pass accuracy (%.1f%%) in the sample,\n",
            spain_style$avg_possession_pct, spain_style$pass_accuracy_pct * 100))
cat(sprintf(">>> yet the LOWEST total defensive-action volume (%.1f/game) of the 9 champions.\n",
            spain_style$total_actions))

# ---------------------------------------------------------------------------
# 4) 2026-only pressing pillar — recovery time + forced-turnover rate,
#    benchmarked against the 32 teams that reached the knockout stage
# ---------------------------------------------------------------------------
pressing <- dbGetQuery(con, "
  SELECT
    t.team_name,
    AVG(CASE WHEN mtsf.stat_name = 'BallRecoveryTime' THEN mtsf.stat_value END) AS recovery_time,
    AVG(CASE WHEN mtsf.stat_name = 'ForcedTurnovers' THEN mtsf.stat_value END) AS forced_turnovers,
    AVG(CASE WHEN mtsf.stat_name = 'Possession' THEN mtsf.stat_value END) AS possession,
    AVG(CASE WHEN mtsf.stat_name = 'PhaseAggregateHighPress' THEN mtsf.stat_value END) AS high_press_pct,
    AVG(CASE WHEN mtsf.stat_name = 'PhaseAggregateLowBlock' THEN mtsf.stat_value END) AS low_block_pct
  FROM match_team_stats_fifa mtsf
  JOIN teams t ON t.team_id = mtsf.team_id
  WHERE mtsf.team_id IN (
    SELECT home_team_id FROM matches m JOIN tournament_stages ts ON ts.stage_id = m.stage_id WHERE ts.is_knockout
    UNION
    SELECT away_team_id FROM matches m JOIN tournament_stages ts ON ts.stage_id = m.stage_id WHERE ts.is_knockout
  )
  GROUP BY t.team_name
") %>%
  mutate(
    minutes_without_ball = 90 * (1 - possession),
    forced_turnovers_rate = forced_turnovers / minutes_without_ball
  )

dbDisconnect(con)

cat("\n"); hr()
cat("4) PRESSING PILLAR (2026-only, 32 knockout-stage teams) — recovery time + forced-turnover rate\n")
hr()
print(pressing %>% arrange(recovery_time) %>%
  select(team_name, recovery_time, forced_turnovers, minutes_without_ball, forced_turnovers_rate))

# ---------------------------------------------------------------------------
# 5) Is Spain's high-press/low-block profile a real outlier?
#     high_press_pct and low_block_pct are strongly correlated across the 32
#     teams, so PC1 IS essentially the trend line itself. Sorting teams along
#     PC1 and measuring consecutive gaps operationalizes "how much further is
#     Spain from its nearest neighbor than any other pair of neighbors."
# ---------------------------------------------------------------------------
cat("\n"); hr()
cat("5) IS SPAIN'S PRESSING PROFILE A REAL OUTLIER? — PCA + nearest-neighbor gap analysis\n")
hr()

phase <- pressing %>% select(team_name, high_press_pct, low_block_pct) %>% na.omit()

r_corr <- cor(phase$high_press_pct, phase$low_block_pct)
cat(sprintf("Pearson r (high_press_pct, low_block_pct): %.3f\n", r_corr))

pca <- prcomp(phase %>% select(high_press_pct, low_block_pct), center = TRUE, scale. = FALSE)
scores <- pca$x[, 1]
spain_idx <- which(phase$team_name == "Spain")
if (scores[spain_idx] < 0) scores <- -scores  # orient so higher score = more high-press (Spain positive)

ordered <- phase %>% mutate(pc1 = scores) %>% arrange(desc(pc1))
gaps <- -diff(ordered$pc1)  # consecutive gaps in descending order; gaps[1] = Spain -> next
spain_gap <- gaps[1]
other_gaps <- gaps[-1]
gap_z <- (spain_gap - mean(other_gaps)) / sd(other_gaps)

cat(sprintf("Spain -> nearest neighbor (%s) gap on PC1: %.2f\n", ordered$team_name[2], spain_gap))
cat(sprintf("Mean of all other consecutive gaps: %.2f (sd = %.2f)\n", mean(other_gaps), sd(other_gaps)))
cat(sprintf("Spain's gap is %.1f standard deviations above the mean of all other gaps (z = %.2f)\n",
            gap_z, gap_z))

rest <- phase %>% filter(team_name != "Spain") %>% select(high_press_pct, low_block_pct)
spain_vec <- phase %>% filter(team_name == "Spain") %>%
  select(high_press_pct, low_block_pct) %>% as.matrix()
maha_spain <- sqrt(mahalanobis(spain_vec, center = colMeans(rest), cov = cov(rest)))
cat(sprintf("Mahalanobis distance, Spain vs rest-of-31 distribution: %.2f\n", maha_spain))

# ---------------------------------------------------------------------------
# 6) ggplot2 figures — meant as Power BI R-script-visual inputs, not
#    standalone deliverables. Fixed, round-number axis limits (via
#    coord_cartesian, not scale limits, so no data is dropped) instead of
#    ggplot2's default tight-to-data expansion — the tight default visually
#    compresses these scatter plots and clips edge labels (e.g. "Paraguay").
# ---------------------------------------------------------------------------
x_origin <- -bisector_intercept / bisector_slope

p_shots_scatter <- ggplot(ms, aes(shots_conceded_per_game, goals_conceded_per_game)) +
  geom_abline(slope = bisector_slope, intercept = bisector_intercept,
              linetype = "dashed", color = "grey55") +
  geom_point(aes(color = world_cup_year == 2026, size = world_cup_year == 2026)) +
  geom_text(aes(label = label, color = world_cup_year == 2026),
            vjust = -1.3, size = 3.2, show.legend = FALSE, fontface = "bold") +
  scale_color_manual(values = c("TRUE" = accent, "FALSE" = gray_mark), guide = "none") +
  scale_size_manual(values = c("TRUE" = 4.5, "FALSE" = 3), guide = "none") +
  scale_x_continuous(breaks = c(round(x_origin, 2), 8, 12, 16)) +
  scale_y_continuous(breaks = c(0, 0.4, 0.8, 1.2)) +
  coord_cartesian(xlim = c(x_origin, 17), ylim = c(0, 1.3), clip = "off") +
  labs(title = "Processo vs. resultado — finalizações sofridas x gols sofridos",
       x = "finalizações sofridas por jogo", y = "gols sofridos / jogo") +
  theme_module_a

ggsave(file.path(OUTPUT_DIR, "module_a_shots_scatter.png"), p_shots_scatter,
       width = 8, height = 6, dpi = 150)

p_style_scatter <- ggplot(style_df, aes(avg_possession_pct, total_actions)) +
  geom_vline(xintercept = mean(style_df$avg_possession_pct), linetype = "dashed", color = "grey60") +
  geom_hline(yintercept = mean(style_df$total_actions), linetype = "dashed", color = "grey60") +
  geom_point(aes(color = champion_team_name == "Spain", size = champion_team_name == "Spain")) +
  geom_text(aes(label = paste(world_cup_year, champion_team_name), color = champion_team_name == "Spain"),
            vjust = -1.3, size = 3.2, show.legend = FALSE, fontface = "bold") +
  scale_color_manual(values = c("TRUE" = accent, "FALSE" = gray_mark), guide = "none") +
  scale_size_manual(values = c("TRUE" = 4.5, "FALSE" = 3), guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0.08, 0.08))) +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.16))) +
  coord_cartesian(clip = "off") +
  labs(title = "Posse x volume de ação defensiva", x = "posse média (%)",
       y = "ações defensivas / jogo (desarme + intercept. + corte)") +
  theme_module_a

ggsave(file.path(OUTPUT_DIR, "module_a_possession_actions.png"), p_style_scatter,
       width = 8, height = 6, dpi = 150)

p_recovery <- pressing %>%
  mutate(is_spain = team_name == "Spain") %>%
  ggplot(aes(x = reorder(team_name, -recovery_time), y = recovery_time, fill = is_spain)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.1fs", recovery_time)), hjust = -0.15, size = 3, color = "grey30") +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  scale_fill_manual(values = c("TRUE" = accent, "FALSE" = gray_mark), guide = "none") +
  labs(title = "Recuperação de bola — 32 times do mata-mata", x = NULL, y = "tempo de recuperação (s)") +
  theme_module_a + theme(axis.text.y = element_text(size = 8))

ggsave(file.path(OUTPUT_DIR, "module_a_recovery.png"), p_recovery, width = 8, height = 7.5, dpi = 150)

p_rate <- pressing %>%
  mutate(is_spain = team_name == "Spain") %>%
  ggplot(aes(x = reorder(team_name, forced_turnovers_rate), y = forced_turnovers_rate, fill = is_spain)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.2f", forced_turnovers_rate)), hjust = -0.15, size = 3, color = "grey30") +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  scale_fill_manual(values = c("TRUE" = accent, "FALSE" = gray_mark), guide = "none") +
  labs(title = "Recuperações forçadas por minuto sem a bola", x = NULL,
       y = "recuperações forçadas / min. sem a bola") +
  theme_module_a + theme(axis.text.y = element_text(size = 8))

ggsave(file.path(OUTPUT_DIR, "module_a_rate.png"), p_rate, width = 8, height = 7.5, dpi = 150)

p_quadrant <- ggplot(phase, aes(high_press_pct, low_block_pct)) +
  geom_vline(xintercept = mean(phase$high_press_pct), linetype = "dashed", color = "grey60") +
  geom_hline(yintercept = mean(phase$low_block_pct), linetype = "dashed", color = "grey60") +
  geom_point(aes(color = team_name == "Spain", size = team_name == "Spain")) +
  geom_text(data = phase %>% filter(team_name == "Spain"),
            aes(label = team_name), vjust = -1.4, color = accent, fontface = "bold") +
  scale_color_manual(values = c("TRUE" = accent, "FALSE" = gray_mark), guide = "none") +
  scale_size_manual(values = c("TRUE" = 4.5, "FALSE" = 3), guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0.05, 0.08))) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.08))) +
  coord_cartesian(xlim = c(0, 10), ylim = c(0, 45), clip = "off") +
  labs(title = "Estilo defensivo — pressão alta x bloco baixo",
       subtitle = "32 times do mata-mata, Copa 2026",
       x = "% do tempo em pressão alta", y = "% do tempo em bloco baixo") +
  theme_module_a

ggsave(file.path(OUTPUT_DIR, "module_a_phase_quadrant.png"), p_quadrant,
       width = 8, height = 6.5, dpi = 150)

cat(sprintf("\nFigures saved to %s/\n", OUTPUT_DIR))
