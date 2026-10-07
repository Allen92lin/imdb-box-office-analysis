# When Is a Film's Box Office Decided?

A regression analysis of 250 IMDb Top 250 films in R, asking a question that
most box-office models skip: **at what point does a film's commercial outcome
stop being open?**

Budget and genre are fixed before shooting. Theatre count is a release
decision. Audience ratings only exist afterward. Grouping predictors by when
each becomes knowable turns a vague question — "what drives box office?" —
into one a studio could act on.

---

## Findings

| | |
|---|---|
| Pre-production characteristics alone | **64%** of variation in inflation-adjusted revenue |
| Adding theatre distribution | **68%** |
| Budget elasticity | **0.67** (95% CI 0.45–0.90) |
| Revenue vs. profitability | 46% vs 22% explained |

**A 10% larger budget returns only about 6.7% more revenue.** Returns to
production spending diminish, and the result holds under all four
heteroskedasticity-robust variance estimators and in the post-1980 subsample
separately.

**Only two predictors survive scrutiny:** budget and theatre count. Runtime,
certificate and genre carry no detectable information once those two are in
the model — genre as a block gives F = 0.72 (p = 0.65).

Full write-up, including robustness checks and limitations: **[REPORT.md](REPORT.md)**

---

## Reproducing

```r
source("IMDb2.R")
```

Requires `dplyr`, `purrr`, `ggplot2`, `forcats`, `readxl`, `car`, `sandwich`,
`lmtest`. The script runs top to bottom and is safe to re-run; it fetches the
CPI series on first run and caches it locally.

Update the two file paths at the top (`IMDB Top 250 Movies.csv`,
`screens.xlsx`) if your working directory differs.

---

## Data

| Source | Contribution |
|---|---|
| [Kaggle: IMDB Top 250 Movies Dataset](https://www.kaggle.com/datasets/rajugc/imdb-top-250-movies-dataset) | Title, year, rating, rank, genre, certificate, runtime, budget, box office |
| [Box Office Mojo](https://www.boxofficemojo.com) yearly charts | Widest-release theatre counts, read off by hand for 135 post-1980 films |
| [FRED series CPIAUCNS](https://fred.stlouisfed.org/series/CPIAUCNS) | Annual CPI 1913–2025, fetched by the script |

`screens.xlsx` is the hand-collected theatre data. There is no free API for
theatre counts, so these were looked up year by year.

---

## Method notes

Three decisions that matter more than the modelling:

**Every compared model is fit on the same rows.** `lm()` silently drops rows
with missing values, so models using budget would otherwise be fit on
different films from models that don't — and their R² compared anyway.

**Genre is parsed, not factored.** The raw field is multi-label
(`"Crime,Drama"`); treating it as a category produces 104 levels for 250
films, enough parameters to fit almost anything.

**Revenue is deflated and logged.** The sample spans the 1920s to 2021, so
nominal dollars aren't comparable, and the distribution is heavily
right-skewed. On the log scale coefficients read as elasticities.

---

## Limitations

The sample is selected on critical acclaim, so ratings vary only from about
8.0 to 9.3 — range restriction that attenuates any correlation involving
rating. Theatre counts are widest release, not opening week, so distributors
expand in response to performance: the coefficient is association, not
causation. And no test set was held out, so the R² is explanatory rather than
predictive.

Full list in [REPORT.md](REPORT.md).

---

## Files

```
IMDb2.R                     analysis, top to bottom
REPORT.md                   full write-up
IMDB Top 250 Movies.csv     source data
screens.xlsx                hand-collected theatre counts
cpi_annual.csv              cached CPI series
```
