"""
PeoplePulse AI — Shared Utilities
===================================
Authentication, RBAC, data loading, theming, and export helpers
shared across all pages of the Streamlit SaaS application.
"""

import streamlit as st
import pandas as pd
import numpy as np
import hashlib
from pathlib import Path
from io import BytesIO

DATA_DIR = Path(__file__).parent.parent / "data"

# ════════════════════════════════════════════════════════════════
# USER DIRECTORY (in production: replace with DB / SSO / Auth0)
# ════════════════════════════════════════════════════════════════
# Passwords are stored as SHA-256 hashes. Demo credentials are
# printed on the login page for evaluation purposes.

def _hash(pw: str) -> str:
    return hashlib.sha256(pw.encode()).hexdigest()

USER_DIRECTORY = {
    "ceo@peoplepulse.ai": {
        "name": "Victoria Chen",
        "role": "CEO/CHRO",
        "password_hash": _hash("admin123"),
        "department": None,   # None = all departments
    },
    "hrdirector@peoplepulse.ai": {
        "name": "Marcus Williams",
        "role": "HR Director",
        "password_hash": _hash("hrdir123"),
        "department": None,
    },
    "hrbp.cs@peoplepulse.ai": {
        "name": "Priya Nair",
        "role": "HRBP",
        "password_hash": _hash("hrbp123"),
        "department": "Customer Success",
    },
    "hrbp.eng@peoplepulse.ai": {
        "name": "Rachel Kim",
        "role": "HRBP",
        "password_hash": _hash("hrbp123"),
        "department": "Engineering",
    },
    "totalrewards@peoplepulse.ai": {
        "name": "David Osei",
        "role": "Total Rewards",
        "password_hash": _hash("comp123"),
        "department": None,
    },
    "admin@peoplepulse.ai": {
        "name": "System Admin",
        "role": "Admin",
        "password_hash": _hash("super123"),
        "department": None,
    },
}

# Pages each role can access (controls sidebar nav rendering)
ROLE_PAGE_ACCESS = {
    "CEO/CHRO":       ["overview","workforce","attrition","compensation","recruitment",
                        "performance","diversity","predictive","employee_search",
                        "admin", "ai_insights"],
    "HR Director":    ["overview","workforce","attrition","compensation","recruitment",
                        "performance","diversity","predictive","employee_search","ai_insights"],
    "HRBP":           ["overview","attrition","performance","predictive","employee_search","ai_insights"],
    "Total Rewards":  ["overview","compensation","diversity","ai_insights"],
    "Admin":          ["overview","workforce","attrition","compensation","recruitment",
                        "performance","diversity","predictive","employee_search",
                        "admin","ai_insights"],
}

PAGE_LABELS = {
    "overview":        "📊 Executive Overview",
    "workforce":       "👥 Workforce Analytics",
    "attrition":       "📉 Attrition Intelligence",
    "compensation":    "💰 Compensation Analytics",
    "recruitment":     "🎯 Recruitment Analytics",
    "performance":     "⭐ Performance Analytics",
    "diversity":       "🌐 Diversity Analytics",
    "predictive":      "🤖 Predictive Analytics (AI)",
    "employee_search": "🔍 Employee Search",
    "ai_insights":     "💡 AI Insights",
    "admin":           "⚙️ Admin Panel",
}


# ════════════════════════════════════════════════════════════════
# AUTHENTICATION
# ════════════════════════════════════════════════════════════════

def check_login(email: str, password: str):
    """Returns user dict if credentials valid, else None."""
    user = USER_DIRECTORY.get(email.lower().strip())
    if user and user["password_hash"] == _hash(password):
        return {**user, "email": email.lower().strip()}
    return None


def require_login():
    """Call at the top of every page. Redirects to login if not authenticated."""
    if "user" not in st.session_state or st.session_state["user"] is None:
        st.switch_page("Home.py")
        st.stop()
    return st.session_state["user"]


def has_access(user, page_key: str) -> bool:
    return page_key in ROLE_PAGE_ACCESS.get(user["role"], [])


# ════════════════════════════════════════════════════════════════
# DATA LOADING (cached)
# ════════════════════════════════════════════════════════════════

@st.cache_data(show_spinner=False)
def load_hr_data() -> pd.DataFrame:
    df = pd.read_csv(DATA_DIR / "PeoplePulse_HR_Dataset.csv")
    df["Exit_Reason"] = df["Exit_Reason"].fillna("N/A")

    # Derived columns (mirrors Phase 4 calculated columns)
    level_medians = df.groupby("Job_Level")["Salary"].median()
    df["Level_Median_Salary"] = df["Job_Level"].map(level_medians)
    df["Compa_Ratio"] = (df["Salary"] / df["Level_Median_Salary"]).round(4)

    bins = [0, 1, 2, 3, 5, 8, 12, 100]
    labels = ["<1yr","1-2yr","2-3yr","3-5yr","5-8yr","8-12yr","12yr+"]
    df["Tenure_Band"] = pd.cut(df["Years_At_Company"], bins=bins, labels=labels)

    df["Engagement_Tier"] = pd.cut(
        df["Engagement_Score"], bins=[0,40,60,75,100],
        labels=["High Risk","Medium Risk","Low Risk","Engaged"]
    )

    df["Promotion_Gap"] = (df["Years_At_Company"]/2.8 - df["Promotions"]).round(2)
    df["Total_Comp"] = df["Salary"] + df["Bonus"]
    return df


@st.cache_data(show_spinner=False)
def load_risk_predictions() -> pd.DataFrame:
    path = DATA_DIR / "PeoplePulse_Attrition_Predictions.csv"
    if path.exists():
        return pd.read_csv(path)
    return pd.DataFrame()


def filter_by_role(df: pd.DataFrame, user: dict) -> pd.DataFrame:
    """Applies row-level security based on the user's department assignment."""
    if user["department"] is None:
        return df
    return df[df["Department"] == user["department"]]


# ════════════════════════════════════════════════════════════════
# EXPORT HELPERS
# ════════════════════════════════════════════════════════════════

def to_excel_bytes(df: pd.DataFrame, sheet_name="Data") -> bytes:
    buffer = BytesIO()
    with pd.ExcelWriter(buffer, engine="openpyxl") as writer:
        df.to_excel(writer, index=False, sheet_name=sheet_name)
        worksheet = writer.sheets[sheet_name]
        # Auto-fit columns (approx)
        for i, col in enumerate(df.columns):
            max_len = max(df[col].astype(str).map(len).max(), len(col)) + 2
            worksheet.column_dimensions[chr(65 + i if i < 26 else 65)].width = min(max_len, 40)
    return buffer.getvalue()


def to_pdf_bytes(title: str, kpi_dict: dict, table_df: pd.DataFrame = None) -> bytes:
    from reportlab.lib.pagesizes import letter
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
    from reportlab.lib.units import inch

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter,
                             topMargin=0.6*inch, bottomMargin=0.6*inch)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("CustomTitle", parent=styles["Title"],
                                  textColor=colors.HexColor("#0066CC"), fontSize=20)
    elements = [Paragraph(title, title_style), Spacer(1, 12)]

    elements.append(Paragraph("Key Metrics", styles["Heading2"]))
    kpi_data = [[k, str(v)] for k, v in kpi_dict.items()]
    kpi_table = Table(kpi_data, colWidths=[3*inch, 2.5*inch])
    kpi_table.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#E6F1FB")),
        ("GRID", (0,0), (-1,-1), 0.5, colors.HexColor("#D3D1C7")),
        ("FONTSIZE", (0,0), (-1,-1), 10),
        ("ROWBACKGROUNDS", (0,0), (-1,-1), [colors.white, colors.HexColor("#F7F6F2")]),
        ("PADDING", (0,0), (-1,-1), 6),
    ]))
    elements.append(kpi_table)
    elements.append(Spacer(1, 20))

    if table_df is not None and len(table_df) > 0:
        elements.append(Paragraph("Detail Table", styles["Heading2"]))
        table_data = [list(table_df.columns)] + table_df.head(30).values.tolist()
        table_data = [[str(c) for c in row] for row in table_data]
        detail_table = Table(table_data, repeatRows=1)
        detail_table.setStyle(TableStyle([
            ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#0066CC")),
            ("TEXTCOLOR", (0,0), (-1,0), colors.white),
            ("FONTSIZE", (0,0), (-1,-1), 7),
            ("GRID", (0,0), (-1,-1), 0.25, colors.HexColor("#D3D1C7")),
            ("ROWBACKGROUNDS", (1,0), (-1,-1), [colors.white, colors.HexColor("#F7F6F2")]),
            ("PADDING", (0,0), (-1,-1), 3),
        ]))
        elements.append(detail_table)

    doc.build(elements)
    return buffer.getvalue()


# ════════════════════════════════════════════════════════════════
# THEME / STYLING
# ════════════════════════════════════════════════════════════════

BRAND_COLORS = {
    "primary": "#0066CC",
    "primary_light": "#E6F1FB",
    "secondary": "#1D9E75",
    "secondary_light": "#E1F5EE",
    "warning": "#BA7517",
    "warning_light": "#FAEEDA",
    "danger": "#D85A30",
    "danger_light": "#FAECE7",
    "purple": "#534AB7",
    "purple_light": "#EEEDFE",
}

CUSTOM_CSS = """
<style>
    .main { padding-top: 1rem; }
    div[data-testid="metric-container"] {
        background: var(--background-color);
        border: 1px solid rgba(128,128,128,0.2);
        border-radius: 10px;
        padding: 12px 16px;
    }
    .pp-header {
        display: flex; align-items: center; justify-content: space-between;
        padding-bottom: 0.5rem; margin-bottom: 1rem;
        border-bottom: 1px solid rgba(128,128,128,0.2);
    }
    .pp-title { font-size: 1.6rem; font-weight: 700; }
    .pp-subtitle { font-size: 0.85rem; opacity: 0.65; }
    .pp-badge {
        display: inline-block; padding: 2px 10px; border-radius: 12px;
        font-size: 0.72rem; font-weight: 600; margin-right: 4px;
    }
    .pp-badge-blue { background: #E6F1FB; color: #185FA5; }
    .pp-badge-green { background: #E1F5EE; color: #0F6E56; }
    .pp-badge-amber { background: #FAEEDA; color: #854F0B; }
    .pp-badge-red { background: #FAECE7; color: #993C1D; }
    .pp-card {
        border: 1px solid rgba(128,128,128,0.2); border-radius: 12px;
        padding: 1rem; margin-bottom: 0.75rem;
    }
    section[data-testid="stSidebar"] { width: 290px !important; }
</style>
"""


def render_header(title: str, subtitle: str, user: dict):
    role_badge_class = {
        "CEO/CHRO": "pp-badge-blue", "HR Director": "pp-badge-blue",
        "HRBP": "pp-badge-green", "Total Rewards": "pp-badge-amber",
        "Admin": "pp-badge-red"
    }.get(user["role"], "pp-badge-blue")

    st.markdown(CUSTOM_CSS, unsafe_allow_html=True)
    st.markdown(f"""
        <div class="pp-header">
            <div>
                <div class="pp-title">{title}</div>
                <div class="pp-subtitle">{subtitle}</div>
            </div>
            <div style="text-align:right">
                <div style="font-weight:600">{user['name']}</div>
                <span class="pp-badge {role_badge_class}">{user['role']}</span>
            </div>
        </div>
    """, unsafe_allow_html=True)
