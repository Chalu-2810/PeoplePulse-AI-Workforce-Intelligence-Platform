"""
PeoplePulse AI — Page 10: AI Insights
========================================
Natural-language narrative summaries and AI-assisted exploration.
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="AI Insights | PeoplePulse AI", page_icon="💡", layout="wide")

user = require_login()
render_sidebar(user, active_page="ai_insights")
apply_dark_mode()

render_header("AI Insights", "Auto-generated narrative summaries and decomposition exploration", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── Generate narrative ──────────────────────────────────────────────
overall_att = (df["Attrition"]=="Yes").mean()*100
benchmark = 18.0
dept_att = df.groupby("Department").apply(lambda x: (x["Attrition"]=="Yes").mean()*100).sort_values(ascending=False)
worst_dept = dept_att.index[0]
worst_dept_rate = dept_att.iloc[0]

worst_dept_df = df[df["Department"]==worst_dept]
worst_dept_compa = worst_dept_df["Compa_Ratio"].mean()
worst_dept_eng = worst_dept_df["Engagement_Score"].mean()
overall_eng = df["Engagement_Score"].mean()

eng_diff = worst_dept_eng - overall_eng
compa_status = "below market" if worst_dept_compa < 0.95 else "near market"

gender_pay_gap = abs((df[df.Gender=="Male"]["Salary"].mean() - df[df.Gender=="Female"]["Salary"].mean())
                       / df[df.Gender=="Male"]["Salary"].mean() * 100)

high_risk_pct = (df["Engagement_Score"]<40).mean()*100

narrative = f"""
**Workforce Health Narrative**

The current attrition rate is **{overall_att:.1f}%**, which is **{overall_att-benchmark:+.1f} percentage points**
relative to the industry benchmark of {benchmark:.0f}%. The department with the highest attrition
is **{worst_dept}** at **{worst_dept_rate:.1f}%**, driven primarily by a compa-ratio of
**{worst_dept_compa:.2f}** ({compa_status}) and an average engagement score of **{worst_dept_eng:.1f}**
({eng_diff:+.1f} points vs. the company average of {overall_eng:.1f}).

The company-wide gender pay gap stands at **{gender_pay_gap:.2f}%**, which is
{"within the typical 'statistical noise' range (<2%)" if gender_pay_gap < 2 else
 "above the 2% threshold that typically warrants proactive monitoring" if gender_pay_gap < 5 else
 "above the 5% threshold that represents material equity risk"}.

Currently, **{high_risk_pct:.1f}%** of the active workforce falls into the "High Flight Risk"
engagement tier (score below 40) — this population should be the focus of HRBP retention
outreach over the next 30 days.
"""

st.markdown(narrative)

st.markdown("---")

# ── Key Influencers (simplified correlation-based) ──────────────────
st.markdown("##### 🔑 Key Influencers — What drives Attrition = Yes?")
st.caption("Correlation-based proxy for Power BI's native Key Influencers visual")

df["Attrition_Bin"] = (df["Attrition"]=="Yes").astype(int)
numeric_cols = ["Engagement_Score","Satisfaction_Score","Attendance_Pct","Performance_Rating",
                "Years_At_Company","Promotions","Leave_Count","Salary","Training_Hours","Compa_Ratio"]

correlations = df[numeric_cols + ["Attrition_Bin"]].corr()["Attrition_Bin"].drop("Attrition_Bin").sort_values()

fig = px.bar(
    x=correlations.values, y=correlations.index, orientation="h",
    color=correlations.values, color_continuous_scale="RdBu_r",
    labels={"x":"Correlation with Attrition","y":""}
)
fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False)
st.plotly_chart(fig, use_container_width=True)

c1, c2 = st.columns(2)
with c1:
    top_positive = correlations.idxmax()
    st.info(f"**Strongest positive driver:** {top_positive} (r={correlations.max():.3f}) — "
            f"higher values of this metric correlate with HIGHER attrition.")
with c2:
    top_negative = correlations.idxmin()
    st.success(f"**Strongest protective factor:** {top_negative} (r={correlations.min():.3f}) — "
               f"higher values of this metric correlate with LOWER attrition.")

st.markdown("---")

# ── Decomposition tree (simplified hierarchical breakdown) ────────────
st.markdown("##### 🌳 Decomposition: Analyze Attrition Count By...")

dim1 = st.selectbox("Primary dimension", ["Department","Job_Level","Gender","Work_Mode","Recruitment_Source"])
dim2_options = [c for c in ["Department","Job_Level","Gender","Work_Mode","Recruitment_Source","Tenure_Band"] if c != dim1]
dim2 = st.selectbox("Secondary dimension (optional)", ["None"] + dim2_options)

attrited = df[df["Attrition"]=="Yes"]

if dim2 == "None":
    decomp = attrited[dim1].value_counts().reset_index()
    decomp.columns = [dim1, "Attrition Count"]
    fig = px.bar(decomp.sort_values("Attrition Count"), x="Attrition Count", y=dim1, orientation="h",
                  color="Attrition Count", color_continuous_scale="Reds")
else:
    decomp = attrited.groupby([dim1, dim2], observed=True).size().reset_index(name="Attrition Count")
    fig = px.treemap(decomp, path=[dim1, dim2], values="Attrition Count", color="Attrition Count",
                      color_continuous_scale="Reds")

fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False)
st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Natural language Q&A (rule-based query parser) ────────────────────
st.markdown("##### 💬 Ask a Question")
st.caption("Try: 'What is attrition rate by department?' or 'Show engagement trend for Sales' or 'Average salary by gender'")

example_questions = [
    "What is attrition rate by department?",
    "Average salary by gender",
    "Engagement score by job level",
    "Top recruitment source by quality",
    "Promotion rate by department"
]

question = st.text_input("Your question", placeholder="Type a question or pick an example below...")

cols = st.columns(len(example_questions))
for i, q in enumerate(example_questions):
    if cols[i].button(q, key=f"ex_{i}", use_container_width=True):
        question = q

if question:
    q_lower = question.lower()

    if "attrition" in q_lower and "department" in q_lower:
        result = df.groupby("Department").apply(lambda x: (x["Attrition"]=="Yes").mean()*100).round(1).sort_values(ascending=False)
        st.bar_chart(result)
        st.dataframe(result.reset_index().rename(columns={0:"Attrition Rate %"}))

    elif "salary" in q_lower and "gender" in q_lower:
        result = df.groupby("Gender")["Salary"].mean().round(0)
        st.bar_chart(result)
        st.dataframe(result.reset_index().rename(columns={"Salary":"Avg Salary"}))

    elif "engagement" in q_lower and "level" in q_lower:
        result = df.groupby("Job_Level")["Engagement_Score"].mean().round(1)
        st.bar_chart(result)
        st.dataframe(result.reset_index())

    elif "recruitment" in q_lower or "source" in q_lower:
        result = df.groupby("Recruitment_Source").agg(
            AvgPerf=("Performance_Rating","mean"),
            RetentionRate=("Attrition", lambda x: (x=="No").mean()*100)
        ).round(2).sort_values("RetentionRate", ascending=False)
        st.dataframe(result)

    elif "promotion" in q_lower:
        result = df.groupby("Department").apply(lambda x: (x["Promotions"]>=1).mean()*100).round(1).sort_values(ascending=False)
        st.bar_chart(result)
        st.dataframe(result.reset_index().rename(columns={0:"Promotion Rate %"}))

    elif "engagement" in q_lower and "sales" in q_lower:
        sales_df = df[df["Department"]=="Sales"]
        st.metric("Sales Avg Engagement", f"{sales_df['Engagement_Score'].mean():.1f}")
        st.bar_chart(sales_df.groupby("Job_Level")["Engagement_Score"].mean())

    else:
        st.info("This is a rule-based demo Q&A engine covering common HR questions. "
                "In production, this connects to an LLM-powered NLQ engine against the dbt semantic layer (Phase 1 architecture).")
