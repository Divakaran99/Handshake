"""The robot adapter interface.

Every concrete robot lives in its own module and subclasses RobotAdapter.
Adding a platform must never require touching a protocol.

The interface has two halves:

  commanding  capabilities / execute / raw   (abstract - every adapter)
  lifecycle   connect / close / await_percept / probe
              (defaults are no-ops, so an adapter that has no transport and
               no perception - like the simulator - needs none of them)
"""

import from domain.capability { Capability, CapabilitySpec, CapabilityCall, CapabilityResult, Support }

"""What a connection test found. Returned to the UI and the API verbatim."""
obj ProbeReport {
    has ok: bool,
        profile: str = "",
        kind: str = "",
        detail: str = "",
        latency_ms: int = 0,
        topics: list[str] = [],
        warnings: list[str] = [],
        capabilities: list[str] = [];
}

obj RobotAdapter {
    has profile_name: str = "unnamed";

    def capabilities -> list[CapabilitySpec] abs;

    def execute(call: CapabilityCall) -> CapabilityResult abs;

    def raw(command: str, args: dict) -> CapabilityResult abs;

    """Open the transport. Called once before a session starts."""
    def connect {}

    """Release the transport. Called once after a session ends, even on error."""
    def close {}

    """Block until one of `expect` is perceived, or `timeout_ms` passes.

    Returns the perceived label, or "" on timeout. `step` is the label of the
    protocol step that is waiting, for adapters that script percepts per step.
    """
    def await_percept(_step: str, _expect: list[str], _timeout_ms: int) -> str {
        return "";
    }

    """Check that the robot is reachable without running a session."""
    def probe -> ProbeReport {
        return ProbeReport(
            ok=True,
            profile=self.profile_name,
            detail="no transport to test",
            capabilities=self.capability_summary()
        );
    }

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

    """One human-readable line per declared capability, e.g. 'EXPRESS: SUBSTITUTED -> DISPLAY'."""
    def capability_summary -> list[str] {
        lines: list[str] = [];
        for spec in self.capabilities() {
            line = f"{spec.capability.name}: {spec.support.name}";
            if spec.substitute is not None {
                line = line + f" -> {spec.substitute.name}";
            }
            lines.append(line);
        }
        return lines;
    }
}
