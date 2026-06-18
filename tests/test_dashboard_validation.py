"""
PeoplePulse AI — Dashboard / Application Validation Tests
=============================================================
Validates the Streamlit application's auth, RBAC, and helper logic
without requiring a running server (unit-level checks). For full
end-to-end browser testing, see the smoke-test instructions in
docs/09_streamlit_deployment_guide.md (Selenium/Playwright optional).

Run: pytest tests/test_dashboard_validation.py -v
"""

import sys
import pathlib
import pytest

PROJECT_ROOT = pathlib.Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "streamlit_app"))


@pytest.fixture(scope="module")
def helpers():
    from utils import helpers
    return helpers


class TestAuthentication:
    def test_valid_login_succeeds(self, helpers):
        user = helpers.check_login("ceo@peoplepulse.ai", "admin123")
        assert user is not None
        assert user["role"] == "CEO/CHRO"

    def test_invalid_password_fails(self, helpers):
        user = helpers.check_login("ceo@peoplepulse.ai", "wrongpassword")
        assert user is None

    def test_nonexistent_user_fails(self, helpers):
        user = helpers.check_login("nobody@peoplepulse.ai", "anything")
        assert user is None

    def test_email_case_insensitive(self, helpers):
        user = helpers.check_login("CEO@PeoplePulse.AI", "admin123")
        assert user is not None

    def test_all_demo_accounts_login_successfully(self, helpers):
        demo_creds = [
            ("ceo@peoplepulse.ai", "admin123"),
            ("hrdirector@peoplepulse.ai", "hrdir123"),
            ("hrbp.cs@peoplepulse.ai", "hrbp123"),
            ("hrbp.eng@peoplepulse.ai", "hrbp123"),
            ("totalrewards@peoplepulse.ai", "comp123"),
            ("admin@peoplepulse.ai", "super123"),
        ]
        for email, pw in demo_creds:
            user = helpers.check_login(email, pw)
            assert user is not None, f"Demo login failed for {email}"


class TestRoleBasedAccessControl:
    def test_ceo_has_access_to_all_pages(self, helpers):
        ceo = helpers.check_login("ceo@peoplepulse.ai", "admin123")
        for page in ["overview", "workforce", "attrition", "compensation",
                     "recruitment", "performance", "diversity", "predictive",
                     "employee_search", "admin"]:
            assert helpers.has_access(ceo, page), f"CEO should have access to {page}"

    def test_hrbp_does_not_have_admin_access(self, helpers):
        hrbp = helpers.check_login("hrbp.cs@peoplepulse.ai", "hrbp123")
        assert not helpers.has_access(hrbp, "admin")

    def test_hrbp_does_not_have_compensation_access(self, helpers):
        hrbp = helpers.check_login("hrbp.cs@peoplepulse.ai", "hrbp123")
        assert not helpers.has_access(hrbp, "compensation")

    def test_total_rewards_has_compensation_access(self, helpers):
        tr = helpers.check_login("totalrewards@peoplepulse.ai", "comp123")
        assert helpers.has_access(tr, "compensation")

    def test_total_rewards_does_not_have_admin_access(self, helpers):
        tr = helpers.check_login("totalrewards@peoplepulse.ai", "comp123")
        assert not helpers.has_access(tr, "admin")


class TestRowLevelSecurity:
    def test_hrbp_filter_returns_only_assigned_department(self, helpers):
        df = helpers.load_hr_data()
        hrbp = helpers.check_login("hrbp.cs@peoplepulse.ai", "hrbp123")
        filtered = helpers.filter_by_role(df, hrbp)
        assert (filtered["Department"] == "Customer Success").all()
        assert len(filtered) > 0
        assert len(filtered) < len(df)

    def test_ceo_filter_returns_full_dataset(self, helpers):
        df = helpers.load_hr_data()
        ceo = helpers.check_login("ceo@peoplepulse.ai", "admin123")
        filtered = helpers.filter_by_role(df, ceo)
        assert len(filtered) == len(df)

    def test_two_hrbps_see_different_data(self, helpers):
        df = helpers.load_hr_data()
        hrbp_cs = helpers.check_login("hrbp.cs@peoplepulse.ai", "hrbp123")
        hrbp_eng = helpers.check_login("hrbp.eng@peoplepulse.ai", "hrbp123")
        filtered_cs = helpers.filter_by_role(df, hrbp_cs)
        filtered_eng = helpers.filter_by_role(df, hrbp_eng)
        assert set(filtered_cs["Employee_ID"]).isdisjoint(set(filtered_eng["Employee_ID"]))


class TestDataLoading:
    def test_load_hr_data_returns_expected_shape(self, helpers):
        df = helpers.load_hr_data()
        assert len(df) == 10_000

    def test_derived_columns_present(self, helpers):
        df = helpers.load_hr_data()
        for col in ["Compa_Ratio", "Tenure_Band", "Engagement_Tier", "Promotion_Gap", "Total_Comp"]:
            assert col in df.columns, f"Derived column {col} missing from load_hr_data() output"

    def test_compa_ratio_is_positive(self, helpers):
        df = helpers.load_hr_data()
        assert (df["Compa_Ratio"] > 0).all()


class TestExportFunctions:
    def test_excel_export_produces_nonempty_bytes(self, helpers):
        import pandas as pd
        sample = pd.DataFrame({"A": [1, 2], "B": [3, 4]})
        result = helpers.to_excel_bytes(sample)
        assert isinstance(result, bytes)
        assert len(result) > 100  # a valid xlsx is never this small

    def test_pdf_export_produces_nonempty_bytes(self, helpers):
        result = helpers.to_pdf_bytes("Test Report", {"Metric A": "100", "Metric B": "200"})
        assert isinstance(result, bytes)
        assert len(result) > 100
        assert result[:4] == b"%PDF"  # PDF magic bytes


class TestPageFileIntegrity:
    """Confirms every page referenced in ROLE_PAGE_ACCESS has a
    corresponding, syntactically valid .py file on disk."""

    def test_all_referenced_pages_exist_on_disk(self, helpers):
        sys.path.insert(0, str(PROJECT_ROOT / "streamlit_app"))
        from utils.nav import PAGE_FILE_MAP

        all_pages = set()
        for pages in helpers.ROLE_PAGE_ACCESS.values():
            all_pages.update(pages)

        for page_key in all_pages:
            file_path = PAGE_FILE_MAP.get(page_key)
            assert file_path is not None, f"No file mapping for page key '{page_key}'"
            full_path = PROJECT_ROOT / "streamlit_app" / file_path
            assert full_path.exists(), f"Page file missing: {full_path}"

    def test_all_page_files_have_valid_python_syntax(self):
        import ast
        pages_dir = PROJECT_ROOT / "streamlit_app" / "pages"
        for py_file in pages_dir.glob("*.py"):
            try:
                ast.parse(py_file.read_text(encoding="utf-8"))
            except SyntaxError as e:
                pytest.fail(f"Syntax error in {py_file.name}: {e}")
