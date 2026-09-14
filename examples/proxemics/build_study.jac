"""End-to-end demo: a two-condition greeting study on the simulated robot.

Run with:  jac run examples/proxemics/build_study.jac
No hardware, no configuration, no database.
"""

import from domain.capability { Capability }
import from domain.protocol { StudyProtocol, Condition, Step, HasCondition, Starts, Next }
import from domain.participant { Participant, ConsentRecord, Consented }
import from domain.session { Session, Ran }
import from adapters.sim { SimAdapter }
import from runtime.clock { Clock }
import from runtime.session_runtime { RunSession }
import from insights.metrics { ComputeMetrics, SessionMetrics }

def build_condition(proto: StudyProtocol, label: str, distance: float) -> Condition {
    cond = (proto +>: HasCondition() :+> Condition(
        label=label, factors={"stop_distance_m": distance}))[0];

    greet = Step(label="greet", capability=Capability.SPEAK,
                 args={"text": "Hello, thanks for joining the study."});
    approach = Step(label="approach", capability=Capability.APPROACH,
                    args={"stop_distance_m": distance, "speed_mps": 0.4});
    look = Step(label="look", capability=Capability.GAZE,
                args={"target": "face", "hold_ms": 1800});
    warm = Step(label="warm_response", capability=Capability.EXPRESS,
                args={"affect": "friendly"});
    neutral = Step(label="neutral_response", capability=Capability.IDLE, args={});
    bye = Step(label="farewell", capability=Capability.SPEAK,
               args={"text": "That is the end of the task."});

    cond +>: Starts() :+> greet;
    greet +>: Next() :+> approach;
    approach +>: Next() :+> look;
    look +>: Next(on_percept="gaze_reciprocated") :+> warm;
    look +>: Next(on_timeout=True) :+> neutral;
    warm +>: Next() :+> bye;
    neutral +>: Next() :+> bye;
    return cond;
}

def run_one(cond: Condition, proto: StudyProtocol, code: str,
            reciprocates: bool) -> SessionMetrics | None {
    person = (root ++> Participant(code=code, enrolled_at="2026-09-11"))[0];
    person +>: Consented() :+> ConsentRecord(scope="audio+video",
                                             granted_at="2026-09-11");
    sess = (root ++> Session(
        code=f"S-{code}-{cond.label}",
        protocol_title=proto.title,
        protocol_version=proto.version,
        condition_label=cond.label,
        robot_profile="sim-tabletop",
        seed=7
    ))[0];
    person +>: Ran() :+> sess;

    script: dict[str, str] = {};
    if reciprocates {
        script["look"] = "gaze_reciprocated";
    }

    res = cond spawn RunSession(
        adapter=SimAdapter(), clock=Clock(), session=sess, percept_script=script
    );
    print(f"\n--- {sess.code} ---");
    for line in res.trace {
        print("   " + line);
    }

    m = sess spawn ComputeMetrics();
    return m.reports[0] if m.reports else None;
}

with entry {
    proto = (root ++> StudyProtocol(
        title="Greeting distance and gaze reciprocity",
        version="0.1.0",
        prereg="H1: closer approach increases reciprocated gaze."
    ))[0];

    near = build_condition(proto, "near", 0.8);
    far = build_condition(proto, "far", 1.6);

    results: list[SessionMetrics] = [];
    for (cond, code, recip) in [(near, "P01", True), (far, "P02", False)] {
        m = run_one(cond, proto, code, recip);
        if m is not None {
            results.append(m);
        }
    }

    print("\n================ DESCRIPTIVES ================");
    print(f"{'session':<18}{'cond':<8}{'steps':>6}{'events':>8}{'percepts':>10}{'fails':>7}{'ms':>7}");
    for m in results {
        print(f"{m.session_code:<18}{m.condition_label:<8}{m.n_steps:>6}{m.n_events:>8}{m.n_percepts:>10}{m.capability_failures:>7}{m.duration_ms:>7}");
    }
    print("\nNote: 1 capability failure per session is expected - the sim profile");
    print("declares APPROACH as UNAVAILABLE, so the degradation path is exercised.");
}
