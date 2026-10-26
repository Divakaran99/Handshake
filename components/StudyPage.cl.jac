"""One study: protocol details, the condition editor, and the run console.

Stateful shell. The page owns every piece of state; StepRail and RunPanel
are stateless and report edits upward. Handler bodies: StudyPage.impl.jac.
"""

import from "@jac/runtime" { Link, useParams, useNavigate }
import from .ui { Badge, Problems, Empty, confirm_action }
import from .StepRail { StepRail }
import from .RunPanel { RunPanel }
import from .SessionTable { SessionTable }
import from .wire { step_spec, branch_spec, copy_step, condition_spec, study_draft, run_request, percept_choice, failed_run }

sv import from ..api.views {
    StudyDetail, StudyDraft, ConditionSpec, StepSpec, BranchSpec, SaveResult,
    CapabilityInfo, RobotView, RunRequest, RunResult, PerceptChoice, SessionSummary
}
sv import from ..api.studies {
    get_study, update_study, start_new_version, delete_study, save_condition,
    delete_condition, capability_catalog
}
sv import from ..api.robots { list_robots }
sv import from ..api.sessions { run_session, list_sessions }

def _unique_label(base: str, taken: list[str]) -> str {
    if base not in taken {
        return base;
    }
    n = 2;
    while (base + "_" + str(n)) in taken {
        n += 1;
    }
    return base + "_" + str(n);
}

def:pub StudyPage -> JsxElement {
    has detail: StudyDetail | None = None,
        missing: bool = False,
        catalog: list[CapabilityInfo] = [],
        robots: list[RobotView] = [],
        sessions: list[SessionSummary] = [],
        m_title: str = "",
        m_version: str = "",
        m_prereg: str = "",
        meta_problems: list[str] = [],
        meta_note: str = "",
        version_note: str = "",
        cond_original: str = "",
        cond_label: str = "",
        cond_factors: str = "{}",
        steps: list[StepSpec] = [],
        dirty: bool = False,
        cond_problems: list[str] = [],
        cond_note: str = "",
        run_robot: str = "",
        run_participant: str = "",
        run_consent: str = "audio+video",
        run_choices: dict[str, str] = {},
        run_result: RunResult | None = None,
        busy: str = "";

    params: any = useParams();
    nav = useNavigate();
    page_id = str(params["id"] or "");

    async can with entry {
        await reload("");
    }

    async def reload(select_label: str);
    def open_condition(c: ConditionSpec);
    def new_condition(copy_current: bool);
    def set_field(i: int, key: str, value: str);
    def add_step(after: int);
    def remove_step(i: int);
    def move_step(i: int, delta: int);
    def add_branch(i: int);
    def set_branch(i: int, j: int, key: str, value: str);
    def remove_branch(i: int, j: int);
    async def save_meta;
    async def save_cond;
    async def remove_cond;
    async def remove_study;
    async def run;
    async def bump_version;

    def set_choice(step_label: str, percept: str) {
        merged: dict[str, str] = {k: v for (k, v) in run_choices.items()};
        merged[step_label] = percept;
        run_choices = merged;
    }

    if missing {
        return <Empty title="This study does not exist in your account"><Link className="btn" to="/studies">Back to studies</Link></Empty>;
    }
    if detail is None {
        return <p className="muted">Loading…</p>;
    }
    d = detail as StudyDetail;
    frozen = d.study.frozen;
    saved_labels = [c.label for c in d.conditions];
    editing_saved = cond_original != "" and cond_original in saved_labels;

    return
        <>
            <header className="page-head">
                <div>
                    <p className="small"><Link to="/studies">Studies</Link></p>
                    <h1>{d.study.title}</h1>
                    <div className="row" style={{"marginTop": "8px"}}>
                        <span className="mono">v{d.study.version}</span>
                        {<Badge value="frozen" text="version frozen"/> if frozen else <Badge value="plain" text="editable"/>}
                        <span className="muted small">{str(len(d.conditions))} conditions, {str(d.study.n_sessions)} sessions</span>
                    </div>
                </div>
                <button className="btn danger" onClick={remove_study} disabled={busy != ""}>Delete study</button>
            </header>

            <details className="panel" open={len(d.conditions) == 0}>
                <summary><strong>Protocol details and pre-registration</strong></summary>
                <div className="stack" style={{"marginTop": "14px"}}>
                    <div className="cols-2">
                        <label className="field">
                            <span>Title</span>
                            <input className="input" value={m_title}
                                onChange={lambda e: ChangeEvent { m_title = e.target.value; }}/>
                        </label>
                        <label className="field">
                            <span>Protocol version</span>
                            <div className="row">
                                <input className="input mono" style={{"flex": "1", "width": "auto"}} value={m_version}
                                    onChange={lambda e: ChangeEvent { m_version = e.target.value; }}/>
                                {frozen and <button className="btn small" type="button" disabled={busy != ""} onClick={lambda e: MouseEvent { bump_version(); }}>Start a new version</button>}
                            </div>
                        </label>
                    </div>
                    <label className="field">
                        <span>Pre-registered hypotheses and analysis plan</span>
                        <textarea className="textarea" rows={4} value={m_prereg}
                            onChange={lambda e: ChangeEvent { m_prereg = e.target.value; }}/>
                    </label>
                    <Problems items={meta_problems}/>
                    {meta_note and <div className="notice good" role="status">{meta_note}</div>}
                    <div className="row"><button className="btn" onClick={save_meta} disabled={busy != ""}>Save details</button></div>
                </div>
            </details>

            {frozen and
                <div className="notice warn row" style={{"marginTop": "16px", "flexWrap": "nowrap"}} role="status">
                    <span className="spacer">
                        Version {d.study.version} has produced sessions, so its protocol is frozen and every
                        session stays traceable to it. Start a new version to change steps or the pre-registration;
                        the steps carry over and existing sessions keep version {d.study.version}.
                    </span>
                    <button className="btn primary" disabled={busy != ""} onClick={lambda e: MouseEvent { bump_version(); }}>
                        {"Starting…" if busy == "version" else "Start a new version"}
                    </button>
                </div>
            }
            {version_note and <div className="notice good" style={{"marginTop": "16px"}} role="status">{version_note}</div>}

            <section style={{"marginTop": "24px"}}>
                <div className="panel-head">
                    <h2>Conditions</h2>
                    <div className="row">
                        {for c in d.conditions {
                            <button key={c.label} className={"btn small primary" if c.label == cond_original else "btn small"}
                                onClick={lambda e: MouseEvent { open_condition(c); }}>{c.label}</button>
                        }}
                        <button className="btn small" disabled={frozen} onClick={lambda e: MouseEvent { new_condition(False); }}>New condition</button>
                        {editing_saved and <button className="btn small" disabled={frozen} onClick={lambda e: MouseEvent { new_condition(True); }}>Duplicate</button>}
                    </div>
                </div>

                {if len(steps) == 0 and cond_original == "" and cond_label == "" {
                    <Empty title="No condition open">
                        <p>Conditions are the arms of your study. Create one, or open an existing one above.</p>
                        <button className="btn" disabled={frozen} onClick={lambda e: MouseEvent { new_condition(False); }}>New condition</button>
                    </Empty>
                } else {
                    <div className="stack">
                        <div className="cols-2">
                            <label className="field">
                                <span>Condition label</span>
                                <input className="input" value={cond_label} disabled={frozen}
                                    onChange={lambda e: ChangeEvent { cond_label = e.target.value; dirty = True; }}/>
                            </label>
                            <label className="field">
                                <span>Factors (JSON)</span>
                                <input className="input mono" value={cond_factors} disabled={frozen}
                                    onChange={lambda e: ChangeEvent { cond_factors = e.target.value; dirty = True; }}/>
                                <small>The independent variables this condition sets, recorded with every session.</small>
                            </label>
                        </div>
                        <StepRail
                            steps={steps}
                            catalog={catalog}
                            locked={frozen}
                            onField={set_field}
                            onAdd={add_step}
                            onRemove={remove_step}
                            onMove={move_step}
                            onAddBranch={add_branch}
                            onBranch={set_branch}
                            onRemoveBranch={remove_branch}
                        />
                        <div className="row">
                            <button className="btn" disabled={frozen} onClick={lambda e: MouseEvent { add_step(len(steps) - 1); }}>Add a step at the end</button>
                            <span className="spacer"></span>
                            {editing_saved and <button className="btn danger" disabled={frozen or busy != ""} onClick={remove_cond}>Delete condition</button>}
                            <button className="btn primary" disabled={frozen or busy != ""} onClick={save_cond}>
                                {"Saving…" if busy == "cond" else ("Save condition" if dirty or not editing_saved else "Saved")}
                            </button>
                        </div>
                        <Problems items={cond_problems} title="The condition was not saved"/>
                        {cond_note and <div className="notice good" role="status">{cond_note}</div>}
                    </div>
                }}
            </section>

            <RunPanel
                conditions={d.conditions}
                selected={cond_original}
                robots={robots}
                robot_id={run_robot}
                participant={run_participant}
                consent={run_consent}
                choices={run_choices}
                result={run_result}
                busy={busy == "run"}
                dirty={dirty}
                onRobot={lambda v: str { run_robot = v; }}
                onParticipant={lambda v: str { run_participant = v; }}
                onConsent={lambda v: str { run_consent = v; }}
                onChoice={set_choice}
                onRun={run}
            />

            <section className="panel" style={{"marginTop": "24px"}}>
                <div className="panel-head">
                    <h2>Sessions of this study</h2>
                    <Link className="btn small" to="/sessions">All sessions and export</Link>
                </div>
                {if len(sessions) == 0 {
                    <p className="muted">No sessions yet. Run one above.</p>
                } else {
                    <SessionTable rows={sessions} show_study={False}/>
                }}
            </section>
        </>;
}
