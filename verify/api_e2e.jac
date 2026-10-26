"""End-to-end check of the served API, the way the web app and lab scripts use it.

Starts the mock rosbridge in-process and `jac start main.jac --no_client` as a
subprocess, then drives the REST surface over HTTP: sign up, register a ROS 2
robot, build the example study, run it on the simulator and on the "ROS"
robot, freeze the version, score Godspeed, export, withdraw.

    jac run verify/api_e2e.jac          # ~30 s, needs no robot and no ROS

Each run signs up a fresh researcher, so it never touches anyone else's data.
"""

import json;
import os;
import subprocess;
import sys;
import time;
import from urllib.request { Request, urlopen }
import from urllib.error { HTTPError, URLError }
import from adapters.bindings { as_dict }
import from tools.mock_rosbridge { start_mock }

glob PORT: int = int(os.environ.get("HANDSHAKE_E2E_PORT", "8791"));
glob MOCK_PORT: int = 9474;
glob BASE: str = f"http://127.0.0.1:{PORT}";
glob PASSED: int = 0;
glob TOKEN: str = "";

def ok(label: str, cond: bool) {
    global PASSED;
    if not cond {
        raise AssertionError(f"FAIL: {label}");
    }
    PASSED += 1;
    print(f"  ok  {label}");
}

def post(path: str, body: dict[str, object]) -> dict[str, object] {
    headers: dict[str, str] = {"Content-Type": "application/json"};
    if TOKEN != "" {
        headers["Authorization"] = f"Bearer {TOKEN}";
    }
    req = Request(BASE + path, data=json.dumps(body).encode("utf-8"), method="POST",
                  headers=headers);
    try {
        resp = urlopen(req, timeout=60);
        try {
            return as_dict(json.loads(str(resp.read().decode("utf-8"))));
        } finally {
            resp.close();
        }
    } except HTTPError as e {
        return {"ok": False, "status": e.code, "body": e.read().decode("utf-8", "replace")};
    }
}

"""Call a def:priv endpoint and return its result (fails loudly on an error envelope)."""
def fn(name: str, body: dict[str, object]) -> object {
    r = post(f"/function/{name}", body);
    if not bool(r.get("ok", False)) {
        raise AssertionError(f"{name} failed: {json.dumps(r)[:400]}");
    }
    return as_dict(r.get("data", None)).get("result", None);
}

"""The `jac` next to the running interpreter (a venv need not be activated)."""
def jac_executable -> str {
    beside = os.path.join(os.path.dirname(sys.executable), "jac");
    return beside if os.path.exists(beside) else "jac";
}

def wait_for_server(proc: subprocess.Popen) -> bool {
    deadline = time.monotonic() + 120;
    while time.monotonic() < deadline {
        if proc.poll() is not None {
            return False;
        }
        try {
            urlopen(BASE + "/healthz", timeout=2).close();
            return True;
        } except (URLError, ConnectionError, OSError) {
            time.sleep(1);
        }
    }
    return False;
}

with entry {
    mock = start_mock(MOCK_PORT);
    print(f"starting jac start main.jac on :{PORT} ...");
    # stdin must not be a terminal that closes: `jac start` exits when stdin does.
    proc = subprocess.Popen(
        [jac_executable(), "start", "main.jac", "--no_client", "--port", str(PORT)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT
    );
    try {
        ok("server starts", wait_for_server(proc));

        user = f"e2e-{int(time.time() * 1000)}";
        reg = post("/user/register", {
            "identities": [{"type": "username", "value": user}],
            "credential": {"type": "password", "password": "verify-e2e-pass"}
        });
        ok("researcher can sign up", bool(reg.get("ok", False)));
        login = post("/user/login", {
            "identity": {"type": "username", "value": user},
            "credential": {"type": "password", "password": "verify-e2e-pass"}
        });
        TOKEN = str(as_dict(login.get("data", None)).get("token", ""));
        ok("researcher can sign in", TOKEN != "");

        signed_in = TOKEN;
        TOKEN = "";
        anon = post("/function/list_robots", {});
        ok("endpoints refuse anonymous callers", not bool(anon.get("ok", True)));
        TOKEN = signed_in;

        robots = fn("list_robots", {});
        ok("a new researcher starts with the simulator",
           isinstance(robots, list) and len(robots) == 1);
        sim_id = str(as_dict(robots[0] if isinstance(robots, list) else None).get("id", ""));

        presets = fn("robot_presets", {});
        contract = [as_dict(p) for p in (presets if isinstance(presets, list) else [])
                    if as_dict(p).get("key", "") == "ros2-contract"][0];
        draft: dict[str, object] = {
            "id": "", "name": "Mock ROS 2 robot", "kind": "rosbridge",
            "url": f"ws://127.0.0.1:{MOCK_PORT}", "ros_version": "2",
            "bindings_json": contract.get("bindings_json", "{}"),
            "percepts_json": contract.get("percepts_json", "[]"), "notes": ""
        };
        probe = as_dict(fn("test_robot", {"draft": draft}));
        ok("connection test reaches the ROS robot", bool(probe.get("ok", False)));
        saved = as_dict(fn("save_robot", {"draft": draft}));
        ok("ROS robot profile saves", bool(saved.get("ok", False)));
        ros_id = str(saved.get("id", ""));
        bad = as_dict(fn("save_robot", {"draft": {**draft, "name": "bad", "url": "http://nope"}}));
        problems = bad.get("problems", []);
        ok("invalid profiles are rejected with reasons",
           not bool(bad.get("ok", True)) and isinstance(problems, list) and len(problems) > 0);

        study_id = str(as_dict(fn("create_example_study", {})).get("id", ""));
        detail = as_dict(fn("get_study", {"study_id": study_id}));
        conds = detail.get("conditions", []);
        ok("example study has two conditions", isinstance(conds, list) and len(conds) == 2);

        def run(robot_id: str, code: str, percepts: list[dict[str, str]]) -> dict[str, object] {
            return as_dict(fn("run_session", {"req": {
                "study_id": study_id, "condition_label": "near", "robot_id": robot_id,
                "participant_code": code, "consent_scope": "video", "percepts": percepts
            }}));
        }

        sim_run = run(sim_id, "E01", [{"step": "look", "percept": "gaze_reciprocated"}]);
        sim_sess = as_dict(sim_run.get("session", None));
        ok("session runs on the simulator", bool(sim_run.get("ok", False)) and sim_sess.get("status", "") == "complete");
        ok("simulator degrades APPROACH as a logged failure", sim_sess.get("capability_failures", 0) == 1);

        ros_run = run(ros_id, "E02", []);
        ros_sess = as_dict(ros_run.get("session", None));
        ok("same protocol runs on the ROS robot", bool(ros_run.get("ok", False)));
        ok("ROS percept drives the branch", ros_sess.get("n_percepts", 0) == 1);
        ok("ROS robot performs every capability", ros_sess.get("capability_failures", -1) == 0);

        sess = as_dict(fn("get_session", {"session_id": ros_sess.get("id", "")}));
        trail = sess.get("trail", []);
        approach = [as_dict(t) for t in (trail if isinstance(trail, list) else [])
                    if as_dict(t).get("label", "") == "approach"][0];
        deltas = approach.get("deltas", []);
        ok("commanded and achieved are both recorded",
           isinstance(deltas, list) and len(deltas) == 2);
        ok("the protocol snapshot is stored with the session",
           "approach" in str(sess.get("protocol_snapshot", "")));

        frozen = as_dict(fn("save_condition", {"study_id": study_id,
                                               "spec": as_dict(conds[0] if isinstance(conds, list) else None),
                                               "original_label": "near"}));
        ok("a version with sessions is frozen", not bool(frozen.get("ok", True)));

        bumped = as_dict(fn("start_new_version", {"study_id": study_id}));
        ok("one click starts the next version", bool(bumped.get("ok", False)) and bumped.get("version", "") == "0.1.1");
        near = as_dict(conds[0] if isinstance(conds, list) else None);
        steps = near.get("steps", []);
        edited_steps = [as_dict(st) for st in (steps if isinstance(steps, list) else [])];
        edited_steps[-1]["args_json"] = "{\"text\": \"version two\"}";
        edited = as_dict(fn("save_condition", {"study_id": study_id,
                                               "spec": {**near, "steps": edited_steps},
                                               "original_label": "near"}));
        ok("the new version is editable", bool(edited.get("ok", False)));
        v2 = as_dict(run(sim_id, "E03", []).get("session", None));
        ok("new sessions record the new version", v2.get("protocol_version", "") == "0.1.1");
        old_sess = as_dict(fn("get_session", {"session_id": sim_sess.get("id", "")}));
        ok("earlier sessions keep their version",
           as_dict(old_sess.get("summary", None)).get("protocol_version", "") == "0.1.0");
        again = as_dict(fn("start_new_version", {"study_id": study_id}));
        ok("versions keep counting up", again.get("version", "") == "0.1.2");

        scored = as_dict(fn("record_godspeed", {"session_id": ros_sess.get("id", ""),
                                                "responses": {"fake_natural": 4, "machine_human": 2}}));
        ok("Godspeed response is scored", scored.get("godspeed", -1) == 3.0);

        rows = fn("export_events", {"study_id": study_id});
        ok("export returns every event", isinstance(rows, list) and len(rows) > 30);

        owner_token = TOKEN;
        other = f"{user}-b";
        post("/user/register", {"identities": [{"type": "username", "value": other}],
                                "credential": {"type": "password", "password": "verify-e2e-pass"}});
        TOKEN = str(as_dict(post("/user/login", {
            "identity": {"type": "username", "value": other},
            "credential": {"type": "password", "password": "verify-e2e-pass"}
        }).get("data", None)).get("token", ""));
        ok("another researcher cannot open this study", fn("get_study", {"study_id": study_id}) is None);
        theirs = fn("list_sessions", {"study_id": ""});
        ok("another researcher sees none of these sessions", isinstance(theirs, list) and len(theirs) == 0);
        TOKEN = owner_token;

        removed = fn("withdraw_participant", {"code": "E02"});
        ok("withdrawal deletes the participant's sessions", removed == 1);
        left = fn("list_sessions", {"study_id": study_id});
        ok("withdrawn data is gone", isinstance(left, list) and len(left) == 2);
    } finally {
        proc.terminate();
        try {
            proc.wait(timeout=15);
        } except subprocess.TimeoutExpired {
            proc.kill();
        }
        mock.stop();
    }
    print(f"\n{PASSED} end-to-end assertions passed");
}
