"""The session runtime.

A session is a walker traversing the protocol graph. The walker's position is
the session state; the trail it leaves is the dataset. Nothing else in the
system needs to know what "step 4" means.

Branching on perception works the same for every robot:

    1. a scripted percept for this step (percept_script) wins - this is how
       the simulator, tests and Wizard-of-Oz overrides inject observations;
    2. otherwise, if the step has percept branches, the adapter is asked to
       wait up to the step's timeout for one of those labels;
    3. nothing perceived -> follow the unconditional edge, else the timeout edge.
"""

import from domain.capability { Capability, CapabilityCall }
import from domain.protocol { Condition, Step, Starts, Next }
import from domain.session { Session, Event, EventKind, Logged }
import from adapters.adapter { RobotAdapter }
import from runtime.clock { Clock }

walker RunSession {
    has adapter: RobotAdapter,
        clock: Clock,
        session: Session,
        percept_script: dict[str, str] = {},
        trace: list[str] = [],
        reports: list[list[str]] = [];

    def log(kind: EventKind, source: str, label: str, payload: dict) {
        t = self.clock.now_ms();
        self.session +>: Logged() :+> Event(
            kind=kind, t_mono_ms=t, source=source, label=label, payload=payload
        );
        self.trace.append(f"{t:>7} ms  {kind.name:<20} {label}");
    }

    can begin with Condition entry {
        self.clock.start();
        self.session.t0_wall_iso = self.clock.t0_wall_iso;
        self.session.status = "running";
        self.log(EventKind.SESSION_START, "runtime", here.label,
                 {"robot_profile": self.adapter.profile_name});
        visit [here ->:Starts:->];
    }

    can on_step with Step entry {
        self.log(EventKind.STEP_ENTER, "runtime", here.label, {});

        executed = self.adapter.resolve(here.capability);
        if executed is None {
            self.log(EventKind.CAPABILITY_RESULT, self.adapter.profile_name,
                     here.label,
                     {"ok": False, "capability": here.capability.name,
                      "reason": "capability unavailable on profile"});
        } else {
            self.log(EventKind.CAPABILITY_CALL, "runtime", here.label,
                     {"capability": here.capability.name, "args": here.args});
            try {
                res = self.adapter.execute(
                    CapabilityCall(capability=here.capability, args=here.args,
                                   timeout_ms=here.timeout_ms)
                );
                self.log(EventKind.CAPABILITY_RESULT, self.adapter.profile_name,
                         here.label,
                         {"ok": res.ok, "executed_as": executed.name,
                          "commanded": res.commanded, "achieved": res.achieved,
                          "duration_ms": res.duration_ms(), "wire": res.wire,
                          "detail": res.detail});
            } except Exception as e {
                # A dropped connection must not lose the session: record the
                # failure as evidence and keep walking the protocol.
                self.log(EventKind.CAPABILITY_RESULT, self.adapter.profile_name,
                         here.label,
                         {"ok": False, "executed_as": executed.name,
                          "reason": f"{type(e).__name__}: {str(e)}"});
            }
        }

        expected = [e.on_percept for e in [edge here ->:Next:->] if e.on_percept != ""];
        observed = self.percept_script.get(here.label, "");
        source = "script";
        if observed == "" and len(expected) > 0 {
            try {
                observed = self.adapter.await_percept(here.label, expected, here.timeout_ms);
            } except Exception {
                observed = "";
            }
            source = "perception";
        }
        if observed != "" {
            self.log(EventKind.PERCEPT, source, observed, {});
            visit [here ->:Next:on_percept == observed:->] else {
                visit [here ->:Next:on_timeout == True:->];
            }
        } else {
            # Nothing perceived: an explicit timeout branch wins; otherwise take
            # the unconditional edge(s). (Timeout edges also carry on_percept "",
            # so trying them first keeps a step from forking down both paths.)
            visit [here ->:Next:on_timeout == True:->] else {
                visit [here ->:Next:on_percept == "":->];
            }
        }
    }

    can finish with Condition exit {
        self.session.status = "complete";
        self.log(EventKind.SESSION_END, "runtime", self.session.code, {});
        report self.trace;
    }
}

"""Run one condition on one robot: connect, walk the protocol, always disconnect.

Raises if the robot cannot be reached at all; the session is then marked
"failed" so the attempt stays in the dataset rather than vanishing.
"""
def run_condition(cond: Condition, adapter: RobotAdapter, session: Session,
                  percept_script: dict[str, str] | None = None) -> list[str] {
    try {
        adapter.connect();
    } except Exception as e {
        session.status = "failed";
        raise ConnectionError(f"could not connect to {adapter.profile_name}: {str(e)}") from e;
    }
    try {
        walker_ = cond spawn RunSession(
            adapter=adapter, clock=Clock(), session=session,
            percept_script=percept_script or {}
        );
        return walker_.trace;
    } finally {
        adapter.close();
    }
}
