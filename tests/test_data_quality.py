"""
PeoplePulse AI — Data Quality Tests
======================================
Validates the structural and statistical integrity of the
generated HR dataset (data/PeoplePulse_HR_Dataset.csv).

Run: pytest tests/test_data_quality.py -v
"""

import pandas as pd
import numpy as np


EXPECTED_COLUMNS = [
    "Employee_ID","Employee_Name","Age","Gender","Department","Job_Role",
    "Job_Level","Manager_ID","Location","Work_Mode","Years_At_Company",
    "Salary","Bonus","Recruitment_Source","Performance_Rating",
    "Performance_Label","Attendance_Pct","Training_Hours","Engagement_Score",
    "Satisfaction_Score","Promotions","Leave_Count","Attrition","Exit_Reason",
]


class TestSchemaIntegrity:
    def test_row_count(self, hr_df):
        assert len(hr_df) == 10_000, f"Expected 10,000 rows, got {len(hr_df)}"

    def test_all_expected_columns_present(self, hr_df):
        missing = set(EXPECTED_COLUMNS) - set(hr_df.columns)
        assert not missing, f"Missing columns: {missing}"

    def test_employee_id_unique(self, hr_df):
        assert hr_df["Employee_ID"].is_unique, "Employee_ID contains duplicates"

    def test_no_unexpected_nulls(self, hr_df):
        non_nullable = [c for c in EXPECTED_COLUMNS if c != "Exit_Reason"]
        for col in non_nullable:
            assert hr_df[col].notna().all(), f"Unexpected NULLs in {col}"


class TestDomainConstraints:
    def test_age_range(self, hr_df):
        assert hr_df["Age"].between(16, 80).all()

    def test_gender_values(self, hr_df):
        assert set(hr_df["Gender"].unique()) <= {"Male", "Female", "Non-binary"}

    def test_attrition_binary(self, hr_df):
        assert set(hr_df["Attrition"].unique()) <= {"Yes", "No"}

    def test_attendance_pct_range(self, hr_df):
        assert hr_df["Attendance_Pct"].between(0, 100).all()

    def test_engagement_score_range(self, hr_df):
        assert hr_df["Engagement_Score"].between(0, 100).all()

    def test_satisfaction_score_range(self, hr_df):
        assert hr_df["Satisfaction_Score"].between(0, 100).all()

    def test_performance_rating_range(self, hr_df):
        assert hr_df["Performance_Rating"].between(1, 5).all()

    def test_salary_positive(self, hr_df):
        assert (hr_df["Salary"] > 0).all()

    def test_years_at_company_non_negative(self, hr_df):
        assert (hr_df["Years_At_Company"] >= 0).all()

    def test_promotions_non_negative(self, hr_df):
        assert (hr_df["Promotions"] >= 0).all()

    def test_job_level_valid(self, hr_df):
        valid_levels = {f"L{i}" for i in range(1, 9)}
        assert set(hr_df["Job_Level"].unique()) <= valid_levels


class TestReferentialIntegrity:
    def test_manager_id_references_valid_employee(self, hr_df):
        valid_ids = set(hr_df["Employee_ID"])
        manager_ids = hr_df["Manager_ID"].dropna()
        invalid = set(manager_ids) - valid_ids
        assert not invalid, f"Manager_ID references non-existent employees: {invalid}"

    def test_no_self_management(self, hr_df):
        self_managed = hr_df[hr_df["Employee_ID"] == hr_df["Manager_ID"]]
        assert len(self_managed) == 0, "Found employees who are their own manager"

    def test_attrited_employees_have_exit_reason(self, hr_df):
        attrited = hr_df[hr_df["Attrition"] == "Yes"]
        missing_reason = attrited["Exit_Reason"].isna().sum()
        assert missing_reason == 0, f"{missing_reason} attrited employees missing Exit_Reason"

    def test_active_employees_have_no_exit_reason(self, hr_df):
        active = hr_df[hr_df["Attrition"] == "No"]
        # Exit_Reason should be NaN (before fillna) for active employees —
        # this test runs on the raw CSV, not the fixture's filled version
        import pathlib
        raw = pd.read_csv(pathlib.Path(__file__).parent.parent / "data" / "PeoplePulse_HR_Dataset.csv")
        active_raw = raw[raw["Attrition"] == "No"]
        assert active_raw["Exit_Reason"].isna().all(), "Active employees should have NULL Exit_Reason"


class TestBusinessLogicSanity:
    """
    Validates that the documented design parameters from Phase 3
    (PeoplePulse_Dataset_Profile.html) still hold. Wide tolerance bands
    account for the fact that filtering/regeneration could shift exact
    values slightly while still being "correct."
    """

    def test_overall_attrition_rate_in_expected_range(self, hr_df):
        rate = (hr_df["Attrition"] == "Yes").mean()
        assert 0.20 <= rate <= 0.28, f"Attrition rate {rate:.1%} outside expected 20-28% range"

    def test_average_salary_in_expected_range(self, hr_df):
        avg_salary = hr_df["Salary"].mean()
        assert 150_000 <= avg_salary <= 190_000, f"Avg salary ${avg_salary:,.0f} outside expected range"

    def test_average_engagement_in_expected_range(self, hr_df):
        avg_eng = hr_df["Engagement_Score"].mean()
        assert 60 <= avg_eng <= 75, f"Avg engagement {avg_eng:.1f} outside expected range"

    def test_department_count(self, hr_df):
        assert hr_df["Department"].nunique() == 11

    def test_high_performers_are_minority_but_substantial(self, hr_df):
        """Per the forced-distribution design: ratings 4-5 should be ~25-35% of workforce."""
        pct_high = (hr_df["Performance_Rating"] >= 4).mean()
        assert 0.20 <= pct_high <= 0.40

    def test_regrettable_attrition_exists_but_is_minority_of_exits(self, hr_df):
        """High performers should leave less often than they're represented, but not zero."""
        attrited = hr_df[hr_df["Attrition"] == "Yes"]
        regrettable_pct = (attrited["Performance_Rating"] >= 4).mean()
        assert 0.10 <= regrettable_pct <= 0.45

    def test_new_hire_attrition_higher_than_baseline(self, hr_df):
        """Honeymoon-period exits (<1yr tenure) should show elevated attrition
        vs overall — validates the causal tenure-risk design."""
        overall_rate = (hr_df["Attrition"] == "Yes").mean()
        new_hire_rate = (hr_df[hr_df["Years_At_Company"] < 1]["Attrition"] == "Yes").mean()
        assert new_hire_rate > overall_rate, (
            f"New hire attrition ({new_hire_rate:.1%}) should exceed "
            f"overall rate ({overall_rate:.1%}) per honeymoon-curve design"
        )
