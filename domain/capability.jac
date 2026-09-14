"""Capability taxonomy.

The single most important design commitment in this project: protocols are
authored against *capabilities*, never against a specific robot. A capability
is behavioural intent ("approach to 1.2 m at 0.4 m/s"), never a motion command
("set joint 3 to 0.7 rad"). The robot's own stack owns motion and safety.
"""

enum Capability {
    SPEAK,      # utter text, optionally with prosody hints
    GAZE,       # direct attention at a target
    GESTURE,    # deictic / iconic / beat gesture
    APPROACH,   # change proxemic distance: stop_distance, speed, angle
    ORIENT,     # change body or head orientation
    EXPRESS,    # affective display
    DISPLAY,    # show media on a screen
    IDLE        # explicit hold / no-op
}

enum Support {
    NATIVE,       # the platform does this directly
    SUBSTITUTED,  # approximated by another capability, declared up front
    UNAVAILABLE   # the platform cannot do this at all
}

obj CapabilitySpec {
    has capability: Capability,
        support: Support = Support.NATIVE,
        substitute: Capability | None = None,
        note: str = "";
}

obj CapabilityCall {
    has capability: Capability,
        args: dict = {},
        timeout_ms: int = 8000;
}

obj CapabilityResult {
    has ok: bool,
        capability: Capability,
        executed_as: Capability | None = None,
        started_ms: int = 0,
        ended_ms: int = 0,
        commanded: dict = {},
        achieved: dict = {},
        detail: str = "";

    def duration_ms -> int {
        return self.ended_ms - self.started_ms;
    }
}
