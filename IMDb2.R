# IMDb Top 250 -- Box Office Analysis
# Q1  When is box office decided? Production, distribution, or reception?
# Q2  What predicts profitability (ROI), as opposed to gross revenue?

library(dplyr)
library(purrr)
library(ggplot2)
library(forcats)
library(readxl)
library(car)
library(sandwich)
library(lmtest)

set.seed(42)

# 1. IMPORT

IMDb250 <- read.csv("~/Downloads/Work/Project Codes/IMDB Top 250 Movies.csv",
                    stringsAsFactors = FALSE)

df <- IMDb250 %>%
  select(
    title        = name,
    release_year = year,
    director     = directors,
    rank, rating, genre, certificate, run_time, budget, box_office
  )

str(df)


# 2. CLEANING

# ---- Runtime: "2h 31m" -> 151 ----
parse_runtime <- function(x){
  x <- trimws(as.character(x))
  hours  <- suppressWarnings(as.numeric(sub("^(\\d+)h.*", "\\1", x)))
  minute <- suppressWarnings(as.numeric(sub(".h\\s*(\\d+)m.*", "\\1", x)))
  hours[is.na(hours)]   <- 0
  minute[is.na(minute)] <- 0
  plain <- suppressWarnings(as.numeric(gsub("[^0-9]", "", x)))
  ifelse(grepl("h", x), hours * 60 + minute, plain)
}

df$run_time <- parse_runtime(df$run_time)
summary(df$run_time)


# ---- Money: text to numbers ----
df$budget_num     <- as.numeric(df$budget)
df$box_office_num <- as.numeric(df$box_office)

cat("Budget NAs:", sum(is.na(df$budget_num)),
    " Box office NAs:", sum(is.na(df$box_office_num)), "\n")


# ---- Flag implausible values ----
# No film has ever had a budget over ~$400M in nominal USD, so anything
# above 5e8 is almost certainly a non-USD figure (yen / rupees) that the
# source stripped the currency symbol from.
bad_budget <- !is.na(df$budget_num) & df$budget_num > 5e8

# A total worldwide gross under $100k is not a real figure for a Top 250
# film; these are partial or re-release numbers, concentrated pre-1970.
bad_box <- !is.na(df$box_office_num) & df$box_office_num < 1e5

cat("Budget flagged as non-USD:", sum(bad_budget), "\n")
cat("Box office implausibly small:", sum(bad_box), "\n")

df[bad_budget, c("title", "release_year", "budget_num")]
df[bad_box,    c("title", "release_year", "box_office_num")]

# Set to NA -- we do not know the true USD figure
df$budget_num[bad_budget]  <- NA
df$box_office_num[bad_box] <- NA


# ---- Genre: multi-label string -> primary genre, then lump ----
# as.factor() on the raw field would make each unique combination its own
# level: 104 levels for 250 films. That is what saturated the original
# model and drove its AIC to -Inf.
df$genre_main <- sub(",.*", "", df$genre)
cat("Genre levels before:", length(unique(df$genre)), "\n")
cat("Genre levels after :", length(unique(df$genre_main)), "\n")

GENRE_MIN_N  <- 8
genre_counts <- table(df$genre_main)
rare_genres  <- names(genre_counts[genre_counts < GENRE_MIN_N])
cat("Rare genres lumped:", paste(rare_genres, collapse = ", "), "\n")

df$genre_main[df$genre_main %in% rare_genres] <- "Other"
df$genre_main <- factor(df$genre_main)

cat("Final genre levels:", nlevels(df$genre_main), "\n")
sort(table(df$genre_main), decreasing = TRUE)


# ---- Certificate: collapse 15 categories into 5 ----
# Several levels have a single film. Old pre-MPAA labels (Approved, Passed)
# and stray TV ratings get folded together.
df$cert_group <- case_when(
  df$certificate %in% c("G")                      ~ "G",
  df$certificate %in% c("PG", "GP", "TV-PG")      ~ "PG",
  df$certificate %in% c("PG-13", "13+")           ~ "PG-13",
  df$certificate %in% c("R", "18+", "X", "TV-MA") ~ "R",
  TRUE                                            ~ "Other/Unrated"
)
df$cert_group <- factor(df$cert_group,
                        levels = c("G", "PG", "PG-13", "R", "Other/Unrated"))
table(df$cert_group)


# 3. INFLATION ADJUSTMENT AND OUTCOME VARIABLES

# ---- CPI: download once, reuse afterwards ----
if (!file.exists("cpi_annual.csv")) {
  cpi_url <- paste0("https://fred.stlouisfed.org/graph/fredgraph.csv",
                    "?id=CPIAUCNS&fq=Annual&fam=avg")
  cpi_raw <- read.csv(url(cpi_url), stringsAsFactors = FALSE)
  names(cpi_raw) <- c("date", "cpi")
  cpi_dl <- data.frame(year = as.integer(substr(cpi_raw$date, 1, 4)),
                       cpi  = as.numeric(cpi_raw$cpi))
  cpi_dl <- cpi_dl[!is.na(cpi_dl$cpi), ]
  write.csv(cpi_dl, "cpi_annual.csv", row.names = FALSE)
  cat("Downloaded CPI:", nrow(cpi_dl), "years\n")
}
cpi <- read.csv("cpi_annual.csv", stringsAsFactors = FALSE)


# ---- Deflate to constant dollars ----
# Drop any cpi column left by a previous run: merging twice would otherwise
# produce cpi.x / cpi.y and silently break the deflation below.
df$cpi <- NULL
df <- merge(df, cpi, by.x = "release_year", by.y = "year", all.x = TRUE)

base_cpi <- cpi$cpi[cpi$year == max(cpi$year)]
df$budget_real     <- df$budget_num     * (base_cpi / df$cpi)
df$box_office_real <- df$box_office_num * (base_cpi / df$cpi)
cat("Deflated to", max(cpi$year), "dollars\n")


# ---- Outcomes ----
# Revenue is heavily right-skewed, so model it on the log scale. In a
# log-log model the coefficients read as elasticities.
df$log_box    <- log(df$box_office_real)
df$log_budget <- log(df$budget_real)

# log ROI = log(revenue) - log(budget): who MADE money, not who sold most.
df$log_roi <- df$log_box - df$log_budget

summary(df$log_box)
hist(df$box_office_real, breaks = 30, main = "Raw (skewed)")
hist(df$log_box,         breaks = 30, main = "Log (symmetric)")


# 4. THEATRE COUNTS
# Widest-release theatre counts, read off Box Office Mojo's yearly charts
# by hand for post-1980 films. BOM indexes by US release year, which
# differs from the Kaggle release year for several foreign titles.

screens <- read_excel("~/Downloads/Work/Project Codes/screens.xlsx")

df$theaters <- NULL   # same re-run guard as the CPI merge above
df <- merge(df, screens[, c("title", "theaters")], by = "title", all.x = TRUE)
df$theaters     <- as.numeric(df$theaters)
df$log_theaters <- log(df$theaters)

cat("Theatre counts filled:", sum(!is.na(df$theaters)), "\n")

# BOM's pre-mid-1980s figures are often the limited opening rather than the
# true widest release. A gross per theatre above $2m is not credible.
gpt <- df$box_office_num / df$theaters
odd <- !is.na(gpt) & gpt > 2e6
cat("Implausible gross-per-theatre:", sum(odd), "\n")
print(df[odd, c("title", "release_year", "theaters", "box_office_num")])


# 5. ANALYSIS SAMPLES
# Models that are COMPARED to each other must be fit on identical rows,
# or their R-squared values are not comparable. lm() silently drops NA
# rows, which is what invalidated the original 220-model comparison.
#
#   md_all  n ~ 187  everything except theatre counts
#   md_th   n ~ 135  adds theatre counts, so post-1980 only

base_vars <- c("log_box", "log_roi", "log_budget", "genre_main",
               "run_time", "cert_group", "release_year", "rating", "rank")

md_all <- df[complete.cases(df[, base_vars]), ]
md_all$genre_main <- droplevels(md_all$genre_main)
md_all$cert_group <- droplevels(md_all$cert_group)

md_th <- md_all[!is.na(md_all$log_theaters), ]
md_th$genre_main <- droplevels(md_th$genre_main)
md_th$cert_group <- droplevels(md_th$cert_group)

cat("md_all n =", nrow(md_all), "   md_th n =", nrow(md_th), "\n")


# 6. Q1 -- WHEN IS BOX OFFICE DECIDED?
# Variables grouped by WHEN they become known:
#   tier1   pre-production  -- known before a film is greenlit
#   tier1b  + distribution  -- adds theatre count, a release decision
#   tier2   + reception     -- adds rating, an OUTCOME of release
tier1  <- c("log_budget", "genre_main", "run_time", "cert_group", "release_year")
tier1b <- c(tier1, "log_theaters")
tier2  <- c(tier1b, "rating", "rank")

# ---- 6.1 Full sample: does reception add anything? (no theatre data) ----
a1 <- lm(reformulate(tier1,                      "log_box"), data = md_all)
a2 <- lm(reformulate(c(tier1, "rating", "rank"), "log_box"), data = md_all)

cat("\n=== Full sample (n =", nrow(md_all), ") ===\n")
cat("Pre-production      :", round(summary(a1)$adj.r.squared, 3), "\n")
cat("+ Audience reception:", round(summary(a2)$adj.r.squared, 3), "\n")
print(anova(a1, a2))

# ---- 6.2 Post-1980 sample: the full three-tier comparison ----
m1  <- lm(reformulate(tier1,  "log_box"), data = md_th)
m1b <- lm(reformulate(tier1b, "log_box"), data = md_th)
m2  <- lm(reformulate(tier2,  "log_box"), data = md_th)

cat("\n=== Post-1980 sample (n =", nrow(md_th), ") ===\n")
cat("Pre-production      :", round(summary(m1)$adj.r.squared,  3), "\n")
cat("+ Distribution      :", round(summary(m1b)$adj.r.squared, 3), "\n")
cat("+ Audience reception:", round(summary(m2)$adj.r.squared,  3), "\n\n")
cat("Distribution adds:",
    round(summary(m1b)$adj.r.squared - summary(m1)$adj.r.squared, 3), "\n")
cat("Reception adds   :",
    round(summary(m2)$adj.r.squared - summary(m1b)$adj.r.squared, 3), "\n\n")
print(anova(m1, m1b, m2))

# Guard: factors eat degrees of freedom. Above ~0.2 this gets fragile.
ratio <- (length(coef(m2)) - 1) / nrow(md_th)
if (ratio > 0.2) {
  cat("\nWARNING:", length(coef(m2)) - 1, "coefficients on", nrow(md_th),
      "rows (ratio", round(ratio, 2), ")\n")
}


# 7. Q2 -- WHAT PREDICTS PROFITABILITY?
# Box office rewards big films for being big. ROI asks who actually made
# money relative to what they spent.
m_roi <- lm(reformulate(tier1, "log_roi"), data = md_all)

cat("\n=== Profitability (n =", nrow(md_all), ") ===\n")
cat("Revenue model adj R2:", round(summary(a1)$adj.r.squared,    3), "\n")
cat("ROI model     adj R2:", round(summary(m_roi)$adj.r.squared, 3), "\n")

# Budget elasticity: below 1 means diminishing returns -- each extra dollar
# of budget brings back less than a dollar of revenue at the margin.
b  <- coef(a1)["log_budget"]
ci <- confint(a1)["log_budget", ]
cat("Budget elasticity:", round(b, 3),
    " 95% CI [", round(ci[1], 3), ",", round(ci[2], 3), "]\n")
cat(if (ci[2] < 1) "  -> diminishing returns to budget\n"
    else if (ci[1] > 1) "  -> increasing returns to budget\n"
    else "  -> cannot distinguish from constant returns\n")

print(summary(m_roi))


# 8. DIAGNOSTICS
# m1b is the reported model: everything knowable at release.

print(summary(m1b))
print(vif(m1b))

par(mfrow = c(2, 2)); plot(m1b); par(mfrow = c(1, 1))


# 9. ROBUSTNESS CHECKS

# ---- 9.1 Does genre contribute as a block? ----
# Individual genre coefficients are all non-significant, but that does not
# settle it: genre is a set of dummies and needs a joint test.
m_nogenre <- lm(reformulate(setdiff(tier1b, "genre_main"), "log_box"),
                data = md_th)
print(anova(m_nogenre, m1b))

cat("With genre   :", round(summary(m1b)$adj.r.squared,       3), "\n")
cat("Without genre:", round(summary(m_nogenre)$adj.r.squared, 3), "\n")
# Genre is kept in the reported specification because it was chosen on
# theoretical grounds before fitting. Dropping it now because a test came
# back null would be the post-hoc selection this analysis sets out to avoid.


# ---- 9.2 Is cert_group just proxying for era? ----
# The Other/Unrated coefficient is large and significant, but that group is
# almost entirely pre-1968, when the MPAA system began -- and pre-1968
# revenue records are systematically incomplete.
table(md_all$cert_group, md_all$release_year >= 1968)


# ---- 9.3 Does the budget result survive on modern films only? ----
m_roi_modern <- lm(reformulate(tier1, "log_roi"),
                   data = md_all[md_all$release_year >= 1980, ])
print(summary(m_roi_modern)$coefficients["log_budget", ])
cat("n =", sum(md_all$release_year >= 1980), "\n")


# ---- 9.4 Heteroskedasticity-robust standard errors ----
# Scale-Location shows mild non-constant variance, so classical SEs
# understate uncertainty. HC3 is the standard small-sample correction.
print(coeftest(m1b, vcov = vcovHC(m1b, type = "HC3")))

# HC3 is the recommended default for n < 250 but also the most conservative;
# HC0-HC2 apply weaker leverage corrections. If the theatre result only
# failed under HC3, that would be worth knowing.
for (v in c("HC0", "HC1", "HC2", "HC3")) {
  ct <- coeftest(m1b, vcov = vcovHC(m1b, type = v))
  cat(sprintf("%-4s  log_theaters: est %.3f  SE %.3f  p %.4f\n",
              v, ct["log_theaters", 1], ct["log_theaters", 2],
              ct["log_theaters", 4]))
}

# Robust SE for the elasticity actually quoted in the writeup (a1, n = 187)
print(coeftest(a1, vcov = vcovHC(a1, type = "HC3"))["log_budget", ])


# 10. SESSION INFO

sessionInfo()
