"""The eight capabilities and how a robot provides each one."""

import from .ui { Badge }

sv import from ..api.views { CapabilityRow }

def:pub CapabilityMatrix(rows: list[CapabilityRow]) -> JsxElement {
    if len(rows) == 0 {
        return <p className="muted small">Fix the profile to see its capabilities.</p>;
    }
    return
        <div className="matrix">
            {for r in rows {
                <div key={r.capability} className="cap">
                    <div className="row">
                        <strong>{r.capability}</strong>
                        <span className="spacer"></span>
                        <Badge value={r.support}/>
                    </div>
                    {r.via and <span className="via">{("shown as " + r.via) if r.support == "SUBSTITUTED" else r.via}</span>}
                    {r.note and r.note != r.via and <span className="small muted">{r.note}</span>}
                </div>
            }}
        </div>;
}
