-- ============================================================
-- PEOPLEPULSE AI — MYSQL SCHEMA
-- Compatible with: MySQL 8.0+ (requires CTE and window function support)
-- ============================================================

CREATE DATABASE IF NOT EXISTS peoplepulse CHARACTER SET utf8mb4;
USE peoplepulse;

-- MySQL has no schemas-as-namespaces like Postgres; using table prefixes instead
-- hr_*, rpt_*, audit_*

CREATE TABLE hr_ref_department (
    department_id       SMALLINT AUTO_INCREMENT PRIMARY KEY,
    department_name     VARCHAR(100) NOT NULL UNIQUE,
    pay_multiplier       DECIMAL(5,4) NOT NULL DEFAULT 1.0000
                          CHECK (pay_multiplier BETWEEN 0.5 AND 2.5),
    base_attrition_rate  DECIMAL(5,4) NOT NULL DEFAULT 0.1500
                          CHECK (base_attrition_rate BETWEEN 0 AND 1),
    is_active            TINYINT(1) NOT NULL DEFAULT 1,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE hr_ref_job_level (
    level_code      CHAR(2) PRIMARY KEY,
    level_name      VARCHAR(50) NOT NULL,
    salary_band_min INT NOT NULL,
    salary_band_max INT NOT NULL,
    career_track    VARCHAR(30) NOT NULL,
    sort_order      SMALLINT NOT NULL,
    CHECK (salary_band_min < salary_band_max),
    CHECK (career_track IN ('Individual-Contributor','Manager','Executive'))
) ENGINE=InnoDB;

CREATE TABLE hr_ref_location (
    location_id    SMALLINT AUTO_INCREMENT PRIMARY KEY,
    location_name  VARCHAR(100) NOT NULL UNIQUE,
    city           VARCHAR(100) NOT NULL,
    country        VARCHAR(60) NOT NULL,
    region         VARCHAR(20) NOT NULL,
    geo_multiplier DECIMAL(5,4) NOT NULL DEFAULT 1.0000,
    is_active      TINYINT(1) NOT NULL DEFAULT 1,
    CHECK (region IN ('Northeast','South','West','Midwest','Remote','EMEA','Canada'))
) ENGINE=InnoDB;

CREATE TABLE hr_ref_recruitment_source (
    source_id    SMALLINT AUTO_INCREMENT PRIMARY KEY,
    source_name  VARCHAR(60) NOT NULL UNIQUE,
    source_type  VARCHAR(30) NOT NULL,
    is_active    TINYINT(1) NOT NULL DEFAULT 1,
    CHECK (source_type IN ('Digital','Referral','Agency','Campus','Internal','Direct'))
) ENGINE=InnoDB;

CREATE TABLE hr_ref_performance_rating (
    rating_value      SMALLINT PRIMARY KEY,
    rating_label      VARCHAR(30) NOT NULL,
    is_high_performer TINYINT(1) NOT NULL DEFAULT 0,
    CHECK (rating_value BETWEEN 1 AND 5)
) ENGINE=InnoDB;

CREATE TABLE hr_employee (
    employee_id          VARCHAR(10) PRIMARY KEY,
    employee_name        VARCHAR(200) NOT NULL,
    age                  SMALLINT NOT NULL CHECK (age BETWEEN 16 AND 80),
    gender               VARCHAR(20) NOT NULL CHECK (gender IN ('Male','Female','Non-binary')),

    department_id        SMALLINT NOT NULL,
    job_role              VARCHAR(100) NOT NULL,
    job_level             CHAR(2) NOT NULL,
    manager_id            VARCHAR(10) NULL,
    location_id           SMALLINT NOT NULL,

    work_mode             VARCHAR(20) NOT NULL CHECK (work_mode IN ('On-site','Hybrid','Remote')),
    years_at_company      DECIMAL(5,2) NOT NULL CHECK (years_at_company >= 0),
    salary                INT NOT NULL CHECK (salary BETWEEN 30000 AND 2000000),
    bonus                 INT NOT NULL DEFAULT 0 CHECK (bonus >= 0),
    recruitment_source_id SMALLINT NOT NULL,

    performance_rating    SMALLINT NOT NULL,
    performance_label     VARCHAR(30) NOT NULL,
    attendance_pct        DECIMAL(5,2) NOT NULL CHECK (attendance_pct BETWEEN 0 AND 100),
    training_hours        DECIMAL(6,2) NOT NULL CHECK (training_hours >= 0),
    engagement_score      DECIMAL(6,2) NOT NULL CHECK (engagement_score BETWEEN 0 AND 100),
    satisfaction_score    DECIMAL(6,2) NOT NULL CHECK (satisfaction_score BETWEEN 0 AND 100),

    promotions            SMALLINT NOT NULL DEFAULT 0 CHECK (promotions >= 0),
    leave_count           SMALLINT NOT NULL DEFAULT 0 CHECK (leave_count BETWEEN 0 AND 365),

    attrition             VARCHAR(3) NOT NULL CHECK (attrition IN ('Yes','No')),
    exit_reason           VARCHAR(60) NULL,

    loaded_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_emp_dept FOREIGN KEY (department_id) REFERENCES hr_ref_department(department_id),
    CONSTRAINT fk_emp_level FOREIGN KEY (job_level) REFERENCES hr_ref_job_level(level_code),
    CONSTRAINT fk_emp_location FOREIGN KEY (location_id) REFERENCES hr_ref_location(location_id),
    CONSTRAINT fk_emp_source FOREIGN KEY (recruitment_source_id) REFERENCES hr_ref_recruitment_source(source_id),
    CONSTRAINT fk_emp_perf FOREIGN KEY (performance_rating) REFERENCES hr_ref_performance_rating(rating_value),
    CONSTRAINT fk_emp_manager FOREIGN KEY (manager_id) REFERENCES hr_employee(employee_id)
) ENGINE=InnoDB;

CREATE INDEX ix_employee_department ON hr_employee (department_id);
CREATE INDEX ix_employee_attrition  ON hr_employee (attrition);
CREATE INDEX ix_employee_job_level  ON hr_employee (job_level);
CREATE INDEX ix_employee_manager    ON hr_employee (manager_id);
CREATE INDEX ix_employee_location   ON hr_employee (location_id);

CREATE TABLE hr_flight_risk_score (
    score_id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id        VARCHAR(10) NOT NULL,
    scoring_date       DATE NOT NULL DEFAULT (CURRENT_DATE),
    risk_score         DECIMAL(5,2) NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_tier          VARCHAR(20) NOT NULL CHECK (risk_tier IN ('Critical','High','Medium','Low')),
    model_probability  DECIMAL(8,6) NOT NULL,
    top_driver_1       VARCHAR(150),
    top_driver_2       VARCHAR(150),
    top_driver_3       VARCHAR(150),
    recommended_action VARCHAR(250),
    model_version      VARCHAR(20) NOT NULL DEFAULT 'v1.0',
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_frs_emp_date (employee_id, scoring_date),
    CONSTRAINT fk_frs_employee FOREIGN KEY (employee_id) REFERENCES hr_employee(employee_id)
) ENGINE=InnoDB;

CREATE TABLE audit_employee_change_log (
    change_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id    VARCHAR(10) NOT NULL,
    changed_column VARCHAR(100) NOT NULL,
    old_value      TEXT,
    new_value      TEXT,
    changed_by     VARCHAR(100) NOT NULL,
    changed_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    change_reason  VARCHAR(200)
) ENGINE=InnoDB;

CREATE TABLE hr_app_user (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    email          VARCHAR(200) NOT NULL UNIQUE,
    full_name      VARCHAR(200) NOT NULL,
    password_hash  VARCHAR(64) NOT NULL,
    role           VARCHAR(30) NOT NULL CHECK (role IN ('CEO/CHRO','HR Director','HRBP','Total Rewards','Admin')),
    department_id  SMALLINT NULL,
    is_active      TINYINT(1) NOT NULL DEFAULT 1,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_dept FOREIGN KEY (department_id) REFERENCES hr_ref_department(department_id)
) ENGINE=InnoDB;

-- ============================================================
-- REFERENCE DATA SEED (identical values to PostgreSQL version)
-- ============================================================

INSERT INTO hr_ref_department (department_name, pay_multiplier, base_attrition_rate) VALUES
    ('Engineering',        1.3500, 0.1400),
    ('Product',            1.4000, 0.1300),
    ('Sales',              1.1000, 0.2000),
    ('Marketing',          1.0500, 0.1600),
    ('Finance',            1.1500, 0.0900),
    ('Human Resources',    0.9500, 0.1200),
    ('Operations',         0.9000, 0.1700),
    ('Customer Success',   0.8800, 0.2200),
    ('Legal & Compliance', 1.3000, 0.0700),
    ('Data & Analytics',   1.3800, 0.1300),
    ('IT Infrastructure',  1.1000, 0.1100);

INSERT INTO hr_ref_job_level (level_code, level_name, salary_band_min, salary_band_max, career_track, sort_order) VALUES
    ('L2','Associate',         55000,  85000, 'Individual-Contributor', 1),
    ('L3','Specialist',        85000, 110000, 'Individual-Contributor', 2),
    ('L4','Senior Specialist', 110000,140000, 'Individual-Contributor', 3),
    ('L5','Staff / Principal', 140000,175000, 'Manager',               4),
    ('L6','Director',          175000,230000, 'Manager',               5),
    ('L7','Vice President',    230000,320000, 'Executive',             6),
    ('L8','C-Suite',           320000,500000, 'Executive',             7);

INSERT INTO hr_ref_location (location_name, city, country, region, geo_multiplier) VALUES
    ('New York, NY',     'New York',     'USA',    'Northeast', 1.2800),
    ('San Francisco, CA','San Francisco','USA',    'West',      1.3000),
    ('Austin, TX',       'Austin',       'USA',    'South',     1.0500),
    ('Seattle, WA',      'Seattle',      'USA',    'West',      1.2200),
    ('Chicago, IL',      'Chicago',      'USA',    'Midwest',   1.0800),
    ('Boston, MA',       'Boston',       'USA',    'Northeast', 1.1800),
    ('Denver, CO',       'Denver',       'USA',    'West',      1.0200),
    ('Atlanta, GA',      'Atlanta',      'USA',    'South',     0.9700),
    ('Remote - US',      'Remote',       'USA',    'Remote',    0.9500),
    ('London, UK',       'London',       'UK',     'EMEA',      1.1500),
    ('Toronto, Canada',  'Toronto',      'Canada', 'Canada',    0.8800);

INSERT INTO hr_ref_recruitment_source (source_name, source_type) VALUES
    ('LinkedIn',          'Digital'),
    ('Employee Referral', 'Referral'),
    ('Company Website',   'Direct'),
    ('Indeed',            'Digital'),
    ('Recruiter/Agency',  'Agency'),
    ('University Campus', 'Campus'),
    ('Glassdoor',         'Digital'),
    ('Internal Transfer', 'Internal');

INSERT INTO hr_ref_performance_rating (rating_value, rating_label, is_high_performer) VALUES
    (1, 'Unacceptable',         0),
    (2, 'Below Expectations',   0),
    (3, 'Meets Expectations',   0),
    (4, 'Exceeds Expectations', 1),
    (5, 'Distinguished',        1);

-- ============================================================
-- VIEWS
-- Note: Use scripts/load_data.py with DB_ENGINE=mysql — it auto-detects
-- table naming (hr_employee vs hr.employee) is NOT automatic; for MySQL
-- set DATABASE_URL explicitly and the loader's `schema="hr"` argument
-- should be changed to schema=None with table="hr_employee" — see
-- inline comment in scripts/load_data.py for the MySQL adaptation note.
-- ============================================================

CREATE OR REPLACE VIEW rpt_vw_employee_full AS
SELECT
    e.employee_id, e.employee_name, e.age, e.gender,
    CASE
        WHEN e.age < 25 THEN 'Under 25' WHEN e.age < 35 THEN '25-34'
        WHEN e.age < 45 THEN '35-44' WHEN e.age < 55 THEN '45-54'
        WHEN e.age < 65 THEN '55-64' ELSE '65+'
    END AS age_band,
    d.department_name AS department, e.job_role, e.job_level, jl.level_name, jl.career_track,
    l.location_name AS location, l.region, e.work_mode, e.manager_id, e.years_at_company,
    CASE
        WHEN e.years_at_company < 1 THEN '< 1 Year' WHEN e.years_at_company < 2 THEN '1-2 Years'
        WHEN e.years_at_company < 3 THEN '2-3 Years' WHEN e.years_at_company < 5 THEN '3-5 Years'
        WHEN e.years_at_company < 8 THEN '5-8 Years' WHEN e.years_at_company < 12 THEN '8-12 Years'
        ELSE '12+ Years'
    END AS tenure_band,
    e.salary, e.bonus, e.salary + e.bonus AS total_comp,
    ROUND(e.salary / (jl.salary_band_min + (jl.salary_band_max-jl.salary_band_min)/2), 4) AS compa_ratio,
    rs.source_name AS recruitment_source, e.performance_rating, e.performance_label, pr.is_high_performer,
    e.attendance_pct, e.training_hours, e.engagement_score, e.satisfaction_score,
    CASE
        WHEN e.engagement_score >= 75 THEN 'Engaged' WHEN e.engagement_score >= 60 THEN 'Low Risk'
        WHEN e.engagement_score >= 40 THEN 'Medium Risk' ELSE 'High Risk'
    END AS engagement_tier,
    e.promotions, e.leave_count, ROUND(e.years_at_company/2.8 - e.promotions, 2) AS promotion_gap,
    e.attrition, CASE e.attrition WHEN 'Yes' THEN 1 ELSE 0 END AS attrition_flag, e.exit_reason,
    CASE WHEN e.attrition='Yes' AND pr.is_high_performer=1 THEN 1 ELSE 0 END AS is_regrettable_exit
FROM hr_employee e
JOIN hr_ref_department d ON e.department_id = d.department_id
JOIN hr_ref_job_level jl ON e.job_level = jl.level_code
JOIN hr_ref_location l ON e.location_id = l.location_id
JOIN hr_ref_recruitment_source rs ON e.recruitment_source_id = rs.source_id
JOIN hr_ref_performance_rating pr ON e.performance_rating = pr.rating_value;

CREATE OR REPLACE VIEW rpt_vw_department_kpis AS
SELECT
    d.department_name,
    COUNT(*) AS total_headcount,
    SUM(CASE WHEN e.attrition='No' THEN 1 ELSE 0 END) AS active_headcount,
    SUM(CASE WHEN e.attrition='Yes' THEN 1 ELSE 0 END) AS attrition_count,
    ROUND(100.0 * SUM(CASE WHEN e.attrition='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_rate_pct,
    ROUND(AVG(e.salary)) AS avg_salary,
    ROUND(AVG(e.engagement_score), 2) AS avg_engagement_score,
    ROUND(AVG(e.satisfaction_score), 2) AS avg_satisfaction_score,
    ROUND(AVG(e.performance_rating), 3) AS avg_performance_rating,
    ROUND(AVG(e.attendance_pct), 2) AS avg_attendance_pct,
    ROUND(AVG(e.training_hours), 2) AS avg_training_hours,
    ROUND(AVG(e.years_at_company), 2) AS avg_tenure_years,
    SUM(CASE WHEN e.performance_rating >= 4 THEN 1 ELSE 0 END) AS high_performer_count,
    ROUND(100.0 * SUM(CASE WHEN e.performance_rating >= 4 THEN 1 ELSE 0 END) / COUNT(*), 2) AS high_performer_pct,
    SUM(CASE WHEN e.engagement_score < 40 THEN 1 ELSE 0 END) AS high_flight_risk_count,
    ROUND(100.0 * SUM(CASE WHEN e.attrition='Yes' AND e.performance_rating>=4 THEN 1 ELSE 0 END) / COUNT(*), 2) AS regrettable_attrition_pct
FROM hr_employee e
JOIN hr_ref_department d ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name;

-- ============================================================
-- END OF MYSQL SCHEMA
-- ============================================================
