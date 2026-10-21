"""Wire types: what the API returns and accepts.

Every endpoint speaks these objects, never raw nodes, so the persisted graph
can evolve without breaking the UI or REST consumers. The Jac client receives
them as typed instances (`robot.name`, not `robot["name"]`).

JSON-shaped fields (step args, bindings, payloads) cross the wire as strings
so the UI can edit them as text and the server stays the single validator.
"""

# ------------------------------------------------------------- robots ----

obj CapabilityRow {
    has capability: str,
        support: str,
        via: str = "",
        note: str = "";
}

obj RobotView {
    has id: str,
        name: str,
        kind: str,
        url: str = "",
        ros_version: str = "2",
        bindings_json: str = "{}",
        percepts_json: str = "[]",
        notes: str = "",
        updated_at: str = "",
        capabilities: list[CapabilityRow] = [],
        problems: list[str] = [];
}

obj RobotDraft {
    has id: str = "",
        name: str = "",
        kind: str = "sim",
        url: str = "",
        ros_version: str = "2",
        bindings_json: str = "{}",
        percepts_json: str = "[]",
        notes: str = "";
}

obj SaveResult {
    has ok: bool,
        id: str = "",
        problems: list[str] = [];
}

# ------------------------------------------------------------ studies ----

obj StudySummary {
    has id: str,
        title: str,
        version: str,
        prereg: str = "",
        n_conditions: int = 0,
        n_sessions: int = 0,
        frozen: bool = False;
}

obj StudyDraft {
    has title: str = "",
        version: str = "0.1.0",
        prereg: str = "";
}

"""A percept branch: when `percept` is observed, go to step `target`."""
obj BranchSpec {
    has percept: str = "",
        target: str = "";
}

"""One protocol step as the editor sees it.

`next` is where to go afterwards: "" means the following step in the list,
"END" ends the session. With percept branches, `next` is taken only when none
of the percepts arrives within `timeout_ms`.
"""
obj StepSpec {
    has label: str = "",
        capability: str = "SPEAK",
        args_json: str = "{}",
        timeout_ms: int = 8000,
        next: str = "",
        branches: list[BranchSpec] = [];
}

obj ConditionSpec {
    has label: str = "",
        factors_json: str = "{}",
        steps: list[StepSpec] = [];
}

obj StudyDetail {
    has study: StudySummary,
        conditions: list[ConditionSpec] = [];
}

# ----------------------------------------------------------- sessions ----

"""Which percept the simulator should 'see' at a step (sim and wizard runs)."""
obj PerceptChoice {
    has step: str = "",
        percept: str = "";
}

obj RunRequest {
    has study_id: str = "",
        condition_label: str = "",
        robot_id: str = "",
        participant_code: str = "",
        consent_scope: str = "audio+video",
        percepts: list[PerceptChoice] = [];
}

obj SessionSummary {
    has id: str,
        code: str,
        study_title: str = "",
        protocol_version: str = "",
        condition_label: str = "",
        robot_profile: str = "",
        participant_code: str = "",
        status: str = "",
        started_at: str = "",
        n_steps: int = 0,
        n_events: int = 0,
        n_percepts: int = 0,
        capability_failures: int = 0,
        duration_ms: int = 0,
        godspeed: float = -1.0;
}

obj RunResult {
    has ok: bool,
        error: str = "",
        session: SessionSummary | None = None,
        trace: list[str] = [];
}

obj EventRow {
    has session_code: str,
        condition_label: str = "",
        robot_profile: str = "",
        participant_code: str = "",
        t_ms: int = 0,
        kind: str = "",
        source: str = "",
        label: str = "",
        ok: str = "",
        duration_ms: int = -1,
        payload_json: str = "{}";
}

"""One commanded-vs-achieved pair from a capability result."""
obj DeltaRow {
    has key: str,
        commanded: str = "",
        achieved: str = "";
}

"""A stop on the session trail: a step (with its capability result), a percept, an instrument, or the start/end."""
obj TrailStop {
    has kind: str,
        t_ms: int = 0,
        label: str = "",
        capability: str = "",
        executed_as: str = "",
        ok: str = "",
        detail: str = "",
        source: str = "",
        duration_ms: int = -1,
        deltas: list[DeltaRow] = [],
        wire_json: str = "";
}

obj SessionDetail {
    has summary: SessionSummary,
        events: list[EventRow] = [],
        trail: list[TrailStop] = [],
        protocol_snapshot: str = "";
}

obj ScaleItemView {
    has key: str,
        anchor_low: str,
        anchor_high: str;
}

obj InstrumentView {
    has name: str,
        citation: str = "",
        points: int = 5,
        items: list[ScaleItemView] = [];
}

obj ParticipantView {
    has code: str,
        enrolled_at: str = "",
        consent_scope: str = "",
        consent_active: bool = False,
        n_sessions: int = 0;
}

obj DashboardView {
    has n_robots: int = 0,
        n_studies: int = 0,
        n_sessions: int = 0,
        n_participants: int = 0,
        recent: list[SessionSummary] = [];
}

obj PresetView {
    has key: str,
        title: str,
        kind: str,
        summary: str,
        url: str = "",
        ros_version: str = "2",
        bindings_json: str = "{}",
        percepts_json: str = "[]";
}

obj ProbeView {
    has ok: bool,
        detail: str = "",
        latency_ms: int = 0,
        topics: list[str] = [],
        warnings: list[str] = [],
        capabilities: list[CapabilityRow] = [];
}

"""A capability as the step editor presents it."""
obj CapabilityInfo {
    has name: str,
        description: str,
        example_args: str = "{}";
}
