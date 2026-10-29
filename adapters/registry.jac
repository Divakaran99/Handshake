"""Profile -> adapter. The only place that knows every connector kind.

The API and the session runtime never construct adapters directly; they hand
a RobotProfile to `make_adapter` and get back something that satisfies the
RobotAdapter interface. Adding a connector kind means adding a branch here and
a module next to this one - protocols, sessions and the UI are untouched.
"""

import json;
import importlib;
import from domain.robot { RobotProfile, CONNECTOR_KINDS }
import from adapters.adapter { RobotAdapter }
import from adapters.sim { SimAdapter }
import from adapters.rosbridge { RosbridgeAdapter }
import from adapters.http { HttpAdapter }
import from adapters.bindings { parse_bindings, parse_percepts, as_dict }

"""A profile that cannot be turned into an adapter; `problems` says why."""
obj ProfileError(Exception) {
    has problems: list[str] = [];

    def __str__ -> str {
        return "; ".join(self.problems);
    }
}

"""Everything wrong with a profile, without connecting to anything."""
def validate_profile(p: RobotProfile) -> list[str] {
    problems: list[str] = [];
    if p.name.strip() == "" {
        problems.append("name is required");
    }
    if p.kind not in CONNECTOR_KINDS {
        problems.append(f"kind must be one of {', '.join(CONNECTOR_KINDS)}");
        return problems;
    }
    if p.kind == "rosbridge" {
        if not (p.url.startswith("ws://") or p.url.startswith("wss://")) {
            problems.append("rosbridge URL must start with ws:// or wss:// (rosbridge listens on port 9090 by default)");
        }
        if p.ros_version not in ["1", "2"] {
            problems.append("ROS version must be 1 or 2");
        }
        table = parse_bindings(p.bindings_json, "rosbridge", p.ros_version);
        problems.extend(table.errors);
        parse_percepts(p.percepts_json, problems);
    } elif p.kind == "http" {
        if not (p.url.startswith("http://") or p.url.startswith("https://")) {
            problems.append("HTTP URL must start with http:// or https://");
        }
        problems.extend(parse_bindings(p.bindings_json, "http").errors);
    } elif p.kind == "plugin" {
        if ":" not in p.url {
            problems.append("plugin path must look like adapters.my_robot:MyRobotAdapter");
        } elif not p.url.startswith("adapters.") {
            problems.append("plugin modules must live under the adapters/ package");
        }
    }
    return problems;
}

"""Import and instantiate a RobotAdapter subclass named 'adapters.module:Class'."""
def _load_plugin(p: RobotProfile) -> RobotAdapter {
    (module_name, _, class_name) = p.url.partition(":");
    module = importlib.import_module(module_name);
    cls = getattr(module, class_name, None);
    if not isinstance(cls, type) or not issubclass(cls, RobotAdapter) {
        raise ProfileError(problems=[f"{p.url} is not a RobotAdapter subclass"]);
    }
    adapter = cls() as RobotAdapter;
    adapter.profile_name = p.name;
    if hasattr(adapter, "configure") and p.bindings_json.strip() not in ["", "{}"] {
        getattr(adapter, "configure")(as_dict(json.loads(p.bindings_json)));
    }
    return adapter;
}

"""Build the adapter for a profile. Raises ProfileError if the profile is invalid."""
def make_adapter(p: RobotProfile) -> RobotAdapter {
    problems = validate_profile(p);
    if len(problems) > 0 {
        raise ProfileError(problems=problems);
    }
    if p.kind == "rosbridge" {
        rules_errors: list[str] = [];
        return RosbridgeAdapter(
            profile_name=p.name,
            url=p.url,
            ros_version=p.ros_version,
            table=parse_bindings(p.bindings_json, "rosbridge", p.ros_version),
            percept_rules=parse_percepts(p.percepts_json, rules_errors)
        );
    }
    if p.kind == "http" {
        return HttpAdapter(profile_name=p.name, url=p.url,
                           table=parse_bindings(p.bindings_json, "http"));
    }
    if p.kind == "plugin" {
        return _load_plugin(p);
    }
    return SimAdapter(profile_name=p.name);
}
