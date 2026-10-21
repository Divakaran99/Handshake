"""Session endpoints: run a participant through a condition on a robot, then
read, score, export or withdraw the resulting data.

`run_session` holds the HTTP request open while the robot performs the
protocol. On the simulator that is milliseconds; on a real robot it is the
length of the interaction, which is fine for a lab console but means a
reverse proxy in front of `jac start` needs a generous read timeout.
"""

import from domain.protocol { StudyProtocol }
import from domain.participant { Participant, ConsentRecord, Consented }
import from domain.session { Session, Event, EventKind, Logged, Ran, Produced }
import from domain.robot { RobotProfile }
import from adapters.registry { make_adapter, ProfileError }
import from runtime.session_runtime { run_condition }
import from runtime.clock { Clock }
import from instruments.godspeed { GODSPEED_ANTHROPOMORPHISM }
import from api.views {
    RunRequest, RunResult, SessionSummary, SessionDetail, EventRow,
    ParticipantView, DashboardView, InstrumentView, ScaleItemView, SaveResult
}
import from api.common {
    find_study, find_robot, find_session, find_participant, has_active_consent,
    session_summary, event_rows, study_sessions, now_iso, ensure_simulator, trail_for
}
import from api.protocol_io { find_condition, condition_snapshot }

def _all_sessions -> list[Session] {
    return [root -->[?:Session]];
}

def _newest_first(rows: list[SessionSummary]) -> list[SessionSummary] {
    rows.sort(key=lambda r: SessionSummary : r.started_at, reverse=True);
    return rows;
}

"""Find or enrol a participant; a returning participant must still have active consent."""
def _participant(code: str, scope: str) -> Participant | str {
    p = find_participant(code);
    if p is not None {
        return p if has_active_consent(p) else f"participant {code} has no active consent";
    }
    if scope.strip() == "" {
        return "record consent (scope) before the first session";
    }
    today = now_iso()[:10];
    created = (root ++> Participant(code=code, enrolled_at=today))[0];
    created +>: Consented() :+> ConsentRecord(scope=scope.strip(), granted_at=today);
    return created;
}

"""Run one participant through one condition on one robot and store the session."""
def:priv run_session(req: RunRequest) -> RunResult {
    study = find_study(req.study_id);
    if study is None {
        return RunResult(ok=False, error="study not found");
    }
    cond = find_condition(study, req.condition_label);
    if cond is None {
        return RunResult(ok=False, error=f"no condition '{req.condition_label}'");
    }
    robot = find_robot(req.robot_id);
    if robot is None {
        return RunResult(ok=False, error="robot not found");
    }
    code = req.participant_code.strip();
    if code == "" {
        return RunResult(ok=False, error="participant code is required (pseudonymous, e.g. P07)");
    }
    try {
        adapter = make_adapter(robot);
    } except ProfileError as e {
        return RunResult(ok=False, error=f"robot profile is invalid: {str(e)}");
    }
    who = _participant(code, req.consent_scope);
    if isinstance(who, str) {
        return RunResult(ok=False, error=who);
    }
    person = who as Participant;

    label = cond.label;
    n = len([s for s in [person ->:Ran:->] if s.condition_label == label]) + 1;
    sess = (root ++> Session(
        code=f"S-{code}-{cond.label}" + (f"-{n}" if n > 1 else ""),
        protocol_title=study.title,
        protocol_version=study.version,
        condition_label=cond.label,
        robot_profile=robot.name,
        participant_code=code,
        protocol_snapshot=condition_snapshot(study, cond)
    ))[0];
    person +>: Ran() :+> sess;
    study +>: Produced() :+> sess;

    script: dict[str, str] = {};
    for choice in req.percepts {
        if choice.step != "" and choice.percept != "" {
            script[choice.step] = choice.percept;
        }
    }
    try {
        trace = run_condition(cond, adapter, sess, script);
    } except Exception as e {
        sess.status = "failed";
        sess.t0_wall_iso = sess.t0_wall_iso or now_iso();
        return RunResult(ok=False, error=str(e), session=session_summary(sess));
    }
    return RunResult(ok=True, session=session_summary(sess), trace=trace);
}

"""Sessions for one study ("" = every study), newest first."""
def:priv list_sessions(study_id: str = "") -> list[SessionSummary] {
    if study_id == "" {
        return _newest_first([session_summary(s) for s in _all_sessions()]);
    }
    study = find_study(study_id);
    if study is None {
        return [];
    }
    return _newest_first([session_summary(s) for s in study_sessions(study)]);
}

def:priv get_session(session_id: str) -> SessionDetail | None {
    s = find_session(session_id);
    if s is None {
        return None;
    }
    return SessionDetail(summary=session_summary(s), events=event_rows(s),
                         trail=trail_for(s), protocol_snapshot=s.protocol_snapshot);
}

"""Delete a session and its events (e.g. a pilot run). Participants are kept."""
def:priv delete_session(session_id: str) -> SaveResult {
    s = find_session(session_id);
    if s is None {
        return SaveResult(ok=False, problems=["session not found"]);
    }
    for e in [s ->:Logged:->] {
        del e;
    }
    del s;
    return SaveResult(ok=True);
}

"""Every event of a study's sessions as flat rows - the CSV export."""
def:priv export_events(study_id: str = "") -> list[EventRow] {
    sessions = _all_sessions();
    if study_id != "" {
        study = find_study(study_id);
        sessions = study_sessions(study) if study is not None else [];
    }
    rows: list[EventRow] = [];
    for s in sessions {
        rows.extend(event_rows(s));
    }
    return rows;
}

def:priv godspeed_instrument -> InstrumentView {
    g = GODSPEED_ANTHROPOMORPHISM;
    return InstrumentView(
        name=g.name, citation=g.citation, points=g.points,
        items=[ScaleItemView(key=i.key, anchor_low=i.anchor_low, anchor_high=i.anchor_high)
               for i in g.items]
    );
}

"""Store a post-session Godspeed response as an event on the session and score it."""
def:priv record_godspeed(session_id: str, responses: dict[str, int]) -> SessionSummary | None {
    s = find_session(session_id);
    if s is None {
        return None;
    }
    g = GODSPEED_ANTHROPOMORPHISM;
    clean: dict[str, int] = {};
    for item in g.items {
        v = responses.get(item.key, 0);
        if 1 <= v and v <= g.points {
            clean[item.key] = v;
        }
    }
    score = g.score(clean);
    last = 0;
    for e in [s ->:Logged:->] {
        last = max(last, e.t_mono_ms);
    }
    s +>: Logged() :+> Event(
        kind=EventKind.INSTRUMENT_RESPONSE, t_mono_ms=last, source="researcher",
        label=g.name,
        payload={"instrument": g.name, "responses": clean, "score": score,
                 "answered": len(clean), "recorded_at": now_iso()}
    );
    return session_summary(s);
}

def:priv list_participants -> list[ParticipantView] {
    out: list[ParticipantView] = [];
    for p in [root -->[?:Participant]] {
        consents = [p ->:Consented:->];
        out.append(ParticipantView(
            code=p.code, enrolled_at=p.enrolled_at,
            consent_scope=consents[0].scope if len(consents) > 0 else "",
            consent_active=has_active_consent(p),
            n_sessions=len([p ->:Ran:->])
        ));
    }
    out.sort(key=lambda v: ParticipantView : v.code);
    return out;
}

"""Withdraw a participant: their sessions, events and consent records are deleted."""
def:priv withdraw_participant(code: str) -> int {
    removed = 0;
    for p in [root -->[?:Participant]] {
        if p.code != code {
            continue;
        }
        for s in [p ->:Ran:->] {
            for e in [s ->:Logged:->] {
                del e;
            }
            del s;
            removed += 1;
        }
        for c in [p ->:Consented:->] {
            del c;
        }
        del p;
    }
    return removed;
}

def:priv dashboard -> DashboardView {
    ensure_simulator();
    sessions = _newest_first([session_summary(s) for s in _all_sessions()]);
    return DashboardView(
        n_robots=len([root -->[?:RobotProfile]]),
        n_studies=len([root -->[?:StudyProtocol]]),
        n_sessions=len(sessions),
        n_participants=len([root -->[?:Participant]]),
        recent=sessions[:6]
    );
}
