# Comm-Log Send Reconciliation — Xeno Data Analyst Take-Home

## Objective

I reconciled Finance's `target_base` for **merchant 501**, **October 2026**, for Campaign communications (`communication_type = '2'`) across the Diwali campaigns.

**Finance target:** `22`  
**Reproduced result:** `22`

## Reconciliation Bridge

| Step | Logic | Result | Reason |
|---|---|---:|---|
| 0 | Naive `COUNT(*)` on merchant/date/type | **30** | Starting point — treat every communication log row as a qualifying send |
| 1 | Excluded non-finalized campaigns | **26** | Campaign `9004` is `approval_awaiting`; its 4 log rows exist, but the campaign itself was never finalized |
| 2 | Looked into why customers kept repeating | Investigation | Repeated customers show up both across retry chains and inside a standalone campaign — for different reasons |
| 3 | Tried a global `COUNT(DISTINCT customer_id)` | **21** | This strips out legitimate repeat sends from standalone campaign `9101`, which is why it's one short |
| 4 | Applied campaign-family-aware logic instead | **22** | Dedupe customers within retry chains, but count every finalized send separately for a standalone campaign |
| **Final** | Sum of the three families: `9001-family = 10` + `9101 standalone = 7` + `9201-family = 5` | **22** | Matches Finance |

## Key Investigation

The campaign hierarchy matters here because a repeated customer doesn't always mean the same thing.

- `9001 → 9002 → 9003` is a retry chain.
- `9001 → 9004` is another branch off the same family, but `9004` never got finalized.
- `9101` is standalone. Customer `C20` shows up twice under it, and both are genuinely separate sends.
- `9201 → 9202` is a retry chain.

That's why a flat, global `DISTINCT` is too aggressive — it treats every repeat as a retry, which isn't true for `9101`. The final query walks the `parent_id` hierarchy to group campaigns into families first, then:
- counts distinct customers within retry chains,
- counts every finalized row, undeduplicated, for standalone campaigns.

That gives `9001-family = 10`, `9101 standalone = 7`, `9201-family = 5` — 22 total.

## Final SQL

The query is in [`reconciliation.sql`](./reconciliation.sql).

It uses a recursive CTE to walk the campaign hierarchy, filters down to finalized campaigns, scopes the communication logs, and applies the family-specific counting rule above.

**Expected result:** `22`

## Something Surprising in the Data

The global `DISTINCT` (step 3) lands on 21 — just one short of Finance's 22 — and that's what made it worth double-checking rather than shipping. The gap comes down to the fact that the same repeated `customer_id` means two different things depending on context: a retry within a chain (count once) or a separate send under a standalone campaign (count both). Nothing in the row itself — same customer, same type — tells you which applies; you have to know the campaign's family structure first. That's what makes the naive dedup dangerous — it's wrong by exactly one, which is easy to miss.

## Assumptions and Checks

**Confirmed by the README/schema**
- A campaign is finalized when `creation_status` is one of `approved`, `aborted`, `resumed`, or `stopped`, and `processing_status = 'processed'`.
- `communication_type = '2'` is the required Campaign scope.
- `9004` is excluded because its creation status is `approval_awaiting`, even though its rows show `processing_status = 'processed'`.

**Confirmed by actually checking the data**
- All 7 campaign names contain "Diwali," so there was no need for a separate name-based filter.
- I checked whether filtering to delivered-only (`delivery_status`) would change anything — it doesn't, here. Every customer counted within a retry chain has at least one delivered row among that chain's finalized campaigns.

**Judgment calls I made**
- I used `sent_time` for the October filter. That's a reasonable reading of "sends in October," but in this dataset `sent_time` and `scheduled_time` are identical on every row, so the data itself can't confirm which one is "correct."
- I built the `parent_id` hierarchy from *all* campaigns, including unfinalized `9004`, not just finalized ones — treating retry topology (who's a retry of whom) as separate from finalization (which sends count). I also tried building the hierarchy from finalized campaigns only, and got the same chain groupings, so it doesn't change the result here. But the README doesn't explicitly say which reading is "correct," so I'm calling this a judgment call rather than a stated rule.

**Open question I'd take to Finance rather than guess**
- What if every finalized attempt for a customer within a retry chain fails — no successful delivery at all? Should that customer still count toward `target_base`? This dataset doesn't have that case (every counted customer has at least one delivered row), and the README doesn't say. I'd rather flag this than assume an answer.

## Files

```text
.
├── README.md
└── reconciliation.sql
```
