"""The session runtime.

A session is a walker traversing the protocol graph. The walker's position is
the session state; the trail it leaves is the dataset. Nothing else in the
system needs to know what "step 4" means.
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

    def log(kind: EventKind, source: str, label: str, payload: dict) -> None {
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
                     {"ok": False, "reason": "capability unavailable on profile"});
        } else {
            self.log(EventKind.CAPABILITY_CALL, "runtime", here.label,
                     {"capability": here.capability.name, "args": here.args});
            res = self.adapter.execute(
                CapabilityCall(capability=here.capability, args=here.args,
                               timeout_ms=here.timeout_ms)
            );
            self.log(EventKind.CAPABILITY_RESULT, self.adapter.profile_name,
                     here.label,
                     {"ok": res.ok, "executed_as": executed.name,
                      "commanded": res.commanded, "achieved": res.achieved});
        }

        observed = self.percept_script.get(here.label, "");
        if observed != "" {
            self.log(EventKind.PERCEPT, "perception", observed, {});
            visit [here ->:Next:on_percept == observed:->] else {
                visit [here ->:Next:on_timeout == True:->];
            }
        } else {
            visit [here ->:Next:on_percept == "":->] else {
                visit [here ->:Next:on_timeout == True:->];
            }
        }
    }

    can finish with Condition exit {
        self.session.status = "complete";
        self.log(EventKind.SESSION_END, "runtime", self.session.code, {});
        report self.trace;
    }
}
