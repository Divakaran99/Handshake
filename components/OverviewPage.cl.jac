"""Overview: where the lab is in the setup sequence, plus the latest sessions."""

import from "@jac/runtime" { Link }
import from .ui { Badge, fmt_ms, fmt_when }
import from .SessionTable { SessionTable }

sv import from ..api.views { DashboardView, SessionSummary }
sv import from ..api.sessions { dashboard }

def:pub OverviewPage -> JsxElement {
    has view: DashboardView | None = None,
        error: str = "";

    async can with entry {
        try {
            view = await dashboard();
        } except Exception {
            error = "Could not load the overview.";
        }
    }

    if view is None {
        return <p className="muted">{error or "Loading…"}</p>;
    }
    v = view as DashboardView;
    real_robot = v.n_robots > 1;

    return
        <>
            <header className="page-head">
                <div>
                    <h1>Overview</h1>
                    <p>From connecting a robot to exporting a dataset. Every step works on the built-in simulator first.</p>
                </div>
            </header>

            <ol className="checklist">
                <li className={"done" if real_robot else ""}>
                    <div>
                        <strong>Connect a robot</strong>
                        <p>The simulator is ready. Add your ROS robot, a simulator such as Gazebo, or an HTTP robot.</p>
                    </div>
                    <Link className="btn" to="/robots">{"Manage robots" if real_robot else "Add a robot"}</Link>
                </li>
                <li className={"done" if v.n_studies > 0 else ""}>
                    <div>
                        <strong>Design a study</strong>
                        <p>Write each condition as steps against capabilities, with branches on what the robot perceives.</p>
                    </div>
                    <Link className="btn" to="/studies">{"Open studies" if v.n_studies > 0 else "Create a study"}</Link>
                </li>
                <li className={"done" if v.n_sessions > 0 else ""}>
                    <div>
                        <strong>Run a session</strong>
                        <p>Pick a condition, a robot and a participant code. The protocol runs and every event is logged.</p>
                    </div>
                    <Link className="btn" to="/studies">Run a session</Link>
                </li>
                <li className={"done" if v.n_sessions > 0 else ""}>
                    <div>
                        <strong>Export the data</strong>
                        <p>Download every event as CSV, with commanded and achieved values side by side.</p>
                    </div>
                    <Link className="btn" to="/sessions">Go to sessions</Link>
                </li>
            </ol>

            <section className="panel" style={{"marginTop": "24px"}}>
                <div className="panel-head">
                    <h2>Latest sessions</h2>
                    <div className="stat-line">
                        <span><b>{v.n_robots}</b>robots</span>
                        <span><b>{v.n_studies}</b>studies</span>
                        <span><b>{v.n_sessions}</b>sessions</span>
                        <span><b>{v.n_participants}</b>participants</span>
                    </div>
                </div>
                {if len(v.recent) == 0 {
                    <p className="muted">No sessions yet. Open a study and run one on the simulator.</p>
                } else {
                    <SessionTable rows={v.recent}/>
                }}
            </section>
        </>;
}
