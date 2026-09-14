"""The robot adapter interface.

Declarations only. Every concrete robot lives in its own module and subclasses
RobotAdapter. Adding a platform must never require touching a protocol.
"""

import from domain.capability { Capability, CapabilitySpec, CapabilityCall, CapabilityResult, Support }

obj RobotAdapter {
    has profile_name: str = "unnamed";

    def capabilities -> list[CapabilitySpec] abs;

    def execute(call: CapabilityCall) -> CapabilityResult abs;

    def raw(command: str, args: dict) -> CapabilityResult abs;

    def spec_for(c: Capability) -> CapabilitySpec | None {
        for spec in self.capabilities() {
            if spec.capability == c {
                return spec;
            }
        }
        return None;
    }

    def supports(c: Capability) -> bool {
        spec = self.spec_for(c);
        return spec is not None and spec.support != Support.UNAVAILABLE;
    }

    def resolve(c: Capability) -> Capability | None {
        spec = self.spec_for(c);
        if spec is None {
            return None;
        }
        if spec.support == Support.NATIVE {
            return c;
        }
        if spec.support == Support.SUBSTITUTED {
            return spec.substitute;
        }
        return None;
    }
}
