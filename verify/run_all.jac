"""Assertion suite.

`jac test` is unreliable in some 0.16.7 environments (bytecode-cache error), so
the suite is a plain runnable module. CI runs `jac check` on every module and
then executes this file.
"""

import from domain.capability { Capability, CapabilitySpec, CapabilityCall, Support }
import from adapters.sim { SimAdapter }
import from instruments.godspeed { GODSPEED_ANTHROPOMORPHISM }

glob PASSED: int = 0;

def ok(label: str, cond: bool) -> None {
    global PASSED;
    if not cond {
        raise AssertionError(f"FAIL: {label}");
    }
    PASSED += 1;
    print(f"  ok  {label}");
}

with entry {
    a = SimAdapter();

    ok("sim supports SPEAK natively", a.supports(Capability.SPEAK));
    ok("sim reports APPROACH unsupported", not a.supports(Capability.APPROACH));
    ok("EXPRESS degrades to DISPLAY",
       a.resolve(Capability.EXPRESS) == Capability.DISPLAY);
    ok("unavailable capability resolves to None",
       a.resolve(Capability.APPROACH) is None);

    r_bad = a.execute(CapabilityCall(capability=Capability.APPROACH, args={}));
    ok("unavailable capability returns ok=False", not r_bad.ok);

    r_ok = a.execute(CapabilityCall(capability=Capability.GAZE,
                                    args={"hold_s": 1.8}));
    ok("available capability returns ok=True", r_ok.ok);
    ok("commanded is recorded", r_ok.commanded["hold_s"] == 1.8);
    ok("achieved differs from commanded (telemetry evidence)",
       r_ok.achieved["hold_s"] != r_ok.commanded["hold_s"]);

    ok("raw passthrough is recorded", a.raw("custom_cmd", {"x": 1}).ok);

    s = GODSPEED_ANTHROPOMORPHISM;
    ok("godspeed has 5 items", len(s.items) == 5);
    ok("godspeed scores midpoint",
       s.score({"fake_natural": 3, "machine_human": 3, "uncons_conscious": 3,
                "artif_lifelike": 3, "rigid_elegant": 3}) == 3.0);
    ok("godspeed ignores missing items",
       s.score({"fake_natural": 5, "machine_human": 5}) == 5.0);

    print(f"\n{PASSED} assertions passed");
}
