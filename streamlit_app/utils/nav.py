"""
Shared sidebar navigation rendered on every authenticated page.
"""

import streamlit as st
from utils.helpers import ROLE_PAGE_ACCESS, PAGE_LABELS

PAGE_FILE_MAP = {
    "overview":        "pages/1_Executive_Overview.py",
    "workforce":       "pages/2_Workforce_Analytics.py",
    "attrition":       "pages/3_Attrition_Intelligence.py",
    "compensation":    "pages/4_Compensation_Analytics.py",
    "recruitment":     "pages/5_Recruitment_Analytics.py",
    "performance":     "pages/6_Performance_Analytics.py",
    "diversity":       "pages/7_Diversity_Analytics.py",
    "predictive":      "pages/8_Predictive_Analytics.py",
    "employee_search": "pages/9_Employee_Search.py",
    "ai_insights":      "pages/10_AI_Insights.py",
    "admin":           "pages/11_Admin_Panel.py",
}


def render_sidebar(user: dict, active_page: str = ""):
    with st.sidebar:
        st.markdown(f"""
            <div style="text-align:center; padding: 0.5rem 0 1rem 0;">
                <div style="font-size:1.6rem;">👥</div>
                <div style="font-weight:800; font-size:1.15rem;">PeoplePulse AI</div>
                <div style="font-size:0.7rem; opacity:0.6;">Workforce Intelligence</div>
            </div>
        """, unsafe_allow_html=True)

        st.markdown(f"**{user['name']}**")
        st.caption(f"{user['role']}" + (f" · {user['department']}" if user['department'] else " · All Departments"))

        st.markdown("---")

        accessible = ROLE_PAGE_ACCESS.get(user["role"], [])
        for page_key in accessible:
            file = PAGE_FILE_MAP.get(page_key)
            label = PAGE_LABELS.get(page_key, page_key)
            is_active = (page_key == active_page)
            if file:
                if is_active:
                    st.markdown(f"**→ {label}**")
                else:
                    st.page_link(file, label=label)

        st.markdown("---")

        # Dark mode toggle
        dark = st.toggle("🌙 Dark Mode", value=st.session_state.get("dark_mode", False))
        if dark != st.session_state.get("dark_mode", False):
            st.session_state["dark_mode"] = dark
            st.rerun()

        if st.button("🚪 Sign Out", use_container_width=True):
            st.session_state["user"] = None
            st.switch_page("Home.py")

        st.markdown("""
            <div style="font-size:0.65rem; opacity:0.45; text-align:center; margin-top:1rem;">
                v1.0 · Data refreshed Jun 14, 2026<br>Model v1.0 (LogReg, AUC 0.601)
            </div>
        """, unsafe_allow_html=True)


def apply_dark_mode():
    """Inject CSS overrides if dark mode is enabled (Streamlit theme workaround)."""
    if st.session_state.get("dark_mode", False):
        st.markdown("""
            <style>
                .stApp { background-color: #0e1117; color: #e6e6e6; }
                section[data-testid="stSidebar"] { background-color: #161a23; }
                div[data-testid="metric-container"] { background: #1a1f2b; border-color: #2d3343; }
                .pp-card { background: #1a1f2b; border-color: #2d3343; }
            </style>
        """, unsafe_allow_html=True)
