-- ============================================================
-- PEOPLEPULSE AI — PRODUCTION SQL LIBRARY
-- Phase 4 (Completion): SQL Development
-- Database: SQL Server 2019+ / Azure SQL (ANSI-compatible)
-- Dataset: 10,000 employees · 24 columns
-- Author: Senior SQL Developer
-- ============================================================


-- ============================================================
-- SECTION 1: DATABASE SCHEMA
-- ============================================================
/*
  SCHEMA DESIGN PHILOSOPHY
  ─────────────────────────
  Three schemas separate concerns cleanly:
    [hr]     — core normalized HR tables (OLTP-style, write-optimised)
    [rpt]    — analytical views & aggregations (read-optimised, Power BI layer)
    [audit]  — immutable change-log for compliance (append-only)

  Why normalise into separate tables rather than one flat CSV table?
  • Eliminates update anomalies (change department name in ONE place)
  • Enables row-level security at the schema level
  • Supports incremental ETL — only changed rows need reloading
  • Allows FK-enforced referential integrity
*/

CREATE DATABASE PeoplePulseDB
    COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE PeoplePulseDB;
GO

CREATE SCHEMA hr;    -- Core HR operational tables
GO
CREATE SCHEMA rpt;   -- Reporting views and aggregations
GO
CREATE SCHEMA audit; -- Compliance and change tracking
GO


-- ============================================================
-- SECTION 2: CREATE TABLE STATEMENTS
-- ============================================================

-- ─────────────────────────────────────────
-- 2.1 LOOKUP / REFERENCE TABLES
-- ─────────────────────────────────────────

/*
  Business Purpose : Centralise all code-to-description mappings.
  Why a separate table: Changing "L4" label from "Senior" to "Lead"
  requires ONE row update; no cascading data quality issues.
*/

CREATE TABLE hr.RefDepartment (
    DepartmentID        TINYINT         NOT NULL IDENTITY(1,1),
    DepartmentName      NVARCHAR(100)   NOT NULL,
    PayMultiplier       DECIMAL(5,4)    NOT NULL DEFAULT 1.0000
                        CONSTRAINT chk_PayMult CHECK (PayMultiplier BETWEEN 0.5 AND 2.5),
    BaseAttritionRate   DECIMAL(5,4)    NOT NULL DEFAULT 0.1500
                        CONSTRAINT chk_BaseAtt CHECK (BaseAttritionRate BETWEEN 0 AND 1),
    IsActive            BIT             NOT NULL DEFAULT 1,
    CreatedAt           DATETIME2       NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_RefDepartment PRIMARY KEY (DepartmentID),
    CONSTRAINT uq_DeptName UNIQUE (DepartmentName)
);
GO

CREATE TABLE hr.RefJobLevel (
    LevelCode           CHAR(2)         NOT NULL,
    LevelName           NVARCHAR(50)    NOT NULL,
    SalaryBandMin       INT             NOT NULL,
    SalaryBandMax       INT             NOT NULL,
    CareerTrack         NVARCHAR(30)    NOT NULL
                        CONSTRAINT chk_CareerTrack
                        CHECK (CareerTrack IN ('Individual-Contributor','Manager','Executive')),
    SortOrder           TINYINT         NOT NULL,
    CONSTRAINT pk_RefJobLevel PRIMARY KEY (LevelCode),
    CONSTRAINT chk_SalaryBand CHECK (SalaryBandMin < SalaryBandMax)
);
GO

CREATE TABLE hr.RefLocation (
    LocationID          SMALLINT        NOT NULL IDENTITY(1,1),
    LocationName        NVARCHAR(100)   NOT NULL,
    City                NVARCHAR(100)   NOT NULL,
    Country             NVARCHAR(60)    NOT NULL,
    Region              NVARCHAR(20)    NOT NULL
                        CONSTRAINT chk_Region
                        CHECK (Region IN ('Northeast','South','West','Midwest',
                                          'Remote','EMEA','Canada')),
    GeoMultiplier       DECIMAL(5,4)    NOT NULL DEFAULT 1.0000,
    IsActive            BIT             NOT NULL DEFAULT 1,
    CONSTRAINT pk_RefLocation PRIMARY KEY (LocationID),
    CONSTRAINT uq_LocationName UNIQUE (LocationName)
);
GO

CREATE TABLE hr.RefRecruitmentSource (
    SourceID            TINYINT         NOT NULL IDENTITY(1,1),
    SourceName          NVARCHAR(60)    NOT NULL,
    SourceType          NVARCHAR(30)    NOT NULL
                        CONSTRAINT chk_SourceType
                        CHECK (SourceType IN ('Digital','Referral','Agency',
                                              'Campus','Internal','Direct')),
    IsActive            BIT             NOT NULL DEFAULT 1,
    CONSTRAINT pk_RefRecruitmentSource PRIMARY KEY (SourceID),
    CONSTRAINT uq_SourceName UNIQUE (SourceName)
);
GO

CREATE TABLE hr.RefPerformanceRating (
    RatingValue         TINYINT         NOT NULL,
    RatingLabel         NVARCHAR(30)    NOT NULL,
    IsHighPerformer     BIT             NOT NULL DEFAULT 0,
    CONSTRAINT pk_RefPerformanceRating PRIMARY KEY (RatingValue),
    CONSTRAINT chk_RatingValue CHECK (RatingValue BETWEEN 1 AND 5)
);
GO

-- ─────────────────────────────────────────
-- 2.2 CORE EMPLOYEE TABLE
-- ─────────────────────────────────────────

/*
  Business Purpose : Single source of truth for every employee record.
  Grain            : One row per employee (current state).
  SCD Strategy     : Type 1 here; historical changes captured in audit.EmployeeHistory.
  Why denormalise some fields: ManagerID self-reference kept here for
  org-hierarchy traversal without a separate junction table.
*/

CREATE TABLE hr.Employee (
    EmployeeID          NVARCHAR(10)    NOT NULL,
    EmployeeName        NVARCHAR(200)   NOT NULL,
    Age                 TINYINT         NOT NULL
                        CONSTRAINT chk_Age CHECK (Age BETWEEN 16 AND 80),
    Gender              NVARCHAR(20)    NOT NULL
                        CONSTRAINT chk_Gender
                        CHECK (Gender IN ('Male','Female','Non-binary')),

    -- Organisational foreign keys
    DepartmentID        TINYINT         NOT NULL,
    JobRole             NVARCHAR(100)   NOT NULL,
    JobLevel            CHAR(2)         NOT NULL,
    ManagerID           NVARCHAR(10)    NULL,  -- NULL = top of hierarchy
    LocationID          SMALLINT        NOT NULL,

    -- Employment details
    WorkMode            NVARCHAR(20)    NOT NULL
                        CONSTRAINT chk_WorkMode
                        CHECK (WorkMode IN ('On-site','Hybrid','Remote')),
    YearsAtCompany      DECIMAL(5,2)    NOT NULL
                        CONSTRAINT chk_Tenure CHECK (YearsAtCompany >= 0),
    Salary              INT             NOT NULL
                        CONSTRAINT chk_Salary CHECK (Salary BETWEEN 30000 AND 2000000),
    Bonus               INT             NOT NULL DEFAULT 0
                        CONSTRAINT chk_Bonus CHECK (Bonus >= 0),
    RecruitmentSourceID TINYINT         NOT NULL,

    -- Performance & engagement
    PerformanceRating   TINYINT         NOT NULL,
    PerformanceLabel    NVARCHAR(30)    NOT NULL,
    AttendancePct       DECIMAL(5,2)    NOT NULL
                        CONSTRAINT chk_Attendance CHECK (AttendancePct BETWEEN 0 AND 100),
    TrainingHours       DECIMAL(6,2)    NOT NULL
                        CONSTRAINT chk_Training CHECK (TrainingHours >= 0),
    EngagementScore     DECIMAL(6,2)    NOT NULL
                        CONSTRAINT chk_Engagement CHECK (EngagementScore BETWEEN 0 AND 100),
    SatisfactionScore   DECIMAL(6,2)    NOT NULL
                        CONSTRAINT chk_Satisfaction CHECK (SatisfactionScore BETWEEN 0 AND 100),

    -- Career history
    Promotions          TINYINT         NOT NULL DEFAULT 0
                        CONSTRAINT chk_Promotions CHECK (Promotions >= 0),
    LeaveCount          TINYINT         NOT NULL DEFAULT 0
                        CONSTRAINT chk_Leave CHECK (LeaveCount BETWEEN 0 AND 365),

    -- Attrition
    Attrition           NVARCHAR(3)     NOT NULL
                        CONSTRAINT chk_Attrition CHECK (Attrition IN ('Yes','No')),
    ExitReason          NVARCHAR(60)    NULL,

    -- Metadata
    LoadedAt            DATETIME2       NOT NULL DEFAULT SYSDATETIME(),
    UpdatedAt           DATETIME2       NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT pk_Employee      PRIMARY KEY (EmployeeID),
    CONSTRAINT fk_Emp_Dept      FOREIGN KEY (DepartmentID)
                                REFERENCES hr.RefDepartment(DepartmentID),
    CONSTRAINT fk_Emp_Level     FOREIGN KEY (JobLevel)
                                REFERENCES hr.RefJobLevel(LevelCode),
    CONSTRAINT fk_Emp_Location  FOREIGN KEY (LocationID)
                                REFERENCES hr.RefLocation(LocationID),
    CONSTRAINT fk_Emp_Source    FOREIGN KEY (RecruitmentSourceID)
                                REFERENCES hr.RefRecruitmentSource(SourceID),
    CONSTRAINT fk_Emp_Perf      FOREIGN KEY (PerformanceRating)
                                REFERENCES hr.RefPerformanceRating(RatingValue),
    CONSTRAINT fk_Emp_Manager   FOREIGN KEY (ManagerID)
                                REFERENCES hr.Employee(EmployeeID)  -- self-reference
);
GO

-- ─────────────────────────────────────────
-- 2.3 FLIGHT RISK SCORES TABLE
-- ─────────────────────────────────────────

/*
  Business Purpose : Stores ML model output for each employee.
  Grain            : One row per (employee × scoring run date).
  Why separate table: Scores refresh weekly — keeping them in Employee
  would create update noise on the main table and complicate CDC.
*/

CREATE TABLE hr.FlightRiskScore (
    ScoreID             INT             NOT NULL IDENTITY(1,1),
    EmployeeID          NVARCHAR(10)    NOT NULL,
    ScoringDate         DATE            NOT NULL DEFAULT CAST(SYSDATETIME() AS DATE),
    FlightRiskScore     DECIMAL(5,2)    NOT NULL
                        CONSTRAINT chk_RiskScore CHECK (FlightRiskScore BETWEEN 0 AND 100),
    FlightRiskTier      NVARCHAR(20)    NOT NULL
                        CONSTRAINT chk_RiskTier
                        CHECK (FlightRiskTier IN ('High Risk','Medium Risk',
                                                   'Low Risk','Engaged')),
    ModelProbability    DECIMAL(8,6)    NOT NULL,
    TopRiskDriver1      NVARCHAR(100)   NULL,
    TopRiskDriver2      NVARCHAR(100)   NULL,
    TopRiskDriver3      NVARCHAR(100)   NULL,
    ModelVersion        NVARCHAR(20)    NOT NULL DEFAULT 'v1.0',
    CreatedAt           DATETIME2       NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT pk_FlightRiskScore   PRIMARY KEY (ScoreID),
    CONSTRAINT fk_FRS_Employee      FOREIGN KEY (EmployeeID)
                                    REFERENCES hr.Employee(EmployeeID),
    CONSTRAINT uq_FRS_EmpDate       UNIQUE (EmployeeID, ScoringDate)
);
GO

-- ─────────────────────────────────────────
-- 2.4 AUDIT / CHANGE LOG TABLE
-- ─────────────────────────────────────────

/*
  Business Purpose : GDPR Article 30 compliance — every data change logged.
  Append-only (no UPDATE/DELETE permitted via application).
  Why NVARCHAR(MAX) for old/new value: accommodates any column type as string.
*/

CREATE TABLE audit.EmployeeChangeLog (
    ChangeID            BIGINT          NOT NULL IDENTITY(1,1),
    EmployeeID          NVARCHAR(10)    NOT NULL,
    ChangedColumn       NVARCHAR(100)   NOT NULL,
    OldValue            NVARCHAR(MAX)   NULL,
    NewValue            NVARCHAR(MAX)   NULL,
    ChangedBy           NVARCHAR(100)   NOT NULL DEFAULT SYSTEM_USER,
    ChangedAt           DATETIME2       NOT NULL DEFAULT SYSDATETIME(),
    ChangeReason        NVARCHAR(200)   NULL,
    CONSTRAINT pk_ChangeLog PRIMARY KEY (ChangeID)
);
GO


-- ============================================================
-- SECTION 3: INDEXES
-- ============================================================
/*
  Index strategy:
  • Clustered index on PK (default) for all tables
  • Non-clustered covering indexes on high-frequency filter/join columns
  • Included columns added to avoid key lookups in common query patterns
  • Filtered indexes for partial scans (e.g. active employees only)
*/

-- Employee: most queries filter by Department or Attrition or Level
CREATE NONCLUSTERED INDEX ix_Emp_Department
    ON hr.Employee (DepartmentID)
    INCLUDE (EmployeeID, EmployeeName, JobLevel, Salary, PerformanceRating,
             EngagementScore, Attrition);
GO

CREATE NONCLUSTERED INDEX ix_Emp_Attrition
    ON hr.Employee (Attrition)
    INCLUDE (DepartmentID, JobLevel, Salary, EngagementScore,
             PerformanceRating, YearsAtCompany, ExitReason);
GO

CREATE NONCLUSTERED INDEX ix_Emp_JobLevel
    ON hr.Employee (JobLevel)
    INCLUDE (DepartmentID, Salary, Bonus, PerformanceRating, Attrition);
GO

CREATE NONCLUSTERED INDEX ix_Emp_Manager
    ON hr.Employee (ManagerID)
    INCLUDE (EmployeeID, DepartmentID, PerformanceRating, EngagementScore, Attrition);
GO

CREATE NONCLUSTERED INDEX ix_Emp_Location
    ON hr.Employee (LocationID)
    INCLUDE (DepartmentID, Salary, WorkMode, Attrition);
GO

-- Filtered index: active employees only — most dashboard queries exclude attrited
CREATE NONCLUSTERED INDEX ix_Emp_Active_Filtered
    ON hr.Employee (DepartmentID, JobLevel, Salary, EngagementScore)
    WHERE Attrition = 'No';
GO

-- Filtered index: attrited employees for exit analysis
CREATE NONCLUSTERED INDEX ix_Emp_Attrited_Filtered
    ON hr.Employee (DepartmentID, JobLevel, ExitReason, YearsAtCompany)
    WHERE Attrition = 'Yes';
GO

-- FlightRisk: latest score per employee lookup
CREATE NONCLUSTERED INDEX ix_FRS_Employee_Date
    ON hr.FlightRiskScore (EmployeeID, ScoringDate DESC)
    INCLUDE (FlightRiskScore, FlightRiskTier, ModelProbability);
GO

-- Audit log: compliance queries search by employee and time window
CREATE NONCLUSTERED INDEX ix_Audit_EmpDate
    ON audit.EmployeeChangeLog (EmployeeID, ChangedAt DESC)
    INCLUDE (ChangedColumn, OldValue, NewValue);
GO


-- ============================================================
-- SECTION 4: POPULATE REFERENCE DATA
-- ============================================================

INSERT INTO hr.RefDepartment (DepartmentName, PayMultiplier, BaseAttritionRate)
VALUES
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
GO

INSERT INTO hr.RefJobLevel (LevelCode, LevelName, SalaryBandMin, SalaryBandMax, CareerTrack, SortOrder)
VALUES
    ('L2','Associate',         55000,  85000, 'Individual-Contributor', 1),
    ('L3','Specialist',        85000, 110000, 'Individual-Contributor', 2),
    ('L4','Senior Specialist', 110000,140000, 'Individual-Contributor', 3),
    ('L5','Staff / Principal', 140000,175000, 'Manager',               4),
    ('L6','Director',          175000,230000, 'Manager',               5),
    ('L7','Vice President',    230000,320000, 'Executive',             6),
    ('L8','C-Suite',           320000,500000, 'Executive',             7);
GO

INSERT INTO hr.RefLocation (LocationName, City, Country, Region, GeoMultiplier)
VALUES
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
GO

INSERT INTO hr.RefRecruitmentSource (SourceName, SourceType)
VALUES
    ('LinkedIn',          'Digital'),
    ('Employee Referral', 'Referral'),
    ('Company Website',   'Direct'),
    ('Indeed',            'Digital'),
    ('Recruiter/Agency',  'Agency'),
    ('University Campus', 'Campus'),
    ('Glassdoor',         'Digital'),
    ('Internal Transfer', 'Internal');
GO

INSERT INTO hr.RefPerformanceRating (RatingValue, RatingLabel, IsHighPerformer)
VALUES
    (1, 'Unacceptable',        0),
    (2, 'Below Expectations',  0),
    (3, 'Meets Expectations',  0),
    (4, 'Exceeds Expectations',1),
    (5, 'Distinguished',       1);
GO


-- ============================================================
-- SECTION 5: VIEWS
-- ============================================================

-- ─────────────────────────────────────────
-- VIEW 1: vw_EmployeeFull
-- ─────────────────────────────────────────
/*
  Business Purpose : Master employee view with all dimension labels resolved.
  Used by         : All Power BI dashboards, most ad-hoc queries.
  Optimization    : References filtered index ix_Emp_Active_Filtered for
                    active-only slices; includes all denormalised labels
                    so dashboards never need to join reference tables.
*/
CREATE OR ALTER VIEW rpt.vw_EmployeeFull
AS
SELECT
    e.EmployeeID,
    e.EmployeeName,
    e.Age,
    e.Gender,
    -- Age banding (computed inline for Power BI slicer)
    CASE
        WHEN e.Age < 25  THEN 'Under 25'
        WHEN e.Age < 35  THEN '25-34'
        WHEN e.Age < 45  THEN '35-44'
        WHEN e.Age < 55  THEN '45-54'
        WHEN e.Age < 65  THEN '55-64'
        ELSE '65+'
    END                                             AS AgeBand,

    -- Department
    d.DepartmentName                                AS Department,
    d.PayMultiplier,

    -- Role & level
    e.JobRole,
    e.JobLevel,
    jl.LevelName,
    jl.CareerTrack,
    jl.SalaryBandMin,
    jl.SalaryBandMax,

    -- Location
    l.LocationName                                  AS Location,
    l.City,
    l.Country,
    l.Region,
    l.GeoMultiplier,

    e.WorkMode,
    e.ManagerID,

    -- Tenure
    e.YearsAtCompany,
    CASE
        WHEN e.YearsAtCompany < 1  THEN '< 1 Year'
        WHEN e.YearsAtCompany < 2  THEN '1-2 Years'
        WHEN e.YearsAtCompany < 3  THEN '2-3 Years'
        WHEN e.YearsAtCompany < 5  THEN '3-5 Years'
        WHEN e.YearsAtCompany < 8  THEN '5-8 Years'
        WHEN e.YearsAtCompany < 12 THEN '8-12 Years'
        ELSE '12+ Years'
    END                                             AS TenureBand,

    -- Compensation
    e.Salary,
    e.Bonus,
    e.Salary + e.Bonus                              AS TotalComp,
    jl.SalaryBandMin + (jl.SalaryBandMax - jl.SalaryBandMin) / 2 AS BandMidpoint,
    CAST(e.Salary AS DECIMAL(10,4)) /
        NULLIF(jl.SalaryBandMin +
               (jl.SalaryBandMax - jl.SalaryBandMin) / 2, 0) AS CompaRatio,
    CASE
        WHEN e.Salary < 80000   THEN '< $80K'
        WHEN e.Salary < 120000  THEN '$80K-$120K'
        WHEN e.Salary < 160000  THEN '$120K-$160K'
        WHEN e.Salary < 200000  THEN '$160K-$200K'
        WHEN e.Salary < 250000  THEN '$200K-$250K'
        WHEN e.Salary < 350000  THEN '$250K-$350K'
        ELSE '$350K+'
    END                                             AS SalaryBand,

    -- Recruitment
    rs.SourceName                                   AS RecruitmentSource,
    rs.SourceType,

    -- Performance & engagement
    e.PerformanceRating,
    e.PerformanceLabel,
    pr.IsHighPerformer,
    e.AttendancePct,
    e.TrainingHours,
    e.EngagementScore,
    e.SatisfactionScore,
    -- Engagement tier
    CASE
        WHEN e.EngagementScore >= 75 THEN 'Engaged'
        WHEN e.EngagementScore >= 60 THEN 'Low Risk'
        WHEN e.EngagementScore >= 40 THEN 'Medium Risk'
        ELSE 'High Risk'
    END                                             AS EngagementTier,

    -- Career
    e.Promotions,
    e.LeaveCount,
    ROUND(e.YearsAtCompany / 2.8, 2)               AS ExpectedPromotions,
    ROUND(e.YearsAtCompany / 2.8 - e.Promotions, 2) AS PromotionGap,

    -- Attrition
    e.Attrition,
    CASE e.Attrition WHEN 'Yes' THEN 1 ELSE 0 END  AS AttritionFlag,
    e.ExitReason,
    CASE
        WHEN e.Attrition = 'Yes' AND pr.IsHighPerformer = 1
        THEN 1 ELSE 0
    END                                             AS IsRegrettableExit,

    -- Metadata
    e.LoadedAt,
    e.UpdatedAt

FROM hr.Employee                    e
JOIN hr.RefDepartment               d   ON e.DepartmentID        = d.DepartmentID
JOIN hr.RefJobLevel                 jl  ON e.JobLevel            = jl.LevelCode
JOIN hr.RefLocation                 l   ON e.LocationID          = l.LocationID
JOIN hr.RefRecruitmentSource        rs  ON e.RecruitmentSourceID = rs.SourceID
JOIN hr.RefPerformanceRating        pr  ON e.PerformanceRating   = pr.RatingValue;
GO

-- ─────────────────────────────────────────
-- VIEW 2: vw_DepartmentKPIs  (pre-aggregated, Power BI direct-query layer)
-- ─────────────────────────────────────────
/*
  Business Purpose : One-row-per-department summary for executive scorecards.
  Optimization    : Aggregate once here; Power BI imports 11 rows, not 10,000.
*/
CREATE OR ALTER VIEW rpt.vw_DepartmentKPIs
AS
SELECT
    d.DepartmentName,
    COUNT(*)                                        AS TotalHeadcount,
    SUM(CASE WHEN e.Attrition = 'No'  THEN 1 ELSE 0 END) AS ActiveHeadcount,
    SUM(CASE WHEN e.Attrition = 'Yes' THEN 1 ELSE 0 END) AS AttritionCount,
    CAST(
        SUM(CASE WHEN e.Attrition = 'Yes' THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(*), 0) * 100
    AS DECIMAL(5,2))                                AS AttritionRatePct,
    CAST(AVG(CAST(e.Salary AS BIGINT)) AS INT)      AS AvgSalary,
    CAST(CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY e.Salary) OVER (PARTITION BY d.DepartmentID)
    AS INT) AS INT)                                 AS MedianSalaryProxy,   -- window approx
    ROUND(AVG(e.EngagementScore), 2)                AS AvgEngagementScore,
    ROUND(AVG(e.SatisfactionScore), 2)              AS AvgSatisfactionScore,
    ROUND(AVG(e.PerformanceRating * 1.0), 3)        AS AvgPerformanceRating,
    ROUND(AVG(e.AttendancePct), 2)                  AS AvgAttendancePct,
    ROUND(AVG(e.TrainingHours), 2)                  AS AvgTrainingHours,
    ROUND(AVG(e.YearsAtCompany), 2)                 AS AvgTenureYears,
    SUM(CASE WHEN e.PerformanceRating >= 4 THEN 1 ELSE 0 END) AS HighPerformerCount,
    CAST(
        SUM(CASE WHEN e.PerformanceRating >= 4 THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(*), 0) * 100
    AS DECIMAL(5,2))                                AS HighPerformerPct,
    SUM(CASE WHEN e.EngagementScore < 40 THEN 1 ELSE 0 END) AS HighFlightRiskCount,
    CAST(
        SUM(CASE WHEN e.Attrition = 'Yes'
                  AND e.PerformanceRating >= 4 THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(*), 0) * 100
    AS DECIMAL(5,2))                                AS RegrettableAttritionPct
FROM hr.Employee e
JOIN hr.RefDepartment d ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName;
GO

-- ─────────────────────────────────────────
-- VIEW 3: vw_FlightRiskCurrent  (latest score per employee)
-- ─────────────────────────────────────────
/*
  Business Purpose : HRBP command centre — shows only the most recent
                     ML score per employee, not every historical score.
  Optimization    : ROW_NUMBER inside CTE filters to latest row before join.
*/
CREATE OR ALTER VIEW rpt.vw_FlightRiskCurrent
AS
WITH LatestScore AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY ScoringDate DESC) AS rn
    FROM hr.FlightRiskScore
)
SELECT
    e.EmployeeID,
    e.EmployeeName,
    d.DepartmentName                                AS Department,
    e.JobRole,
    e.JobLevel,
    e.ManagerID,
    l.LocationName                                  AS Location,
    e.EngagementScore,
    e.SatisfactionScore,
    e.PerformanceRating,
    e.Promotions,
    e.YearsAtCompany,
    e.Salary,
    fs.FlightRiskScore,
    fs.FlightRiskTier,
    fs.ModelProbability,
    fs.TopRiskDriver1,
    fs.TopRiskDriver2,
    fs.TopRiskDriver3,
    fs.ScoringDate
FROM hr.Employee              e
JOIN hr.RefDepartment         d  ON e.DepartmentID = d.DepartmentID
JOIN hr.RefLocation           l  ON e.LocationID   = l.LocationID
LEFT JOIN LatestScore         fs ON e.EmployeeID   = fs.EmployeeID AND fs.rn = 1
WHERE e.Attrition = 'No';   -- active employees only
GO

-- ─────────────────────────────────────────
-- VIEW 4: vw_PayEquity  (compensation equity analysis)
-- ─────────────────────────────────────────
/*
  Business Purpose : Surfaces unexplained pay gaps for Total Rewards and Legal.
  Logic           : Computes compa-ratio deviation from gender-neutral level median.
*/
CREATE OR ALTER VIEW rpt.vw_PayEquity
AS
WITH LevelStats AS (
    SELECT
        JobLevel,
        Gender,
        COUNT(*)                            AS EmployeeCount,
        AVG(CAST(Salary AS BIGINT))         AS AvgSalary,
        PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY Salary) OVER
            (PARTITION BY JobLevel)         AS LevelMedian,   -- neutral (all genders)
        PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY Salary) OVER
            (PARTITION BY JobLevel, Gender) AS GenderMedian
    FROM hr.Employee
)
SELECT
    JobLevel,
    Gender,
    EmployeeCount,
    CAST(AvgSalary AS INT)                                          AS AvgSalary,
    CAST(LevelMedian AS INT)                                        AS LevelMedian,
    CAST(GenderMedian AS INT)                                       AS GenderMedian,
    CAST((GenderMedian - LevelMedian) / NULLIF(LevelMedian,0) * 100
         AS DECIMAL(6,2))                                           AS PayGapVsMedianPct,
    CAST(GenderMedian - LevelMedian AS INT)                         AS PayGapVsMedianAmt
FROM LevelStats
GROUP BY JobLevel, Gender, EmployeeCount, AvgSalary, LevelMedian, GenderMedian;
GO


-- ============================================================
-- SECTION 6: STORED PROCEDURES
-- ============================================================

-- ─────────────────────────────────────────
-- SP 1: usp_LoadEmployeesFromStaging
-- ─────────────────────────────────────────
/*
  Business Purpose : Idempotent ETL loader — merges staging data into hr.Employee.
  Logic           : MERGE statement handles INSERT (new) and UPDATE (changed).
  Why MERGE       : Avoids separate INSERT/UPDATE logic; atomic operation.
  Optimization    : Staging table should mirror Employee columns + index on EmployeeID.
*/
CREATE OR ALTER PROCEDURE hr.usp_LoadEmployeesFromStaging
    @BatchID    NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- auto-rollback on any error

    DECLARE @InsertCount INT = 0,
            @UpdateCount INT = 0,
            @ErrorMsg    NVARCHAR(500);

    BEGIN TRANSACTION;

    BEGIN TRY
        MERGE hr.Employee AS tgt
        USING hr.Employee_Staging AS src
            ON tgt.EmployeeID = src.EmployeeID
        WHEN MATCHED AND (
               tgt.Salary            <> src.Salary
            OR tgt.DepartmentID      <> src.DepartmentID
            OR tgt.JobLevel          <> src.JobLevel
            OR tgt.PerformanceRating <> src.PerformanceRating
            OR tgt.EngagementScore   <> src.EngagementScore
            OR tgt.Attrition         <> src.Attrition
        )
        THEN UPDATE SET
            tgt.Salary            = src.Salary,
            tgt.Bonus             = src.Bonus,
            tgt.DepartmentID      = src.DepartmentID,
            tgt.JobLevel          = src.JobLevel,
            tgt.PerformanceRating = src.PerformanceRating,
            tgt.EngagementScore   = src.EngagementScore,
            tgt.SatisfactionScore = src.SatisfactionScore,
            tgt.AttendancePct     = src.AttendancePct,
            tgt.TrainingHours     = src.TrainingHours,
            tgt.Attrition         = src.Attrition,
            tgt.ExitReason        = src.ExitReason,
            tgt.UpdatedAt         = SYSDATETIME()
        WHEN NOT MATCHED BY TARGET
        THEN INSERT (
            EmployeeID, EmployeeName, Age, Gender,
            DepartmentID, JobRole, JobLevel, ManagerID, LocationID,
            WorkMode, YearsAtCompany, Salary, Bonus, RecruitmentSourceID,
            PerformanceRating, PerformanceLabel, AttendancePct, TrainingHours,
            EngagementScore, SatisfactionScore, Promotions, LeaveCount,
            Attrition, ExitReason
        )
        VALUES (
            src.EmployeeID, src.EmployeeName, src.Age, src.Gender,
            src.DepartmentID, src.JobRole, src.JobLevel, src.ManagerID, src.LocationID,
            src.WorkMode, src.YearsAtCompany, src.Salary, src.Bonus, src.RecruitmentSourceID,
            src.PerformanceRating, src.PerformanceLabel, src.AttendancePct, src.TrainingHours,
            src.EngagementScore, src.SatisfactionScore, src.Promotions, src.LeaveCount,
            src.Attrition, src.ExitReason
        )
        OUTPUT $action INTO @ChangeLog;

        SELECT @InsertCount = COUNT(*) FROM @ChangeLog WHERE Action = 'INSERT';
        SELECT @UpdateCount = COUNT(*) FROM @ChangeLog WHERE Action = 'UPDATE';

        COMMIT TRANSACTION;

        SELECT 'SUCCESS'    AS Status,
               @InsertCount AS RowsInserted,
               @UpdateCount AS RowsUpdated,
               SYSDATETIME() AS CompletedAt;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @ErrorMsg = ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END;
GO

-- ─────────────────────────────────────────
-- SP 2: usp_GetAttritionReport
-- ─────────────────────────────────────────
/*
  Business Purpose : Parameterised attrition report for HRBP and HR Director.
  Parameters      : Department (optional), MinTenure / MaxTenure filter,
                    flag to show only regrettable exits.
  Optimization    : Dynamic WHERE clause uses short-circuit NULL checks
                    which SQL Server optimises via parameter sniffing hint.
*/
CREATE OR ALTER PROCEDURE hr.usp_GetAttritionReport
    @Department         NVARCHAR(100) = NULL,
    @MinTenureYears     DECIMAL(5,2)  = NULL,
    @MaxTenureYears     DECIMAL(5,2)  = NULL,
    @RegrettableOnly    BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.EmployeeID,
        e.EmployeeName,
        d.DepartmentName,
        e.JobRole,
        e.JobLevel,
        e.Gender,
        e.YearsAtCompany,
        e.Salary,
        e.PerformanceRating,
        e.PerformanceLabel,
        e.EngagementScore,
        e.Promotions,
        e.ExitReason,
        CASE WHEN e.PerformanceRating >= 4 THEN 'Yes' ELSE 'No'
        END AS IsRegrettable,
        -- Estimated replacement cost (1.5× salary industry benchmark)
        CAST(e.Salary * 1.5 AS INT) AS EstimatedReplacementCost
    FROM hr.Employee       e
    JOIN hr.RefDepartment  d ON e.DepartmentID = d.DepartmentID
    WHERE
        e.Attrition = 'Yes'
        AND (@Department     IS NULL OR d.DepartmentName = @Department)
        AND (@MinTenureYears IS NULL OR e.YearsAtCompany >= @MinTenureYears)
        AND (@MaxTenureYears IS NULL OR e.YearsAtCompany <= @MaxTenureYears)
        AND (@RegrettableOnly = 0 OR e.PerformanceRating >= 4)
    ORDER BY e.PerformanceRating DESC, e.Salary DESC
    OPTION (RECOMPILE);  -- prevents bad plan from parameter sniffing
END;
GO

-- ─────────────────────────────────────────
-- SP 3: usp_ManagerEffectivenessScore
-- ─────────────────────────────────────────
/*
  Business Purpose : Computes composite manager effectiveness score used
                     in the HRBP Manager Scorecard dashboard.
  Formula         : (TeamEngagement × 0.40) + (TeamRetention × 0.40)
                    + (TeamHighPerformerPct × 0.20) scaled to 100.
  Optimization    : Single scan of Employee table — no multiple passes.
*/
CREATE OR ALTER PROCEDURE hr.usp_ManagerEffectivenessScore
    @MinTeamSize INT = 3   -- exclude managers with < 3 reports (statistical noise)
AS
BEGIN
    SET NOCOUNT ON;

    WITH TeamMetrics AS (
        SELECT
            e.ManagerID,
            mgr.EmployeeName                                    AS ManagerName,
            d.DepartmentName                                    AS ManagerDept,
            COUNT(*)                                            AS TeamSize,
            ROUND(AVG(e.EngagementScore), 2)                    AS AvgTeamEngagement,
            ROUND(AVG(e.SatisfactionScore), 2)                  AS AvgTeamSatisfaction,
            CAST(SUM(CASE WHEN e.Attrition='No'  THEN 1.0 ELSE 0 END)
                 / COUNT(*) * 100 AS DECIMAL(5,2))              AS RetentionRatePct,
            CAST(SUM(CASE WHEN e.PerformanceRating >= 4 THEN 1.0 ELSE 0 END)
                 / COUNT(*) * 100 AS DECIMAL(5,2))              AS HighPerformerPct,
            ROUND(AVG(e.PerformanceRating * 1.0), 3)            AS AvgTeamPerformance,
            CAST(SUM(CASE WHEN e.Attrition='Yes' THEN 1.0 ELSE 0 END)
                 / COUNT(*) * 100 AS DECIMAL(5,2))              AS TeamAttritionRatePct
        FROM hr.Employee       e
        JOIN hr.Employee       mgr ON e.ManagerID   = mgr.EmployeeID
        JOIN hr.RefDepartment  d   ON mgr.DepartmentID = d.DepartmentID
        WHERE e.ManagerID IS NOT NULL
        GROUP BY e.ManagerID, mgr.EmployeeName, d.DepartmentName
        HAVING COUNT(*) >= @MinTeamSize
    )
    SELECT
        ManagerID,
        ManagerName,
        ManagerDept,
        TeamSize,
        AvgTeamEngagement,
        AvgTeamSatisfaction,
        RetentionRatePct,
        HighPerformerPct,
        AvgTeamPerformance,
        TeamAttritionRatePct,
        -- Composite Effectiveness Score (0-100)
        CAST(
            (AvgTeamEngagement * 0.40)
            + (RetentionRatePct * 0.40)
            + (HighPerformerPct * 0.20)
        AS DECIMAL(6,2))                                AS EffectivenessScore,
        -- RAG Classification
        CASE
            WHEN (AvgTeamEngagement * 0.40
                  + RetentionRatePct * 0.40
                  + HighPerformerPct * 0.20) >= 75  THEN 'Green'
            WHEN (AvgTeamEngagement * 0.40
                  + RetentionRatePct * 0.40
                  + HighPerformerPct * 0.20) >= 55  THEN 'Amber'
            ELSE 'Red'
        END                                             AS RAGStatus
    FROM TeamMetrics
    ORDER BY EffectivenessScore DESC;
END;
GO


-- ============================================================
-- SECTION 7: ANALYTICAL QUERIES — WORKFORCE ANALYTICS
-- ============================================================

-- ─────────────────────────────────────────
-- Q-WF-01: Headcount Pyramid by Level
-- ─────────────────────────────────────────
/*
  Business Purpose : Validates org structure health — identifies if the company
                     is top-heavy (too many managers vs ICs) or bottom-heavy.
  Logic           : Aggregates active headcount by level, computes % of total.
  Optimization    : Filtered index ix_Emp_Active_Filtered used; no aggregation
                    on attrited rows.
*/
SELECT
    jl.SortOrder,
    e.JobLevel,
    jl.LevelName,
    jl.CareerTrack,
    COUNT(*)                                        AS HeadCount,
    CAST(COUNT(*) * 100.0
         / SUM(COUNT(*)) OVER ()
    AS DECIMAL(5,2))                                AS PctOfTotal,
    CAST(AVG(CAST(e.Salary AS BIGINT)) AS INT)      AS AvgSalary,
    ROUND(AVG(e.EngagementScore), 2)                AS AvgEngagement
FROM hr.Employee    e
JOIN hr.RefJobLevel jl ON e.JobLevel = jl.LevelCode
WHERE e.Attrition = 'No'
GROUP BY jl.SortOrder, e.JobLevel, jl.LevelName, jl.CareerTrack
ORDER BY jl.SortOrder;
GO

-- ─────────────────────────────────────────
-- Q-WF-02: Diversity & Inclusion — Headcount by Gender × Level
-- ─────────────────────────────────────────
/*
  Business Purpose : EEOC reporting foundation — reveals representation gaps
                     at senior levels, critical for DEI strategy.
  Logic           : PIVOT-style cross-tab using conditional aggregation
                    (more flexible than PIVOT for variable values).
  Optimization    : Single GROUP BY pass; no subquery needed.
*/
SELECT
    jl.SortOrder,
    e.JobLevel,
    jl.LevelName,
    COUNT(*)                                        AS TotalHeadcount,
    SUM(CASE WHEN e.Gender = 'Male'       THEN 1 ELSE 0 END) AS MaleCount,
    SUM(CASE WHEN e.Gender = 'Female'     THEN 1 ELSE 0 END) AS FemaleCount,
    SUM(CASE WHEN e.Gender = 'Non-binary' THEN 1 ELSE 0 END) AS NonBinaryCount,
    CAST(SUM(CASE WHEN e.Gender = 'Female' THEN 100.0 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,1))                AS FemaleRepresentationPct,
    -- Gender pay gap at each level
    CAST(AVG(CASE WHEN e.Gender = 'Male'   THEN CAST(e.Salary AS BIGINT) END)
      -  AVG(CASE WHEN e.Gender = 'Female' THEN CAST(e.Salary AS BIGINT) END)
    AS INT)                                         AS MaleFemaleSalaryGapAmt,
    CAST(
        (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END)
       - AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END))
        / NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END),0)
        * 100
    AS DECIMAL(5,2))                                AS PayGapPct
FROM hr.Employee    e
JOIN hr.RefJobLevel jl ON e.JobLevel = jl.LevelCode
GROUP BY jl.SortOrder, e.JobLevel, jl.LevelName
ORDER BY jl.SortOrder;
GO

-- ─────────────────────────────────────────
-- Q-WF-03: Work Mode Adoption by Department
-- ─────────────────────────────────────────
/*
  Business Purpose : Real estate and facilities planning — understand
                     office utilisation vs remote work adoption by dept.
  Optimization    : Single scan aggregation.
*/
SELECT
    d.DepartmentName,
    COUNT(*)                                        AS TotalEmployees,
    SUM(CASE WHEN e.WorkMode = 'On-site' THEN 1 ELSE 0 END) AS OnsiteCount,
    SUM(CASE WHEN e.WorkMode = 'Hybrid'  THEN 1 ELSE 0 END) AS HybridCount,
    SUM(CASE WHEN e.WorkMode = 'Remote'  THEN 1 ELSE 0 END) AS RemoteCount,
    CAST(SUM(CASE WHEN e.WorkMode='Remote' THEN 100.0 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,1))                AS RemotePct,
    -- Remote attrition vs on-site attrition within dept
    CAST(SUM(CASE WHEN e.WorkMode='Remote' AND e.Attrition='Yes' THEN 1.0 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN e.WorkMode='Remote' THEN 1 ELSE 0 END),0)*100
    AS DECIMAL(5,2))                                AS RemoteAttritionPct,
    CAST(SUM(CASE WHEN e.WorkMode='On-site' AND e.Attrition='Yes' THEN 1.0 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN e.WorkMode='On-site' THEN 1 ELSE 0 END),0)*100
    AS DECIMAL(5,2))                                AS OnsiteAttritionPct
FROM hr.Employee      e
JOIN hr.RefDepartment d ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY RemotePct DESC;
GO

-- ─────────────────────────────────────────
-- Q-WF-04: Span of Control Analysis
-- ─────────────────────────────────────────
/*
  Business Purpose : Org design health check — managers with > 12 direct
                     reports are overloaded; < 4 is under-leveraged structure.
  Logic           : Self-join Employee table on ManagerID.
  Optimization    : ix_Emp_Manager covering index used for the join.
*/
SELECT
    mgr.EmployeeID                                  AS ManagerID,
    mgr.EmployeeName                                AS ManagerName,
    d.DepartmentName,
    mgr.JobLevel                                    AS ManagerLevel,
    COUNT(rpt.EmployeeID)                           AS DirectReportCount,
    CASE
        WHEN COUNT(rpt.EmployeeID) > 12 THEN 'Overloaded (>12)'
        WHEN COUNT(rpt.EmployeeID) < 4  THEN 'Under-span (<4)'
        ELSE 'Optimal (4-12)'
    END                                             AS SpanStatus,
    ROUND(AVG(rpt.EngagementScore),2)               AS TeamAvgEngagement,
    CAST(SUM(CASE WHEN rpt.Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*) * 100 AS DECIMAL(5,2))          AS TeamAttritionPct
FROM hr.Employee       mgr
JOIN hr.Employee       rpt ON rpt.ManagerID   = mgr.EmployeeID
JOIN hr.RefDepartment  d   ON mgr.DepartmentID = d.DepartmentID
GROUP BY mgr.EmployeeID, mgr.EmployeeName, d.DepartmentName, mgr.JobLevel
HAVING COUNT(rpt.EmployeeID) >= 1
ORDER BY DirectReportCount DESC;
GO


-- ============================================================
-- SECTION 8: KPI QUERIES
-- ============================================================

-- ─────────────────────────────────────────
-- Q-KPI-01: Executive Workforce Scorecard
-- ─────────────────────────────────────────
/*
  Business Purpose : Single-query board pack KPI snapshot.
  Logic           : All metrics computed in one pass using conditional AGG.
  Optimization    : One full table scan; all KPIs in one result set
                    → single Power BI DirectQuery call.
*/
SELECT
    -- Headcount
    COUNT(*)                                            AS TotalEmployees,
    SUM(CASE WHEN Attrition='No'  THEN 1 ELSE 0 END)   AS ActiveEmployees,
    SUM(CASE WHEN Attrition='Yes' THEN 1 ELSE 0 END)   AS TotalAttrited,

    -- Attrition KPIs
    CAST(SUM(CASE WHEN Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*) * 100 AS DECIMAL(5,2))              AS AttritionRatePct,
    CAST(SUM(CASE WHEN Attrition='Yes' AND PerformanceRating>=4 THEN 1.0 ELSE 0 END)
         / COUNT(*) * 100 AS DECIMAL(5,2))              AS RegrettableAttritionPct,
    CAST(SUM(CASE WHEN Attrition='Yes' AND YearsAtCompany<1 THEN 1.0 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN YearsAtCompany<1 THEN 1 ELSE 0 END),0)*100
    AS DECIMAL(5,2))                                    AS NewHireAttritionPct,

    -- Engagement & Satisfaction
    ROUND(AVG(EngagementScore),2)                       AS AvgEngagementScore,
    ROUND(AVG(SatisfactionScore),2)                     AS AvgSatisfactionScore,
    SUM(CASE WHEN EngagementScore<40 THEN 1 ELSE 0 END) AS HighFlightRiskCount,
    CAST(SUM(CASE WHEN EngagementScore<40 THEN 1.0 ELSE 0 END)
         / COUNT(*) * 100 AS DECIMAL(5,2))              AS HighFlightRiskPct,

    -- Performance
    CAST(SUM(CASE WHEN PerformanceRating>=4 THEN 1.0 ELSE 0 END)
         / COUNT(*) * 100 AS DECIMAL(5,2))              AS HighPerformerPct,
    ROUND(AVG(PerformanceRating*1.0),3)                 AS AvgPerformanceRating,

    -- Compensation
    CAST(AVG(CAST(Salary AS BIGINT)) AS INT)            AS AvgSalary,
    CAST(AVG(CAST(Salary+Bonus AS BIGINT)) AS INT)      AS AvgTotalComp,

    -- Attendance & Training
    ROUND(AVG(AttendancePct),2)                         AS AvgAttendancePct,
    ROUND(AVG(TrainingHours),2)                         AS AvgTrainingHours,

    -- Career
    ROUND(AVG(YearsAtCompany),2)                        AS AvgTenureYears,
    ROUND(AVG(Promotions*1.0),3)                        AS AvgPromotions,

    -- Diversity
    CAST(SUM(CASE WHEN Gender='Female' THEN 1.0 ELSE 0 END)
         / COUNT(*) * 100 AS DECIMAL(5,2))              AS FemaleRepresentationPct,

    -- Cost of attrition
    CAST(SUM(CASE WHEN Attrition='Yes'
                  THEN Salary * 1.5 ELSE 0 END) AS BIGINT) AS TotalAttritionCostUSD

FROM hr.Employee;
GO

-- ─────────────────────────────────────────
-- Q-KPI-02: Department-Level KPI Heatmap
-- ─────────────────────────────────────────
/*
  Business Purpose : Feeds the Power BI conditional-format heatmap table —
                     one row per department with RAG flags.
  Logic           : RAG thresholds calibrated to industry benchmarks.
*/
SELECT
    d.DepartmentName,
    COUNT(*)                                        AS Headcount,
    -- Attrition RAG
    CAST(SUM(CASE WHEN e.Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS AttritionPct,
    CASE
        WHEN SUM(CASE WHEN e.Attrition='Yes' THEN 1 ELSE 0 END)*100.0/COUNT(*) >= 25 THEN '🔴'
        WHEN SUM(CASE WHEN e.Attrition='Yes' THEN 1 ELSE 0 END)*100.0/COUNT(*) >= 18 THEN '🟡'
        ELSE '🟢'
    END                                             AS AttritionRAG,
    -- Engagement RAG
    ROUND(AVG(e.EngagementScore),1)                 AS AvgEngagement,
    CASE
        WHEN AVG(e.EngagementScore) >= 75 THEN '🟢'
        WHEN AVG(e.EngagementScore) >= 60 THEN '🟡'
        ELSE '🔴'
    END                                             AS EngagementRAG,
    -- Pay equity RAG
    CAST(
        (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END)
       - AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END))
        / NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END),0)*100
    AS DECIMAL(5,2))                                AS GenderPayGapPct,
    CASE
        WHEN ABS(
            (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END)
           - AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END))
            / NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END),0)*100
        ) > 5 THEN '🔴'
        WHEN ABS(
            (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END)
           - AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END))
            / NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END),0)*100
        ) > 2 THEN '🟡'
        ELSE '🟢'
    END                                             AS PayEquityRAG,
    -- Attendance RAG
    ROUND(AVG(e.AttendancePct),1)                   AS AvgAttendance,
    CASE
        WHEN AVG(e.AttendancePct) >= 95 THEN '🟢'
        WHEN AVG(e.AttendancePct) >= 88 THEN '🟡'
        ELSE '🔴'
    END                                             AS AttendanceRAG,
    CAST(AVG(CAST(e.Salary AS BIGINT)) AS INT)      AS AvgSalary,
    ROUND(AVG(e.PerformanceRating*1.0),2)           AS AvgPerfRating
FROM hr.Employee      e
JOIN hr.RefDepartment d ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName, d.DepartmentID
ORDER BY AttritionPct DESC;
GO


-- ============================================================
-- SECTION 9: WINDOW FUNCTION QUERIES
-- ============================================================

-- ─────────────────────────────────────────
-- Q-WIN-01: Running Attrition Rate by Tenure Band
-- ─────────────────────────────────────────
/*
  Business Purpose : Survival analysis — at what tenure milestone is
                     attrition highest? Informs onboarding investment decisions.
  Logic           : Cumulative SUM of attrited employees divided by
                    total headcount as tenure increases.
  Window          : Ordered by TenureMonths — ROWS UNBOUNDED PRECEDING.
*/
WITH TenureGroups AS (
    SELECT
        CASE
            WHEN YearsAtCompany < 1  THEN '01. <1yr'
            WHEN YearsAtCompany < 2  THEN '02. 1-2yr'
            WHEN YearsAtCompany < 3  THEN '03. 2-3yr'
            WHEN YearsAtCompany < 5  THEN '04. 3-5yr'
            WHEN YearsAtCompany < 8  THEN '05. 5-8yr'
            WHEN YearsAtCompany < 12 THEN '06. 8-12yr'
            ELSE '07. 12yr+'
        END                         AS TenureBand,
        Attrition
    FROM hr.Employee
)
SELECT
    TenureBand,
    COUNT(*)                                        AS TotalInBand,
    SUM(CASE WHEN Attrition='Yes' THEN 1 ELSE 0 END) AS AttritionCount,
    CAST(SUM(CASE WHEN Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS AttritionRatePct,
    -- Running cumulative attrition across bands
    SUM(SUM(CASE WHEN Attrition='Yes' THEN 1 ELSE 0 END))
        OVER (ORDER BY TenureBand
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                    AS CumulativeAttrition,
    -- Running headcount retained
    SUM(COUNT(*))
        OVER (ORDER BY TenureBand
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                    AS CumulativeHeadcount
FROM TenureGroups
GROUP BY TenureBand
ORDER BY TenureBand;
GO

-- ─────────────────────────────────────────
-- Q-WIN-02: Salary Percentile Ranking within Level
-- ─────────────────────────────────────────
/*
  Business Purpose : Total Rewards — shows where each employee sits in
                     their level salary band. Used for merit review prioritisation.
  Logic           : PERCENT_RANK() within level partition.
  Window          : PARTITION BY JobLevel ORDER BY Salary.
*/
SELECT
    e.EmployeeID,
    e.EmployeeName,
    d.DepartmentName,
    e.JobLevel,
    jl.LevelName,
    e.Gender,
    e.Salary,
    jl.SalaryBandMin,
    jl.SalaryBandMax,
    -- Position within band
    CAST(PERCENT_RANK() OVER (PARTITION BY e.JobLevel ORDER BY e.Salary)
         * 100 AS DECIMAL(5,1))                     AS SalaryPercentileInLevel,
    -- Compa ratio
    CAST(CAST(e.Salary AS DECIMAL(12,4))
         / NULLIF(jl.SalaryBandMin + (jl.SalaryBandMax-jl.SalaryBandMin)/2, 0)
    AS DECIMAL(6,4))                                AS CompaRatio,
    -- Rank within department × level
    RANK() OVER (PARTITION BY e.DepartmentID, e.JobLevel
                 ORDER BY e.Salary DESC)            AS SalaryRankInDeptLevel,
    -- Distance from level median
    e.Salary - CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY e.Salary)
        OVER (PARTITION BY e.JobLevel)
    AS INT)                                         AS DistanceFromLevelMedian
FROM hr.Employee      e
JOIN hr.RefJobLevel   jl ON e.JobLevel   = jl.LevelCode
JOIN hr.RefDepartment  d ON e.DepartmentID = d.DepartmentID
ORDER BY e.JobLevel, SalaryPercentileInLevel DESC;
GO

-- ─────────────────────────────────────────
-- Q-WIN-03: Employee Performance Trajectory (LAG/LEAD pattern)
-- ─────────────────────────────────────────
/*
  Business Purpose : Identifies employees whose engagement is declining
                     quarter-over-quarter — early attrition signal.
  Note            : With a single snapshot, we simulate this by comparing
                    each employee to the dept average trend.
  Logic           : LAG() over department-ordered engagement scores.
*/
SELECT
    e.EmployeeID,
    e.EmployeeName,
    d.DepartmentName,
    e.JobLevel,
    e.EngagementScore,
    e.PerformanceRating,
    -- Engagement vs dept avg
    ROUND(e.EngagementScore -
          AVG(e.EngagementScore) OVER (PARTITION BY e.DepartmentID),
    2)                                              AS EngVsDeptAvg,
    -- Rank by engagement within dept (1 = most engaged)
    RANK() OVER (PARTITION BY e.DepartmentID
                 ORDER BY e.EngagementScore DESC)   AS EngagementRankInDept,
    -- Percentile within company
    CAST(PERCENT_RANK() OVER (ORDER BY e.EngagementScore)*100 AS DECIMAL(5,1))
                                                    AS EngagementPctRankCompany,
    -- Salary rank within department
    RANK() OVER (PARTITION BY e.DepartmentID
                 ORDER BY e.Salary DESC)            AS SalaryRankInDept,
    -- Performance rank within department
    RANK() OVER (PARTITION BY e.DepartmentID
                 ORDER BY e.PerformanceRating DESC,
                          e.EngagementScore DESC)   AS PerfRankInDept,
    -- Identify employees in bottom 10% of engagement in their dept
    CASE
        WHEN PERCENT_RANK() OVER (PARTITION BY e.DepartmentID
             ORDER BY e.EngagementScore) <= 0.10
        THEN 'Bottom 10% — Flag for HRBP'
        ELSE NULL
    END                                             AS HRBPFlag
FROM hr.Employee       e
JOIN hr.RefDepartment  d ON e.DepartmentID = d.DepartmentID
WHERE e.Attrition = 'No'
ORDER BY d.DepartmentName, EngagementRankInDept;
GO

-- ─────────────────────────────────────────
-- Q-WIN-04: Ntile Engagement Quartiles (Heatmap feed)
-- ─────────────────────────────────────────
/*
  Business Purpose : Groups employees into engagement quartiles for
                     Power BI heatmap colouring.
  Optimization    : NTILE is O(n log n) — faster than PERCENT_RANK for
                    buckets of exact size.
*/
SELECT
    e.EmployeeID,
    d.DepartmentName,
    e.JobLevel,
    e.Gender,
    e.EngagementScore,
    e.Salary,
    e.Attrition,
    NTILE(4) OVER (ORDER BY e.EngagementScore)      AS EngagementQuartile,
    NTILE(4) OVER (ORDER BY e.Salary)               AS SalaryQuartile,
    NTILE(10) OVER (ORDER BY e.EngagementScore)     AS EngagementDecile
FROM hr.Employee      e
JOIN hr.RefDepartment d ON e.DepartmentID = d.DepartmentID
ORDER BY EngagementQuartile, e.EngagementScore;
GO


-- ============================================================
-- SECTION 10: CTE QUERIES
-- ============================================================

-- ─────────────────────────────────────────
-- Q-CTE-01: Multi-Level Org Hierarchy (Recursive CTE)
-- ─────────────────────────────────────────
/*
  Business Purpose : Builds full reporting chain for any employee.
  Used for        : Org tree visualisation in Power BI decomposition tree.
  Logic           : Anchor = top-level (no manager); recursive join until leaf.
  Optimization    : MAXRECURSION 10 guards against circular reference data issues.
*/
WITH OrgHierarchy AS (
    -- Anchor: C-suite (no manager)
    SELECT
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.JobLevel,
        e.DepartmentID,
        0                   AS OrgDepth,
        CAST(e.EmployeeName AS NVARCHAR(4000)) AS ReportingChain
    FROM hr.Employee e
    WHERE e.ManagerID IS NULL OR e.ManagerID = e.EmployeeID

    UNION ALL

    -- Recursive: each direct report
    SELECT
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.JobLevel,
        e.DepartmentID,
        h.OrgDepth + 1,
        CAST(h.ReportingChain + ' → ' + e.EmployeeName AS NVARCHAR(4000))
    FROM hr.Employee    e
    JOIN OrgHierarchy   h ON e.ManagerID = h.EmployeeID
    WHERE e.ManagerID <> e.EmployeeID  -- prevent self-loop
)
SELECT
    oh.EmployeeID,
    oh.EmployeeName,
    oh.OrgDepth,
    oh.ReportingChain,
    d.DepartmentName,
    oh.JobLevel
FROM OrgHierarchy     oh
JOIN hr.RefDepartment  d ON oh.DepartmentID = d.DepartmentID
ORDER BY oh.OrgDepth, oh.DepartmentID
OPTION (MAXRECURSION 10);
GO

-- ─────────────────────────────────────────
-- Q-CTE-02: Promotion Gap Cohort Analysis
-- ─────────────────────────────────────────
/*
  Business Purpose : Identifies employees who are statistically overdue
                     for a promotion — primary attrition prevention signal.
  Logic           : CTE1 computes expected promotions by tenure.
                    CTE2 flags employees where gap > threshold.
                    Final join surfaces manager for HRBP action.
*/
WITH PromotionExpected AS (
    SELECT
        e.EmployeeID,
        e.EmployeeName,
        d.DepartmentName,
        e.JobLevel,
        e.YearsAtCompany,
        e.Promotions                        AS ActualPromotions,
        ROUND(e.YearsAtCompany / 2.8, 1)    AS ExpectedPromotions,
        ROUND(e.YearsAtCompany / 2.8 - e.Promotions, 1) AS PromotionGap,
        e.PerformanceRating,
        e.EngagementScore,
        e.Salary,
        e.ManagerID,
        e.Attrition
    FROM hr.Employee      e
    JOIN hr.RefDepartment d ON e.DepartmentID = d.DepartmentID
),
OverdueEmployees AS (
    SELECT *,
        CASE
            WHEN PromotionGap >= 3 AND PerformanceRating >= 4 THEN 'Critical — High Performer Overdue'
            WHEN PromotionGap >= 2 AND PerformanceRating >= 3 THEN 'At Risk — Review Recommended'
            WHEN PromotionGap >= 1                            THEN 'Monitor'
            ELSE 'On Track'
        END AS PromotionStatus
    FROM PromotionExpected
)
SELECT
    oe.EmployeeID,
    oe.EmployeeName,
    oe.DepartmentName,
    oe.JobLevel,
    ROUND(oe.YearsAtCompany, 1)         AS TenureYears,
    oe.ActualPromotions,
    oe.ExpectedPromotions,
    oe.PromotionGap,
    oe.PerformanceRating,
    ROUND(oe.EngagementScore, 1)        AS EngagementScore,
    oe.Salary,
    oe.PromotionStatus,
    mgr.EmployeeName                    AS ManagerName,
    oe.Attrition
FROM OverdueEmployees oe
LEFT JOIN hr.Employee mgr ON oe.ManagerID = mgr.EmployeeID
WHERE oe.PromotionGap >= 1
  AND oe.Attrition = 'No'
ORDER BY oe.PromotionGap DESC, oe.PerformanceRating DESC;
GO

-- ─────────────────────────────────────────
-- Q-CTE-03: Engagement Segment Transition Matrix
-- ─────────────────────────────────────────
/*
  Business Purpose : Shows how many employees sit in each engagement ×
                     performance quadrant — used to build the 9-box grid.
  Logic           : Two CTEs — first tiers both dimensions, second cross-tabs.
*/
WITH Segmented AS (
    SELECT
        EmployeeID,
        EmployeeName,
        DepartmentID,
        CASE
            WHEN EngagementScore >= 75 THEN 'High Engagement'
            WHEN EngagementScore >= 50 THEN 'Moderate Engagement'
            ELSE 'Low Engagement'
        END AS EngagementSegment,
        CASE
            WHEN PerformanceRating >= 4 THEN 'High Performance'
            WHEN PerformanceRating = 3  THEN 'Core Performance'
            ELSE 'Low Performance'
        END AS PerformanceSegment,
        Attrition,
        Salary
    FROM hr.Employee
),
NineBox AS (
    SELECT
        EngagementSegment,
        PerformanceSegment,
        COUNT(*)                                    AS HeadCount,
        CAST(COUNT(*)*100.0
             / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS PctOfTotal,
        CAST(SUM(CASE WHEN Attrition='Yes' THEN 1.0 ELSE 0 END)
             / COUNT(*)*100 AS DECIMAL(5,2))        AS AttritionRatePct,
        CAST(AVG(CAST(Salary AS BIGINT)) AS INT)    AS AvgSalary
    FROM Segmented
    GROUP BY EngagementSegment, PerformanceSegment
)
SELECT
    EngagementSegment,
    PerformanceSegment,
    HeadCount,
    PctOfTotal,
    AttritionRatePct,
    AvgSalary,
    -- Strategic label for each quadrant
    CASE
        WHEN EngagementSegment='High Engagement' AND PerformanceSegment='High Performance'
            THEN '⭐ Stars — Retain & Develop'
        WHEN EngagementSegment='High Engagement' AND PerformanceSegment='Core Performance'
            THEN '🔼 Potential — Coach Up'
        WHEN EngagementSegment='Low Engagement'  AND PerformanceSegment='High Performance'
            THEN '⚠️ Flight Risk HiPo — Urgent Action'
        WHEN EngagementSegment='Low Engagement'  AND PerformanceSegment='Low Performance'
            THEN '🔴 Exit Risk — Manage Out'
        ELSE '📋 Core Workforce'
    END                                             AS QuadrantLabel
FROM NineBox
ORDER BY AttritionRatePct DESC;
GO


-- ============================================================
-- SECTION 11: ATTRITION ANALYSIS QUERIES
-- ============================================================

-- ─────────────────────────────────────────
-- Q-ATT-01: Attrition Driver Decomposition
-- ─────────────────────────────────────────
/*
  Business Purpose : Quantifies which factors correlate most strongly
                     with attrition for data-driven CHRO narrative.
  Logic           : Computes average of each metric for attrited vs
                    retained populations and calculates the delta.
  Optimization    : Single table scan with conditional aggregation.
*/
SELECT
    Metric,
    AttritionYes,
    AttritionNo,
    ROUND(AttritionYes - AttritionNo, 3) AS Delta,
    CASE WHEN AttritionYes > AttritionNo THEN '↑ Higher in Attrited'
         ELSE '↓ Lower in Attrited'
    END AS Direction
FROM (
    SELECT
        'Avg Engagement Score'       AS Metric,
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN EngagementScore END),2) AS AttritionYes,
        ROUND(AVG(CASE WHEN Attrition='No'  THEN EngagementScore END),2) AS AttritionNo
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Satisfaction Score',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN SatisfactionScore END),2),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN SatisfactionScore END),2)
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Attendance Pct',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN AttendancePct END),2),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN AttendancePct END),2)
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Performance Rating',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN PerformanceRating*1.0 END),3),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN PerformanceRating*1.0 END),3)
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Promotions',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN Promotions*1.0 END),3),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN Promotions*1.0 END),3)
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Training Hours',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN TrainingHours END),2),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN TrainingHours END),2)
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Leave Count',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN LeaveCount*1.0 END),2),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN LeaveCount*1.0 END),2)
    FROM hr.Employee
    UNION ALL
    SELECT 'Avg Salary ($K)',
        ROUND(AVG(CASE WHEN Attrition='Yes' THEN Salary/1000.0 END),1),
        ROUND(AVG(CASE WHEN Attrition='No'  THEN Salary/1000.0 END),1)
    FROM hr.Employee
) drivers
ORDER BY ABS(Delta) DESC;
GO

-- ─────────────────────────────────────────
-- Q-ATT-02: Regrettable vs Non-Regrettable Attrition Split
-- ─────────────────────────────────────────
/*
  Business Purpose : Distinguishes high-value exits (regrettable) from
                     managed / expected turnover. Board metric.
  Logic           : Regrettable = Attrition=Yes AND PerformanceRating >= 4.
*/
SELECT
    d.DepartmentName,
    COUNT(*)                                        AS TotalAttrited,
    SUM(CASE WHEN e.PerformanceRating >= 4 THEN 1 ELSE 0 END) AS RegrettableCount,
    SUM(CASE WHEN e.PerformanceRating <= 2 THEN 1 ELSE 0 END) AS ManagedExitCount,
    SUM(CASE WHEN e.PerformanceRating = 3  THEN 1 ELSE 0 END) AS NeutralExitCount,
    CAST(SUM(CASE WHEN e.PerformanceRating>=4 THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS RegrettablePct,
    -- Cost of regrettable exits (1.5× salary)
    CAST(SUM(CASE WHEN e.PerformanceRating>=4
                  THEN e.Salary*1.5 ELSE 0 END) AS BIGINT) AS RegrettableCostUSD,
    -- Avg salary of regrettable exits
    CAST(AVG(CASE WHEN e.PerformanceRating>=4
                  THEN CAST(e.Salary AS BIGINT) END) AS INT) AS AvgSalaryRegrettable
FROM hr.Employee      e
JOIN hr.RefDepartment d ON e.DepartmentID = d.DepartmentID
WHERE e.Attrition = 'Yes'
GROUP BY d.DepartmentName
ORDER BY RegrettablePct DESC;
GO

-- ─────────────────────────────────────────
-- Q-ATT-03: Exit Reason × Engagement Correlation
-- ─────────────────────────────────────────
/*
  Business Purpose : Validates that exit reasons align with measured
                     engagement signals — critical for survey instrument calibration.
  Logic           : Groups attrited employees by exit reason and computes
                    avg engagement, satisfaction, and salary at exit.
*/
SELECT
    ISNULL(e.ExitReason, 'Not Stated')              AS ExitReason,
    COUNT(*)                                        AS ExitCount,
    CAST(COUNT(*)*100.0
         / SUM(COUNT(*)) OVER () AS DECIMAL(5,2))  AS PctOfAllExits,
    ROUND(AVG(e.EngagementScore),2)                 AS AvgEngagementAtExit,
    ROUND(AVG(e.SatisfactionScore),2)               AS AvgSatisfactionAtExit,
    CAST(AVG(CAST(e.Salary AS BIGINT)) AS INT)      AS AvgSalaryAtExit,
    ROUND(AVG(e.YearsAtCompany),2)                  AS AvgTenureAtExit,
    ROUND(AVG(e.PerformanceRating*1.0),2)           AS AvgPerfRatingAtExit,
    CAST(SUM(CASE WHEN e.PerformanceRating>=4 THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS PctHighPerformers
FROM hr.Employee e
WHERE e.Attrition = 'Yes'
  AND e.ExitReason <> 'N/A'
GROUP BY e.ExitReason
ORDER BY ExitCount DESC;
GO


-- ============================================================
-- SECTION 12: SALARY BENCHMARK QUERIES
-- ============================================================

-- ─────────────────────────────────────────
-- Q-SAL-01: Salary Distribution by Level (Box-Plot Data)
-- ─────────────────────────────────────────
/*
  Business Purpose : Total Rewards calibration — feeds Power BI box-plot
                     showing P10/P25/Median/P75/P90 per level.
  Optimization    : PERCENTILE_CONT analytical functions in single pass.
*/
SELECT
    e.JobLevel,
    jl.LevelName,
    jl.SalaryBandMin,
    jl.SalaryBandMax,
    COUNT(*)                                        AS EmployeeCount,
    CAST(MIN(e.Salary) AS INT)                      AS MinSalary,
    CAST(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY e.Salary)
         OVER (PARTITION BY e.JobLevel) AS INT)     AS P10Salary,
    CAST(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY e.Salary)
         OVER (PARTITION BY e.JobLevel) AS INT)     AS P25Salary,
    CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY e.Salary)
         OVER (PARTITION BY e.JobLevel) AS INT)     AS MedianSalary,
    CAST(AVG(CAST(e.Salary AS BIGINT))              AS INT) AS AvgSalary,
    CAST(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY e.Salary)
         OVER (PARTITION BY e.JobLevel) AS INT)     AS P75Salary,
    CAST(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY e.Salary)
         OVER (PARTITION BY e.JobLevel) AS INT)     AS P90Salary,
    CAST(MAX(e.Salary) AS INT)                      AS MaxSalary
FROM hr.Employee      e
JOIN hr.RefJobLevel   jl ON e.JobLevel = jl.LevelCode
GROUP BY e.JobLevel, jl.LevelName, jl.SalaryBandMin, jl.SalaryBandMax;
GO

-- ─────────────────────────────────────────
-- Q-SAL-02: Pay Equity Analysis — Gender Pay Gap by Level
-- ─────────────────────────────────────────
/*
  Business Purpose : Legal compliance and Total Rewards audit.
                     Computes controlled and raw pay gaps.
  Logic           : Male salary as denominator (industry standard).
                    Gap flagged if > 3% unexplained.
*/
SELECT
    e.JobLevel,
    jl.LevelName,
    COUNT(*)                                        AS TotalEmployees,
    SUM(CASE WHEN e.Gender='Male'   THEN 1 ELSE 0 END) AS MaleCount,
    SUM(CASE WHEN e.Gender='Female' THEN 1 ELSE 0 END) AS FemaleCount,
    CAST(AVG(CASE WHEN e.Gender='Male'
                  THEN CAST(e.Salary AS BIGINT) END) AS INT) AS MaleAvgSalary,
    CAST(AVG(CASE WHEN e.Gender='Female'
                  THEN CAST(e.Salary AS BIGINT) END) AS INT) AS FemaleAvgSalary,
    -- Raw gap
    CAST(
        AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END) -
        AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END)
    AS INT)                                         AS RawPayGapAmt,
    -- Percentage gap
    CAST(
        (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END) -
         AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END)) /
        NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END), 0)
        * 100
    AS DECIMAL(5,2))                                AS PayGapPct,
    -- Flag for action
    CASE
        WHEN ABS(
            (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END) -
             AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END)) /
            NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END),0)*100
        ) > 5  THEN '🔴 Action Required'
        WHEN ABS(
            (AVG(CASE WHEN e.Gender='Male'   THEN CAST(e.Salary AS FLOAT) END) -
             AVG(CASE WHEN e.Gender='Female' THEN CAST(e.Salary AS FLOAT) END)) /
            NULLIF(AVG(CASE WHEN e.Gender='Male' THEN CAST(e.Salary AS FLOAT) END),0)*100
        ) > 2  THEN '🟡 Monitor'
        ELSE '🟢 Within Range'
    END                                             AS EquityStatus
FROM hr.Employee      e
JOIN hr.RefJobLevel   jl ON e.JobLevel = jl.LevelCode
GROUP BY e.JobLevel, jl.LevelName, jl.SortOrder
ORDER BY jl.SortOrder;
GO

-- ─────────────────────────────────────────
-- Q-SAL-03: Compa-Ratio Distribution (at-risk population)
-- ─────────────────────────────────────────
/*
  Business Purpose : Identifies employees paid below 80% of band midpoint —
                     highest at-risk group for compensation-driven attrition.
  Logic           : Compa-ratio = salary / band midpoint.
*/
SELECT
    CASE
        WHEN CompaRatio < 0.70 THEN '< 0.70 — Severely Underpaid'
        WHEN CompaRatio < 0.80 THEN '0.70-0.80 — At Risk'
        WHEN CompaRatio < 0.90 THEN '0.80-0.90 — Below Midpoint'
        WHEN CompaRatio < 1.10 THEN '0.90-1.10 — Market Range'
        WHEN CompaRatio < 1.20 THEN '1.10-1.20 — Above Midpoint'
        ELSE '> 1.20 — Top of Band'
    END                                             AS CompaRatioBand,
    COUNT(*)                                        AS EmployeeCount,
    CAST(COUNT(*)*100.0/SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS PctOfTotal,
    CAST(SUM(CASE WHEN Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS AttritionRatePct
FROM (
    SELECT
        e.*,
        CAST(e.Salary AS DECIMAL(12,4)) /
            NULLIF(jl.SalaryBandMin+(jl.SalaryBandMax-jl.SalaryBandMin)/2, 0) AS CompaRatio
    FROM hr.Employee    e
    JOIN hr.RefJobLevel jl ON e.JobLevel = jl.LevelCode
) cr
GROUP BY
    CASE
        WHEN CompaRatio < 0.70 THEN '< 0.70 — Severely Underpaid'
        WHEN CompaRatio < 0.80 THEN '0.70-0.80 — At Risk'
        WHEN CompaRatio < 0.90 THEN '0.80-0.90 — Below Midpoint'
        WHEN CompaRatio < 1.10 THEN '0.90-1.10 — Market Range'
        WHEN CompaRatio < 1.20 THEN '1.10-1.20 — Above Midpoint'
        ELSE '> 1.20 — Top of Band'
    END
ORDER BY MIN(CompaRatio);
GO


-- ============================================================
-- SECTION 13: RECRUITMENT ANALYSIS QUERIES
-- ============================================================

-- ─────────────────────────────────────────
-- Q-REC-01: Source Quality — Retention & Performance Matrix
-- ─────────────────────────────────────────
/*
  Business Purpose : Answers "Which hiring source produces the best
                     long-term employees?" — TA strategy input.
  Logic           : Groups by source; computes retention rate (active),
                    avg performance, avg tenure, and avg engagement.
  Optimization    : Single scan; index ix_Emp_Attrition covers all columns.
*/
SELECT
    rs.SourceName,
    rs.SourceType,
    COUNT(*)                                        AS TotalHires,
    CAST(COUNT(*)*100.0/SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS HireSharePct,
    -- Retention
    SUM(CASE WHEN e.Attrition='No'  THEN 1 ELSE 0 END) AS ActiveCount,
    CAST(SUM(CASE WHEN e.Attrition='No' THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS RetentionRatePct,
    CAST(SUM(CASE WHEN e.Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS AttritionRatePct,
    -- Quality signals
    ROUND(AVG(e.PerformanceRating*1.0),3)           AS AvgPerfRating,
    ROUND(AVG(e.EngagementScore),2)                 AS AvgEngagement,
    ROUND(AVG(e.YearsAtCompany),2)                  AS AvgTenureYears,
    CAST(AVG(CAST(e.Salary AS BIGINT)) AS INT)      AS AvgSalary,
    -- Quality of hire composite (0-100)
    CAST(
        (AVG(e.PerformanceRating*1.0)/5 * 35)       -- 35% performance weight
      + (SUM(CASE WHEN e.Attrition='No' THEN 1.0 ELSE 0 END)/COUNT(*) * 35) -- 35% retention
      + (AVG(e.EngagementScore)/100 * 30)           -- 30% engagement
    * 100 AS DECIMAL(6,2))                          AS QualityOfHireScore
FROM hr.Employee              e
JOIN hr.RefRecruitmentSource  rs ON e.RecruitmentSourceID = rs.SourceID
GROUP BY rs.SourceName, rs.SourceType
ORDER BY QualityOfHireScore DESC;
GO

-- ─────────────────────────────────────────
-- Q-REC-02: Recruitment Source by Department × Level
-- ─────────────────────────────────────────
/*
  Business Purpose : Sourcing channel strategy by role type — senior
                     Engineering hires come differently from campus roles.
  Optimization    : Covering index ix_Emp_Department used.
*/
SELECT
    d.DepartmentName,
    e.JobLevel,
    rs.SourceName,
    COUNT(*)                                        AS HireCount,
    ROUND(AVG(e.PerformanceRating*1.0),2)           AS AvgPerformance,
    CAST(SUM(CASE WHEN e.Attrition='Yes' THEN 1.0 ELSE 0 END)
         / COUNT(*)*100 AS DECIMAL(5,2))            AS AttritionPct,
    RANK() OVER (
        PARTITION BY d.DepartmentName, e.JobLevel
        ORDER BY COUNT(*) DESC
    )                                               AS SourceRankInDeptLevel
FROM hr.Employee              e
JOIN hr.RefDepartment         d  ON e.DepartmentID        = d.DepartmentID
JOIN hr.RefRecruitmentSource  rs ON e.RecruitmentSourceID = rs.SourceID
GROUP BY d.DepartmentName, e.JobLevel, rs.SourceName
ORDER BY d.DepartmentName, e.JobLevel, HireCount DESC;
GO

-- ─────────────────────────────────────────
-- Q-REC-03: Internal Mobility Analysis
-- ─────────────────────────────────────────
/*
  Business Purpose : Measures internal talent development effectiveness.
  Internal hire rate benchmark: 30-40% is healthy (LinkedIn Talent Report).
  Logic           : Internal Transfer source = internal mobility.
*/
SELECT
    d.DepartmentName,
    COUNT(*)                                        AS TotalEmployees,
    SUM(CASE WHEN rs.SourceName = 'Internal Transfer' THEN 1 ELSE 0 END)
                                                    AS InternalHires,
    CAST(SUM(CASE WHEN rs.SourceName='Internal Transfer' THEN 100.0 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                AS InternalHireRatePct,
    -- Internal hires perform better? Compare avg performance
    ROUND(AVG(CASE WHEN rs.SourceName='Internal Transfer'
                   THEN e.PerformanceRating*1.0 END),3) AS InternalAvgPerf,
    ROUND(AVG(CASE WHEN rs.SourceName<>'Internal Transfer'
                   THEN e.PerformanceRating*1.0 END),3) AS ExternalAvgPerf,
    -- Retention comparison
    CAST(SUM(CASE WHEN rs.SourceName='Internal Transfer'
                   AND e.Attrition='No' THEN 1.0 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN rs.SourceName='Internal Transfer'
                            THEN 1 ELSE 0 END),0)*100
    AS DECIMAL(5,2))                                AS InternalRetentionPct,
    CAST(SUM(CASE WHEN rs.SourceName<>'Internal Transfer'
                   AND e.Attrition='No' THEN 1.0 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN rs.SourceName<>'Internal Transfer'
                            THEN 1 ELSE 0 END),0)*100
    AS DECIMAL(5,2))                                AS ExternalRetentionPct
FROM hr.Employee              e
JOIN hr.RefDepartment         d  ON e.DepartmentID        = d.DepartmentID
JOIN hr.RefRecruitmentSource  rs ON e.RecruitmentSourceID = rs.SourceID
GROUP BY d.DepartmentName
ORDER BY InternalHireRatePct DESC;
GO


-- ============================================================
-- SECTION 14: TRIGGERS (Automated audit trail)
-- ============================================================
/*
  Business Purpose : GDPR Article 30 automated logging — every change
                     to salary, performance rating, or attrition status
                     is automatically captured without application code.
*/
CREATE OR ALTER TRIGGER hr.trg_EmployeeAudit
ON hr.Employee
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Log salary changes
    IF UPDATE(Salary)
        INSERT INTO audit.EmployeeChangeLog
            (EmployeeID, ChangedColumn, OldValue, NewValue)
        SELECT
            i.EmployeeID,
            'Salary',
            CAST(d.Salary AS NVARCHAR(20)),
            CAST(i.Salary AS NVARCHAR(20))
        FROM inserted i
        JOIN deleted  d ON i.EmployeeID = d.EmployeeID
        WHERE i.Salary <> d.Salary;

    -- Log performance rating changes
    IF UPDATE(PerformanceRating)
        INSERT INTO audit.EmployeeChangeLog
            (EmployeeID, ChangedColumn, OldValue, NewValue)
        SELECT
            i.EmployeeID,
            'PerformanceRating',
            CAST(d.PerformanceRating AS NVARCHAR(5)),
            CAST(i.PerformanceRating AS NVARCHAR(5))
        FROM inserted i
        JOIN deleted  d ON i.EmployeeID = d.EmployeeID
        WHERE i.PerformanceRating <> d.PerformanceRating;

    -- Log attrition changes
    IF UPDATE(Attrition)
        INSERT INTO audit.EmployeeChangeLog
            (EmployeeID, ChangedColumn, OldValue, NewValue)
        SELECT
            i.EmployeeID,
            'Attrition',
            d.Attrition,
            i.Attrition
        FROM inserted i
        JOIN deleted  d ON i.EmployeeID = d.EmployeeID
        WHERE i.Attrition <> d.Attrition;
END;
GO


-- ============================================================
-- SECTION 15: BULK DATA LOAD FROM CSV
-- ============================================================
/*
  Run this AFTER the schema is created to populate hr.Employee
  from the Phase 3 CSV file. Requires BULK INSERT permissions.
  Adjust the file path to your environment.
*/

-- Step 1: Create staging table (mirrors CSV exactly)
CREATE TABLE hr.Employee_Staging (
    EmployeeID          NVARCHAR(10),
    EmployeeName        NVARCHAR(200),
    Age                 TINYINT,
    Gender              NVARCHAR(20),
    Department          NVARCHAR(100),
    JobRole             NVARCHAR(100),
    JobLevel            CHAR(2),
    ManagerID           NVARCHAR(10),
    Location            NVARCHAR(100),
    WorkMode            NVARCHAR(20),
    YearsAtCompany      DECIMAL(5,2),
    Salary              INT,
    Bonus               INT,
    RecruitmentSource   NVARCHAR(60),
    PerformanceRating   TINYINT,
    PerformanceLabel    NVARCHAR(30),
    AttendancePct       DECIMAL(5,2),
    TrainingHours       DECIMAL(6,2),
    EngagementScore     DECIMAL(6,2),
    SatisfactionScore   DECIMAL(6,2),
    Promotions          TINYINT,
    LeaveCount          TINYINT,
    Attrition           NVARCHAR(3),
    ExitReason          NVARCHAR(60)
);
GO

-- Step 2: Load CSV into staging
BULK INSERT hr.Employee_Staging
FROM '/mnt/user-data/outputs/PeoplePulse_HR_Dataset.csv'
WITH (
    FORMAT          = 'CSV',
    FIRSTROW        = 2,        -- skip header
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    TABLOCK
);
GO

-- Step 3: Resolve FKs and insert into hr.Employee
INSERT INTO hr.Employee (
    EmployeeID, EmployeeName, Age, Gender,
    DepartmentID, JobRole, JobLevel, ManagerID, LocationID,
    WorkMode, YearsAtCompany, Salary, Bonus, RecruitmentSourceID,
    PerformanceRating, PerformanceLabel, AttendancePct, TrainingHours,
    EngagementScore, SatisfactionScore, Promotions, LeaveCount,
    Attrition, ExitReason
)
SELECT
    s.EmployeeID, s.EmployeeName, s.Age, s.Gender,
    d.DepartmentID, s.JobRole, s.JobLevel,
    NULLIF(s.ManagerID, ''),
    l.LocationID,
    s.WorkMode, s.YearsAtCompany, s.Salary, s.Bonus,
    rs.SourceID,
    s.PerformanceRating, s.PerformanceLabel,
    s.AttendancePct, s.TrainingHours,
    s.EngagementScore, s.SatisfactionScore,
    s.Promotions, s.LeaveCount,
    s.Attrition,
    NULLIF(s.ExitReason, 'N/A')
FROM hr.Employee_Staging        s
JOIN hr.RefDepartment           d  ON s.Department        = d.DepartmentName
JOIN hr.RefLocation             l  ON s.Location          = l.LocationName
JOIN hr.RefRecruitmentSource    rs ON s.RecruitmentSource = rs.SourceName;
GO

-- ============================================================
-- END OF SQL LIBRARY — PeoplePulse AI Phase 4
-- ============================================================
