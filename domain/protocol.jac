"""Design-time graph: the protocol a researcher authors once and versions."""

import from domain.capability { Capability }

node StudyProtocol {
    has title: str,
        version: str = "0.1.0",
        prereg: str = "";
}

node Condition {
    has label: str,
        factors: dict = {};
}

node Step {
    has label: str,
        capability: Capability,
        args: dict = {},
        timeout_ms: int = 8000,
        wizard_gated: bool = False,
        position: int = 0;   # authoring order in the editor; traversal ignores it
}

edge HasCondition: StudyProtocol --> Condition {}

edge Starts: Condition --> Step {}

edge Next: Step --> Step {
    has on_percept: str = "",
        on_timeout: bool = False,
        note: str = "";
}
