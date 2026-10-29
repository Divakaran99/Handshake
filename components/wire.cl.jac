"""Builders for request objects sent to the server.

On the client an `sv import`-ed name compiles to an RPC stub, so server types
cannot be constructed here with `StepSpec(...)`. Responses arrive as typed
instances; for requests we build plain objects with the same fields and cast
them to the server type. The server validates and hydrates them on arrival.
"""

sv import from ..api.views {
    StepSpec, BranchSpec, ConditionSpec, StudyDraft, RobotDraft, RunRequest,
    PerceptChoice, RunResult
}

def:pub branch_spec(percept: str, target: str) -> BranchSpec {
    raw: any = {"percept": percept, "target": target};
    return raw as BranchSpec;
}

def:pub step_spec(label: str, capability: str, args_json: str, timeout_ms: int = 8000,
                  then: str = "", branches: list[BranchSpec] = []) -> StepSpec {
    raw: any = {
        "label": label, "capability": capability, "args_json": args_json,
        "timeout_ms": timeout_ms, "next": then,
        "branches": [branch_spec(b.percept, b.target) for b in branches]
    };
    return raw as StepSpec;
}

def:pub copy_step(s: StepSpec) -> StepSpec {
    return step_spec(s.label, s.capability, s.args_json, s.timeout_ms, s.next, s.branches);
}

def:pub condition_spec(label: str, factors_json: str, steps: list[StepSpec]) -> ConditionSpec {
    raw: any = {"label": label, "factors_json": factors_json,
                "steps": [copy_step(s) for s in steps]};
    return raw as ConditionSpec;
}

def:pub study_draft(title: str, version: str, prereg: str) -> StudyDraft {
    raw: any = {"title": title, "version": version, "prereg": prereg};
    return raw as StudyDraft;
}

def:pub robot_draft(robot_id: str, name: str, kind: str, url: str, ros_version: str,
                    bindings_json: str, percepts_json: str, notes: str) -> RobotDraft {
    raw: any = {"id": robot_id, "name": name, "kind": kind, "url": url,
                "ros_version": ros_version, "bindings_json": bindings_json,
                "percepts_json": percepts_json, "notes": notes};
    return raw as RobotDraft;
}

def:pub percept_choice(step: str, percept: str) -> PerceptChoice {
    raw: any = {"step": step, "percept": percept};
    return raw as PerceptChoice;
}

def:pub run_request(study_id: str, condition_label: str, robot_id: str,
                    participant_code: str, consent_scope: str,
                    percepts: list[PerceptChoice]) -> RunRequest {
    raw: any = {"study_id": study_id, "condition_label": condition_label,
                "robot_id": robot_id, "participant_code": participant_code,
                "consent_scope": consent_scope, "percepts": percepts};
    return raw as RunRequest;
}

def:pub failed_run(error: str) -> RunResult {
    raw: any = {"ok": False, "error": error, "session": None, "trace": []};
    return raw as RunResult;
}
