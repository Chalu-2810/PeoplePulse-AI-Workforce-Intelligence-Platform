"""
PeoplePulse AI — Enterprise Workforce Intelligence Platform
=============================================================
Phase 9: Streamlit SaaS Application | Entry Point / Login

Run with: streamlit run Home.py
"""

import streamlit as st
from utils.helpers import check_login, USER_DIRECTORY, CUSTOM_CSS, BRAND_COLORS

st.set_page_config(
    page_title="PeoplePulse AI | Login",
    page_icon="👥",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# ── Session state initialization ─────────────────────────────────
if "user" not in st.session_state:
    st.session_state["user"] = None
if "dark_mode" not in st.session_state:
    st.session_state["dark_mode"] = False

st.markdown(CUSTOM_CSS, unsafe_allow_html=True)

# Hide sidebar entirely on login page
st.markdown("""
    <style>
        section[data-testid="stSidebar"] {display: none;}
        [data-testid="collapsedControl"] {display: none;}
    </style>
""", unsafe_allow_html=True)


# ── If already logged in, redirect to overview ───────────────────
if st.session_state["user"] is not None:
    st.switch_page("pages/1_Executive_Overview.py")


# ── Login UI ───────────────────────────────────────────────────────
col_l, col_mid, col_r = st.columns([1, 1.3, 1])

with col_mid:
    st.markdown("<br><br>", unsafe_allow_html=True)

    st.markdown(f"""
        <div style="text-align:center; margin-bottom:1.5rem;">
            <div style="font-size:2.2rem;">👥</div>
            <div style="font-size:1.8rem; font-weight:800; color:{BRAND_COLORS['primary']};">
                PeoplePulse AI
            </div>
            <div style="font-size:0.95rem; opacity:0.65; margin-top:4px;">
                Enterprise Workforce Intelligence Platform
            </div>
        </div>
    """, unsafe_allow_html=True)

    with st.container(border=True):
        st.markdown("#### Sign In")

        email = st.text_input("Work Email", placeholder="you@peoplepulse.ai")
        password = st.text_input("Password", type="password", placeholder="••••••••")

        col_a, col_b = st.columns(2)
        with col_a:
            login_clicked = st.button("Sign In", type="primary", use_container_width=True)
        with col_b:
            sso_clicked = st.button("SSO (SAML)", use_container_width=True, disabled=True,
                                     help="SSO available on Enterprise tier")

        if login_clicked:
            user = check_login(email, password)
            if user:
                st.session_state["user"] = user
                st.success(f"Welcome back, {user['name']}!")
                st.switch_page("pages/1_Executive_Overview.py")
            else:
                st.error("Invalid email or password. Try a demo account below.")

    with st.expander("🔑 Demo credentials (click to expand)"):
        st.markdown("""
        | Role | Email | Password | Scope |
        |---|---|---|---|
        | **CEO / CHRO** | `ceo@peoplepulse.ai` | `admin123` | All departments, all pages |
        | **HR Director** | `hrdirector@peoplepulse.ai` | `hrdir123` | All departments |
        | **HRBP — Customer Success** | `hrbp.cs@peoplepulse.ai` | `hrbp123` | Customer Success only |
        | **HRBP — Engineering** | `hrbp.eng@peoplepulse.ai` | `hrbp123` | Engineering only |
        | **Total Rewards** | `totalrewards@peoplepulse.ai` | `comp123` | Comp & Diversity pages |
        | **Admin** | `admin@peoplepulse.ai` | `super123` | Full access + Admin Panel |
        """)

    st.markdown(f"""
        <div style="text-align:center; margin-top:1.5rem; font-size:0.78rem; opacity:0.5;">
            PeoplePulse AI v1.0 &nbsp;·&nbsp; SOC 2 Type II &nbsp;·&nbsp; GDPR Compliant<br>
            10,000 employees &nbsp;·&nbsp; 11 departments &nbsp;·&nbsp; ML-powered flight risk
        </div>
    """, unsafe_allow_html=True)
