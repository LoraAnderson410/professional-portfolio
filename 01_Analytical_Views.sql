USE northstar;

-- ============================================
-- NORTHSTAR ANALYTICAL VIEWS
-- ============================================

-- --------------------------------------------
-- Workforce Monthly Analytical View
-- --------------------------------------------

CREATE OR REPLACE VIEW vw_workforce_monthly AS

SELECT
    w.snapshot_month,
    w.employee_id,
    w.department,
    w.job_title,
    w.job_level,
    w.manager_id,
    w.manager_name,
    w.work_location,
    w.shift,
    w.pay_type,
    w.fte,
    w.tenure_years,

    a.scheduled_hours,
    a.actual_worked_hours,
    a.overtime_hours,
    a.pto_hours,
    a.unscheduled_absence_hours,
    a.late_callout_events,

    CASE
        WHEN a.scheduled_hours = 0 THEN NULL
        ELSE ROUND(a.overtime_hours / a.scheduled_hours * 100, 2)
    END AS overtime_rate_pct,

    CASE
        WHEN a.scheduled_hours = 0 THEN NULL
        ELSE ROUND(a.pto_hours / a.scheduled_hours * 100, 2)
    END AS pto_rate_pct,

    CASE
        WHEN a.scheduled_hours = 0 THEN NULL
        ELSE ROUND(a.unscheduled_absence_hours / a.scheduled_hours * 100, 2)
    END AS unscheduled_absence_rate_pct

FROM workforce_monthly_snapshots w

LEFT JOIN attendance_overtime_monthly a
    ON w.employee_id = a.employee_id
   AND w.snapshot_month = a.month_end;


-- --------------------------------------------
-- Preview Workforce Monthly View
-- --------------------------------------------

SELECT *
FROM vw_workforce_monthly
ORDER BY snapshot_month DESC, employee_id
LIMIT 50;


-- --------------------------------------------
-- Validate Workforce Monthly View
-- --------------------------------------------

SELECT
    COUNT(*) AS view_rows,
    COUNT(DISTINCT CONCAT(employee_id, '|', snapshot_month)) AS unique_employee_months,
    SUM(scheduled_hours IS NULL) AS missing_attendance_rows,
    MIN(snapshot_month) AS first_month,
    MAX(snapshot_month) AS last_month
FROM vw_workforce_monthly;