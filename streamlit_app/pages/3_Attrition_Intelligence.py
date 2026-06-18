"""
PeoplePulse AI — Page 3: Attrition Intelligence
==================================================
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS, to_excel_bytes
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Attrition Intelligence | PeoplePulse AI", page_icon="📉", layout="wide")

user = require_login()
render_sidebar(user, active_page="attrition")
apply_dark_mode()

render_header("Attrition Intelligence", "Root-cause analysis of voluntary and regrettable attrition", user)

df = load_hr_data()
df = filter_by_role(df, user)

attrition_type = st.radio("Attrition View", ["All", "Voluntary Only", "Regrettable Only"], horizontal=True)

if attrition_type == "Regrettable Only":
    view_df = df[(df["Attrition"]=="Yes") & (df["Performance_Rating"]>=4)]
elif attrition_type == "Voluntary Only":
    view_df = df[(df["Attrition"]=="Yes") & (df["Exit_Reason"]!="N/A")]
else:
    view_df = df[df["Attrition"]=="Yes"]

# ── KPIs ─────────────────────────────────────────────────────────
overall_rate = (df["Attrition"]=="Yes").mean()*100
voluntary_rate = ((df["Attrition"]=="Yes") & (df["Exit_Reason"]!="N/A")).mean()*100
regrettable_rate = ((df["Attrition"]=="Yes") & (df["Performance_Rating"]>=4)).mean()*100
new_hire_mask = df["Years_At_Company"]<1
new_hire_attrition = (df[new_hire_mask]["Attrition"]=="Yes").mean()*100 if new_hire_mask.any() else 0
attrition_cost = (df[df["Attrition"]=="Yes"]["Salary"] * 1.5).sum()

k1,k2,k3,k4,k5 = st.columns(5)
k1.metric("Overall Attrition Rate", f"{overall_rate:.1f}%")
k2.metric("Voluntary Rate", f"{voluntary_rate:.1f}%")
k3.metric("Regrettable Rate", f"{regrettable_rate:.1f}%")
k4.metric("New Hire (<1yr) Attrition", f"{new_hire_attrition:.1f}%")
k5.metric("Attrition Cost Impact", f"${attrition_cost/1e6:.1f}M")

st.markdown("---")

# ── Attrition by Department + Survival curve ───────────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Attrition Rate by Department")
    dept_att = df.groupby("Department").agg(
        AttritionRate=("Attrition", lambda x: (x=="Yes").mean()*100),
        Headcount=("Employee_ID","count")
    ).reset_index().sort_values("AttritionRate", ascending=True)

    colors = [BRAND_COLORS["danger"] if v>=28 else BRAND_COLORS["warning"] if v>=18 else BRAND_COLORS["secondary"]
              for v in dept_att["AttritionRate"]]
    fig = go.Figure(go.Bar(
        y=dept_att["Department"], x=dept_att["AttritionRate"], orientation="h",
        marker_color=colors, text=dept_att["AttritionRate"].round(1), texttemplate="%{text}%",
        textposition="outside"
    ))
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), xaxis_title="Attrition Rate %")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Attrition by Tenure Band (Survival Curve)")
    tenure_order = ["<1yr","1-2yr","2-3yr","3-5yr","5-8yr","8-12yr","12yr+"]
    tenure_att = df.groupby("Tenure_Band", observed=True).agg(
        AttritionRate=("Attrition", lambda x: (x=="Yes").mean()*100)
    ).reindex(tenure_order).reset_index()

    fig = go.Figure(go.Scatter(
        x=tenure_att["Tenure_Band"], y=tenure_att["AttritionRate"],
        mode="lines+markers+text", text=tenure_att["AttritionRate"].round(1),
        texttemplate="%{text}%", textposition="top center",
        line=dict(color=BRAND_COLORS["danger"], width=3), marker=dict(size=10)
    ))
    fig.add_vrect(x0=-0.5, x1=1.5, fillcolor=BRAND_COLORS["danger_light"], opacity=0.4,
                   layer="below", line_width=0, annotation_text="Onboarding Risk Zone")
    fig.add_vrect(x0=4.5, x1=6.5, fillcolor=BRAND_COLORS["warning_light"], opacity=0.4,
                   layer="below", line_width=0, annotation_text="Career Pivot Zone")
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), yaxis_title="Attrition Rate %")
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Exit reasons + 9-box ────────────────────────────────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Exit Reason Distribution")
    exit_df = df[(df["Attrition"]=="Yes") & (df["Exit_Reason"]!="N/A")]
    exit_counts = exit_df["Exit_Reason"].value_counts().reset_index()
    exit_counts.columns = ["Reason","Count"]
    fig = px.bar(exit_counts.sort_values("Count"), x="Count", y="Reason", orientation="h",
                  color="Count", color_continuous_scale="Oranges")
    fig.update_layout(height=400, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False)
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### 9-Box: Engagement × Performance Matrix")
    df["EngSeg"] = pd.cut(df["Engagement_Score"], bins=[0,50,75,100], labels=["Low Eng","Mod Eng","High Eng"])
    df["PerfSeg"] = pd.cut(df["Performance_Rating"], bins=[0,2,3,5], labels=["Low Perf","Core Perf","High Perf"])

    nine_box = df.groupby(["EngSeg","PerfSeg"], observed=True).agg(
        Count=("Employee_ID","count"),
        AttritionRate=("Attrition", lambda x: (x=="Yes").mean()*100)
    ).reset_index()

    pivot = nine_box.pivot(index="EngSeg", columns="PerfSeg", values="AttritionRate")
    pivot = pivot.reindex(index=["High Eng","Mod Eng","Low Eng"], columns=["Low Perf","Core Perf","High Perf"])
    fig = px.imshow(pivot, text_auto=".1f", color_continuous_scale="RdYlGn_r", aspect="auto",
                     labels=dict(color="Attrition %"))
    fig.update_layout(height=400, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Driver decomposition ─────────────────────────────────────────────
st.markdown("##### Attrition Driver Decomposition")
metrics = {
    "Engagement Score": "Engagement_Score",
    "Satisfaction Score": "Satisfaction_Score",
    "Attendance %": "Attendance_Pct",
    "Performance Rating": "Performance_Rating",
    "Promotions": "Promotions",
    "Training Hours": "Training_Hours",
    "Leave Count": "Leave_Count",
    "Salary ($K)": None,  # special
}

rows = []
for label, col in metrics.items():
    if col is None:
        att_val = df[df["Attrition"]=="Yes"]["Salary"].mean()/1000
        ret_val = df[df["Attrition"]=="No"]["Salary"].mean()/1000
    else:
        att_val = df[df["Attrition"]=="Yes"][col].mean()
        ret_val = df[df["Attrition"]=="No"][col].mean()
    rows.append({"Metric": label, "Attrited Avg": round(att_val,2), "Retained Avg": round(ret_val,2),
                  "Delta": round(att_val-ret_val,2)})

driver_df = pd.DataFrame(rows).sort_values("Delta", key=abs, ascending=False)
driver_df["Direction"] = driver_df["Delta"].apply(lambda d: "↑ Higher in Attrited" if d>0 else "↓ Lower in Attrited")

st.dataframe(driver_df, use_container_width=True, hide_index=True,
             column_config={"Delta": st.column_config.NumberColumn(format="%.2f")})

# ── Export ───────────────────────────────────────────────────────────
excel_data = to_excel_bytes(driver_df, sheet_name="Attrition Drivers")
st.download_button("📊 Export Driver Analysis (Excel)", data=excel_data,
                    file_name="PeoplePulse_Attrition_Drivers.xlsx",
                    mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
