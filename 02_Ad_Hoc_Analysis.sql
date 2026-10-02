USE northstar;

-- ============================================================
-- NORTHSTAR IT
-- AD HOC WORKFORCE AND SERVICE DELIVERY ANALYSIS
-- ============================================================
-- Purpose:
-- Investigate elevated overtime within the 24/7 Service Desk
-- and identify operational factors associated with the pattern.
--
-- Analytical path:
-- Company -> Department -> Shift -> Manager -> Role
-- -> Attendance -> Workload -> Service Complexity
-- ============================================================


-- ------------------------------------------------------------
-- 1. COMPANYWIDE OVERTIME BY DEPARTMENT
-- Question:
-- Which departments have the highest overtime rate?
-- ------------------------------------------------------------

SELECT
    department,
    ROUND(SUM(overtime_hours), 2) AS total_overtime_hours,
    ROUND(SUM(scheduled_hours), 2) AS total_scheduled_hours,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct
FROM vw_workforce_monthly
GROUP BY department
ORDER BY overtime_rate_pct DESC;


-- ------------------------------------------------------------
-- 2. 24/7 SERVICE DESK MONTHLY OVERTIME TREND
-- Question:
-- Is elevated overtime persistent or caused by isolated spikes?
-- ------------------------------------------------------------

SELECT
    snapshot_month,
    ROUND(SUM(overtime_hours), 2) AS total_overtime_hours,
    ROUND(SUM(scheduled_hours), 2) AS total_scheduled_hours,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct
FROM vw_workforce_monthly
WHERE department = '24/7 Service Desk'
GROUP BY snapshot_month
ORDER BY snapshot_month;


-- ------------------------------------------------------------
-- 3. OVERTIME BY SHIFT
-- Question:
-- Which Service Desk shifts carry the greatest overtime burden?
-- ------------------------------------------------------------

SELECT
    shift,
    ROUND(SUM(overtime_hours), 2) AS total_overtime_hours,
    ROUND(SUM(scheduled_hours), 2) AS total_scheduled_hours,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct
FROM vw_workforce_monthly
WHERE department = '24/7 Service Desk'
GROUP BY shift
ORDER BY overtime_rate_pct DESC;


-- ------------------------------------------------------------
-- 4. MANAGER, SHIFT, AND ROLE COMPARISON
-- Question:
-- Is overtime concentrated within particular teams or roles?
-- ------------------------------------------------------------

SELECT
    manager_name,
    shift,
    job_title,
    ROUND(SUM(overtime_hours), 2) AS total_overtime_hours,
    ROUND(SUM(scheduled_hours), 2) AS total_scheduled_hours,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct
FROM vw_workforce_monthly
WHERE department = '24/7 Service Desk'
  AND shift IN ('Evening', 'Overnight')
GROUP BY
    manager_name,
    shift,
    job_title
ORDER BY
    manager_name,
    overtime_rate_pct DESC;


-- ------------------------------------------------------------
-- 5. COMPARABLE ROLE ANALYSIS
-- Question:
-- For the same Support Technician I role, how do Blake Ward's
-- Overnight team and Cameron Stone's Evening team compare?
-- ------------------------------------------------------------

SELECT
    manager_name,
    shift,
    ROUND(SUM(overtime_hours), 2) AS total_overtime_hours,
    ROUND(SUM(scheduled_hours), 2) AS total_scheduled_hours,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct
FROM vw_workforce_monthly
WHERE department = '24/7 Service Desk'
  AND job_title = 'Support Technician I'
  AND manager_name IN ('Blake Ward', 'Cameron Stone')
GROUP BY
    manager_name,
    shift
ORDER BY overtime_rate_pct DESC;


-- ------------------------------------------------------------
-- 6. COMPARABLE ROLE OPERATING CONDITIONS
-- Question:
-- Do staffing, tenure, PTO, or unscheduled absence differ
-- between Blake Ward and Cameron Stone?
-- ------------------------------------------------------------

WITH monthly_team_metrics AS (
    SELECT
        snapshot_month,
        manager_name,
        shift,
        COUNT(DISTINCT employee_id) AS headcount,
        AVG(tenure_years) AS avg_tenure_years,
        SUM(scheduled_hours) AS scheduled_hours,
        SUM(overtime_hours) AS overtime_hours,
        SUM(pto_hours) AS pto_hours,
        SUM(unscheduled_absence_hours) AS unscheduled_absence_hours
    FROM vw_workforce_monthly
    WHERE department = '24/7 Service Desk'
      AND job_title = 'Support Technician I'
      AND manager_name IN ('Blake Ward', 'Cameron Stone')
    GROUP BY
        snapshot_month,
        manager_name,
        shift
)

SELECT
    manager_name,
    shift,
    ROUND(AVG(headcount), 2) AS avg_monthly_headcount,
    ROUND(AVG(avg_tenure_years), 2) AS avg_tenure_years,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct,
    ROUND(
        SUM(pto_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS pto_rate_pct,
    ROUND(
        SUM(unscheduled_absence_hours)
        / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS unscheduled_absence_rate_pct
FROM monthly_team_metrics
GROUP BY
    manager_name,
    shift
ORDER BY overtime_rate_pct DESC;


-- ------------------------------------------------------------
-- 7. BLAKE WARD MONTHLY STAFFING AND TIME AWAY
-- Question:
-- Do overtime spikes correspond with headcount or employee
-- time away?
-- ------------------------------------------------------------

SELECT
    snapshot_month,
    COUNT(DISTINCT employee_id) AS headcount,
    ROUND(
        SUM(overtime_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS overtime_rate_pct,
    ROUND(
        SUM(pto_hours) / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS pto_rate_pct,
    ROUND(
        SUM(unscheduled_absence_hours)
        / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS unscheduled_absence_rate_pct,
    ROUND(
        (SUM(pto_hours) + SUM(unscheduled_absence_hours))
        / NULLIF(SUM(scheduled_hours), 0) * 100,
        2
    ) AS total_time_away_rate_pct
FROM vw_workforce_monthly
WHERE department = '24/7 Service Desk'
  AND job_title = 'Support Technician I'
  AND manager_name = 'Blake Ward'
GROUP BY snapshot_month
ORDER BY snapshot_month;


-- ------------------------------------------------------------
-- 8. BLAKE WARD MONTHLY WORKLOAD AND SERVICE PRESSURE
-- Question:
-- How do ticket volume, service complexity, attendance,
-- and overtime behave together?
-- ------------------------------------------------------------

WITH blake_team AS (
    SELECT
        snapshot_month,
        employee_id,
        scheduled_hours,
        overtime_hours,
        pto_hours,
        unscheduled_absence_hours
    FROM vw_workforce_monthly
    WHERE department = '24/7 Service Desk'
      AND job_title = 'Support Technician I'
      AND manager_name = 'Blake Ward'
),

monthly_workforce AS (
    SELECT
        snapshot_month,
        COUNT(DISTINCT employee_id) AS headcount,
        SUM(scheduled_hours) AS scheduled_hours,
        SUM(overtime_hours) AS overtime_hours,
        SUM(pto_hours) AS pto_hours,
        SUM(unscheduled_absence_hours) AS unscheduled_absence_hours
    FROM blake_team
    GROUP BY snapshot_month
),

monthly_service AS (
    SELECT
        bt.snapshot_month,
        COUNT(st.ticket_id) AS ticket_volume,
        SUM(
            CASE
                WHEN st.priority IN ('Critical', 'High') THEN 1
                ELSE 0
            END
        ) AS high_priority_tickets,
        SUM(
            CASE
                WHEN st.escalated = 'Yes' THEN 1
                ELSE 0
            END
        ) AS escalated_tickets,
        SUM(
            CASE
                WHEN st.sla_met = 'No' THEN 1
                ELSE 0
            END
        ) AS sla_misses,
        AVG(st.resolution_hours) AS avg_resolution_hours
    FROM blake_team bt
    LEFT JOIN support_tickets st
        ON st.assigned_employee_id = bt.employee_id
       AND LAST_DAY(st.created_date) = bt.snapshot_month
    GROUP BY bt.snapshot_month
)

SELECT
    mw.snapshot_month,
    mw.headcount,
    ms.ticket_volume,
    ROUND(
        ms.high_priority_tickets
        / NULLIF(ms.ticket_volume, 0) * 100,
        2
    ) AS high_priority_rate_pct,
    ROUND(
        ms.escalated_tickets
        / NULLIF(ms.ticket_volume, 0) * 100,
        2
    ) AS escalation_rate_pct,
    ROUND(
        ms.sla_misses
        / NULLIF(ms.ticket_volume, 0) * 100,
        2
    ) AS sla_miss_rate_pct,
    ROUND(ms.avg_resolution_hours, 2)
        AS avg_resolution_hours,
    ROUND(
        mw.overtime_hours
        / NULLIF(mw.scheduled_hours, 0) * 100,
        2
    ) AS overtime_rate_pct,
    ROUND(
        (mw.pto_hours + mw.unscheduled_absence_hours)
        / NULLIF(mw.scheduled_hours, 0) * 100,
        2
    ) AS total_time_away_rate_pct
FROM monthly_workforce mw
LEFT JOIN monthly_service ms
    ON mw.snapshot_month = ms.snapshot_month
ORDER BY mw.snapshot_month;


-- ------------------------------------------------------------
-- 9. TICKET VOLUME AND OVERTIME CORRELATION
-- Question:
-- How strongly are monthly ticket volume and overtime related?
--
-- MariaDB does not provide CORR() in this environment,
-- so Pearson correlation is calculated manually.
-- ------------------------------------------------------------

WITH blake_team AS (
    SELECT
        snapshot_month,
        employee_id,
        scheduled_hours,
        overtime_hours
    FROM vw_workforce_monthly
    WHERE department = '24/7 Service Desk'
      AND job_title = 'Support Technician I'
      AND manager_name = 'Blake Ward'
),

monthly_workforce AS (
    SELECT
        snapshot_month,
        SUM(overtime_hours)
        / NULLIF(SUM(scheduled_hours), 0) * 100
            AS overtime_rate_pct
    FROM blake_team
    GROUP BY snapshot_month
),

monthly_tickets AS (
    SELECT
        bt.snapshot_month,
        COUNT(st.ticket_id) AS ticket_volume
    FROM blake_team bt
    LEFT JOIN support_tickets st
        ON st.assigned_employee_id = bt.employee_id
       AND LAST_DAY(st.created_date) = bt.snapshot_month
    GROUP BY bt.snapshot_month
),

combined AS (
    SELECT
        mw.snapshot_month,
        mt.ticket_volume,
        mw.overtime_rate_pct
    FROM monthly_workforce mw
    JOIN monthly_tickets mt
        ON mw.snapshot_month = mt.snapshot_month
)

SELECT
    ROUND(
        (
            COUNT(*) * SUM(ticket_volume * overtime_rate_pct)
            - SUM(ticket_volume) * SUM(overtime_rate_pct)
        )
        /
        NULLIF(
            SQRT(
                (
                    COUNT(*) * SUM(ticket_volume * ticket_volume)
                    - POW(SUM(ticket_volume), 2)
                )
                *
                (
                    COUNT(*)
                    * SUM(overtime_rate_pct * overtime_rate_pct)
                    - POW(SUM(overtime_rate_pct), 2)
                )
            ),
            0
        ),
        3
    ) AS ticket_overtime_correlation
FROM combined;


-- ------------------------------------------------------------
-- 10. HIGHEST OVERTIME MONTHS DIAGNOSTIC RANKING
-- Question:
-- What operating conditions are present during the highest
-- overtime months?
-- ------------------------------------------------------------

WITH blake_team AS (
    SELECT
        snapshot_month,
        employee_id,
        scheduled_hours,
        overtime_hours,
        pto_hours,
        unscheduled_absence_hours
    FROM vw_workforce_monthly
    WHERE department = '24/7 Service Desk'
      AND job_title = 'Support Technician I'
      AND manager_name = 'Blake Ward'
),

monthly_workforce AS (
    SELECT
        snapshot_month,
        COUNT(DISTINCT employee_id) AS headcount,
        SUM(scheduled_hours) AS scheduled_hours,
        SUM(overtime_hours) AS overtime_hours,
        SUM(pto_hours) AS pto_hours,
        SUM(unscheduled_absence_hours) AS unscheduled_absence_hours
    FROM blake_team
    GROUP BY snapshot_month
),

monthly_service AS (
    SELECT
        bt.snapshot_month,
        COUNT(st.ticket_id) AS ticket_volume,
        SUM(
            CASE
                WHEN st.priority IN ('Critical', 'High') THEN 1
                ELSE 0
            END
        ) AS high_priority_tickets,
        SUM(
            CASE
                WHEN st.escalated = 'Yes' THEN 1
                ELSE 0
            END
        ) AS escalated_tickets,
        SUM(
            CASE
                WHEN st.sla_met = 'No' THEN 1
                ELSE 0
            END
        ) AS sla_misses,
        AVG(st.resolution_hours) AS avg_resolution_hours
    FROM blake_team bt
    LEFT JOIN support_tickets st
        ON st.assigned_employee_id = bt.employee_id
       AND LAST_DAY(st.created_date) = bt.snapshot_month
    GROUP BY bt.snapshot_month
)

SELECT
    mw.snapshot_month,
    ms.ticket_volume,
    ROUND(
        ms.high_priority_tickets
        / NULLIF(ms.ticket_volume, 0) * 100,
        2
    ) AS high_priority_rate_pct,
    ROUND(
        ms.escalated_tickets
        / NULLIF(ms.ticket_volume, 0) * 100,
        2
    ) AS escalation_rate_pct,
    ROUND(
        ms.sla_misses
        / NULLIF(ms.ticket_volume, 0) * 100,
        2
    ) AS sla_miss_rate_pct,
    ROUND(ms.avg_resolution_hours, 2)
        AS avg_resolution_hours,
    ROUND(
        mw.overtime_hours
        / NULLIF(mw.scheduled_hours, 0) * 100,
        2
    ) AS overtime_rate_pct,
    ROUND(
        (mw.pto_hours + mw.unscheduled_absence_hours)
        / NULLIF(mw.scheduled_hours, 0) * 100,
        2
    ) AS total_time_away_rate_pct
FROM monthly_workforce mw
LEFT JOIN monthly_service ms
    ON mw.snapshot_month = ms.snapshot_month
ORDER BY overtime_rate_pct DESC;