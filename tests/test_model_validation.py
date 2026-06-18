"""
PeoplePulse AI — Model Validation Tests
==========================================
Validates the trained attrition prediction model's outputs:
risk tier monotonicity, SHAP driver presence, score boundedness,
and model comparison sanity.

Requires ml_models/train_attrition_model.py to have been run first
(tests will be skipped with a clear message otherwise).

Run: pytest tests/test_model_validation.py -v
"""

import pandas as pd
import numpy as np


class TestRiskScoreOutput:
    def test_all_employees_scored(self, risk_predictions_df, hr_df):
        assert len(risk_predictions_df) == len(hr_df)

    def test_risk_score_bounded_0_100(self, risk_predictions_df):
        assert risk_predictions_df["Risk_Score"].between(0, 100).all()

    def test_model_probability_bounded_0_1(self, risk_predictions_df):
        assert risk_predictions_df["Model_Probability"].between(0, 1).all()

    def test_risk_tier_values_valid(self, risk_predictions_df):
        valid_tiers = {"Low", "Medium", "High", "Critical"}
        assert set(risk_predictions_df["Risk_Tier"].unique()) <= valid_tiers

    def test_every_employee_has_top3_drivers(self, risk_predictions_df):
        assert risk_predictions_df["Top_3_Drivers"].notna().all()
        assert (risk_predictions_df["Top_3_Drivers"].str.len() > 0).all()

    def test_risk_score_consistent_with_probability(self, risk_predictions_df):
        """Risk_Score should equal Model_Probability * 100 (within rounding)."""
        diff = (risk_predictions_df["Risk_Score"] - risk_predictions_df["Model_Probability"] * 100).abs()
        assert (diff < 0.5).all(), "Risk_Score and Model_Probability*100 diverge beyond rounding tolerance"


class TestRiskTierCalibration:
    """
    The core model validation: actual historical attrition rate MUST
    increase monotonically across Low -> Medium -> High -> Critical tiers.
    This is the test that would have caught the fixed-threshold
    miscalibration bug documented in the Phase 8 case study.
    """

    def test_monotonic_attrition_rate_across_tiers(self, risk_predictions_df):
        tier_order = ["Low", "Medium", "High", "Critical"]
        rates = []
        for tier in tier_order:
            subset = risk_predictions_df[risk_predictions_df["Risk_Tier"] == tier]
            if len(subset) == 0:
                continue
            rate = (subset["Attrition"] == "Yes").mean()
            rates.append(rate)

        assert len(rates) >= 2, "Need at least 2 populated tiers to test monotonicity"
        assert all(rates[i] <= rates[i+1] for i in range(len(rates)-1)), (
            f"Risk tiers are NOT monotonically increasing in actual attrition rate: {rates}. "
            f"This indicates a threshold calibration bug — see docs/10_career_assets.md "
            f"'Debugging a Model Validation Failure' for the known failure pattern."
        )

    def test_critical_tier_meaningfully_riskier_than_low(self, risk_predictions_df):
        """Validates the documented 3.4x lift finding — uses a conservative
        1.5x minimum to avoid over-fitting the test to one exact run."""
        low = risk_predictions_df[risk_predictions_df["Risk_Tier"] == "Low"]
        critical = risk_predictions_df[risk_predictions_df["Risk_Tier"] == "Critical"]
        if len(low) == 0 or len(critical) == 0:
            return
        low_rate = (low["Attrition"] == "Yes").mean()
        critical_rate = (critical["Attrition"] == "Yes").mean()
        lift = critical_rate / low_rate if low_rate > 0 else float("inf")
        assert lift >= 1.5, f"Critical/Low attrition lift is only {lift:.2f}x — expected >= 1.5x"

    def test_critical_tier_is_small_minority(self, risk_predictions_df):
        """Critical tier should be a small, actionable list (~2.5% of population
        per the documented percentile-based segmentation design), not a large
        chunk — otherwise it isn't operationally useful for HRBP triage."""
        critical_pct = (risk_predictions_df["Risk_Tier"] == "Critical").mean()
        assert critical_pct <= 0.10, f"Critical tier is {critical_pct:.1%} of population — too large to be actionable"


class TestModelComparison:
    def test_all_four_models_present(self, model_comparison_df):
        expected_models = {"Logistic Regression", "Random Forest", "XGBoost (default)", "XGBoost (tuned)"}
        actual_models = set(model_comparison_df["Model"])
        assert expected_models <= actual_models

    def test_all_models_beat_random_baseline(self, model_comparison_df):
        """AUC of 0.5 = random guessing. Every trained model should exceed this."""
        assert (model_comparison_df["AUC"] > 0.5).all()

    def test_precision_at_top10_exceeds_base_rate(self, model_comparison_df):
        """Lift > 1.0 means the model concentrates true positives better
        than random selection — the minimum bar for the model to be useful."""
        assert (model_comparison_df["Lift vs Baseline"] > 1.0).all()


class TestFeatureImportance:
    def test_feature_importance_file_has_expected_columns(self):
        import pathlib
        path = pathlib.Path(__file__).parent.parent / "ml_models" / "feature_importance.csv"
        if not path.exists():
            import pytest
            pytest.skip("feature_importance.csv not found")
        df = pd.read_csv(path)
        assert "feature" in df.columns
        assert "mean_abs_shap" in df.columns

    def test_no_negative_shap_importance_values(self):
        """mean_abs_shap is, by definition, an absolute value and must be >= 0."""
        import pathlib
        path = pathlib.Path(__file__).parent.parent / "ml_models" / "feature_importance.csv"
        if not path.exists():
            import pytest
            pytest.skip("feature_importance.csv not found")
        df = pd.read_csv(path)
        assert (df["mean_abs_shap"] >= 0).all()
