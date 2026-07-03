# Ledgerly — SaaS Billing Reconciliation & Revenue Analytics

**Billing Reconciliation, MRR Movement, Net Revenue Retention, Cohort Analysis, and Processor Settlement Analytics**

<br>
End-to-end SaaS billing analytics project analyzing synthetic Stripe-style billing data from a B2B subscription business. The analysis covers processor settlement reconciliation, chargeback restatements, MRR movement, and net revenue retention by paid signup cohort — built entirely in Snowflake using a RAW → STAGING → ANALYTICS architecture.

<br><br>

➤ **Executive Summary :**<br>
What the project was trying to find out

Does what Stripe settled in June 2024 match what the billing system recorded — and where are the gaps?
Which prior-period invoices had their net revenue restated by chargebacks that landed in June 2024?
Is recurring revenue growing, and what's driving the movement each month?
How much recurring revenue was permanently lost in 2024 after all payment retries were exhausted?
Which paid signup cohorts retained and expanded revenue through 2024, and which didn't?
<br>

➤ **What the data showed**


[To be completed after running BQ01–BQ06 outputs]


➤ **What the key numbers are**

25,000 customers · 26,250 subscriptions · 321,114 invoices · 359,466 charges
4,158 refunds · 288 disputes · 324,306 balance transactions · 156 payouts
Dataset spans 2022–2024, with analytics scoped to 2024 reporting windows
<br>

➤ **What actions should follow**

[To be completed after running BQ01–BQ06 outputs]

<br><br>

➤ **Project Scope:**<br>

This project evaluates how a simulated B2B SaaS billing system generates, collects, and reconciles recurring revenue — examining whether the processor settlement matches internal billing records, whether chargebacks are distorting prior-period revenue, whether recurring revenue growth is healthy, and whether existing customers are expanding or contracting over time.

The reconciliation layer compares Stripe-side balance transactions against invoice-side billing records to surface gaps and classify them by cause. The revenue analytics layer tracks MRR movement month over month and decomposes it into new, expansion, contraction, churn, and reactivation drivers. The cohort layer measures net revenue retention by paid signup cohort and identifies which movement types — expansion, contraction, or churn — drove each cohort's 2024 outcome.

The project is built entirely in Snowflake using a RAW → STAGING → ANALYTICS three-layer architecture. Raw CSV files load into the RAW schema without transformation. STAGING cleans and types the data. ANALYTICS holds all business logic — reconciliation tables, MRR tables, cohort outputs, and lost-revenue summaries. Every analytics object documents its grain.
<br>

➤ **A Note on Synthetic Data:**<br>

Real Stripe exports contain PII and are proprietary. This dataset was generated from scratch using published Stripe API schemas, real SaaS churn and dispute benchmarks, and intentionally seeded edge cases that appear in production billing systems — including timing gaps, partial refunds, chargeback restatements of prior periods, and retry-exhausted uncollectible invoices. The goal was a dataset realistic enough that every business question produces a defensible answer, not a convenient one.
<br>

➤ **The Dataset :**<br>
The raw dataset spans 2022 through 2024, and all reporting and conclusions in this project are intentionally scoped to 2024 reporting windows, with 2022–2023 history used as the baseline for cohort anchoring and MRR movement calculations.

The analysis uses nine core tables modeled on the Stripe API, covering customers, subscriptions, subscription lifecycle events, invoices, charges, refunds, disputes, processor balance transactions, and bank payouts.
<br>

➤ **Skills Demonstrated:**

(SQL • Snowflake • Billing Reconciliation • MRR Movement Analytics • Net Revenue Retention • Cohort Analysis • Window Functions • Data Quality Validation)

<br><br>

##Core Business Questions :
<br>

BILLING RECONCILIATION<br>
BQ01 — Which June Stripe invoices have reconciliation gaps, and why?<br>
BQ02 — How much old invoice revenue did we lose to June chargebacks, and why?

<br>
REVENUE ANALYTICS<br>
BQ03 — What was month-by-month MRR movement in 2024?<br>
BQ04 — What drove the 2024 MRR movement?<br>
BQ05 — How much recurring revenue was permanently lost each month in 2024 after all payment retries were exhausted?

<br>
COHORT & RETENTION ANALYTICS<br>
BQ06 — Which paid signup cohorts had the strongest and weakest 2024 year-end NRR?<br>
BQ07 — How did expansion, contraction, and churn affect 2024 year-end NRR by paid signup cohort?

<br>

---

<br>>

## The Main Report - Key Questions Answered

### BILLING RECONCILIATION

<br>

**1  Which June Stripe invoices have reconciliation gaps, and why?**

**Charts**

<p align="center">
  <img src="Charts/01_1_Monthly_Recurring_Revenue.png" width="100%">
</p>

<br>

**Key Insights**

- Of 12,972 June invoices processed through Stripe, 12,722 reconcile cleanly (98.1%)
- 250 invoices have a gap, totaling $49,354.15 in unreconciled revenue
- All gaps are caused by refunds and disputes, not timing differences, missing charges, or double charges.
- Partial refunds account for the highest volume of gaps: 199 invoices, $16,933.90
- Disputes drive the highest dollar impact: 51 invoices, $32,420.25 — despite being fewer in number, dispute deductions are larger per invoice than refunds
- No double charges detected across any June invoice — PROCESSOR_CHARGE_COUNT is 1 for all 12,972 invoices

