"""
PeoplePulse AI — KPI Validation Tests
========================================
Recomputes key KPIs from raw data and checks them against the
documented values in docs/05_kpi_framework.md, catching silent
drift if the dataset or KPI logic changes.

Run: pytest tests/test_kpi_validation.py -v
"""

import pandas as pd
import numpy as np


def attrition_rate(df):
    return (df["Attrition"] == "Yes").mean() * 100


def regrettable_attrition_rate(df):
    return ((df["Attrition"] == "Yes") & (df["Performance_Rating"] >= 4)).mean() * 100


class TestWorkforceKPIs:
    def test_total_headcount(self, hr_df):
        assert len(hr_df) == 10_000

    def test_span_of_control_reasonable(self, hr_df):
        span = hr_df.groupby("Manager_ID").size()
        avg_span = span.mean()
        # Documented healthy range from KPI Framework Section 1.3
        assert 3 <= avg_span <= 20, f"Avg span of control {avg_span:.1f} outside plausible range"

    def test_remote_hybrid_onsite_sum_to_100(self, hr_df):
        mix = hr_df["Work_Mode"].value_counts(normalize=True) * 100
        assert abs(mix.sum() - 100) < 0.01


class TestAttritionKPIs:
    def test_overall_attrition_rate(self, hr_df):
        rate = attrition_rate(hr_df)
        assert 20 <= rate <= 28, f"Overall attrition {rate:.1f}% outside documented 20-28% band"

    def test_regrettable_attrition_is_subset_of_total(self, hr_df):
        total = attrition_rate(hr_df)
        regrettable = regrettable_attrition_rate(hr_df)
        assert regrettable < total, "Regrettable attrition rate cannot exceed total attrition rate"

    def test_attrition_cost_impact_positive(self, hr_df):
        cost = (hr_df[hr_df["Attrition"] == "Yes"]["Salary"] * 1.5).sum()
        assert cost > 0
        # Sanity: with ~2,380 exits at ~$170K avg salary * 1.5, expect cost in the hundreds of millions
        assert 200_000_000 <= cost <= 800_000_000, f"Attrition cost ${cost:,.0f} outside plausible range"

    def test_department_attrition_rates_vary(self, hr_df):
        """If every department had identical attrition, the causal model
        (dept-specific base rates) would have failed to apply."""
        dept_rates = hr_df.groupby("Department")["Attrition"].apply(lambda x: (x == "Yes").mean())
        assert dept_rates.std() > 0.02, "Department attrition rates show implausibly little variance"


class TestRetentionKPIs:
    def test_high_performer_retention_computed(self, hr_df):
        hipo = hr_df[hr_df["Performance_Rating"] >= 4]
        retention = (hipo["Attrition"] == "No").mean() * 100
        assert 0 <= retention <= 100

    def test_internal_mobility_rate_low_but_nonzero(self, hr_df):
        """Documented finding: PeoplePulse's internal transfer rate is
        well below the 30-40% healthy benchmark — this test locks in
        that known characteristic rather than asserting health."""
        internal_rate = (hr_df["Recruitment_Source"] == "Internal Transfer").mean() * 100
        assert 0 < internal_rate < 15


class TestEngagementKPIs:
    def test_average_engagement_score(self, hr_df):
        avg = hr_df["Engagement_Score"].mean()
        assert 60 <= avg <= 75

    def test_enps_computable_and_bounded(self, hr_df):
        promoters = (hr_df["Satisfaction_Score"] >= 80).mean()
        detractors = (hr_df["Satisfaction_Score"] < 40).mean()
        enps = (promoters - detractors) * 100
        assert -100 <= enps <= 100

    def test_flight_risk_distribution_sums_correctly(self, hr_df):
        high = (hr_df["Engagement_Score"] < 40).sum()
        medium = ((hr_df["Engagement_Score"] >= 40) & (hr_df["Engagement_Score"] < 60)).sum()
        low = ((hr_df["Engagement_Score"] >= 60) & (hr_df["Engagement_Score"] < 75)).sum()
        engaged = (hr_df["Engagement_Score"] >= 75).sum()
        assert high + medium + low + engaged == len(hr_df)


class TestCompensationKPIs:
    def test_compa_ratio_centers_near_one(self, hr_df):
        level_medians = hr_df.groupby("Job_Level")["Salary"].median()
        compa = hr_df["Salary"] / hr_df["Job_Level"].map(level_medians)
        # By construction, median compa-ratio per level should be close to 1.0
        assert 0.9 <= compa.median() <= 1.1

    def test_gender_pay_gap_within_documented_range(self, hr_df):
        male_avg = hr_df[hr_df["Gender"] == "Male"]["Salary"].mean()
        female_avg = hr_df[hr_df["Gender"] == "Female"]["Salary"].mean()
        gap_pct = (male_avg - female_avg) / male_avg * 100
        # Documented design target: ~2-4% gap at mid levels: overall should be small but present
        assert -2 <= gap_pct <= 8, f"Gender pay gap {gap_pct:.2f}% outside plausible designed range"

    def test_salary_increases_with_job_level(self, hr_df):
        """Monotonicity check: median salary must increase with level rank."""
        level_order = ["L1","L2","L3","L4","L5","L6","L7","L8"]
        medians = hr_df.groupby("Job_Level")["Salary"].median()
        present_levels = [l for l in level_order if l in medians.index]
        values = [medians[l] for l in present_levels]
        assert values == sorted(values), "Median salary is not monotonically increasing with job level"


class TestPerformanceKPIs:
    def test_performance_distribution_matches_forced_curve(self, hr_df):
        """Validates against the documented target distribution:
        5% Distinguished, 26% Exceeds, 53% Meets, 12% Below, 3% Unacceptable
        (Phase 3 design doc) — wide tolerance since this is a statistical target."""
        dist = hr_df["Performance_Rating"].value_counts(normalize=True).sort_index() * 100
        assert abs(dist.get(5, 0) - 5) < 4
        assert abs(dist.get(3, 0) - 53) < 8

    def test_pip_population_is_small_minority(self, hr_df):
        pip_rate = (hr_df["Performance_Rating"] == 1).mean()
        assert pip_rate < 0.10
