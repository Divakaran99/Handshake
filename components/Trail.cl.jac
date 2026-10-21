"""The session trail: the path the walker actually took through the protocol.

Same rail as the editor, but read-only and stamped with time. A green
station did what was commanded, a red one failed (or the robot cannot do it),
an amber dot is something the robot perceived.
"""

import from .ui { fmt_ms }

sv import from ..api.views { TrailStop, DeltaRow }

def:pub Trail(stops: list[TrailStop]) -> JsxElement {
    if len(stops) == 0 {
        return <p className="muted">No events were recorded.</p>;
    }
    return
        <div className="rail trail">
            {for (i, st) in enumerate(stops) {
                <div key={str(i)} className={"station " + _station_class(st)}>
                    <div className="trail-row">
                        <span className="trail-time">{str(st.t_ms)} ms</span>
                        <div className="trail-body">
                            <StopBody stop={st}/>
                        </div>
                    </div>
                </div>
            }}
        </div>;
}

def _station_class(st: TrailStop) -> str {
    if st.kind == "percept" {
        return "percept";
    }
    if st.kind == "step" and st.ok == "false" {
        return "fail";
    }
    if st.kind in ["start", "end", "instrument"] {
        return "edge";
    }
    return "";
}

def:pub StopBody(stop: TrailStop) -> JsxElement {
    if stop.kind == "start" {
        return <span className="muted">Session started, condition <strong>{stop.label}</strong> {stop.detail}</span>;
    }
    if stop.kind == "end" {
        return <span className="muted">Session ended</span>;
    }
    if stop.kind == "percept" {
        return <span>Perceived <strong className="mono">{stop.label}</strong> <span className="small muted">from {stop.source}</span></span>;
    }
    if stop.kind == "instrument" {
        return <span>{stop.label} <span className="small muted">{stop.detail}</span></span>;
    }
    substituted = stop.executed_as != "" and stop.executed_as != stop.capability and stop.capability != "";
    return
        <div>
            <div className="row" style={{"gap": "8px"}}>
                <strong>{stop.label}</strong>
                <span className="mono small">{stop.capability or "no call"}</span>
                {substituted and <span className="badge SUBSTITUTED">as {stop.executed_as}</span>}
                {stop.ok == "true" and <span className="badge ok">done</span>}
                {stop.ok == "false" and <span className="badge bad">failed</span>}
                {stop.duration_ms > 0 and <span className="small muted">{fmt_ms(stop.duration_ms)}</span>}
            </div>
            {stop.detail and <p className="small muted" style={{"marginTop": "2px"}}>{stop.detail}</p>}
            {if len(stop.deltas) > 0 {
                <table className="data" style={{"marginTop": "6px", "maxWidth": "560px"}}>
                    <thead><tr><th>Argument</th><th>Commanded</th><th>Achieved</th></tr></thead>
                    <tbody>
                        {for dr in stop.deltas {
                            <tr key={dr.key}>
                                <td className="mono">{dr.key}</td>
                                <td className="mono">{dr.commanded}</td>
                                <td className="mono" style={{"color": "var(--substituted)" if dr.achieved != "" and dr.achieved != dr.commanded else "inherit"}}>
                                    {dr.achieved or "–"}
                                </td>
                            </tr>
                        }}
                    </tbody>
                </table>
            }}
            {if stop.wire_json != "" {
                <details className="wire">
                    <summary>Sent to the robot</summary>
                    <pre className="block">{stop.wire_json}</pre>
                </details>
            }}
        </div>;
}
