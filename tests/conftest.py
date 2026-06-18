"""
PeoplePulse AI — Pytest Shared Fixtures
==========================================
"""

import pytest
import pandas as pd
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent


@pytest.fixture(scope="session")
def hr_df():
    """Loads the raw HR dataset once per test session."""
    path = PROJECT_ROOT / "data" / "PeoplePulse_HR_Dataset.csv"
    df = pd.read_csv(path)
    df["Exit_Reason"] = df["Exit_Reason"].fillna("N/A")
    return df


@pytest.fixture(scope="session")
def risk_predictions_df():
    """Loads ML risk prediction output, if it has been generated."""
    path = PROJECT_ROOT / "ml_models" / "attrition_predictions.csv"
    if not path.exists():
        pytest.skip("attrition_predictions.csv not found — run ml_models/train_attrition_model.py first")
    return pd.read_csv(path)


@pytest.fixture(scope="session")
def model_comparison_df():
    path = PROJECT_ROOT / "ml_models" / "model_comparison.csv"
    if not path.exists():
        pytest.skip("model_comparison.csv not found — run ml_models/train_attrition_model.py first")
    return pd.read_csv(path)
