"""Graph lookups and view builders shared by the API modules.

Nothing here is an endpoint: only names imported by main.jac (or referenced
from the client with `sv import`) are served. Every lookup walks out from the
caller's own `root`, which is what makes one researcher's jid useless against
another researcher's data - `jobj(id)` would resolve it, so it is not used.
"""

import json;
import from datetime { datetime, timezone }
import from domain.capability { Support }
import from domain.protocol { StudyProtocol, HasCondition }
import from domain.participant { Participant, ConsentRecord, Consented }
import from domain.session { Session, Event, EventKind, Logged, Produced, Ran }
import from domain.robot { RobotProfile }
import from adapters.adapter { RobotAdapter, ProbeReport }
import from adapters.bindings { parse_bindings, as_dict }
import from adapters.registry { validate_profile }
import from adapters.sim { SimAdapter }
import from insights.metrics { ComputeMetrics, SessionMetrics }
import from instruments.godspeed { GODSPEED_ANTHROPOMORPHISM }
import from api.views {
    CapabilityRow, RobotView, StudySummary, SessionSummary, EventRow, ProbeView,
    TrailStop, DeltaRow
}

"""json.dumps fallback for values JSON cannot encode (enums, datetimes)."""
def as_text(v: object) -> object {
    return str(v);
}

def to_json(v: object) -> str {
    return json.dumps(v, default=as_text);
}

def now_iso -> str {
    return datetime.now(timezone.utc).isoformat(timespec="seconds");
}

# ------------------------------------------------------------ lookups ----

def find_study(study_id: str) -> StudyProtocol | None {
    for s in [root -->[?:StudyProtocol]] {
        if jid(s) == study_id {
            return s;
        }
    }
    return None;
}

def find_robot(robot_id: str) -> RobotProfile | None {
    for r in [root -->[?:RobotProfile]] {
        if jid(r) == robot_id {
            return r;
        }
    }
    return None;
}

def find_session(session_id: str) -> Session | None {
    for s in [root -->[?:Session]] {
        if jid(s) == session_id {
            return s;
        }
    }
    return None;
}

def find_participant(code: str) -> Participant | None {
    for p in [root -->[?:Participant]] {
        if p.code == code {
            return p;
        }
    }
    return None;
}

def study_sessions(study: StudyProtocol) -> list[Session] {
    return [study ->:Produced:->];
}

"""A protocol version that has produced data is frozen: edits need a new version."""
def is_frozen(study: StudyProtocol) -> bool {
    for s in study_sessions(study) {
        if s.protocol_version == study.version {
            return True;
        }
    }
    return False;
}

def has_active_consent(p: Participant) -> bool {
    for c in [p ->:Consented:->] {
        if c.active() {
            return True;
        }
    }
    return False;
}

"""Every researcher starts with the built-in simulator, so nothing needs hardware."""
def ensure_simulator {
    if len([root -->[?:RobotProfile]]) == 0 {
        root ++> RobotProfile(
            name="Simulator (tabletop)",
            kind="sim",
            notes="Built in. APPROACH is unavailable and EXPRESS is shown on screen, so degradation is exercised.",
            created_at=now_iso()
        );
    }
}

# -------------------------------------------------------------- views ----

def capability_rows(adapter: RobotAdapter) -> list[CapabilityRow] {
    rows: list[CapabilityRow] = [];
    for spec in adapter.capabilities() {
        rows.append(CapabilityRow(
            capability=spec.capability.name,
            support=spec.support.name,
            via=spec.substitute.name if spec.substitute is not None else "",
            note=spec.note
        ));
    }
    return rows;
}

"""Capability matrix for a profile, computed from its bindings without connecting."""
def profile_rows(p: RobotProfile) -> list[CapabilityRow] {
    if p.kind == "sim" {
        return capability_rows(SimAdapter(profile_name=p.name));
    }
    if p.kind in ["rosbridge", "http"] {
        table = parse_bindings(p.bindings_json, p.kind, p.ros_version);
        rows: list[CapabilityRow] = [];
        for spec in table.specs {
            b = table.binding_for(spec.capability);
            via = "";
            if spec.support == Support.SUBSTITUTED and spec.substitute is not None {
                via = spec.substitute.name;
            } elif b is not None and b.op not in ["unavailable", "substitute"] {
                via = b.op if b.target == "" else f"{b.op} {b.target}";
            }
            rows.append(CapabilityRow(capability=spec.capability.name,
                                      support=spec.support.name, via=via,
                                      note=spec.note));
        }
        return rows;
    }
    return [];
}

def robot_view(p: RobotProfile) -> RobotView {
    return RobotView(
        id=jid(p), name=p.name, kind=p.kind, url=p.url, ros_version=p.ros_version,
        bindings_json=p.bindings_json, percepts_json=p.percepts_json,
        notes=p.notes, updated_at=p.updated_at or p.created_at,
        capabilities=profile_rows(p), problems=validate_profile(p)
    );
}

def probe_view(r: ProbeReport, rows: list[CapabilityRow]) -> ProbeView {
    return ProbeView(ok=r.ok, detail=r.detail, latency_ms=r.latency_ms,
                     topics=r.topics, warnings=r.warnings, capabilities=rows);
}

def study_summary(s: StudyProtocol) -> StudySummary {
    return StudySummary(
        id=jid(s), title=s.title, version=s.version, prereg=s.prereg,
        n_conditions=len([s ->:HasCondition:->]),
        n_sessions=len(study_sessions(s)),
        frozen=is_frozen(s)
    );
}

def metrics_for(s: Session) -> SessionMetrics | None {
    w = s spawn ComputeMetrics();
    return w.metrics;
}

def godspeed_score(s: Session) -> float {
    score: float = -1.0;
    for e in [s ->:Logged:->] {
        if e.kind == EventKind.INSTRUMENT_RESPONSE
           and e.payload.get("instrument", "") == GODSPEED_ANTHROPOMORPHISM.name {
            v = e.payload.get("score", -1.0);
            if isinstance(v, (int, float)) {
                score = float(v);
            }
        }
    }
    return score;
}

def session_summary(s: Session) -> SessionSummary {
    m = metrics_for(s);
    out = SessionSummary(
        id=jid(s), code=s.code, study_title=s.protocol_title,
        protocol_version=s.protocol_version, condition_label=s.condition_label,
        robot_profile=s.robot_profile, participant_code=s.participant_code,
        status=s.status, started_at=s.t0_wall_iso, godspeed=godspeed_score(s)
    );
    if m is not None {
        out.n_steps = m.n_steps;
        out.n_events = m.n_events;
        out.n_percepts = m.n_percepts;
        out.capability_failures = m.capability_failures;
        out.duration_ms = m.duration_ms;
    }
    return out;
}

def event_rows(s: Session) -> list[EventRow] {
    rows: list[EventRow] = [];
    for e in [s ->:Logged:->] {
        ok = e.payload.get("ok", None);
        dur = e.payload.get("duration_ms", -1);
        rows.append(EventRow(
            session_code=s.code, condition_label=s.condition_label,
            robot_profile=s.robot_profile, participant_code=s.participant_code,
            t_ms=e.t_mono_ms, kind=e.kind.name, source=e.source, label=e.label,
            ok="" if ok is None else ("true" if ok else "false"),
            duration_ms=int(dur) if isinstance(dur, int) else -1,
            payload_json=to_json(e.payload)
        ));
    }
    rows.sort(key=lambda r: EventRow : r.t_ms);
    return rows;
}

def _show(v: object) -> str {
    if v is None {
        return "";
    }
    if isinstance(v, str) {
        return v;
    }
    return to_json(v);
}

def _deltas(commanded: object, achieved: object) -> list[DeltaRow] {
    c = as_dict(commanded);
    a = as_dict(achieved);
    keys: list[str] = list(c.keys());
    for k in a.keys() {
        if k not in keys {
            keys.append(k);
        }
    }
    return [DeltaRow(key=k, commanded=_show(c.get(k, None)), achieved=_show(a.get(k, None)))
            for k in keys];
}

"""The session as a readable trail: one stop per step, percept and milestone."""
def trail_for(s: Session) -> list[TrailStop] {
    stops: list[TrailStop] = [];
    current: TrailStop | None = None;
    for e in sorted([s ->:Logged:->], key=_event_time) {
        p = as_dict(e.payload);
        if e.kind == EventKind.SESSION_START {
            stops.append(TrailStop(kind="start", t_ms=e.t_mono_ms, label=e.label,
                                   detail=f"on {_show(p.get('robot_profile', ''))}"));
        } elif e.kind == EventKind.STEP_ENTER {
            current = TrailStop(kind="step", t_ms=e.t_mono_ms, label=e.label);
            stops.append(current);
        } elif e.kind == EventKind.CAPABILITY_CALL and current is not None {
            current.capability = _show(p.get("capability", ""));
        } elif e.kind == EventKind.CAPABILITY_RESULT and current is not None {
            ok = p.get("ok", None);
            current.ok = "true" if ok else "false";
            if current.capability == "" {
                current.capability = _show(p.get("capability", ""));
            }
            current.executed_as = _show(p.get("executed_as", ""));
            current.detail = _show(p.get("detail", p.get("reason", "")));
            dur = p.get("duration_ms", -1);
            current.duration_ms = int(dur) if isinstance(dur, int) else -1;
            current.deltas = _deltas(p.get("commanded", None), p.get("achieved", None));
            wire = p.get("wire", None);
            current.wire_json = json.dumps(wire, indent=2, default=as_text) if wire else "";
        } elif e.kind == EventKind.PERCEPT {
            stops.append(TrailStop(kind="percept", t_ms=e.t_mono_ms, label=e.label, source=e.source));
        } elif e.kind == EventKind.INSTRUMENT_RESPONSE {
            stops.append(TrailStop(kind="instrument", t_ms=e.t_mono_ms, label=e.label,
                                   detail=f"score {_show(p.get('score', ''))} from {_show(p.get('answered', 0))} items"));
        } elif e.kind == EventKind.SESSION_END {
            stops.append(TrailStop(kind="end", t_ms=e.t_mono_ms, label=e.label));
        }
    }
    return stops;
}

def _event_time(e: Event) -> int {
    return e.t_mono_ms;
}
