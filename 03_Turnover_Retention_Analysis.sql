USE northstar;

-- ============================================================
-- NORTHSTAR IT
-- TURNOVER AND RETENTION ANALYSIS
-- ============================================================
-- Purpose:
-- Investigate workforce stability within the 24/7 Service Desk,
-- with emphasis on the Overnight shift.
--
-- Analytical path:
-- Terminations -> Turnover Rate -> Exit Themes
-- -> Manager Context -> Compensation -> Recruiting
-- -> Retention -> Internal Mobility -> Training
-- -> Workforce Stability Summary
-- ============================================================


-- ------------------------------------------------------------
-- 1. TERMINATIONS AND TENURE AT EXIT
-- Question:
-- Which departments and shifts have the highest termination
-- counts, and how long are employees staying before exit?
-- ------------------------------------------------------------

SELECT
    department,
    shift,
    COUNT(*) AS terminated_employees,
    ROUND(
        AVG(DATEDIFF(termination_date, original_hire_date) / 365.25),
        2
    ) AS avg_tenure_years_at_exit
FROM employees
WHERE employee_status = 'Terminated'
GROUP BY
    department,
    shift
ORDER BY
    terminated_employees DESC,
    avg_tenure_years_at_exit ASC;


-- ------------------------------------------------------------
-- 2. PERIOD TURNOVER RATE
-- Question:
-- How large are termination counts relative to the average
-- monthly workforce operating in each department and shift?
--
-- Reporting period:
-- January 2025 through September 2026
-- ------------------------------------------------------------

WITH monthly_headcount AS (
    SELECT
        snapshot_month,
        department,
        shift,
        COUNT(DISTINCT employee_id) AS headcount
    FROM workforce_monthly_snapshots
    GROUP BY
        snapshot_month,
        department,
        shift
),

average_headcount AS (
    SELECT
        department,
        shift,
        ROUND(AVG(headcount), 2) AS avg_monthly_headcount
    FROM monthly_headcount
    GROUP BY
        department,
        shift
),

terminations AS (
    SELECT
        department,
        shift,
        COUNT(*) AS terminated_employees,
        ROUND(
            AVG(DATEDIFF(termination_date, original_hire_date) / 365.25),
            2
        ) AS avg_tenure_years_at_exit
    FROM employees
    WHERE employee_status = 'Terminated'
      AND termination_date BETWEEN '2025-01-01' AND '2026-09-30'
    GROUP BY
        department,
        shift
)

SELECT
    a.department,
    a.shift,
    a.avg_monthly_headcount,
    COALESCE(t.terminated_employees, 0) AS terminated_employees,
    t.avg_tenure_years_at_exit,
    ROUND(
        COALESCE(t.terminated_employees, 0)
        / NULLIF(a.avg_monthly_headcount, 0) * 100,
        2
    ) AS period_turnover_rate_pct
FROM average_headcount a
LEFT JOIN terminations t
    ON a.department = t.department
   AND a.shift = t.shift
ORDER BY
    period_turnover_rate_pct DESC,
    a.department,
    a.shift;


-- ------------------------------------------------------------
-- 3. 24/7 SERVICE DESK EXIT THEMES BY SHIFT
-- Question:
-- Why are Service Desk employees leaving, and do exit themes
-- differ between Day, Evening, and Overnight?
-- ------------------------------------------------------------

SELECT
    shift,
    primary_exit_theme,
    termination_type,
    COUNT(*) AS exit_count,
    ROUND(AVG(exit_satisfaction), 2) AS avg_exit_satisfaction,
    SUM(complaint_raised) AS complaints_raised
FROM exit_interviews
WHERE department = '24/7 Service Desk'
GROUP BY
    shift,
    primary_exit_theme,
    termination_type
ORDER BY
    shift,
    exit_count DESC,
    primary_exit_theme;


-- ------------------------------------------------------------
-- 4. INDIVIDUAL OVERNIGHT EXITS
-- Question:
-- What do the individual Overnight exit records show?
-- ------------------------------------------------------------

SELECT
    employee_name,
    job_title,
    hire_date,
    termination_date,
    ROUND(
        DATEDIFF(termination_date, hire_date) / 365.25,
        2
    ) AS tenure_years_at_exit,
    termination_reason,
    primary_exit_theme,
    exit_satisfaction,
    complaint_raised,
    complaint_type,
    eligible_for_rehire,
    exit_comments
FROM exit_interviews
WHERE department = '24/7 Service Desk'
  AND shift = 'Overnight'
ORDER BY termination_date;


-- ------------------------------------------------------------
-- 5. MANAGER CONTEXT FOR OVERNIGHT EXITS
-- Question:
-- Who was the most recently recorded manager for each
-- Overnight employee before termination?
--
-- Note:
-- One employee may not have a manager match because the
-- termination occurred before available workforce history.
-- ------------------------------------------------------------

SELECT
    e.employee_name,
    e.job_title,
    e.termination_date,
    e.primary_exit_theme,
    e.complaint_raised,
    e.complaint_type,
    w.snapshot_month,
    w.manager_name
FROM exit_interviews e
LEFT JOIN workforce_monthly_snapshots w
    ON w.employee_id = e.employee_id
   AND w.snapshot_month = (
        SELECT MAX(w2.snapshot_month)
        FROM workforce_monthly_snapshots w2
        WHERE w2.employee_id = e.employee_id
          AND w2.snapshot_month <= LAST_DAY(e.termination_date)
   )
WHERE e.department = '24/7 Service Desk'
  AND e.shift = 'Overnight'
ORDER BY e.termination_date;


-- ------------------------------------------------------------
-- 6. SERVICE DESK PAY BANDS
-- Question:
-- How are Service Desk roles positioned within Northstar's
-- compensation structure, and which roles are eligible for
-- shift differential?
-- ------------------------------------------------------------

SELECT
    position_title,
    job_family,
    grade,
    range_minimum,
    range_midpoint,
    range_maximum,
    target_bonus_pct,
    shift_differential_eligible,
    critical_role,
    effective_date
FROM position_pay_bands
WHERE position_title IN (
    'Support Technician I',
    'Support Technician II',
    'Senior Support Technician',
    'Service Desk Coordinator',
    'Service Desk Manager'
)
ORDER BY
    range_minimum,
    position_title;


-- ------------------------------------------------------------
-- 7A. SERVICE DESK COMPENSATION POSITIONING
-- Question:
-- Where are Service Desk employees positioned relative to the
-- official pay band midpoint, and does pay differ by shift?
-- ------------------------------------------------------------

WITH latest_compensation AS (
    SELECT
        j.employee_id,
        j.effective_date,
        j.new_position,
        j.new_shift,
        j.new_annualized_pay,
        j.data_quality_flag,
        ROW_NUMBER() OVER (
            PARTITION BY j.employee_id
            ORDER BY j.effective_date DESC
        ) AS rn
    FROM job_compensation_history j
    WHERE j.new_position IN (
        'Support Technician I',
        'Support Technician II',
        'Senior Support Technician',
        'Service Desk Coordinator'
    )
      AND j.new_annualized_pay IS NOT NULL
),

service_desk_pay AS (
    SELECT
        lc.employee_id,
        lc.new_position,
        lc.new_shift,
        lc.new_annualized_pay,
        pb.range_minimum,
        pb.range_midpoint,
        pb.range_maximum,
        pb.shift_differential_eligible
    FROM latest_compensation lc
    LEFT JOIN position_pay_bands pb
        ON lc.new_position = pb.position_title
    WHERE lc.rn = 1
)

SELECT
    new_shift AS shift,
    new_position AS job_title,
    COUNT(*) AS employees,
    ROUND(AVG(new_annualized_pay), 2) AS avg_annualized_pay,
    ROUND(AVG(range_midpoint), 2) AS pay_band_midpoint,
    ROUND(
        AVG(new_annualized_pay)
        / NULLIF(AVG(range_midpoint), 0) * 100,
        2
    ) AS avg_pay_as_pct_of_midpoint,
    MIN(new_annualized_pay) AS lowest_pay,
    MAX(new_annualized_pay) AS highest_pay,
    MAX(shift_differential_eligible) AS shift_differential_eligible
FROM service_desk_pay
GROUP BY
    new_shift,
    new_position
ORDER BY
    new_shift,
    new_position;


-- ------------------------------------------------------------
-- 7B. PAY RANGE ALIGNMENT
-- Question:
-- How many Service Desk employees fall below, within, or above
-- their formal compensation range?
-- ------------------------------------------------------------

WITH latest_compensation AS (
    SELECT
        j.employee_id,
        j.new_position,
        j.new_shift,
        j.new_annualized_pay,
        ROW_NUMBER() OVER (
            PARTITION BY j.employee_id
            ORDER BY j.effective_date DESC
        ) AS rn
    FROM job_compensation_history j
    WHERE j.new_position IN (
        'Support Technician I',
        'Support Technician II',
        'Senior Support Technician',
        'Service Desk Coordinator'
    )
      AND j.new_annualized_pay IS NOT NULL
)

SELECT
    lc.new_shift AS shift,
    lc.new_position AS job_title,
    COUNT(*) AS employees,
    SUM(
        CASE
            WHEN lc.new_annualized_pay < pb.range_minimum THEN 1
            ELSE 0
        END
    ) AS below_range,
    SUM(
        CASE
            WHEN lc.new_annualized_pay BETWEEN pb.range_minimum
                                         AND pb.range_maximum THEN 1
            ELSE 0
        END
    ) AS within_range,
    SUM(
        CASE
            WHEN lc.new_annualized_pay > pb.range_maximum THEN 1
            ELSE 0
        END
    ) AS above_range
FROM latest_compensation lc
JOIN position_pay_bands pb
    ON lc.new_position = pb.position_title
WHERE lc.rn = 1
GROUP BY
    lc.new_shift,
    lc.new_position
ORDER BY
    lc.new_shift,
    lc.new_position;


-- ------------------------------------------------------------
-- 8. SERVICE DESK RECRUITING OUTCOMES BY SHIFT
-- Question:
-- Are Overnight Service Desk roles harder or more expensive
-- to fill than Day or Evening roles?
--
-- Recruiting source data uses 'Accepted' as the completed
-- recruiting outcome.
-- ------------------------------------------------------------

SELECT
    shift,
    COUNT(*) AS requisitions,
    ROUND(AVG(days_to_fill), 2) AS avg_days_to_fill,
    ROUND(AVG(offers_made), 2) AS avg_offers_made,
    ROUND(AVG(recruiting_cost), 2) AS avg_recruiting_cost,
    SUM(
        CASE
            WHEN outcome = 'Accepted' THEN 1
            ELSE 0
        END
    ) AS accepted_hires
FROM recruiting_requisitions
WHERE department = '24/7 Service Desk'
GROUP BY shift
ORDER BY avg_days_to_fill DESC;


-- ------------------------------------------------------------
-- 9. SERVICE DESK RETENTION BY MANAGER
-- Question:
-- Do Service Desk managers show meaningful differences in
-- turnover and tenure after accounting for team size?
--
-- Manager at exit is based on the most recent available
-- workforce snapshot on or before termination.
-- ------------------------------------------------------------

WITH manager_headcount_monthly AS (
    SELECT
        snapshot_month,
        manager_name,
        shift,
        COUNT(DISTINCT employee_id) AS headcount
    FROM workforce_monthly_snapshots
    WHERE department = '24/7 Service Desk'
      AND manager_name IS NOT NULL
    GROUP BY
        snapshot_month,
        manager_name,
        shift
),

manager_average_headcount AS (
    SELECT
        manager_name,
        shift,
        ROUND(AVG(headcount), 2) AS avg_monthly_headcount
    FROM manager_headcount_monthly
    GROUP BY
        manager_name,
        shift
),

exits_with_manager AS (
    SELECT
        e.employee_id,
        e.employee_name,
        e.job_title,
        e.shift,
        e.hire_date,
        e.termination_date,
        e.primary_exit_theme,
        e.complaint_raised,
        w.manager_name
    FROM exit_interviews e
    LEFT JOIN workforce_monthly_snapshots w
        ON w.employee_id = e.employee_id
       AND w.snapshot_month = (
            SELECT MAX(w2.snapshot_month)
            FROM workforce_monthly_snapshots w2
            WHERE w2.employee_id = e.employee_id
              AND w2.snapshot_month <= LAST_DAY(e.termination_date)
       )
    WHERE e.department = '24/7 Service Desk'
      AND e.termination_date BETWEEN '2025-01-01' AND '2026-09-30'
),

manager_exits AS (
    SELECT
        manager_name,
        shift,
        COUNT(*) AS exits,
        ROUND(
            AVG(DATEDIFF(termination_date, hire_date) / 365.25),
            2
        ) AS avg_tenure_years_at_exit,
        SUM(complaint_raised) AS complaints_raised
    FROM exits_with_manager
    WHERE manager_name IS NOT NULL
    GROUP BY
        manager_name,
        shift
)

SELECT
    h.manager_name,
    h.shift,
    h.avg_monthly_headcount,
    COALESCE(e.exits, 0) AS exits,
    e.avg_tenure_years_at_exit,
    COALESCE(e.complaints_raised, 0) AS complaints_raised,
    ROUND(
        COALESCE(e.exits, 0)
        / NULLIF(h.avg_monthly_headcount, 0) * 100,
        2
    ) AS period_turnover_rate_pct
FROM manager_average_headcount h
LEFT JOIN manager_exits e
    ON h.manager_name = e.manager_name
   AND h.shift = e.shift
ORDER BY
    period_turnover_rate_pct DESC,
    h.manager_name;


-- ------------------------------------------------------------
-- 10. EXIT THEMES BY MANAGER
-- Question:
-- Do exit themes differ between Service Desk managers?
-- ------------------------------------------------------------

WITH exits_with_manager AS (
    SELECT
        e.employee_id,
        e.employee_name,
        e.job_title,
        e.shift,
        e.termination_date,
        e.primary_exit_theme,
        e.complaint_raised,
        e.complaint_type,
        w.manager_name
    FROM exit_interviews e
    LEFT JOIN workforce_monthly_snapshots w
        ON w.employee_id = e.employee_id
       AND w.snapshot_month = (
            SELECT MAX(w2.snapshot_month)
            FROM workforce_monthly_snapshots w2
            WHERE w2.employee_id = e.employee_id
              AND w2.snapshot_month <= LAST_DAY(e.termination_date)
       )
    WHERE e.department = '24/7 Service Desk'
      AND e.termination_date BETWEEN '2025-01-01' AND '2026-09-30'
)

SELECT
    manager_name,
    shift,
    primary_exit_theme,
    COUNT(*) AS exits,
    SUM(complaint_raised) AS complaints_raised
FROM exits_with_manager
WHERE manager_name IS NOT NULL
GROUP BY
    manager_name,
    shift,
    primary_exit_theme
ORDER BY
    manager_name,
    exits DESC,
    primary_exit_theme;


-- ------------------------------------------------------------
-- 11. POST-HIRE RETENTION BY SHIFT
-- Question:
-- Do employees hired into Overnight leave sooner than
-- employees hired into Day or Evening?
-- ------------------------------------------------------------

SELECT
    shift,
    COUNT(*) AS terminated_employees,
    ROUND(
        AVG(DATEDIFF(termination_date, original_hire_date) / 365.25),
        2
    ) AS avg_tenure_years_at_exit,
    ROUND(
        AVG(DATEDIFF(termination_date, original_hire_date) / 30.44),
        1
    ) AS avg_tenure_months_at_exit,
    SUM(
        CASE
            WHEN DATEDIFF(termination_date, original_hire_date) <= 365
            THEN 1
            ELSE 0
        END
    ) AS exits_within_1_year,
    ROUND(
        SUM(
            CASE
                WHEN DATEDIFF(termination_date, original_hire_date) <= 365
                THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS pct_exits_within_1_year
FROM employees
WHERE department = '24/7 Service Desk'
  AND employee_status = 'Terminated'
  AND termination_date BETWEEN '2025-01-01' AND '2026-09-30'
GROUP BY shift
ORDER BY avg_tenure_years_at_exit ASC;


-- ------------------------------------------------------------
-- 12. CURRENT SERVICE DESK TENURE BY SHIFT
-- Question:
-- Is the Overnight shift currently staffed with less tenured
-- employees than Day or Evening?
-- ------------------------------------------------------------

SELECT
    shift,
    COUNT(DISTINCT employee_id) AS current_headcount,
    ROUND(AVG(tenure_years), 2) AS avg_tenure_years,
    ROUND(MIN(tenure_years), 2) AS shortest_tenure_years,
    ROUND(MAX(tenure_years), 2) AS longest_tenure_years
FROM workforce_monthly_snapshots
WHERE department = '24/7 Service Desk'
  AND snapshot_month = '2026-09-30'
GROUP BY shift
ORDER BY avg_tenure_years ASC;


-- ------------------------------------------------------------
-- 13. INTERNAL MOBILITY AND PROMOTION BY SHIFT
-- Question:
-- Are Overnight Service Desk employees moving into other
-- shifts or receiving promotions, or do they tend to remain
-- on Overnight until they leave?
-- ------------------------------------------------------------

SELECT
    previous_shift,
    new_shift,
    action,
    internal_move,
    promotion_flag,
    COUNT(*) AS movement_count
FROM job_compensation_history
WHERE
    (
        previous_department = '24/7 Service Desk'
        OR new_department = '24/7 Service Desk'
    )
    AND (
        previous_shift IS NOT NULL
        OR new_shift IS NOT NULL
    )
GROUP BY
    previous_shift,
    new_shift,
    action,
    internal_move,
    promotion_flag
ORDER BY
    previous_shift,
    new_shift,
    movement_count DESC;


-- ------------------------------------------------------------
-- 14. TRAINING COMPLETION BY SHIFT
-- Question:
-- Do Service Desk employees on Overnight have different
-- training completion or overdue rates than other shifts?
-- ------------------------------------------------------------

SELECT
    shift,
    COUNT(*) AS training_records,
    SUM(
        CASE
            WHEN status = 'Completed' THEN 1
            ELSE 0
        END
    ) AS completed_records,
    SUM(
        CASE
            WHEN status = 'Overdue' THEN 1
            ELSE 0
        END
    ) AS overdue_records,
    SUM(
        CASE
            WHEN status = 'Assigned' THEN 1
            ELSE 0
        END
    ) AS assigned_records,
    ROUND(
        SUM(
            CASE
                WHEN status = 'Completed' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS completion_rate_pct,
    ROUND(
        SUM(
            CASE
                WHEN status = 'Overdue' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS overdue_rate_pct
FROM training_history
WHERE department = '24/7 Service Desk'
GROUP BY shift
ORDER BY completion_rate_pct ASC;


-- ------------------------------------------------------------
-- 15. TRAINING MIX BY SHIFT
-- Question:
-- What types of training are employees on each Service Desk
-- shift actually receiving?
-- ------------------------------------------------------------

SELECT
    shift,
    course,
    COUNT(*) AS training_records,
    SUM(
        CASE
            WHEN status = 'Completed' THEN 1
            ELSE 0
        END
    ) AS completed_records,
    SUM(
        CASE
            WHEN status = 'Overdue' THEN 1
            ELSE 0
        END
    ) AS overdue_records,
    SUM(
        CASE
            WHEN status = 'Assigned' THEN 1
            ELSE 0
        END
    ) AS assigned_records,
    ROUND(AVG(training_minutes), 1) AS avg_training_minutes
FROM training_history
WHERE department = '24/7 Service Desk'
GROUP BY
    shift,
    course
ORDER BY
    shift,
    training_records DESC,
    course;


-- ------------------------------------------------------------
-- 16. TRAINING COMPLETION BY MANAGER
-- Question:
-- Are Service Desk training completion gaps concentrated under
-- a specific manager, or are they more strongly tied to shift?
--
-- Manager is derived from the most recent workforce snapshot
-- on or before the training assigned date.
-- ------------------------------------------------------------

WITH training_with_manager AS (
    SELECT
        t.training_record_id,
        t.employee_id,
        t.shift,
        t.status,
        w.manager_name
    FROM training_history t
    LEFT JOIN workforce_monthly_snapshots w
        ON w.employee_id = t.employee_id
       AND w.snapshot_month = (
            SELECT MAX(w2.snapshot_month)
            FROM workforce_monthly_snapshots w2
            WHERE w2.employee_id = t.employee_id
              AND w2.snapshot_month <= LAST_DAY(t.assigned_date)
       )
    WHERE t.department = '24/7 Service Desk'
)

SELECT
    manager_name,
    shift,
    COUNT(*) AS training_records,
    SUM(
        CASE
            WHEN status = 'Completed' THEN 1
            ELSE 0
        END
    ) AS completed_records,
    SUM(
        CASE
            WHEN status = 'Overdue' THEN 1
            ELSE 0
        END
    ) AS overdue_records,
    SUM(
        CASE
            WHEN status = 'Assigned' THEN 1
            ELSE 0
        END
    ) AS assigned_records,
    ROUND(
        SUM(
            CASE
                WHEN status = 'Completed' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS completion_rate_pct,
    ROUND(
        SUM(
            CASE
                WHEN status = 'Overdue' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS overdue_rate_pct
FROM training_with_manager
GROUP BY
    manager_name,
    shift
ORDER BY
    completion_rate_pct ASC,
    manager_name;


-- ------------------------------------------------------------
-- 17. TRAINING COMPLETION BY MANAGER AND JOB ROLE
-- Question:
-- Does the training completion gap remain after comparing
-- employees in similar Service Desk roles?
-- ------------------------------------------------------------

WITH training_with_manager AS (
    SELECT
        t.training_record_id,
        t.employee_id,
        t.shift,
        t.status,
        w.manager_name,
        w.job_title
    FROM training_history t
    LEFT JOIN workforce_monthly_snapshots w
        ON w.employee_id = t.employee_id
       AND w.snapshot_month = (
            SELECT MAX(w2.snapshot_month)
            FROM workforce_monthly_snapshots w2
            WHERE w2.employee_id = t.employee_id
              AND w2.snapshot_month <= LAST_DAY(t.assigned_date)
       )
    WHERE t.department = '24/7 Service Desk'
)

SELECT
    manager_name,
    shift,
    job_title,
    COUNT(*) AS training_records,
    SUM(
        CASE
            WHEN status = 'Completed' THEN 1
            ELSE 0
        END
    ) AS completed_records,
    SUM(
        CASE
            WHEN status = 'Overdue' THEN 1
            ELSE 0
        END
    ) AS overdue_records,
    SUM(
        CASE
            WHEN status = 'Assigned' THEN 1
            ELSE 0
        END
    ) AS assigned_records,
    ROUND(
        SUM(
            CASE
                WHEN status = 'Completed' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS completion_rate_pct,
    ROUND(
        SUM(
            CASE
                WHEN status = 'Overdue' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS overdue_rate_pct
FROM training_with_manager
WHERE manager_name IS NOT NULL
GROUP BY
    manager_name,
    shift,
    job_title
ORDER BY
    shift,
    job_title,
    completion_rate_pct ASC;


-- ------------------------------------------------------------
-- 18. SERVICE DESK WORKFORCE STABILITY SUMMARY
-- Question:
-- What does the combined workforce picture look like across
-- Day, Evening, and Overnight Service Desk shifts?
-- ------------------------------------------------------------

WITH monthly_headcount AS (
    SELECT
        snapshot_month,
        shift,
        COUNT(DISTINCT employee_id) AS headcount
    FROM workforce_monthly_snapshots
    WHERE department = '24/7 Service Desk'
      AND shift IN ('Day', 'Evening', 'Overnight')
    GROUP BY
        snapshot_month,
        shift
),

average_headcount AS (
    SELECT
        shift,
        AVG(headcount) AS avg_monthly_headcount
    FROM monthly_headcount
    GROUP BY shift
),

terminations AS (
    SELECT
        shift,
        COUNT(*) AS terminated_employees,
        AVG(
            DATEDIFF(termination_date, original_hire_date) / 365.25
        ) AS avg_tenure_years_at_exit
    FROM employees
    WHERE department = '24/7 Service Desk'
      AND employee_status = 'Terminated'
      AND termination_date BETWEEN '2025-01-01' AND '2026-09-30'
      AND shift IN ('Day', 'Evening', 'Overnight')
    GROUP BY shift
),

current_tenure AS (
    SELECT
        shift,
        COUNT(DISTINCT employee_id) AS current_headcount,
        AVG(tenure_years) AS current_avg_tenure_years
    FROM workforce_monthly_snapshots
    WHERE department = '24/7 Service Desk'
      AND snapshot_month = '2026-09-30'
      AND shift IN ('Day', 'Evening', 'Overnight')
    GROUP BY shift
),

training AS (
    SELECT
        shift,
        COUNT(*) AS training_records,
        SUM(
            CASE
                WHEN status = 'Completed' THEN 1
                ELSE 0
            END
        ) AS completed_training,
        SUM(
            CASE
                WHEN status = 'Overdue' THEN 1
                ELSE 0
            END
        ) AS overdue_training
    FROM training_history
    WHERE department = '24/7 Service Desk'
      AND shift IN ('Day', 'Evening', 'Overnight')
    GROUP BY shift
),

recruiting AS (
    SELECT
        shift,
        COUNT(*) AS requisitions,
        AVG(days_to_fill) AS avg_days_to_fill,
        AVG(recruiting_cost) AS avg_recruiting_cost
    FROM recruiting_requisitions
    WHERE department = '24/7 Service Desk'
      AND shift IN ('Day', 'Evening', 'Overnight')
    GROUP BY shift
)

SELECT
    h.shift,

    ROUND(h.avg_monthly_headcount, 2)
        AS avg_monthly_headcount,

    COALESCE(t.terminated_employees, 0)
        AS terminated_employees,

    ROUND(
        COALESCE(t.terminated_employees, 0)
        / NULLIF(h.avg_monthly_headcount, 0) * 100,
        2
    ) AS period_turnover_rate_pct,

    ROUND(t.avg_tenure_years_at_exit, 2)
        AS avg_tenure_years_at_exit,

    c.current_headcount,

    ROUND(c.current_avg_tenure_years, 2)
        AS current_avg_tenure_years,

    ROUND(
        tr.completed_training
        / NULLIF(tr.training_records, 0) * 100,
        2
    ) AS training_completion_rate_pct,

    ROUND(
        tr.overdue_training
        / NULLIF(tr.training_records, 0) * 100,
        2
    ) AS training_overdue_rate_pct,

    r.requisitions,

    ROUND(r.avg_days_to_fill, 2)
        AS avg_days_to_fill,

    ROUND(r.avg_recruiting_cost, 2)
        AS avg_recruiting_cost

FROM average_headcount h

LEFT JOIN terminations t
    ON h.shift = t.shift

LEFT JOIN current_tenure c
    ON h.shift = c.shift

LEFT JOIN training tr
    ON h.shift = tr.shift

LEFT JOIN recruiting r
    ON h.shift = r.shift

ORDER BY period_turnover_rate_pct DESC;


-- ============================================================
-- DATA QUALITY / FOLLOW-UP ITEMS
-- ============================================================
-- Review after completion of the primary analysis.
--
-- 1. One Overnight exit could not be linked to a manager
--    because available workforce history did not predate exit.
--
-- 2. Eight training records could not be linked to a manager
--    at the training assignment date.
--
-- 3. Formal G4 pay bands do not align with actual compensation
--    for some advanced technical support roles.
--
-- 4. Recruiting data contains only Accepted outcomes and does
--    not represent a complete applicant or unsuccessful-search
--    funnel.
--
-- These items require separate validation before final findings.
-- ============================================================