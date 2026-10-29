"""Robot endpoints: register, edit, test and remove robot profiles.

All endpoints are def:priv - each researcher has their own robots on their
own root. Connection tests run from the server, so the URL must be reachable
from wherever `jac start` runs (usually the lab machine on the robot's LAN).
"""

import from domain.robot { RobotProfile }
import from adapters.registry { make_adapter, validate_profile, ProfileError }
import from adapters.presets { robot_presets as _presets }
import from api.views { RobotView, RobotDraft, SaveResult, PresetView, ProbeView }
import from api.common { find_robot, robot_view, profile_rows, probe_view, now_iso, ensure_simulator }

def _profile_from(d: RobotDraft) -> RobotProfile {
    return RobotProfile(
        name=d.name.strip(), kind=d.kind, url=d.url.strip(),
        ros_version=d.ros_version, bindings_json=d.bindings_json,
        percepts_json=d.percepts_json, notes=d.notes
    );
}

"""Every robot profile, creating the built-in simulator on first use."""
def:priv list_robots -> list[RobotView] {
    ensure_simulator();
    views = [robot_view(r) for r in [root -->[?:RobotProfile]]];
    views.sort(key=lambda v: RobotView : v.name.lower());
    return views;
}

def:priv get_robot(robot_id: str) -> RobotView | None {
    r = find_robot(robot_id);
    return robot_view(r) if r is not None else None;
}

"""Starting points for new profiles (simulator, ROS 1/2, Nav2, HTTP, plugin)."""
def:priv robot_presets -> list[PresetView] {
    return [
        PresetView(key=p.key, title=p.title, kind=p.kind, summary=p.summary,
                   url=p.url, ros_version=p.ros_version,
                   bindings_json=p.bindings_json, percepts_json=p.percepts_json)
        for p in _presets()
    ];
}

"""Check a draft without saving it - drives live validation in the editor."""
def:priv check_robot(draft: RobotDraft) -> RobotView {
    p = _profile_from(draft);
    return RobotView(id=draft.id, name=p.name, kind=p.kind, url=p.url,
                     ros_version=p.ros_version, bindings_json=p.bindings_json,
                     percepts_json=p.percepts_json, notes=p.notes,
                     capabilities=profile_rows(p), problems=validate_profile(p));
}

"""Create (empty id) or update a profile. Invalid profiles are not saved."""
def:priv save_robot(draft: RobotDraft) -> SaveResult {
    p = _profile_from(draft);
    problems = validate_profile(p);
    for other in [root -->[?:RobotProfile]] {
        if other.name == p.name and jid(other) != draft.id {
            problems.append(f"another robot is already called '{p.name}'");
        }
    }
    if len(problems) > 0 {
        return SaveResult(ok=False, id=draft.id, problems=problems);
    }
    if draft.id == "" {
        p.created_at = now_iso();
        created = (root ++> p)[0];
        return SaveResult(ok=True, id=jid(created));
    }
    existing = find_robot(draft.id);
    if existing is None {
        return SaveResult(ok=False, id=draft.id, problems=["robot not found"]);
    }
    existing.name = p.name;
    existing.kind = p.kind;
    existing.url = p.url;
    existing.ros_version = p.ros_version;
    existing.bindings_json = p.bindings_json;
    existing.percepts_json = p.percepts_json;
    existing.notes = p.notes;
    existing.updated_at = now_iso();
    return SaveResult(ok=True, id=draft.id);
}

def:priv delete_robot(robot_id: str) -> bool {
    r = find_robot(robot_id);
    if r is None {
        return False;
    }
    del r;
    return True;
}

"""Connect to the robot described by a draft (saved or not) and report what it offers."""
def:priv test_robot(draft: RobotDraft) -> ProbeView {
    p = _profile_from(draft);
    try {
        adapter = make_adapter(p);
    } except ProfileError as e {
        return ProbeView(ok=False, detail="profile is invalid", warnings=e.problems,
                         capabilities=profile_rows(p));
    }
    try {
        return probe_view(adapter.probe(), profile_rows(p));
    } except Exception as e {
        return ProbeView(ok=False, detail=f"{type(e).__name__}: {str(e)}",
                         capabilities=profile_rows(p));
    }
}
