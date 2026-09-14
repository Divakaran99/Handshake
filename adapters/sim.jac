"""Simulated robot. The default adapter, the CI adapter, the demo adapter.

Anyone can clone this repository and run a complete study with no hardware.
It deliberately declares one UNAVAILABLE and one SUBSTITUTED capability so the
degradation path is exercised on every run rather than only on exotic robots.
"""

import random;
import from domain.capability { Capability, CapabilitySpec, CapabilityCall, CapabilityResult, Support }
import from adapters.adapter { RobotAdapter }

obj SimAdapter(RobotAdapter) {
    has profile_name: str = "sim-tabletop",
        jitter: float = 0.12,
        rng: random.Random = random.Random(7);

    def capabilities -> list[CapabilitySpec] {
        return [
            CapabilitySpec(capability=Capability.SPEAK),
            CapabilitySpec(capability=Capability.GAZE),
            CapabilitySpec(capability=Capability.GESTURE),
            CapabilitySpec(capability=Capability.DISPLAY),
            CapabilitySpec(capability=Capability.IDLE),
            CapabilitySpec(
                capability=Capability.EXPRESS,
                support=Support.SUBSTITUTED,
                substitute=Capability.DISPLAY,
                note="no actuated face; affect is rendered on the screen"
            ),
            CapabilitySpec(
                capability=Capability.APPROACH,
                support=Support.UNAVAILABLE,
                note="tabletop platform has no mobile base"
            )
        ];
    }

    def execute(call: CapabilityCall) -> CapabilityResult {
        executed = self.resolve(call.capability);
        if executed is None {
            return CapabilityResult(
                ok=False,
                capability=call.capability,
                detail="capability unavailable on this profile"
            );
        }
        commanded = dict(call.args);
        achieved = dict(call.args);
        # commanded-vs-achieved: the sim perturbs continuous parameters
        for (k, v) in call.args.items() {
            if isinstance(v, float) {
                fv: float = v as float;
                r: float = self.rng.random() as float;
                # NOTE: round(x, n) runs correctly but fails `jac check` in
                # jaclang 0.16.7 (checker stub gap). Fixed-point instead.
                achieved[k] = int(fv * (1.0 - self.jitter * r) * 10000) / 10000.0;
            }
        }
        return CapabilityResult(
            ok=True,
            capability=call.capability,
            executed_as=executed,
            commanded=commanded,
            achieved=achieved,
            detail=f"sim executed {executed.name}"
        );
    }

    def raw(command: str, args: dict) -> CapabilityResult {
        return CapabilityResult(
            ok=True,
            capability=Capability.IDLE,
            commanded={"raw": command} | args,
            detail="raw passthrough recorded but not executed by the simulator"
        );
    }
}
