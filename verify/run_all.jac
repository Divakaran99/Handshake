"""Assertion suite.

`jac test` is unreliable in some 0.16.7 environments (bytecode-cache error), so
the suite is a plain runnable module. CI runs `jac check` on every module and
then executes this file. It needs no robot and no ROS install: the rosbridge
sections run against tools/mock_rosbridge.jac, started in-process.

    jac run verify/run_all.jac
"""

import json;
import from domain.capability { Capability, CapabilitySpec, CapabilityCall, Support }
import from domain.protocol { StudyProtocol, Condition, HasCondition }
import from domain.session { Session, Event, Logged, EventKind }
import from domain.robot { RobotProfile }
import from adapters.sim { SimAdapter }
import from adapters.bindings { parse_bindings, parse_percepts, render, TemplateError }
import from adapters.registry { make_adapter, validate_profile, ProfileError }
import from adapters.presets { robot_presets }
import from adapters.rosbridge { RosbridgeAdapter }
import from runtime.session_runtime { run_condition }
import from instruments.godspeed { GODSPEED_ANTHROPOMORPHISM }
import from api.views { ConditionSpec, StepSpec, BranchSpec }
import from api.protocol_io { validate_condition, write_condition, condition_spec, condition_steps }
import from tools.mock_rosbridge { start_mock }

glob PASSED: int = 0;
glob MOCK_PORT: int = 9473;

def ok(label: str, cond: bool) {
    global PASSED;
    if not cond {
        raise AssertionError(f"FAIL: {label}");
    }
    PASSED += 1;
    print(f"  ok  {label}");
}

def section(title: str) {
    print(f"\n{title}");
}

def preset(key: str) -> RobotProfile {
    for p in robot_presets() {
        if p.key == key {
            return RobotProfile(name=p.key, kind=p.kind, url=f"ws://127.0.0.1:{MOCK_PORT}",
                                ros_version=p.ros_version, bindings_json=p.bindings_json,
                                percepts_json=p.percepts_json);
        }
    }
    raise KeyError(key);
}

def greeting_spec(label: str) -> ConditionSpec {
    return ConditionSpec(label=label, factors_json="{\"stop_distance_m\": 0.8}", steps=[
        StepSpec(label="greet", capability="SPEAK", args_json="{\"text\": \"hi\"}"),
        StepSpec(label="look", capability="GAZE", args_json="{\"target\": \"face\"}",
                 timeout_ms=600, next="neutral",
                 branches=[BranchSpec(percept="gaze_reciprocated", target="warm")]),
        StepSpec(label="warm", capability="EXPRESS", args_json="{\"affect\": \"friendly\"}",
                 next="bye"),
        StepSpec(label="neutral", capability="IDLE", args_json="{}"),
        StepSpec(label="bye", capability="SPEAK", args_json="{\"text\": \"bye\"}")
    ]);
}

def labels_of(s: Session, kind: EventKind) -> list[str] {
    return [e.label for e in [s ->:Logged:->] if e.kind == kind];
}

with entry {
    section("simulator");
    a = SimAdapter();
    ok("sim supports SPEAK natively", a.supports(Capability.SPEAK));
    ok("sim reports APPROACH unsupported", not a.supports(Capability.APPROACH));
    ok("EXPRESS degrades to DISPLAY",
       a.resolve(Capability.EXPRESS) == Capability.DISPLAY);
    ok("unavailable capability resolves to None",
       a.resolve(Capability.APPROACH) is None);
    r_bad = a.execute(CapabilityCall(capability=Capability.APPROACH, args={}));
    ok("unavailable capability returns ok=False", not r_bad.ok);
    r_ok = a.execute(CapabilityCall(capability=Capability.GAZE, args={"hold_s": 1.8}));
    ok("available capability returns ok=True", r_ok.ok);
    ok("commanded is recorded", r_ok.commanded["hold_s"] == 1.8);
    ok("achieved differs from commanded (telemetry evidence)",
       r_ok.achieved["hold_s"] != r_ok.commanded["hold_s"]);
    ok("raw passthrough is recorded", a.raw("custom_cmd", {"x": 1}).ok);

    section("instruments");
    s = GODSPEED_ANTHROPOMORPHISM;
    ok("godspeed has 5 items", len(s.items) == 5);
    ok("godspeed scores midpoint",
       s.score({"fake_natural": 3, "machine_human": 3, "uncons_conscious": 3,
                "artif_lifelike": 3, "rigid_elegant": 3}) == 3.0);
    ok("godspeed ignores missing items",
       s.score({"fake_natural": 5, "machine_human": 5}) == 5.0);

    section("bindings and templates");
    ok("whole-string placeholder keeps the JSON type",
       render({"x": "{d}"}, {"d": 0.8}) == {"x": 0.8});
    ok("default is parsed as JSON", render("{v|0.4}", {}) == 0.4);
    ok("placeholders interpolate inside text",
       render("faces/{affect}.png", {"affect": "happy"}) == "faces/happy.png");
    try {
        render("{missing}", {});
        ok("missing argument raises", False);
    } except TemplateError as e {
        ok("missing argument raises TemplateError", e.missing == "missing");
    }
    t = parse_bindings("{\"SPEAK\": {\"op\": \"publish\", \"topic\": \"/s\", \"type\": \"std_msgs/msg/String\"}, \"EXPRESS\": {\"op\": \"substitute\", \"with\": \"SPEAK\"}}", "rosbridge");
    ok("valid bindings parse cleanly", len(t.errors) == 0);
    ok("unbound capability is UNAVAILABLE",
       [sp.support for sp in t.specs if sp.capability == Capability.GAZE][0] == Support.UNAVAILABLE);
    ok("substitute is SUBSTITUTED",
       [sp.support for sp in t.specs if sp.capability == Capability.EXPRESS][0] == Support.SUBSTITUTED);
    ok("IDLE is always available",
       [sp.support for sp in t.specs if sp.capability == Capability.IDLE][0] == Support.NATIVE);
    ok("http op is rejected on a ROS robot",
       len(parse_bindings("{\"SPEAK\": {\"op\": \"http\", \"path\": \"/x\"}}", "rosbridge").errors) == 1);
    ok("actions are rejected on ROS 1",
       len(parse_bindings("{\"APPROACH\": {\"op\": \"action\", \"action\": \"/a\", \"type\": \"t/action/T\"}}", "rosbridge", "1").errors) == 1);
    perrs: list[str] = [];
    ok("percept rule needs a label", len(parse_percepts("[{\"topic\": \"/x\"}]", perrs)) == 0 and len(perrs) == 1);

    section("registry");
    for p in robot_presets() {
        prof = RobotProfile(name=p.key, kind=p.kind,
                            url=p.url if p.kind != "rosbridge" else "ws://localhost:9090",
                            ros_version=p.ros_version, bindings_json=p.bindings_json,
                            percepts_json=p.percepts_json);
        ok(f"preset '{p.key}' is a valid profile", len(validate_profile(prof)) == 0);
    }
    ok("plugin preset loads a RobotAdapter",
       make_adapter(RobotProfile(name="plug", kind="plugin", url="adapters.sim:SimAdapter")).supports(Capability.SPEAK));
    try {
        make_adapter(RobotProfile(name="x", kind="plugin", url="os:system"));
        ok("plugins outside adapters/ are refused", False);
    } except ProfileError {
        ok("plugins outside adapters/ are refused", True);
    }

    section("protocol editor round trip");
    study = (root ++> StudyProtocol(title="verify", version="0.0.1"))[0];
    cond = (study +>: HasCondition() :+> Condition(label="near"))[0];
    spec = greeting_spec("near");
    ok("editor spec validates", len(validate_condition(spec)) == 0);
    write_condition(cond, spec);
    back = condition_spec(cond);
    ok("step order survives the graph", [st.label for st in back.steps] == ["greet", "look", "warm", "neutral", "bye"]);
    ok("percept branch survives the graph",
       back.steps[1].branches[0].percept == "gaze_reciprocated" and back.steps[1].branches[0].target == "warm");
    ok("timeout fallback survives the graph", back.steps[1].next == "neutral");
    broken = ConditionSpec(label="x", steps=[StepSpec(label="a", capability="FLY", next="nowhere", args_json="[1]")]);
    ok("invalid specs are rejected with reasons", len(validate_condition(broken)) == 3);

    section("sessions on the simulator");
    sim_sess = (root ++> Session(code="V-sim", protocol_title="verify", protocol_version="0.0.1",
                                 condition_label="near", robot_profile="sim"))[0];
    run_condition(cond, SimAdapter(), sim_sess, {"look": "gaze_reciprocated"});
    ok("scripted percept takes the branch", "warm" in labels_of(sim_sess, EventKind.STEP_ENTER));
    sim_sess2 = (root ++> Session(code="V-sim2", protocol_title="verify", protocol_version="0.0.1",
                                  condition_label="near", robot_profile="sim"))[0];
    run_condition(cond, SimAdapter(), sim_sess2, {});
    entered = labels_of(sim_sess2, EventKind.STEP_ENTER);
    ok("no percept takes the timeout path, once", entered == ["greet", "look", "neutral", "bye"]);

    section("rosbridge (mock server)");
    mock = start_mock(MOCK_PORT);
    try {
        contract = make_adapter(preset("ros2-contract"));
        report_ = contract.probe();
        ok("probe connects and lists topics", report_.ok and len(report_.topics) > 0);
        ok("probe finds no warnings on a healthy robot", len(report_.warnings) == 0);

        ros_sess = (root ++> Session(code="V-ros", protocol_title="verify", protocol_version="0.0.1",
                                     condition_label="near", robot_profile="mock"))[0];
        run_condition(cond, contract, ros_sess, {});
        ok("real percept from ROS takes the branch", "warm" in labels_of(ros_sess, EventKind.STEP_ENTER));
        ok("percept is logged from perception", "gaze_reciprocated" in labels_of(ros_sess, EventKind.PERCEPT));
        results = [e.payload for e in [ros_sess ->:Logged:->] if e.kind == EventKind.CAPABILITY_RESULT];
        ok("every intent was acknowledged by the robot", all([bool(p.get("ok", False)) for p in results]));
        ok("the wire payload is recorded", all([bool(p.get("wire", None)) for p in results]));
        ok("session completes and disconnects", ros_sess.status == "complete" and isinstance(contract, RosbridgeAdapter));

        mock.reciprocate = False;
        quiet = (root ++> Session(code="V-ros2", protocol_title="verify", protocol_version="0.0.1",
                                  condition_label="near", robot_profile="mock"))[0];
        run_condition(cond, make_adapter(preset("ros2-contract")), quiet, {});
        ok("no ROS percept within timeout takes the fallback", "neutral" in labels_of(quiet, EventKind.STEP_ENTER));
        mock.reciprocate = True;

        topics = make_adapter(preset("ros2-topics"));
        topics.connect();
        r = topics.execute(CapabilityCall(capability=Capability.GAZE, args={"target": "face", "hold_ms": 300}));
        got = topics.await_percept("look", ["gaze_reciprocated"], 1000);
        topics.close();
        ok("direct topic publish succeeds", r.ok and r.wire.get("publish", "") == "/hri/gaze_target");
        ok("Bool percept rule fires", got == "gaze_reciprocated");

        nav = make_adapter(preset("ros2-nav2"));
        nav.connect();
        missing = nav.execute(CapabilityCall(capability=Capability.APPROACH, args={"stop_distance_m": 1.0}));
        goal = nav.execute(CapabilityCall(capability=Capability.APPROACH, args={"x": 1.5, "y": -0.5}));
        nav.close();
        ok("Nav2 goal without a pose is refused, not defaulted", not missing.ok and "x" in missing.detail);
        ok("Nav2 action goal succeeds", goal.ok);
        ok("goal carries the pose", json.dumps(goal.wire).count("1.5") == 1);
    } finally {
        mock.stop();
    }

    offline = make_adapter(RobotProfile(name="off", kind="rosbridge", url="ws://127.0.0.1:9",
                                        bindings_json="{}", percepts_json="[]"));
    ok("unreachable robot probes as not ok", not offline.probe().ok);
    failed = (root ++> Session(code="V-off", protocol_title="verify", protocol_version="0.0.1",
                               condition_label="near", robot_profile="off"))[0];
    try {
        run_condition(cond, offline, failed, {});
        ok("unreachable robot raises", False);
    } except ConnectionError {
        ok("unreachable robot fails the session instead of hanging", failed.status == "failed");
    }

    print(f"\n{PASSED} assertions passed");
}
