"""A table of session summaries (overview, sessions page, study page)."""

import from "@jac/runtime" { Link }
import from .ui { Badge, fmt_ms, fmt_when }

sv import from ..api.views { SessionSummary }

def:pub SessionTable(rows: list[SessionSummary], show_study: bool = True) -> JsxElement {
    return
        <div className="table-wrap">
            <table className="data">
                <thead>
                    <tr>
                        <th>Session</th>
                        {show_study and <th>Study</th>}
                        <th>Condition</th>
                        <th>Robot</th>
                        <th>Status</th>
                        <th className="num">Steps</th>
                        <th className="num">Percepts</th>
                        <th className="num">Failed calls</th>
                        <th className="num">Duration</th>
                        <th className="num">Godspeed</th>
                        <th>Started (UTC)</th>
                    </tr>
                </thead>
                <tbody>
                    {for s in rows {
                        <tr key={s.id}>
                            <td><Link to={"/sessions/" + s.id}>{s.code}</Link></td>
                            {show_study and <td>{s.study_title} <span className="muted">v{s.protocol_version}</span></td>}
                            <td>{s.condition_label}</td>
                            <td>{s.robot_profile}</td>
                            <td><Badge value={s.status}/></td>
                            <td className="num">{s.n_steps}</td>
                            <td className="num">{s.n_percepts}</td>
                            <td className="num">{s.capability_failures}</td>
                            <td className="num">{fmt_ms(s.duration_ms)}</td>
                            <td className="num">{f"{s.godspeed:.2f}" if s.godspeed >= 0 else "–"}</td>
                            <td>{fmt_when(s.started_at)}</td>
                        </tr>
                    }}
                </tbody>
            </table>
        </div>;
}
