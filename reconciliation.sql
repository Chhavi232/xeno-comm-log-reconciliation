WITH RECURSIVE
roots AS (
    SELECT id, id AS root_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, r.root_id
    FROM campaign c
    JOIN roots r
        ON c.parent_id = r.id
),

chain_sizes AS (
    SELECT
        root_id,
        COUNT(*) AS chain_size
    FROM roots
    GROUP BY root_id
),

finalized_campaigns AS (
    SELECT id
    FROM campaign
    WHERE creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND processing_status = 'processed'
),

scoped_sends AS (
    SELECT
        cl.customer_id,
        r.root_id,
        cs.chain_size
    FROM communication_log cl
    JOIN roots r
        ON cl.communication_id = r.id
    JOIN chain_sizes cs
        ON cs.root_id = r.root_id
    WHERE cl.communication_id IN (
        SELECT id
        FROM finalized_campaigns
    )
      AND cl.merchant_id = 501
      AND cl.communication_type = '2'
      AND cl.sent_time >= '2026-10-01'
      AND cl.sent_time < '2026-11-01'
),

per_chain_counts AS (
    SELECT
        root_id,
        CASE
            WHEN chain_size = 1 THEN COUNT(*)
            ELSE COUNT(DISTINCT customer_id)
        END AS chain_target_base
    FROM scoped_sends
    GROUP BY root_id, chain_size
)

SELECT SUM(chain_target_base) AS target_base
FROM per_chain_counts;