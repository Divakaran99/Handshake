"""Protocol graph <-> editor form.

The protocol IS a graph (Condition -Starts-> Step -Next-> Step ...). The UI
edits it as an ordered list of StepSpec rows. These two functions are the
only translation between the two shapes, so the runtime never sees the form
and the form never sees an edge.
"""

import json;
import from domain.capability { Capability }
import from domain.protocol { StudyProtocol, Condition, Step, Starts, Next, HasCondition }
import from adapters.bindings { capability_names, capability_named, as_dict }
import from api.views { ConditionSpec, StepSpec, BranchSpec }

glob END: str = "END";

def _percept_labels(st: Step) -> list[str] {
    labels: list[str] = [];
    for e in [edge st ->:Next:->] {
        if e.on_percept != "" and e.on_percept not in labels {
            labels.append(e.on_percept);
        }
    }
    return labels;
}

def _fallback(st: Step) -> list[Step] {
    timeout_targets = [st ->:Next:on_timeout == True:->];
    if len(timeout_targets) > 0 {
        return timeout_targets;
    }
    return [st ->:Next:on_percept == "", on_timeout == False:->];
}

def _by_position(st: Step) -> int {
    return st.position;
}

"""Steps of a condition in authoring order (reachable steps only).

Reachability comes from the graph; order comes from Step.position, which the
editor writes. Protocols built in code without positions fall back to
traversal order: main path first, percept branches after.
"""
def condition_steps(cond: Condition) -> list[Step] {
    order: list[Step] = [];
    queue: list[Step] = [cond ->:Starts:->];
    while len(queue) > 0 {
        st = queue.pop(0);
        if st in order {
            continue;
        }
        order.append(st);
        queue = _fallback(st) + queue;
        for label in _percept_labels(st) {
            queue = queue + [st ->:Next:on_percept == label:->];
        }
    }
    if len(order) > 0 and all([st.position > 0 for st in order]) {
        order.sort(key=_by_position);
    }
    return order;
}

def condition_spec(cond: Condition) -> ConditionSpec {
    steps = condition_steps(cond);
    specs: list[StepSpec] = [];
    for (i, st) in enumerate(steps) {
        nxt = _fallback(st);
        following = steps[i + 1].label if i + 1 < len(steps) else "";
        target = nxt[0].label if len(nxt) > 0 else END;
        branches: list[BranchSpec] = [];
        for label in _percept_labels(st) {
            for t in [st ->:Next:on_percept == label:->] {
                branches.append(BranchSpec(percept=label, target=t.label));
            }
        }
        specs.append(StepSpec(
            label=st.label,
            capability=st.capability.name,
            args_json=json.dumps(st.args),
            timeout_ms=st.timeout_ms,
            next="" if target == following else target,
            branches=branches
        ));
    }
    return ConditionSpec(label=cond.label, factors_json=json.dumps(cond.factors),
                         steps=specs);
}

"""Everything wrong with an edited condition. Empty list = safe to save."""
def validate_condition(spec: ConditionSpec) -> list[str] {
    problems: list[str] = [];
    if spec.label.strip() == "" {
        problems.append("condition needs a label");
    }
    try {
        if not isinstance(json.loads(spec.factors_json or "{}"), dict) {
            problems.append("factors must be a JSON object");
        }
    } except ValueError {
        problems.append("factors are not valid JSON");
    }
    if len(spec.steps) == 0 {
        problems.append("a condition needs at least one step");
    }
    labels = [s.label.strip() for s in spec.steps];
    names = capability_names();
    for (i, s) in enumerate(spec.steps) {
        where = f"step {i + 1}";
        lbl = s.label.strip();
        if lbl == "" {
            problems.append(f"{where}: label is required");
        } elif lbl == END {
            problems.append(f"{where}: '{END}' is reserved");
        } elif labels.count(lbl) > 1 {
            problems.append(f"{where}: label '{lbl}' is used twice");
        }
        if s.capability not in names {
            problems.append(f"{where}: unknown capability '{s.capability}'");
        }
        try {
            if not isinstance(json.loads(s.args_json or "{}"), dict) {
                problems.append(f"{where} ({lbl}): args must be a JSON object");
            }
        } except ValueError as e {
            problems.append(f"{where} ({lbl}): args are not valid JSON ({str(e)})");
        }
        if s.timeout_ms < 100 or s.timeout_ms > 600000 {
            problems.append(f"{where} ({lbl}): timeout must be between 100 ms and 10 min");
        }
        if s.next not in ["", END] and s.next not in labels {
            problems.append(f"{where} ({lbl}): 'then' points at unknown step '{s.next}'");
        }
        for b in s.branches {
            if b.percept.strip() == "" {
                problems.append(f"{where} ({lbl}): a branch needs a percept label");
            }
            if b.target not in labels {
                problems.append(f"{where} ({lbl}): branch '{b.percept}' points at unknown step '{b.target}'");
            }
        }
    }
    return problems;
}

"""Replace a condition's step graph with the edited form (validate first)."""
def write_condition(cond: Condition, spec: ConditionSpec) {
    for st in condition_steps(cond) {
        del st;
    }
    cond.factors = as_dict(json.loads(spec.factors_json or "{}"));
    nodes: dict[str, Step] = {};
    for (i, s) in enumerate(spec.steps) {
        nodes[s.label.strip()] = Step(
            label=s.label.strip(),
            capability=capability_named(s.capability),
            args=as_dict(json.loads(s.args_json or "{}")),
            timeout_ms=s.timeout_ms,
            position=i + 1
        );
    }
    first = nodes[spec.steps[0].label.strip()];
    cond +>: Starts() :+> first;
    for (i, s) in enumerate(spec.steps) {
        here_ = nodes[s.label.strip()];
        target = s.next;
        if target == "" {
            target = spec.steps[i + 1].label.strip() if i + 1 < len(spec.steps) else END;
        }
        if len(s.branches) > 0 {
            for b in s.branches {
                here_ +>: Next(on_percept=b.percept.strip()) :+> nodes[b.target];
            }
            if target != END {
                here_ +>: Next(on_timeout=True) :+> nodes[target];
            }
        } elif target != END {
            here_ +>: Next() :+> nodes[target];
        }
    }
}

def find_condition(study: StudyProtocol, label: str) -> Condition | None {
    for c in [study ->:HasCondition:->] {
        if c.label == label {
            return c;
        }
    }
    return None;
}

"""A frozen JSON copy of the condition, stored on each session for provenance."""
def condition_snapshot(study: StudyProtocol, cond: Condition) -> str {
    spec = condition_spec(cond);
    return json.dumps({
        "study": study.title,
        "version": study.version,
        "prereg": study.prereg,
        "condition": spec.label,
        "factors": json.loads(spec.factors_json),
        "steps": [
            {"label": s.label, "capability": s.capability,
             "args": json.loads(s.args_json), "timeout_ms": s.timeout_ms,
             "next": s.next,
             "branches": [{"percept": b.percept, "target": b.target} for b in s.branches]}
            for s in spec.steps
        ]
    }, indent=2);
}

"""Default example arguments per capability, for the step editor."""
glob EXAMPLE_ARGS: dict[str, dict[str, object]] = {
    "SPEAK": {"text": "Hello, thanks for joining the study."},
    "GAZE": {"target": "face", "hold_ms": 1800},
    "GESTURE": {"name": "wave"},
    "APPROACH": {"stop_distance_m": 1.2, "speed_mps": 0.4},
    "ORIENT": {"yaw": 1.57},
    "EXPRESS": {"affect": "friendly"},
    "DISPLAY": {"media": "slides/intro.png"},
    "IDLE": {"hold_ms": 1000}
};

glob DESCRIPTIONS: dict[str, str] = {
    "SPEAK": "Utter text, optionally with prosody hints",
    "GAZE": "Direct attention at a target",
    "GESTURE": "Deictic, iconic or beat gesture",
    "APPROACH": "Change proxemic distance (stop distance, speed, angle)",
    "ORIENT": "Change body or head orientation",
    "EXPRESS": "Affective display",
    "DISPLAY": "Show media on a screen",
    "IDLE": "Explicit hold / no-op"
};

def example_args(c: Capability) -> str {
    return json.dumps(EXAMPLE_ARGS.get(c.name, {}));
}
