"""CSV export of event rows, built and downloaded in the browser."""

import from .ui { join_text }

sv import from ..api.views { EventRow }

glob _NL: str = chr(10);

def _cell(v: str) -> str {
    q = chr(34);
    if q in v or "," in v or _NL in v {
        return q + v.replace(q, q + q) + q;
    }
    return v;
}

def:pub events_csv(rows: list[EventRow]) -> str {
    header = ["session", "condition", "robot", "participant", "t_ms", "kind",
              "source", "label", "ok", "duration_ms", "payload_json"];
    lines: list[str] = [join_text(header, ",")];
    for r in rows {
        cells = [r.session_code, r.condition_label, r.robot_profile, r.participant_code,
                 str(r.t_ms), r.kind, r.source, r.label, r.ok,
                 "" if r.duration_ms < 0 else str(r.duration_ms), r.payload_json];
        lines.append(join_text([_cell(c) for c in cells], ","));
    }
    return join_text(lines, _NL) + _NL;
}

"""Hand the browser a text file to save."""
def:pub download_text(filename: str, text: str, mime: str = "text/csv") {
    # Browser globals are untyped to `jac check`; they are typed `any` here on purpose.
    blob_cls: any = Blob;
    url_api: any = URL;
    doc: any = document;
    blob = new(blob_cls, [text], {"type": mime + ";charset=utf-8"});  # jac:ignore[E1053]
    url = url_api.createObjectURL(blob);
    a: any = doc.createElement("a");
    a.href = url;
    a.download = filename;
    doc.body.appendChild(a);
    a.click();
    a.remove();
    url_api.revokeObjectURL(url);
}
