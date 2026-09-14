"""Run-time graph: one subgraph per session. This is the dataset."""

import from domain.participant { Participant }

enum EventKind {
    SESSION_START,
    STEP_ENTER,
    CAPABILITY_CALL,
    CAPABILITY_RESULT,
    PERCEPT,
    WIZARD_ACTION,
    INSTRUMENT_RESPONSE,
    SESSION_END
}

node Session {
    has code: str,
        protocol_title: str,
        protocol_version: str,
        condition_label: str,
        robot_profile: str,
        seed: int = 0,
        t0_wall_iso: str = "",
        status: str = "created";
}

node Event {
    has kind: EventKind,
        t_mono_ms: int,
        source: str,
        label: str = "",
        payload: dict = {};
}

edge Logged: Session --> Event {}

edge Ran: Participant --> Session {}
