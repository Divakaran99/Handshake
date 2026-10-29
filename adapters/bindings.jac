"""Capability bindings: the translation table between Handshake and a robot.

A robot profile stores two JSON documents. This module parses and validates
both, and renders argument templates. It knows nothing about transports.

bindings_json - one entry per capability the robot can perform:

    {
      "SPEAK":    {"op": "publish", "topic": "/hri/speak",
                   "type": "std_msgs/msg/String", "msg": {"data": "{text}"},
                   "hold_ms": "{hold_ms|1500}"},
      "GAZE":     {"op": "service", "service": "/head/look_at",
                   "type": "my_msgs/srv/LookAt", "args": {"target": "{target}"}},
      "APPROACH": {"op": "action", "action": "/approach_person",
                   "type": "my_msgs/action/Approach",
                   "goal": {"stop_distance": "{stop_distance_m}"}},
      "GESTURE":  {"op": "intent", "wait_result": true},
      "EXPRESS":  {"op": "substitute", "with": "DISPLAY",
                   "args": {"media": "faces/{affect}.png"}},
      "DISPLAY":  {"op": "http", "method": "POST", "path": "/api/display",
                   "body": {"file": "{media}"}},
      "ORIENT":   {"op": "unavailable", "note": "fixed torso"},
      "_namespace": "/robot1"
    }

A capability with no entry is UNAVAILABLE - except IDLE, which is always a
native hold. Templates are any JSON value; a string "{name}" is replaced by
the step argument `name` (keeping its JSON type), "{name|default}" falls back
to `default`, and placeholders inside longer strings are interpolated.

percepts_json - rules that turn incoming ROS messages into percept labels:

    [
      {"label": "gaze_reciprocated", "topic": "/hri/gaze_on_robot",
       "type": "std_msgs/msg/Bool", "field": "data", "equals": true},
      {"label_from": "data", "topic": "/handshake/percept",
       "type": "std_msgs/msg/String"}
    ]
"""

import json;
import re;
import from domain.capability { Capability, CapabilitySpec, Support }

glob ROS_OPS: list[str] = ["publish", "service", "action", "intent"];
glob HTTP_OPS: list[str] = ["http"];
glob META_OPS: list[str] = ["substitute", "unavailable", "noop"];

glob PLACEHOLDER: re.Pattern[str] = re.compile(
    r"\{([A-Za-z_][A-Za-z0-9_]*)(?:\|([^}]*))?\}"
);

"""Raised when a template names an argument the step did not supply."""
obj TemplateError(Exception) {
    has missing: str = "";

    def __str__ -> str {
        return f"step is missing argument '{self.missing}'";
    }
}

obj Binding {
    has capability: Capability,
        op: str,
        target: str = "",
        msg_type: str = "",
        template: object = None,
        query: object = None,
        method: str = "POST",
        substitute: Capability | None = None,
        hold_ms: object = 0,
        wait_result: bool = False,
        note: str = "";
}

obj PerceptRule {
    has topic: str,
        msg_type: str = "",
        label: str = "",
        label_from: str = "",
        field: str = "",
        has_equals: bool = False,
        equals: object = None;

    """The label this message produces, or "" if the rule does not fire."""
    def match(msg: object) -> str {
        if self.label_from != "" {
            v = field_value(msg, self.label_from);
            return "" if v is None else str(v);
        }
        if self.has_equals {
            return self.label if field_value(msg, self.field) == self.equals else "";
        }
        return self.label;
    }
}

obj BindingTable {
    has specs: list[CapabilitySpec] = [],
        bindings: dict[str, Binding] = {},
        namespace: str = "",
        probe_path: str = "",
        errors: list[str] = [],
        warnings: list[str] = [];

    def binding_for(c: Capability) -> Binding | None {
        return self.bindings.get(c.name, None);
    }

    def uses_op(op: str) -> bool {
        for b in self.bindings.values() {
            if b.op == op {
                return True;
            }
        }
        return False;
    }
}

"""Every capability name, in declaration order."""
def capability_names -> list[str] {
    return [c.name for c in Capability];
}

"""Look up a capability by its enum name (raises KeyError if unknown)."""
def capability_named(name: str) -> Capability {
    for c in Capability {
        if c.name == name {
            return c;
        }
    }
    raise KeyError(name);
}

"""Narrow a decoded JSON value to a string-keyed dict ({} if it is not one)."""
def as_dict(v: object) -> dict[str, object] {
    if isinstance(v, dict) {
        d = v as dict[str, object];
        return {str(k): x for (k, x) in d.items()};
    }
    return {};
}

"""Read a dotted field path ("pose.position.x") out of a decoded message."""
def field_value(msg: object, path: str) -> object {
    cur: object = msg;
    if path == "" {
        return cur;
    }
    for part in path.split(".") {
        if isinstance(cur, dict) and part in cur {
            cur = cur[part];
        } else {
            return None;
        }
    }
    return cur;
}

"""Parse a template default: JSON if it parses ("0.4", "true"), else the raw text."""
def _parse_default(text: str) -> object {
    try {
        return json.loads(text);
    } except ValueError {
        return text;
    }
}

def _lookup(name: str, fallback: str | None, args: dict[str, object]) -> object {
    if name in args {
        return args[name];
    }
    if fallback is not None {
        return _parse_default(fallback);
    }
    raise TemplateError(missing=name);
}

"""Render a JSON template against step arguments."""
def render(tpl: object, args: dict[str, object]) -> object {
    if isinstance(tpl, str) {
        whole = PLACEHOLDER.fullmatch(tpl);
        if whole is not None {
            return _lookup(whole.group(1), whole.group(2), args);
        }
        def _sub(m: re.Match[str]) -> str {
            return str(_lookup(m.group(1), m.group(2), args));
        }
        return PLACEHOLDER.sub(_sub, tpl);
    }
    if isinstance(tpl, dict) {
        return {str(k): render(v, args) for (k, v) in tpl.items()};
    }
    if isinstance(tpl, list) {
        return [render(x, args) for x in tpl];
    }
    return tpl;
}

"""Resolve a hold duration (int, numeric string or template) to milliseconds."""
def hold_ms_of(b: Binding, args: dict[str, object]) -> int {
    v = render(b.hold_ms, args);
    if isinstance(v, bool) {
        return 0;
    }
    if isinstance(v, (int, float)) {
        return max(0, int(v));
    }
    if isinstance(v, str) and v.strip() != "" {
        try {
            return max(0, int(float(v)));
        } except ValueError {
            return 0;
        }
    }
    return 0;
}

def _str_field(cfg: dict[str, object], key: str) -> str {
    v = cfg.get(key, "");
    return v if isinstance(v, str) else str(v);
}

def _decode(text: str, what: str, errors: list[str]) -> object {
    if text.strip() == "" {
        return None;
    }
    try {
        return json.loads(text);
    } except ValueError as e {
        errors.append(f"{what} is not valid JSON: {str(e)}");
        return None;
    }
}

"""Parse and validate bindings_json for a connector kind ("rosbridge" | "http")."""
def parse_bindings(text: str, kind: str, ros_version: str = "2") -> BindingTable {
    table = BindingTable();
    raw = _decode(text, "bindings", table.errors);
    if raw is None {
        raw = {};
    }
    if not isinstance(raw, dict) {
        table.errors.append("bindings must be a JSON object keyed by capability name");
        return table;
    }
    allowed = ROS_OPS if kind == "rosbridge" else HTTP_OPS;
    names = capability_names();
    pending_subs: dict[str, str] = {};

    for (key, item) in raw.items() {
        k = str(key);
        if k == "_namespace" {
            table.namespace = str(item).rstrip("/");
            continue;
        }
        if k == "_probe" {
            table.probe_path = str(item);
            continue;
        }
        if k not in names {
            table.errors.append(f"'{k}' is not a capability (expected one of {', '.join(names)})");
            continue;
        }
        if not isinstance(item, dict) {
            table.errors.append(f"{k}: binding must be a JSON object");
            continue;
        }
        cfg = item as dict[str, object];
        cap = capability_named(k);
        op = _str_field(cfg, "op");
        note = _str_field(cfg, "note");
        if op not in allowed and op not in META_OPS {
            table.errors.append(
                f"{k}: op '{op}' is not available for a {kind} robot (use one of {', '.join(allowed + META_OPS)})"
            );
            continue;
        }
        b = Binding(capability=cap, op=op, note=note, hold_ms=cfg.get("hold_ms", 0));
        if op == "publish" {
            b.target = _str_field(cfg, "topic");
            b.msg_type = _str_field(cfg, "type");
            b.template = cfg.get("msg", {});
            if b.target == "" or b.msg_type == "" {
                table.errors.append(f"{k}: publish needs 'topic' and 'type'");
                continue;
            }
        } elif op == "service" {
            b.target = _str_field(cfg, "service");
            b.msg_type = _str_field(cfg, "type");
            b.template = cfg.get("args", {});
            if b.target == "" {
                table.errors.append(f"{k}: service needs 'service'");
                continue;
            }
        } elif op == "action" {
            b.target = _str_field(cfg, "action");
            b.msg_type = _str_field(cfg, "type");
            b.template = cfg.get("goal", {});
            if b.target == "" or b.msg_type == "" {
                table.errors.append(f"{k}: action needs 'action' and 'type'");
                continue;
            }
            if ros_version == "1" {
                table.errors.append(
                    f"{k}: rosbridge actions need ROS 2; on ROS 1 publish to the action's /goal topic or use op 'intent'"
                );
                continue;
            }
        } elif op == "intent" {
            b.wait_result = bool(cfg.get("wait_result", True));
        } elif op == "http" {
            b.target = _str_field(cfg, "path");
            b.method = _str_field(cfg, "method").upper() or "POST";
            b.template = cfg.get("body", None);
            b.query = cfg.get("query", None);
            if b.target == "" {
                table.errors.append(f"{k}: http needs 'path'");
                continue;
            }
        } elif op == "substitute" {
            target = _str_field(cfg, "with");
            if target not in names or target == k {
                table.errors.append(f"{k}: substitute 'with' must name another capability");
                continue;
            }
            b.substitute = capability_named(target);
            b.template = cfg.get("args", None);
            pending_subs[k] = target;
        }
        table.bindings[k] = b;
    }

    for (k, target) in pending_subs.items() {
        tb = table.bindings.get(target, None);
        if tb is None or tb.op in META_OPS {
            table.errors.append(f"{k}: substitute target {target} has no executable binding");
            table.bindings.pop(k);
        }
    }

    if "IDLE" not in table.bindings {
        table.bindings["IDLE"] = Binding(capability=Capability.IDLE, op="noop",
                                         hold_ms="{hold_ms|0}", note="built-in hold");
    }

    for c in Capability {
        bound = table.bindings.get(c.name, None);
        if bound is None {
            table.specs.append(CapabilitySpec(capability=c, support=Support.UNAVAILABLE,
                                              note="no binding"));
        } elif bound.op == "unavailable" {
            table.specs.append(CapabilitySpec(capability=c, support=Support.UNAVAILABLE,
                                              note=bound.note));
        } elif bound.op == "substitute" {
            table.specs.append(CapabilitySpec(capability=c, support=Support.SUBSTITUTED,
                                              substitute=bound.substitute, note=bound.note));
        } else {
            table.specs.append(CapabilitySpec(capability=c, note=bound.note or bound.op));
        }
    }
    return table;
}

"""Parse and validate percepts_json."""
def parse_percepts(text: str, errors: list[str]) -> list[PerceptRule] {
    rules: list[PerceptRule] = [];
    raw = _decode(text, "percepts", errors);
    if raw is None {
        return rules;
    }
    if not isinstance(raw, list) {
        errors.append("percepts must be a JSON list of rules");
        return rules;
    }
    for (i, item) in enumerate(raw) {
        if not isinstance(item, dict) {
            errors.append(f"percept rule {i}: must be a JSON object");
            continue;
        }
        cfg = item as dict[str, object];
        rule = PerceptRule(
            topic=_str_field(cfg, "topic"),
            msg_type=_str_field(cfg, "type"),
            label=_str_field(cfg, "label"),
            label_from=_str_field(cfg, "label_from"),
            field=_str_field(cfg, "field"),
            has_equals="equals" in cfg,
            equals=cfg.get("equals", None)
        );
        if rule.topic == "" {
            errors.append(f"percept rule {i}: needs 'topic'");
            continue;
        }
        if rule.label == "" and rule.label_from == "" {
            errors.append(f"percept rule {i}: needs 'label' or 'label_from'");
            continue;
        }
        rules.append(rule);
    }
    return rules;
}
