-- ============================================================
-- PEOPLEPULSE AI — DATABASE VALIDATION QUERIES
-- Run after schema deployment + data load to confirm correctness.
-- Written for PostgreSQL; MySQL users replace "hr." prefix with "hr_"
-- and remove schema-qualification (see inline notes).
-- ============================================================

-- ── 1. ROW COUNT CHECKS ──────────────────────────────────────
-- Expected: 10,000 employees, 11 departments, 7 levels, 11 locations,
-- 8 recruitment sources, 5 performance ratings.

SELECT 'hr.employee' AS table_name, COUNT(*) AS row_count, 10000 AS expected FROM hr.employee
UNION ALL
SELECT 'hr.ref_department', COUNT(*), 11 FROM hr.ref_department
UNION ALL
SELECT 'hr.ref_job_level', COUNT(*), 7 FROM hr.ref_job_level
UNION ALL
SELECT 'hr.ref_location', COUNT(*), 11 FROM hr.ref_location
UNION ALL
SELECT 'hr.ref_recruitment_source', COUNT(*), 8 FROM hr.ref_recruitment_source
UNION ALL
SELECT 'hr.ref_performance_rating', COUNT(*), 5 FROM hr.ref_performance_rating;

-- PASS CONDITION: every row_count matches its expected value exactly.


-- ── 2. REFERENTIAL INTEGRITY CHECKS ──────────────────────────
-- Expected: 0 rows returned by every query below (no orphaned FKs)

SELECT 'orphaned_department' AS issue, COUNT(*) AS count
FROM hr.employee e LEFT JOIN hr.ref_department d ON e.department_id = d.department_id
WHERE d.department_id IS NULL
UNION ALL
SELECT 'orphaned_location', COUNT(*)
FROM hr.employee e LEFT JOIN hr.ref_location l ON e.location_id = l.location_id
WHERE l.location_id IS NULL
UNION ALL
SELECT 'orphaned_manager', COUNT(*)
FROM hr.employee e LEFT JOIN hr.employee m ON e.manager_id = m.employee_id
WHERE e.manager_id IS NOT NULL AND m.employee_id IS NULL
UNION ALL
SELECT 'self_managing_employee', COUNT(*)
FROM hr.employee WHERE employee_id = manager_id;

-- PASS CONDITION: all counts = 0


-- ── 3. NULL / COMPLETENESS CHECKS ────────────────────────────
-- Expected: 0 unexpected NULLs in NOT NULL-equivalent business columns

SELECT
    SUM(CASE WHEN employee_name IS NULL OR employee_name = '' THEN 1 ELSE 0 END) AS null_names,
    SUM(CASE WHEN salary IS NULL OR salary <= 0 THEN 1 ELSE 0 END) AS bad_salaries,
    SUM(CASE WHEN attrition NOT IN ('Yes','No') THEN 1 ELSE 0 END) AS bad_attrition_flag,
    SUM(CASE WHEN attrition = 'Yes' AND exit_reason IS NULL THEN 1 ELSE 0 END) AS attrited_missing_reason
FROM hr.employee;

-- PASS CONDITION: all four columns return 0


-- ── 4. RANGE / DOMAIN CHECKS ──────────────────────────────────
-- Expected: 0 rows — confirms CHECK constraints are actually enforced
-- (useful if data was loaded via a path that bypasses constraints)

SELECT COUNT(*) AS out_of_range_rows FROM hr.employee
WHERE age NOT BETWEEN 16 AND 80
   OR attendance_pct NOT BETWEEN 0 AND 100
   OR engagement_score NOT BETWEEN 0 AND 100
   OR satisfaction_score NOT BETWEEN 0 AND 100
   OR performance_rating NOT BETWEEN 1 AND 5
   OR years_at_company < 0;

-- PASS CONDITION: 0


-- ── 5. BUSINESS LOGIC SANITY CHECKS ──────────────────────────
-- Expected ranges based on Phase 3 dataset design documentation

SELECT
    ROUND(100.0 * SUM(CASE WHEN attrition='Yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS attrition_rate_pct,
    ROUND(AVG(salary)) AS avg_salary,
    ROUND(AVG(engagement_score), 1) AS avg_engagement,
    ROUND(AVG(years_at_company), 1) AS avg_tenure
FROM hr.employee;

-- PASS CONDITION (per Phase 3 documented design):
--   attrition_rate_pct  ≈ 23.8  (acceptable range: 22.0 - 25.5)
--   avg_salary          ≈ 169,953  (acceptable range: 165,000 - 175,000)
--   avg_engagement      ≈ 67.3  (acceptable range: 65.0 - 70.0)
--   avg_tenure          ≈ 2.7   (acceptable range: 2.3 - 3.1)
-- Any value outside these ranges suggests the CSV load did not complete
-- correctly, or a non-default random seed was used during generation.


-- ── 6. VIEW VALIDATION ────────────────────────────────────────
-- Confirms the analytical views resolve without error and return data

SELECT COUNT(*) AS vw_employee_full_rows FROM rpt.vw_employee_full;       -- expect 10000
SELECT COUNT(*) AS vw_department_kpis_rows FROM rpt.vw_department_kpis;  -- expect 11
SELECT COUNT(*) AS vw_pay_equity_rows FROM rpt.vw_pay_equity;            -- expect ~21 (7 levels x up to 3 genders)


-- ── 7. ORG HIERARCHY WALKABILITY CHECK ───────────────────────
-- Confirms every employee's manager chain eventually terminates
-- (no infinite loops) — uses a recursive CTE with a depth guard

WITH RECURSIVE org_chain AS (
    SELECT employee_id, manager_id, 0 AS depth
    FROM hr.employee
    WHERE manager_id IS NULL
    UNION ALL
    SELECT e.employee_id, e.manager_id, oc.depth + 1
    FROM hr.employee e
    JOIN org_chain oc ON e.manager_id = oc.employee_id
    WHERE oc.depth < 15  -- guard against cycles; org should be <8 levels deep
)
SELECT MAX(depth) AS max_org_depth, COUNT(*) AS employees_reached
FROM org_chain;

-- PASS CONDITION: employees_reached = 10000 (everyone is reachable from
-- the top of the org with no cycles); max_org_depth should be well under 15


-- ── 8. FLIGHT RISK SCORE VALIDATION (after running ML pipeline) ──
-- Confirms risk tiers correlate monotonically with actual attrition
-- (mirrors the validation table from ml_models/train_attrition_model.py)

SELECT
    frs.risk_tier,
    COUNT(*) AS employee_count,
    ROUND(AVG(frs.model_probability)*100, 1) AS avg_predicted_prob_pct,
    ROUND(100.0 * SUM(CASE WHEN e.attrition='Yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS actual_attrition_rate_pct
FROM hr.flight_risk_score frs
JOIN hr.employee e ON frs.employee_id = e.employee_id
GROUP BY frs.risk_tier
ORDER BY CASE frs.risk_tier
    WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 WHEN 'High' THEN 3 WHEN 'Critical' THEN 4 END;

-- PASS CONDITION: actual_attrition_rate_pct must increase monotonically
-- from Low -> Medium -> High -> Critical (per Phase 8 methodology).
-- Reference values from the documented model run:
--   Low: 16.1% | Medium: 25.3% | High: 35.4% | Critical: 54.4%

-- ============================================================
-- MYSQL ADAPTATION NOTES
-- ============================================================
-- 1. Replace "hr.employee" with "hr_employee" (and similarly for all
--    other hr.* / rpt.* / audit.* references) throughout this file.
-- 2. MySQL 8.0+ supports WITH RECURSIVE identically to Postgres for
--    query #7 — no syntax change needed beyond the table name prefix.
-- 3. MySQL's information_schema can be used for an equivalent FK-orphan
--    check via foreign key constraint introspection if preferred over
--    the explicit LEFT JOIN pattern above.
-- ============================================================
