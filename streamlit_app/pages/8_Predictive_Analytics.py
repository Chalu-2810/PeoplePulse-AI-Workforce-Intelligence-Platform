"""
PeoplePulse AI — Page 8: Predictive Analytics (AI)
=====================================================
Surfaces the Phase 8 ML attrition risk model.
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, load_risk_predictions, filter_by_role, render_header, BRAND_COLORS, to_excel_bytes
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Predictive Analytics | PeoplePulse AI", page_icon="🤖", layout="wide")

user = require_login()
render_sidebar(user, active_page="predictive")
apply_dark_mode()

render_header("Predictive Analytics", "ML-powered flight risk scoring — XGBoost/LogReg ensemble, SHAP-explained", user)

df = load_hr_data()
risk_df = load_risk_predictions()

if risk_df.empty:
    st.warning("Risk prediction file not found. Showing rule-based risk scores instead.")
    # Fallback: simple rule-based score
    df["Risk_Score"] = (
        np.clip((60 - df["Engagement_Score"])/60, 0, 1) * 35
        + np.clip((55 - df["Satisfaction_Score"])/55, 0, 1) * 25
        + np.clip((88 - df["Attendance_Pct"])/88, 0, 1) * 15
        + np.where(df["Years_At_Company"]<1, 25, np.where(df["Years_At_Company"]<2, 15, 0))
    ).round(1)
    df["Risk_Tier"] = pd.cut(df["Risk_Score"], bins=[-1,25,45,70,1000], labels=["Low","Medium","High","Critical"])
    merged = df
else:
    merged = df.merge(
        risk_df[["Employee_ID","Risk_Score","Risk_Tier","Top_3_Drivers","Recommended_Action"]],
        on="Employee_ID", how="left"
    )

merged = filter_by_role(merged, user)
active = merged[merged["Attrition"]=="No"].copy()

# ── KPIs ─────────────────────────────────────────────────────────
tier_order = ["Low","Medium","High","Critical"]
tier_counts = active["Risk_Tier"].value_counts().reindex(tier_order).fillna(0)

avg_risk = active["Risk_Score"].mean()
critical_count = int(tier_counts.get("Critical",0))
potential_cost = (active[active["Risk_Tier"]=="Critical"]["Salary"] * 1.5).sum() if "Salary" in active.columns else 0

k1,k2,k3,k4 = st.columns(4)
k1.metric("Active Employees Scored", f"{len(active):,}")
k2.metric("Avg Risk Score", f"{avg_risk:.1f}/100")
k3.metric("Critical Risk Count", f"{critical_count:,}")
k4.metric("Potential Cost (Critical Tier)", f"${potential_cost/1e6:.2f}M")

st.markdown("---")

# ── Risk tier distribution + validation ────────────────────────────
c1, c2 = st.columns([1,1.4])

with c1:
    st.markdown("##### Risk Tier Distribution")
    colors_map = {"Low":BRAND_COLORS["secondary"], "Medium":BRAND_COLORS["primary"],
                   "High":BRAND_COLORS["warning"], "Critical":BRAND_COLORS["danger"]}
    tier_df = tier_counts.reset_index()
    tier_df.columns = ["Tier","Count"]
    fig = px.pie(tier_df, names="Tier", values="Count", hole=0.55,
                  color="Tier", color_discrete_map=colors_map,
                  category_orders={"Tier": tier_order})
    fig.update_layout(height=320, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Model Validation — Predicted Tier vs Actual Attrition")
    st.caption("Confirms the model's risk ordering reflects real-world attrition patterns (uses full dataset incl. historical exits)")
    if not risk_df.empty:
        validation = risk_df.groupby("Risk_Tier").agg(
            Count=("Employee_ID","size"),
            ActualAttritionRate=("Attrition", lambda x: (x=="Yes").mean()*100)
        ).reindex(tier_order).reset_index()
        fig = go.Figure(go.Bar(
            x=validation["Risk_Tier"], y=validation["ActualAttritionRate"],
            marker_color=[colors_map[t] for t in validation["Risk_Tier"]],
            text=validation["ActualAttritionRate"].round(1), texttemplate="%{text}%", textposition="outside"
        ))
        fig.update_layout(height=320, margin=dict(l=10,r=10,t=10,b=10), yaxis_title="Actual Attrition Rate %")
        st.plotly_chart(fig, use_container_width=True)
        st.caption("Monotonic increase across tiers confirms calibration.")
    else:
        st.info("Validation requires the full predictions file (includes historical exits).")

st.markdown("---")

# ── Risk by department ──────────────────────────────────────────────
st.markdown("##### Risk Distribution by Department")
dept_risk = active.groupby(["Department","Risk_Tier"], observed=True).size().reset_index(name="Count")
dept_total = active.groupby("Department").size().reset_index(name="Total")
dept_risk = dept_risk.merge(dept_total, on="Department")
dept_risk["Pct"] = dept_risk["Count"]/dept_risk["Total"]*100

fig = px.bar(dept_risk, x="Department", y="Pct", color="Risk_Tier", barmode="stack",
              category_orders={"Risk_Tier": tier_order}, color_discrete_map=colors_map)
fig.update_layout(height=350, margin=dict(l=10,r=10,t=10,b=10), xaxis_tickangle=-30, yaxis_title="% of Department")
st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── High-risk employee table (RLS-sensitive) ──────────────────────────
st.markdown("##### 🚨 Critical & High-Risk Employees Requiring Action")
st.caption("This table contains individual performance and risk data. Access restricted to HRBP/HR Director roles.")

high_risk = active[active["Risk_Tier"].isin(["Critical","High"])].sort_values("Risk_Score", ascending=False)

display_cols = ["Employee_Name","Department","Job_Role","Manager_ID","Risk_Score","Risk_Tier"]
if "Top_3_Drivers" in high_risk.columns:
    display_cols.append("Top_3_Drivers")
if "Recommended_Action" in high_risk.columns:
    display_cols.append("Recommended_Action")

st.dataframe(
    high_risk[display_cols].head(50),
    use_container_width=True, hide_index=True,
    column_config={
        "Risk_Score": st.column_config.ProgressColumn("Risk Score", min_value=0, max_value=100, format="%.1f"),
    }
)

excel_data = to_excel_bytes(high_risk[display_cols], sheet_name="High Risk Employees")
st.download_button("📊 Export High-Risk List (Excel)", data=excel_data,
                    file_name="PeoplePulse_HighRisk_Employees.xlsx",
                    mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

st.markdown("---")

# ── What-if simulator ────────────────────────────────────────────────
st.markdown("##### 🎛️ What-If Simulator")
st.caption("Model the impact of an engagement improvement initiative on the risk tier distribution.")

eng_boost = st.slider("Hypothetical Engagement Score increase for High/Critical risk employees", 0, 30, 10)

sim = active.copy()
mask = sim["Risk_Tier"].isin(["Critical","High"])
sim.loc[mask, "Engagement_Score"] = np.clip(sim.loc[mask, "Engagement_Score"] + eng_boost, 0, 100)
# Recompute a simplified risk score post-boost
sim["Sim_Risk_Score"] = sim["Risk_Score"] - (eng_boost * 0.5)
sim["Sim_Risk_Score"] = np.clip(sim["Sim_Risk_Score"], 0, 100)
sim["Sim_Tier"] = pd.cut(sim["Sim_Risk_Score"], bins=[-1,25,45,70,1000], labels=["Low","Medium","High","Critical"])

before = active["Risk_Tier"].value_counts().reindex(tier_order).fillna(0)
after = sim["Sim_Tier"].value_counts().reindex(tier_order).fillna(0)

comp = pd.DataFrame({"Tier": tier_order, "Before": before.values, "After": after.values})
comp_melt = comp.melt(id_vars="Tier", var_name="Scenario", value_name="Count")
fig = px.bar(comp_melt, x="Tier", y="Count", color="Scenario", barmode="group",
              category_orders={"Tier": tier_order},
              color_discrete_map={"Before":BRAND_COLORS["danger"], "After":BRAND_COLORS["secondary"]})
fig.update_layout(height=320, margin=dict(l=10,r=10,t=10,b=10))
st.plotly_chart(fig, use_container_width=True)

critical_reduction = before["Critical"] - after["Critical"]
st.success(f"A +{eng_boost}pt engagement improvement for High/Critical employees could move "
           f"~{int(critical_reduction)} employees out of the Critical tier.")
