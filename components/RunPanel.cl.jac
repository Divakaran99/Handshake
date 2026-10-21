"""The run console: pick a condition, a robot and a participant, then run.

On the simulator (or as a Wizard-of-Oz override on a real robot) the
researcher decides what the robot "perceives" at each branching step; on a
real robot those steps wait for the robot's own percepts instead.
"""

import from "@jac/runtime" { Link }
import from .ui { Badge, fmt_ms, LineBlock }

sv import from ..api.views { ConditionSpec, StepSpec, RobotView, RunResult }

def:pub RunPanel(
    conditions: list[ConditionSpec],
    selected: str,
    robots: list[RobotView],
    robot_id: str,
    participant: str,
    consent: str,
    choices: dict[str, str],
    result: RunResult | None,
    busy: bool,
    dirty: bool,
    onRobot: Callable[[str], None],
    onParticipant: Callable[[str], None],
    onConsent: Callable[[str], None],
    onChoice: Callable[[str, str], None],
    onRun: Callable[[], None]
) -> JsxElement {
    has_cond = False;
    branching: list[StepSpec] = [];
    for c in conditions {
        if c.label == selected {
            has_cond = True;
            branching = [s for s in c.steps if len(s.branches) > 0];
        }
    }
    has_robot = False;
    is_sim = False;
    robot_has_problems = False;
    for r in robots {
        if r.id == robot_id {
            has_robot = True;
            is_sim = r.kind == "sim";
            robot_has_problems = len(r.problems) > 0;
        }
    }
    can_run = has_cond and has_robot and participant.strip() != "" and not busy;

    return
        <section className="panel stack" style={{"marginTop": "24px"}} aria-label="Run a session">
            <div className="panel-head">
                <h2>Run a session</h2>
                <span className="small muted">
                    {("Condition " + selected) if has_cond else "Open a saved condition to run it"}
                </span>
            </div>
            {dirty and has_cond and
                <div className="notice warn">The editor has unsaved changes. Sessions run the saved version of the condition.</div>
            }
            <div className="cols-2">
                <label className="field">
                    <span>Robot</span>
                    <select className="select" value={robot_id}
                        onChange={lambda e: ChangeEvent { onRobot(e.target.value); }}>
                        {for r in robots {
                            <option key={r.id} value={r.id}>{r.name}</option>
                        }}
                    </select>
                    {robot_has_problems and
                        <small style={{"color": "var(--unavailable)"}}>This profile has problems. Fix it on the Robots page.</small>}
                </label>
                <div className="cols-2">
                    <label className="field">
                        <span>Participant code</span>
                        <input className="input mono" value={participant} placeholder="P07"
                            onChange={lambda e: ChangeEvent { onParticipant(e.target.value); }}/>
                        <small>Pseudonymous. Never a name.</small>
                    </label>
                    <label className="field">
                        <span>Consent recorded for</span>
                        <input className="input" value={consent}
                            onChange={lambda e: ChangeEvent { onConsent(e.target.value); }}/>
                        <small>Stored on first enrolment.</small>
                    </label>
                </div>
            </div>

            {if len(branching) > 0 {
                <div className="stack">
                    <strong className="small">
                        {"What the simulator perceives" if is_sim else "Percepts (leave on 'wait for the robot' for a real run)"}
                    </strong>
                    {for s in branching {
                        <label key={s.label} className="row small">
                            <span className="mono" style={{"minWidth": "140px"}}>{s.label}</span>
                            <select className="select" style={{"width": "auto"}} value={choices[s.label] if s.label in choices else ""}
                                onChange={lambda e: ChangeEvent { onChoice(s.label, e.target.value); }}>
                                <option value="">{"nothing (time out)" if is_sim else "wait for the robot"}</option>
                                {for b in s.branches {
                                    <option key={b.percept} value={b.percept}>{b.percept}</option>
                                }}
                            </select>
                        </label>
                    }}
                </div>
            }}

            <div className="row">
                <button className="btn primary" disabled={not can_run} onClick={lambda e: MouseEvent { onRun(); }}>
                    {"Running…" if busy else "Run session"}
                </button>
                {busy and not is_sim and <span className="small muted">The robot is performing the protocol. This takes as long as the interaction.</span>}
            </div>

            {if result is not None {
                <RunOutcome outcome={result}/>
            }}
        </section>;
}

def:pub RunOutcome(outcome: RunResult) -> JsxElement {
    s = outcome.session;
    return
        <div className="stack" aria-live="polite">
            {if not outcome.ok {
                <div className="notice error" role="alert">{outcome.error}</div>
            }}
            {if s is not None {
                <div className="row">
                    <Badge value={s.status}/>
                    <Link to={"/sessions/" + s.id}><strong>{s.code}</strong></Link>
                    <span className="small muted">
                        {str(s.n_steps)} steps, {str(s.n_percepts)} percepts, {str(s.capability_failures)} failed calls, {fmt_ms(s.duration_ms)}
                    </span>
                </div>
            }}
            {if len(outcome.trace) > 0 {
                <LineBlock lines={outcome.trace}/>
            }}
        </div>;
}
