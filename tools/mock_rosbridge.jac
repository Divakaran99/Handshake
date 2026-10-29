"""A stand-in for rosbridge_server plus a cooperative robot, with no ROS install.

Run it, then point a rosbridge robot profile at ws://localhost:9090:

    jac run tools/mock_rosbridge.jac            # port from MOCK_ROSBRIDGE_PORT, default 9090

It speaks enough of the rosbridge v2 protocol to exercise every code path in
adapters/rosbridge.jac:

    advertise / subscribe / publish      topics, fan-out to subscribers
    call_service                         /rosapi/topics, /rosapi/get_ros_version,
                                         /rosapi/subscribers, anything else -> success
    send_action_goal                     result after a short delay
                                         (action names containing "fail" abort)

and it behaves like a robot running the Handshake contract node: every intent
on */handshake/intent is answered on */handshake/result, and a GAZE intent
(or a publish on /hri/gaze_target) is reciprocated with a gaze percept when
`reciprocate` is on. Tests start it in-process with `start_mock(port)`.
"""

import json;
import logging;
import os;
import time;
import random;
import threading;
import from websockets.sync.server { serve, Server, ServerConnection }
import from websockets.exceptions { ConnectionClosed }
import from adapters.bindings { as_dict }

obj MockRosbridge {
    has port: int = 9090,
        reciprocate: bool = True,
        latency_s: float = 0.05,
        server: Server | None = None,
        published: list[dict[str, object]] = [],
        goals: list[dict[str, object]] = [],
        rng: random.Random = random.Random(11),
        lock: threading.Lock = threading.Lock();

    def topics -> list[str] {
        base = ["/rosout", "/parameter_events", "/hri/speak", "/hri/gaze_target",
                "/hri/gaze_on_robot", "/handshake/intent", "/handshake/result",
                "/handshake/percept"];
        return base;
    }

    def emit(conn: ServerConnection, subs: list[str], topic: str, msg: dict[str, object]) {
        if topic in subs {
            conn.send(json.dumps({"op": "publish", "topic": topic, "msg": msg}));
        }
    }

    def on_intent(conn: ServerConnection, subs: list[str], topic: str, data: str) {
        intent = as_dict(json.loads(data));
        ns = topic[: -len("/handshake/intent")];
        args = as_dict(intent.get("args", None));
        achieved: dict[str, object] = {};
        for (k, v) in args.items() {
            if isinstance(v, float) {
                fv = v as float;
                achieved[k] = int(fv * (1.0 - 0.15 * self.rng.random()) * 1000) / 1000.0;
            } else {
                achieved[k] = v;
            }
        }
        time.sleep(self.latency_s);
        if intent.get("executed_as", "") == "GAZE" and self.reciprocate {
            self.emit(conn, subs, f"{ns}/handshake/percept", {"data": "gaze_reciprocated"});
        }
        result = {"id": intent.get("id", ""), "ok": True, "achieved": achieved,
                  "detail": f"mock robot executed {intent.get('executed_as', '?')}"};
        self.emit(conn, subs, f"{ns}/handshake/result", {"data": json.dumps(result)});
    }

    def on_service(conn: ServerConnection, msg: dict[str, object]) {
        service = str(msg.get("service", ""));
        values: dict[str, object] = {"success": True};
        if service == "/rosapi/topics" {
            names = self.topics();
            values = {"topics": names, "types": ["std_msgs/msg/String" for _n in names]};
        } elif service == "/rosapi/get_ros_version" {
            values = {"version": 2, "distro": "mock"};
        } elif service == "/rosapi/subscribers" {
            values = {"subscribers": ["/handshake_node"]};
        }
        conn.send(json.dumps({"op": "service_response", "id": msg.get("id", ""),
                              "service": service, "values": values, "result": True}));
    }

    def on_goal(conn: ServerConnection, msg: dict[str, object]) {
        with self.lock {
            self.goals.append(msg);
        }
        time.sleep(self.latency_s);
        action = str(msg.get("action", ""));
        failed = "fail" in action;
        conn.send(json.dumps({
            "op": "action_result", "id": msg.get("id", ""), "action": action,
            "values": {"result": {}}, "status": 6 if failed else 4, "result": not failed
        }));
    }

    def handle(conn: ServerConnection) {
        subs: list[str] = [];
        try {
            for raw in conn {
                msg = as_dict(json.loads(raw));
                op = msg.get("op", "");
                if op == "subscribe" {
                    subs.append(str(msg.get("topic", "")));
                } elif op == "unsubscribe" {
                    t = str(msg.get("topic", ""));
                    subs = [s for s in subs if s != t];
                } elif op == "publish" {
                    topic = str(msg.get("topic", ""));
                    body = as_dict(msg.get("msg", None));
                    with self.lock {
                        self.published.append({"topic": topic, "msg": body});
                    }
                    self.emit(conn, subs, topic, body);
                    if topic.endswith("/handshake/intent") {
                        self.on_intent(conn, subs, topic, str(body.get("data", "{}")));
                    } elif topic == "/hri/gaze_target" and self.reciprocate {
                        time.sleep(self.latency_s);
                        self.emit(conn, subs, "/hri/gaze_on_robot", {"data": True});
                    }
                } elif op == "call_service" {
                    self.on_service(conn, msg);
                } elif op == "send_action_goal" {
                    self.on_goal(conn, msg);
                }
            }
        } except ConnectionClosed {}
    }

    def start -> MockRosbridge {
        logging.getLogger("websockets").setLevel("WARNING");
        self.server = serve(self.handle, "127.0.0.1", self.port);
        threading.Thread(target=self.server.serve_forever, daemon=True).start();
        return self;
    }

    def stop {
        if self.server is not None {
            self.server.shutdown();
            self.server = None;
        }
    }
}

def start_mock(port: int = 9090, reciprocate: bool = True) -> MockRosbridge {
    return MockRosbridge(port=port, reciprocate=reciprocate).start();
}

with entry:__main__ {
    port = int(os.environ.get("MOCK_ROSBRIDGE_PORT", "9090"));
    mock = start_mock(port);
    print(f"mock rosbridge listening on ws://localhost:{port}  (Ctrl+C to stop)");
    try {
        while True {
            time.sleep(1);
        }
    } except KeyboardInterrupt {
        mock.stop();
    }
}
