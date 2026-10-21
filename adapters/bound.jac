"""Shared machinery for adapters driven by a binding table (ROS, HTTP).

A BoundAdapter turns one CapabilityCall into one transport operation:

    resolve capability (native / substituted / unavailable)
      -> remap args if substituted
      -> pick the binding of the capability that will actually execute
      -> dispatch(binding, args)   # the only transport-specific step
      -> stamp timing, commanded args, and the exact wire payload

Subclasses implement `dispatch` and `hold`; everything else is here so every
transport degrades and records evidence the same way.
"""

import os;
import time;
import from urllib.parse { urlparse }
import from domain.capability { Capability, CapabilitySpec, CapabilityCall, CapabilityResult }
import from adapters.adapter { RobotAdapter }
import from adapters.bindings { Binding, BindingTable, TemplateError, render, hold_ms_of, as_dict }

def now_ms -> int {
    return time.monotonic_ns() // 1000000;
}

"""Refuse robot URLs outside HANDSHAKE_ROBOT_HOSTS when that variable is set.

A hosted, multi-user Handshake server makes outbound connections on behalf of
researchers; the allowlist keeps it from being pointed at internal services.
"""
def check_host(url: str) {
    allowed = os.environ.get("HANDSHAKE_ROBOT_HOSTS", "").strip();
    if allowed == "" {
        return;
    }
    host = urlparse(url).hostname or "";
    hosts = [h.strip() for h in allowed.split(",") if h.strip() != ""];
    if host not in hosts {
        raise PermissionError(
            f"robot host '{host}' is not in HANDSHAKE_ROBOT_HOSTS ({allowed})"
        );
    }
}

obj BoundAdapter(RobotAdapter) {
    has table: BindingTable = BindingTable();

    override def capabilities -> list[CapabilitySpec] {
        return self.table.specs;
    }

    """Send one binding to the robot. Implemented per transport."""
    def dispatch(b: Binding, args: dict[str, object], call: CapabilityCall) -> CapabilityResult abs;

    """Wait `ms` while staying responsive (ROS keeps reading percepts)."""
    def hold(ms: int) {
        if ms > 0 {
            time.sleep(ms / 1000.0);
        }
    }

    override def execute(call: CapabilityCall) -> CapabilityResult {
        started = now_ms();
        executed = self.resolve(call.capability);
        res = CapabilityResult(ok=False, capability=call.capability,
                               commanded=dict(call.args));
        if executed is None {
            res.detail = "capability unavailable on this profile";
            res.started_ms = started;
            res.ended_ms = now_ms();
            return res;
        }
        b = self.table.binding_for(executed);
        if b is None {
            res.detail = f"no binding for {executed.name}";
            return res;
        }
        try {
            args: dict[str, object] = {str(k): v for (k, v) in call.args.items()};
            if executed != call.capability {
                sub = self.table.binding_for(call.capability);
                if sub is not None and sub.template is not None {
                    args = {**args, **as_dict(render(sub.template, args))};
                }
            }
            if b.op == "noop" {
                self.hold(hold_ms_of(b, args));
                res = CapabilityResult(ok=True, capability=call.capability,
                                       detail="hold");
            } else {
                res = self.dispatch(b, args, call);
                self.hold(hold_ms_of(b, args));
            }
        } except TemplateError as e {
            res = CapabilityResult(ok=False, capability=call.capability, detail=str(e));
        } except Exception as e {
            res = CapabilityResult(ok=False, capability=call.capability,
                                   detail=f"{type(e).__name__}: {str(e)}");
        }
        res.capability = call.capability;
        res.executed_as = executed;
        res.commanded = dict(call.args);
        res.started_ms = started;
        res.ended_ms = now_ms();
        return res;
    }

    override def raw(command: str, args: dict) -> CapabilityResult {
        return CapabilityResult(
            ok=False,
            capability=Capability.IDLE,
            commanded={"raw": command} | args,
            detail="raw commands are not sent to configured robots; add a binding instead"
        );
    }
}
