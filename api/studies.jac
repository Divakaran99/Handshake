"""Study endpoints: author and version protocols.

A protocol version that has produced sessions is frozen. Editing it requires
a new version number, so every session can always be traced to the exact
protocol - and pre-registered analysis plan - it ran under.
"""

import from domain.protocol { StudyProtocol, Condition, HasCondition }
import from domain.capability { Capability }
import from api.views {
    StudySummary, StudyDraft, StudyDetail, ConditionSpec, StepSpec, BranchSpec,
    SaveResult, CapabilityInfo
}
import from api.common { find_study, study_summary, study_sessions, is_frozen }
import from api.protocol_io {
    condition_spec, condition_steps, validate_condition, write_condition,
    find_condition, example_args, DESCRIPTIONS
}

def _frozen_message(s: StudyProtocol) -> str {
    return f"version {s.version} already has sessions - bump the version to change the protocol";
}

def:priv list_studies -> list[StudySummary] {
    out = [study_summary(s) for s in [root -->[?:StudyProtocol]]];
    out.sort(key=lambda v: StudySummary : v.title.lower());
    return out;
}

def:priv create_study(draft: StudyDraft) -> SaveResult {
    if draft.title.strip() == "" {
        return SaveResult(ok=False, problems=["title is required"]);
    }
    s = (root ++> StudyProtocol(title=draft.title.strip(),
                                version=draft.version.strip() or "0.1.0",
                                prereg=draft.prereg))[0];
    return SaveResult(ok=True, id=jid(s));
}

"""Edit title / version / pre-registration. A frozen version cannot change its prereg."""
def:priv update_study(study_id: str, draft: StudyDraft) -> SaveResult {
    s = find_study(study_id);
    if s is None {
        return SaveResult(ok=False, problems=["study not found"]);
    }
    new_version = draft.version.strip() or s.version;
    if is_frozen(s) and new_version == s.version and draft.prereg != s.prereg {
        return SaveResult(ok=False, id=study_id, problems=[_frozen_message(s)]);
    }
    for other in study_sessions(s) {
        if other.protocol_version == new_version and new_version != s.version {
            return SaveResult(ok=False, id=study_id,
                              problems=[f"version {new_version} was used before - pick a new number"]);
        }
    }
    if draft.title.strip() != "" {
        s.title = draft.title.strip();
    }
    s.version = new_version;
    s.prereg = draft.prereg;
    return SaveResult(ok=True, id=study_id);
}

"""The version after `current` that no session has used: 0.1.0 -> 0.1.1, v2 -> v3, pilot -> pilot.1."""
def next_version(current: str, used: list[str]) -> str {
    candidate = current.strip() or "0.1.0";
    for _attempt in range(1000) {
        parts: list[str] = candidate.split(".");
        last = parts[-1];
        digits = len(last) - len(last.rstrip("0123456789"));
        if digits > 0 {
            bumped = last[: len(last) - digits] + str(int(last[len(last) - digits :]) + 1);
            candidate = ".".join(parts[:-1] + [bumped]);
        } else {
            candidate = candidate + ".1";
        }
        if candidate not in used {
            return candidate;
        }
    }
    raise ValueError(f"no free version after {current}");
}

"""Unfreeze a study by moving it to the next protocol version, in one step.

Sessions keep the version (and the protocol snapshot) they ran under; the
steps carry over unchanged and become editable for the new version.
"""
def:priv start_new_version(study_id: str) -> SaveResult {
    s = find_study(study_id);
    if s is None {
        return SaveResult(ok=False, problems=["study not found"]);
    }
    study: StudyProtocol = s;
    if not is_frozen(study) {
        return SaveResult(ok=True, id=study_id, version=study.version);
    }
    used = [x.protocol_version for x in study_sessions(study)] + [study.version];
    study.version = next_version(study.version, used);
    return SaveResult(ok=True, id=study_id, version=study.version);
}

"""Delete a study and its protocol. Studies with sessions are kept - delete those first."""
def:priv delete_study(study_id: str) -> SaveResult {
    s = find_study(study_id);
    if s is None {
        return SaveResult(ok=False, problems=["study not found"]);
    }
    if len(study_sessions(s)) > 0 {
        return SaveResult(ok=False, id=study_id,
                          problems=["this study has sessions; delete or withdraw them first"]);
    }
    for c in [s ->:HasCondition:->] {
        for st in condition_steps(c) {
            del st;
        }
        del c;
    }
    del s;
    return SaveResult(ok=True);
}

def:priv get_study(study_id: str) -> StudyDetail | None {
    s = find_study(study_id);
    if s is None {
        return None;
    }
    conds = [condition_spec(c) for c in [s ->:HasCondition:->]];
    return StudyDetail(study=study_summary(s), conditions=conds);
}

"""Create or replace one condition (matched by label) from the editor form."""
def:priv save_condition(study_id: str, spec: ConditionSpec, original_label: str = "") -> SaveResult {
    s = find_study(study_id);
    if s is None {
        return SaveResult(ok=False, problems=["study not found"]);
    }
    if is_frozen(s) {
        return SaveResult(ok=False, id=study_id, problems=[_frozen_message(s)]);
    }
    problems = validate_condition(spec);
    label = spec.label.strip();
    lookup = original_label or label;
    clash = find_condition(s, label);
    if clash is not None and label != lookup {
        problems.append(f"a condition called '{label}' already exists");
    }
    if len(problems) > 0 {
        return SaveResult(ok=False, id=study_id, problems=problems);
    }
    cond = find_condition(s, lookup);
    if cond is None {
        cond = (s +>: HasCondition() :+> Condition(label=label))[0];
    }
    cond.label = label;
    write_condition(cond, spec);
    return SaveResult(ok=True, id=study_id);
}

def:priv delete_condition(study_id: str, label: str) -> SaveResult {
    s = find_study(study_id);
    if s is None {
        return SaveResult(ok=False, problems=["study not found"]);
    }
    if is_frozen(s) {
        return SaveResult(ok=False, id=study_id, problems=[_frozen_message(s)]);
    }
    c = find_condition(s, label);
    if c is None {
        return SaveResult(ok=False, problems=[f"no condition '{label}'"]);
    }
    for st in condition_steps(c) {
        del st;
    }
    del c;
    return SaveResult(ok=True, id=study_id);
}

"""The capability taxonomy with example arguments, for the step editor."""
def:priv capability_catalog -> list[CapabilityInfo] {
    return [
        CapabilityInfo(name=c.name, description=DESCRIPTIONS.get(c.name, ""),
                       example_args=example_args(c))
        for c in Capability
    ];
}

def _greeting_condition(label: str, distance: float) -> ConditionSpec {
    return ConditionSpec(
        label=label,
        factors_json=f"{{\"stop_distance_m\": {distance}}}",
        steps=[
            StepSpec(label="greet", capability="SPEAK",
                     args_json="{\"text\": \"Hello, thanks for joining the study.\"}"),
            StepSpec(label="approach", capability="APPROACH",
                     args_json=f"{{\"stop_distance_m\": {distance}, \"speed_mps\": 0.4}}"),
            StepSpec(label="look", capability="GAZE",
                     args_json="{\"target\": \"face\", \"hold_ms\": 1800}",
                     timeout_ms=4000, next="neutral_response",
                     branches=[BranchSpec(percept="gaze_reciprocated", target="warm_response")]),
            StepSpec(label="warm_response", capability="EXPRESS",
                     args_json="{\"affect\": \"friendly\"}", next="farewell"),
            StepSpec(label="neutral_response", capability="IDLE", args_json="{}"),
            StepSpec(label="farewell", capability="SPEAK",
                     args_json="{\"text\": \"That is the end of the task.\"}", next="END")
        ]
    );
}

"""Create the reference two-condition proxemics study from examples/proxemics."""
def:priv create_example_study -> SaveResult {
    s = (root ++> StudyProtocol(
        title="Greeting distance and gaze reciprocity",
        version="0.1.0",
        prereg="H1: closer approach increases reciprocated gaze."
    ))[0];
    for (label, distance) in [("near", 0.8), ("far", 1.6)] {
        cond = (s +>: HasCondition() :+> Condition(label=label))[0];
        write_condition(cond, _greeting_condition(label, distance));
    }
    return SaveResult(ok=True, id=jid(s));
}
