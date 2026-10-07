# When Is a Film's Box Office Decided?

A re-analysis of the IMDb Top 250, rebuilding an earlier university group
project after diagnosing a specification failure in the original model.

---

## Summary

Grouping predictors by *when the information becomes available* shows that
**roughly 64% of the variation in real box office revenue is already explained
by characteristics fixed before production begins**. Release width adds a
further 4 points — about a tenth of what production characteristics leave
unexplained — and audience reception adds a similar amount again.

The most robust finding is not about revenue at all: **the budget elasticity
of revenue is 0.67 (95% CI 0.45–0.90), significantly below 1**. A 10% larger
budget returns roughly 6.7% more revenue, so return on investment falls as
budgets grow. This survives heteroskedasticity-robust standard errors and
holds separately among post-1980 releases.

Only two predictors survive scrutiny: budget and theatre count. Runtime,
certificate and genre carry no detectable information once those two are in
the model.

---

## Data

| Source | Contribution |
|---|---|
| Kaggle *IMDB Top 250 Movies Dataset* (rajugc) | Title, year, rating, rank, genre, certificate, runtime, budget, box office |
| Box Office Mojo yearly charts | Widest-release theatre counts, collected by hand for 135 films |
| FRED series CPIAUCNS | Annual CPI, 1913–2025, for constant-dollar conversion |

### Cleaning decisions

**Runtime** arrived as `"2h 22m"` strings. Converting with `as.numeric()`
directly would have silently turned every value into `NA`.

**Currency.** Two budgets exceeded $500m — *Princess Mononoke* (¥2.4bn) and
*3 Idiots* (₹550m). The source had stripped the currency symbols, so these
read as US dollars. Both were set to missing rather than converted, since
period-accurate exchange rates were not available.

**Implausible revenue.** Nineteen films reported worldwide grosses below
$100,000, all released before 1970 — almost certainly partial or re-release
figures rather than lifetime totals. These were set to missing.

**Genre** was the field that broke the original model. The raw column is
multi-label (`"Crime,Drama"`), and treating it as a factor created **104
levels for 250 films**. Taking the primary genre reduced this to 15, and
lumping genres with fewer than 8 films produced 8 usable levels.

**Certificate** was collapsed from 15 categories to 5. Pre-1968 labels
(`Approved`, `Passed`) and stray TV ratings cannot support separate estimates.

**Inflation.** The sample spans the 1920s to 2021. All monetary values were
deflated to 2025 dollars; the median real gross is $252m against $100m
nominal.

### Analysis samples

| Sample | n | Used for |
|---|---|---|
| `md_all` | 187 | Profitability model; reception test on the full period |
| `md_th`  | 135 | Three-tier comparison (requires theatre counts, so post-1980) |

Models that are compared to each other are fit on identical rows. In the
original project they were not: `lm()` silently drops rows with missing
values, so models using budget were fit on different films from models that
did not, and their R-squared values were compared anyway.

---

## Method

Revenue is heavily right-skewed, so the outcome is `log(real box office)`.
On the log scale the distribution is close to symmetric and coefficients on
logged predictors read as elasticities.

Predictors are grouped by information timing:

| Tier | Variables | Known by |
|---|---|---|
| Pre-production | log budget, genre, runtime, certificate, release year | Before filming |
| + Distribution | + log theatre count | At release |
| + Reception | + IMDb rating, rank | After release |

Rating and rank are **outcomes** of release, not inputs to it. Treating them
as ordinary predictors — as the original project did — answers no clean
question.

---

## Results

### Q1. When is revenue decided?

**Post-1980 sample (n = 135)**

| Information set | Adjusted R² | Increment | F-test |
|---|---|---|---|
| Pre-production | 0.641 | — | — |
| + Distribution | 0.678 | +0.036 | p < 0.001 |
| + Audience reception | 0.714 | +0.036 | p < 0.001 |

**Full sample (n = 187, no theatre data)**

| Information set | Adjusted R² | Increment | F-test |
|---|---|---|---|
| Pre-production | 0.464 | — | — |
| + Audience reception | 0.471 | +0.007 | p = 0.118 (n.s.) |

Two things are worth noting.

First, the same five pre-production variables explain 64% of variation among
post-1980 films but only 46% across the full period. The difference is almost
certainly measurement quality: the films excluded from the smaller sample are
the older ones whose revenue figures were already flagged as unreliable.

Second, **the two samples disagree about audience reception.** It contributes
nothing detectable across the full period (p = 0.118) but is highly
significant post-1980 (p < 0.001). The most plausible reading is that noise
in early box office records masks the effect rather than that no effect
exists — but this should be treated as unresolved.

### Q2. What predicts profitability?

Profitability is modelled as `log(ROI) = log(revenue) − log(budget)`.

Because the predictors are unchanged, this model is mathematically a
reparameterisation of the revenue model: every coefficient is identical
except budget's, which shifts by exactly −1, and the residuals are the same.
Its value lies in two things.

**The budget coefficient becomes directly readable.** At −0.327 (p = 0.004),
a 10% larger budget is associated with roughly 3.3% lower return. Equivalently,
the revenue elasticity of budget is **0.673, 95% CI [0.451, 0.895]** — the
upper bound sits clearly below 1, so returns to budget diminish.

**The R² gap is itself a finding.** The same variables reach adjusted R² of
0.464 for revenue but only **0.215 for ROI**. How much a film will gross is
substantially more predictable than whether it will be a good investment.

**Genre predicts neither.** No genre coefficient approaches significance in
either model, and a joint F-test on the whole block confirms it contributes
nothing to revenue: F = 0.72 on 7 and 119 degrees of freedom, p = 0.65.
An F below 1 means the seven genre parameters bought less improvement than
noise alone typically produces. Excluding genre raises adjusted R² slightly,
from 0.678 to 0.683.

Genre was retained in the reported specification because it was chosen on
theoretical grounds before the models were fit; dropping it now because a
test came back null would be the same post-hoc selection this analysis sets
out to avoid. But the conclusion stands: once budget, runtime, certificate,
release year and theatre count are controlled, genre carries no information
about either revenue or return.

---

## Robustness

**Heteroskedasticity-robust standard errors (HC3).** The Scale-Location plot
shows mild non-constant variance, so classical standard errors overstate
precision. Under HC3:

| Coefficient | Classical p | Robust p (HC3) |
|---|---|---|
| log budget | < 0.001 | 0.004 |
| log theatres | < 0.001 | 0.044 |
| certificate R | 0.042 | 0.081 (n.s.) |

The certificate effect does not survive. Budget and theatres both do, though
the theatre standard error nearly doubles under HC3, so its significance was
checked against the full family of estimators:

| Estimator | Coefficient | SE | p |
|---|---|---|---|
| HC0 | 0.406 | 0.144 | 0.006 |
| HC1 | 0.406 | 0.153 | 0.009 |
| HC2 | 0.406 | 0.168 | 0.017 |
| HC3 | 0.406 | 0.199 | 0.044 |

The point estimate is identical across all four; only the leverage correction
differs, and HC3 applies the strongest one. **The theatre effect is
significant under every variance estimator**, including the most conservative.
A 10% wider release is associated with roughly 4% higher revenue, and the
variable accounts for about 10% of the variation left unexplained by
production characteristics alone.

**Modern subsample.** Re-estimating the ROI model on post-1980 films alone
leaves the budget coefficient at −0.206 (p = 0.022), an elasticity of 0.794.
Weaker than the full-sample estimate but the same direction and still
significant — the result is not an artifact of older records.

**Multicollinearity.** VIF is 3.4 for budget and 2.8 for theatres — moderate
correlation, well short of the conventional threshold of 10. The small
increment from distribution reflects genuinely limited marginal information,
not unstable estimation.

**Influence.** No observation crosses Cook's distance contours in the
residuals-versus-leverage plot. The findings are not driven by a handful of
outlying films.

**One coefficient rejected.** The `Other/Unrated` certificate group shows a
large negative ROI effect (−3.17, p = 0.003 robust). A cross-tabulation
shows 17 of its 20 films predate 1968, when the MPAA rating system began.
Since pre-1968 revenue figures are systematically incomplete, this coefficient
measures data quality rather than certification, and is not interpreted as a
substantive result.

---

## Limitations

**Sample selection.** The Top 250 is selected on critical acclaim. Ratings
range only from roughly 8.0 to 9.3, which mechanically attenuates any
correlation involving rating. None of these results should be generalised to
the wider film market without a comparison sample that includes commercial
failures.

**Theatre counts measure widest release, not opening week.** Distributors add
screens in response to performance, so the variable is partly endogenous: its
coefficient describes association, not causation. It is suitable for asking
how well revenue can be predicted at release, not for a greenlight decision.

**Theatre counts cover North America only**, while box office is worldwide.
For films whose revenue came largely from other markets — *Amores Perros*
played 187 US theatres against a mostly Mexican gross — the variable has
little explanatory content.

**Cumulative revenue, single-year deflation.** Older films' reported grosses
accumulate across decades of re-release, but are deflated here by the release
year's CPI, which overstates their real scale.

**Post-1980 restriction.** The three-tier comparison covers modern releases
only and does not describe the silent or studio eras.

---

