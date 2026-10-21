"""ROS 1 / ROS 2 adapter over rosbridge_suite's WebSocket protocol.

One adapter reaches every ROS system - a physical robot, Gazebo, Webots,
Isaac Sim, CoppeliaSim - as long as `rosbridge_server` is running on the ROS
side. Handshake never imports rclpy or rospy; it speaks rosbridge JSON
(https://github.com/RobotWebTools/rosbridge_suite, ROSBRIDGE_PROTOCOL.md).

The transport is deliberately single-threaded. Every read happens inside
`_pump`, which routes each incoming message:

    publish on a percept topic  -> percept rules -> self.percepts (timestamped)
    anything else               -> self.inbox, until a waiter claims it

Request/response pairs (service calls, action goals, Handshake intents) send
first, then pump until their reply id shows up. Percepts that arrive while
waiting are kept, so nothing the robot reports is lost between steps.

Interop boundary: `websockets.sync.client` is the only third-party API used,
and it is used directly so readers can see exactly what crosses the wire.
"""

import json;
import time;
import from websockets.sync.client { connect as ws_connect, ClientConnection }
import from domain.capability { Capability, CapabilityCall, CapabilityResult }
import from adapters.adapter { ProbeReport }
import from adapters.bindings { Binding, PerceptRule, render, as_dict }
import from adapters.bound { BoundAdapter, check_host, now_ms }

"""A percept label observed at a monotonic time."""
obj Percept {
    has label: str,
        t_ms: int,
        topic: str = "";
}

"""GoalStatus.STATUS_SUCCEEDED in action_msgs (ROS 2)."""
glob ACTION_SUCCEEDED: int = 4;

obj RosbridgeAdapter(BoundAdapter) {
    has url: str = "ws://localhost:9090",
        ros_version: str = "2",
        percept_rules: list[PerceptRule] = [],
        open_timeout_s: float = 4.0,
        ws: ClientConnection | None = None,
        seq: int = 0,
        inbox: list[dict[str, object]] = [],
        percepts: list[Percept] = [],
        advertised: list[str] = [],
        step_mark_ms: int = 0;

    # ---------------------------------------------------------- naming ----

    def string_type -> str {
        return "std_msgs/String" if self.ros_version == "1" else "std_msgs/msg/String";
    }

    def contract_topic(leaf: str) -> str {
        return f"{self.table.namespace}/handshake/{leaf}";
    }

    def next_id(prefix: str) -> str {
        self.seq += 1;
        return f"handshake:{prefix}:{self.seq}";
    }

    # ------------------------------------------------------- transport ----

    def send(msg: dict[str, object]) {
        if self.ws is None {
            raise ConnectionError("rosbridge connection is not open");
        }
        self.ws.send(json.dumps(msg));
    }

    """Read at most one message (waiting up to timeout_s) and route it."""
    def _pump(timeout_s: float) -> dict[str, object] | None {
        if self.ws is None {
            raise ConnectionError("rosbridge connection is not open");
        }
        try {
            raw = self.ws.recv(timeout=max(0.0, timeout_s));
        } except TimeoutError {
            return None;
        }
        msg = as_dict(json.loads(raw));
        if msg.get("op", "") == "publish" {
            topic = str(msg.get("topic", ""));
            fired = False;
            for rule in self.percept_rules {
                if rule.topic == topic {
                    label = rule.match(msg.get("msg", None));
                    if label != "" {
                        self.percepts.append(Percept(label=label, t_ms=now_ms(), topic=topic));
                        fired = True;
                    }
                }
            }
            if fired {
                return None;
            }
        }
        self.inbox.append(msg);
        return msg;
    }

    """Pump for `seconds`, keeping every message that arrives."""
    def drain(seconds: float) {
        deadline = time.monotonic() + seconds;
        while time.monotonic() < deadline {
            self._pump(deadline - time.monotonic());
        }
    }

    """True if `msg` answers request `rid` (service, action, status or intent result)."""
    def _answers(msg: dict[str, object], rid: str, intent: bool) -> bool {
        op = msg.get("op", "");
        if intent {
            if op != "publish" or msg.get("topic", "") != self.contract_topic("result") {
                return False;
            }
            body = as_dict(msg.get("msg", None)).get("data", "");
            try {
                return as_dict(json.loads(str(body))).get("id", "") == rid;
            } except ValueError {
                return False;
            }
        }
        if msg.get("id", "") != rid {
            return False;
        }
        if op == "status" {
            return msg.get("level", "") == "error";
        }
        return op in ["service_response", "action_result"];
    }

    """Wait for the reply to `rid`, checking messages that already arrived first."""
    def wait_reply(rid: str, timeout_s: float, intent: bool = False) -> dict[str, object] | None {
        for (i, m) in enumerate(self.inbox) {
            if self._answers(m, rid, intent) {
                self.inbox.pop(i);
                return m;
            }
        }
        deadline = time.monotonic() + timeout_s;
        while time.monotonic() < deadline {
            m = self._pump(deadline - time.monotonic());
            if m is not None and self._answers(m, rid, intent) {
                self.inbox.remove(m);
                return m;
            }
            if len(self.inbox) > 500 {
                self.inbox = self.inbox[-200:];
            }
        }
        return None;
    }

    def advertise(topic: str, msg_type: str) {
        if topic in self.advertised {
            return;
        }
        self.send({"op": "advertise", "topic": topic, "type": msg_type});
        self.advertised.append(topic);
    }

    """Call a ROS service and wait for its response (used by probe)."""
    def call_service(service: str, args: dict[str, object], timeout_s: float) -> dict[str, object] | None {
        rid = self.next_id("call");
        self.send({"op": "call_service", "id": rid, "service": service,
                   "args": args, "timeout": timeout_s});
        return self.wait_reply(rid, timeout_s + 0.5);
    }

    # ------------------------------------------------------- lifecycle ----

    override def connect {
        check_host(self.url);
        self.ws = ws_connect(self.url, open_timeout=self.open_timeout_s,
                             proxy=None, max_size=8 * 1024 * 1024);
        self.inbox = [];
        self.percepts = [];
        self.advertised = [];
        for rule in self.percept_rules {
            sub: dict[str, object] = {"op": "subscribe", "topic": rule.topic,
                                      "id": self.next_id("sub")};
            if rule.msg_type != "" {
                sub["type"] = rule.msg_type;
            }
            self.send(sub);
        }
        for b in self.table.bindings.values() {
            if b.op == "publish" {
                self.advertise(b.target, b.msg_type);
            }
        }
        if self.table.uses_op("intent") {
            self.advertise(self.contract_topic("intent"), self.string_type());
            self.send({"op": "subscribe", "topic": self.contract_topic("result"),
                       "type": self.string_type(), "id": self.next_id("sub")});
        }
        # ROS 2 discovery needs a moment before a new publisher is matched;
        # without this the first command of a session can be dropped.
        self.drain(0.3);
    }

    override def close {
        if self.ws is not None {
            try {
                self.ws.close();
            } except Exception {}
            self.ws = None;
        }
    }

    override def hold(ms: int) {
        if ms > 0 {
            self.drain(ms / 1000.0);
        }
    }

    override def await_percept(_step: str, expect: list[str], timeout_ms: int) -> str {
        deadline = time.monotonic() + timeout_ms / 1000.0;
        remaining = timeout_ms / 1000.0;
        while remaining > 0 {
            for p in self.percepts {
                if p.t_ms >= self.step_mark_ms and p.label in expect {
                    return p.label;
                }
            }
            self._pump(min(remaining, 0.25));
            remaining = deadline - time.monotonic();
        }
        for p in self.percepts {
            if p.t_ms >= self.step_mark_ms and p.label in expect {
                return p.label;
            }
        }
        return "";
    }

    # -------------------------------------------------------- dispatch ----

    override def execute(call: CapabilityCall) -> CapabilityResult {
        # Percepts only count if they arrive after the step's command went out.
        self.step_mark_ms = now_ms();
        return super.execute(call);
    }

    override def dispatch(b: Binding, args: dict[str, object], call: CapabilityCall) -> CapabilityResult {
        timeout_s = max(0.5, call.timeout_ms / 1000.0);
        res = CapabilityResult(ok=False, capability=call.capability);

        if b.op == "publish" {
            msg = render(b.template, args);
            self.advertise(b.target, b.msg_type);
            self.send({"op": "publish", "topic": b.target, "msg": msg});
            res.ok = True;
            res.wire = {"publish": b.target, "type": b.msg_type, "msg": msg};
            res.detail = "published (fire-and-forget)";
            return res;
        }

        if b.op == "service" {
            req = render(b.template, args);
            rid = self.next_id("call");
            wire: dict[str, object] = {"op": "call_service", "id": rid,
                                       "service": b.target, "args": req,
                                       "timeout": timeout_s};
            if b.msg_type != "" {
                wire["type"] = b.msg_type;
            }
            self.send(wire);
            res.wire = {"service": b.target, "type": b.msg_type, "args": req};
            reply = self.wait_reply(rid, timeout_s + 0.5);
            if reply is None {
                res.detail = f"no response from {b.target} within {call.timeout_ms} ms";
            } elif reply.get("op", "") == "status" {
                res.detail = str(reply.get("msg", "rosbridge error"));
            } else {
                res.ok = bool(reply.get("result", False));
                res.achieved = as_dict(reply.get("values", None));
                res.detail = "service ok" if res.ok else str(reply.get("values", "service failed"));
            }
            return res;
        }

        if b.op == "action" {
            goal = render(b.template, args);
            rid = self.next_id("goal");
            self.send({"op": "send_action_goal", "id": rid, "action": b.target,
                       "action_type": b.msg_type, "args": goal, "feedback": False});
            res.wire = {"action": b.target, "type": b.msg_type, "goal": goal};
            reply = self.wait_reply(rid, timeout_s);
            if reply is None {
                self.send({"op": "cancel_action_goal", "id": rid, "action": b.target});
                res.detail = f"goal not finished within {call.timeout_ms} ms; cancel requested";
            } elif reply.get("op", "") == "status" {
                res.detail = str(reply.get("msg", "rosbridge error"));
            } else {
                status = reply.get("status", as_dict(reply.get("values", None)).get("status", 0));
                res.ok = bool(reply.get("result", False)) and status == ACTION_SUCCEEDED;
                res.achieved = as_dict(reply.get("values", None));
                res.detail = f"action status {status}";
            }
            return res;
        }

        if b.op == "intent" {
            rid = self.next_id("intent");
            executed = self.resolve(call.capability);
            body = {
                "id": rid,
                "capability": call.capability.name,
                "executed_as": executed.name if executed is not None else call.capability.name,
                "args": args,
                "timeout_ms": call.timeout_ms
            };
            topic = self.contract_topic("intent");
            self.advertise(topic, self.string_type());
            self.send({"op": "publish", "topic": topic, "msg": {"data": json.dumps(body)}});
            res.wire = {"publish": topic, "intent": body};
            if not b.wait_result {
                res.ok = True;
                res.detail = "intent published (not waiting for result)";
                return res;
            }
            reply = self.wait_reply(rid, timeout_s, intent=True);
            if reply is None {
                res.detail = f"robot did not report a result within {call.timeout_ms} ms";
                return res;
            }
            result = as_dict(json.loads(str(as_dict(reply.get("msg", None)).get("data", "{}"))));
            res.ok = bool(result.get("ok", False));
            res.achieved = as_dict(result.get("achieved", None));
            res.detail = str(result.get("detail", "intent result"));
            return res;
        }

        res.detail = f"op '{b.op}' is not a ROS operation";
        return res;
    }

    # ----------------------------------------------------------- probe ----

    override def probe -> ProbeReport {
        report_ = ProbeReport(ok=False, profile=self.profile_name, kind="rosbridge",
                              capabilities=self.capability_summary());
        try {
            self.connect();
        } except Exception as e {
            report_.detail = f"could not open {self.url}: {type(e).__name__}: {str(e)}";
            return report_;
        }
        try {
            report_.ok = True;
            t0 = now_ms();
            topics_reply = self.call_service("/rosapi/topics", {}, 3.0);
            report_.latency_ms = now_ms() - t0;
            if topics_reply is None or not bool(topics_reply.get("result", False)) {
                report_.detail = f"connected to {self.url}";
                report_.warnings.append(
                    "rosapi did not answer - topic discovery skipped (launch rosbridge with rosapi enabled)"
                );
            } else {
                values = as_dict(topics_reply.get("values", None));
                names = values.get("topics", []);
                kinds = values.get("types", []);
                if isinstance(names, list) and isinstance(kinds, list) {
                    for (i, n) in enumerate(names) {
                        t = str(kinds[i]) if i < len(kinds) else "";
                        report_.topics.append(f"{n}  [{t}]" if t != "" else str(n));
                    }
                }
                plain = [str(n) for n in names] if isinstance(names, list) else [];
                report_.detail = f"connected to {self.url}; {len(plain)} topics visible";
                version = self.call_service("/rosapi/get_ros_version", {}, 2.0);
                if version is not None and bool(version.get("result", False)) {
                    v = as_dict(version.get("values", None));
                    report_.detail = report_.detail + f"; ROS {v.get('version', '?')} {v.get('distro', '')}".rstrip();
                }
                for rule in self.percept_rules {
                    if rule.topic not in plain {
                        report_.warnings.append(f"percept topic {rule.topic} has no publisher or subscriber yet");
                    }
                }
                if self.table.uses_op("intent") {
                    subs = self.call_service("/rosapi/subscribers",
                                             {"topic": self.contract_topic("intent")}, 2.0);
                    found = as_dict(subs.get("values", None) if subs is not None else None).get("subscribers", []);
                    if isinstance(found, list) and len(found) == 0 {
                        report_.warnings.append(
                            f"nothing subscribes to {self.contract_topic('intent')} - is the robot-side Handshake node running?"
                        );
                    }
                }
            }
        } except Exception as e {
            report_.ok = False;
            report_.detail = f"connected but probing failed: {type(e).__name__}: {str(e)}";
        } finally {
            self.close();
        }
        return report_;
    }
}
