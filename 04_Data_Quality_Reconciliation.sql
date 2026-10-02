USE northstar;

-- ============================================================
-- NORTHSTAR IT
-- DATA QUALITY RECONCILIATION
-- ============================================================
-- Purpose:
-- Document and verify data quality discrepancies identified
-- during workforce, turnover, retention, compensation, and
-- recruiting analysis.
--
-- Reconciliation approach:
-- Identify discrepancy -> Test source data -> Classify issue
-- -> Document impact on analysis
-- ============================================================


-- ------------------------------------------------------------
-- 1. TRAINING MANAGER COVERAGE CHECK
-- Question:
-- Which Service Desk training records cannot be linked to a
-- manager using the most recent workforce snapshot available
-- on or before the training assignment date?
--
-- Finding:
-- All unmatched records belong to Reese Bell.
-- No workforce snapshot is available for the relevant period.
--
-- Classification:
-- Source coverage / timing limitation.
--
-- Analytical impact:
-- These records cannot be assigned to a manager and should not
-- be used to evaluate manager-level training performance.
-- ------------------------------------------------------------

WITH training_with_manager AS (
    SELECT
        t.training_record_id,
        t.employee_id,
        t.employee_name,
        t.shift,
        t.course,
        t.assigned_date,
        t.due_date,
        t.status,
        w.snapshot_month,
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
    employee_id,
    employee_name,
    shift,
    course,
    assigned_date,
    due_date,
    status,
    snapshot_month
FROM training_with_manager
WHERE manager_name IS NULL
ORDER BY
    employee_id,
    assigned_date,
    course;


-- ------------------------------------------------------------
-- 2. PAY BAND ALIGNMENT DETAIL CHECK
-- Question:
-- Do Support Technician II and Senior Support Technician
-- compensation records fall outside the documented G4 range?
--
-- Finding:
-- Multiple records are above the documented G4 maximum.
--
-- Note:
-- This detailed query includes historical compensation records,
-- including some records that predate the current pay band.
-- A second reconciliation check below limits the comparison to
-- records effective on or after the pay band effective date.
-- ------------------------------------------------------------

SELECT
    j.employee_id,
    j.new_position,
    j.new_shift,
    j.effective_date,
    j.new_annualized_pay,
    pb.grade,
    pb.range_minimum,
    pb.range_midpoint,
    pb.range_maximum,
    pb.effective_date AS pay_band_effective_date,
    CASE
        WHEN j.new_annualized_pay < pb.range_minimum THEN 'Below Range'
        WHEN j.new_annualized_pay > pb.range_maximum THEN 'Above Range'
        ELSE 'Within Range'
    END AS range_status
FROM job_compensation_history j
JOIN position_pay_bands pb
    ON j.new_position = pb.position_title
WHERE j.new_position IN (
    'Support Technician II',
    'Senior Support Technician'
)
  AND j.new_annualized_pay IS NOT NULL
ORDER BY
    j.new_position,
    j.new_annualized_pay DESC;


-- ------------------------------------------------------------
-- 3. PAY BAND ALIGNMENT POST EFFECTIVE DATE
-- Question:
-- Does the above-range compensation pattern remain when only
-- compensation actions effective on or after the current pay
-- band effective date are included?
--
-- Finding:
-- Yes. All reviewed Support Technician II and Senior Support
-- Technician compensation records effective on or after the
-- 2025-01-01 pay band effective date remain above the stated
-- $61,000 G4 maximum.
--
-- Classification:
-- Verified compensation structure / governance discrepancy.
--
-- Possible causes requiring business review:
-- Outdated pay band
-- Incorrect grade assignment
-- Undocumented premium or exception structure
-- Compensation practices operating outside documented ranges
--
-- Analytical impact:
-- The formal G4 band should not be treated as fully aligned
-- with actual compensation practices until reconciled.
-- ------------------------------------------------------------

SELECT
    j.new_position,
    j.new_shift,
    COUNT(*) AS compensation_records,
    ROUND(MIN(j.new_annualized_pay), 2) AS lowest_pay,
    ROUND(AVG(j.new_annualized_pay), 2) AS avg_pay,
    ROUND(MAX(j.new_annualized_pay), 2) AS highest_pay,
    pb.range_minimum,
    pb.range_midpoint,
    pb.range_maximum,
    SUM(
        CASE
            WHEN j.new_annualized_pay > pb.range_maximum THEN 1
            ELSE 0
        END
    ) AS above_range_records
FROM job_compensation_history j
JOIN position_pay_bands pb
    ON j.new_position = pb.position_title
WHERE j.new_position IN (
    'Support Technician II',
    'Senior Support Technician'
)
  AND j.new_annualized_pay IS NOT NULL
  AND j.effective_date >= pb.effective_date
GROUP BY
    j.new_position,
    j.new_shift,
    pb.range_minimum,
    pb.range_midpoint,
    pb.range_maximum
ORDER BY
    j.new_position,
    j.new_shift;
	-- ------------------------------------------------------------
-- 4. RECRUITING OUTCOME COVERAGE CHECK
-- Question:
-- Does the recruiting table contain a full recruiting funnel
-- or only completed accepted requisitions?
-- ------------------------------------------------------------

SELECT
    outcome,
    COUNT(*) AS requisition_count
FROM recruiting_requisitions
GROUP BY outcome
ORDER BY outcome;
-- ------------------------------------------------------------
-- 5. EXIT MANAGER COVERAGE CHECK
-- Question:
-- Which Service Desk exits cannot be linked to a manager using
-- the most recent workforce snapshot available on or before
-- the employee's termination date?
-- ------------------------------------------------------------

WITH exits_with_manager AS (
    SELECT
        e.employee_id,
        e.employee_name,
        e.shift,
        e.termination_date,
        e.termination_type,
        e.primary_exit_theme,
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
)

SELECT
    employee_id,
    employee_name,
    shift,
    termination_date,
    termination_type,
    primary_exit_theme,
    snapshot_month,
    manager_name
FROM exits_with_manager
WHERE manager_name IS NULL
ORDER BY termination_date;