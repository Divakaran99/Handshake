#!/usr/bin/env python3
"""Robot-side half of the Handshake ROS contract (ROS 2, rclpy).

Handshake never commands motors. It publishes *intents* - "SPEAK this text",
"APPROACH to 0.8 m" - and this node turns each one into whatever your robot's
own stack does (TTS service, Nav2 goal, head controller, face display...).
Fill in the do_<capability> methods; everything else is plumbing.

Contract (all std_msgs/String carrying JSON, relative to the node namespace):

    handshake/intent   Handshake -> robot
        {"id": "...", "capability": "EXPRESS", "executed_as": "DISPLAY",
         "args": {...}, "timeout_ms": 8000}
    handshake/result   robot -> Handshake, exactly one per intent
        {"id": "...", "ok": true, "achieved": {...}, "detail": "..."}
    handshake/percept  robot -> Handshake, whenever something is perceived
        "gaze_reciprocated"   (the bare label; data field of the String)

`achieved` is the evidence Handshake stores next to what was commanded - put
measured values there (actual stop distance, actual speech duration...).

Run (with rosbridge already up: ros2 launch rosbridge_server rosbridge_websocket_launch.xml):

    python3 handshake_node.py                          # real handlers (edit below)
    python3 handshake_node.py --ros-args -p demo:=true  # log-only, always succeeds,
                                                       # reciprocates gaze - for testing the link
    python3 handshake_node.py --ros-args -r __ns:=/robot1   # match "_namespace" in the profile

ROS 1: the same contract works over rosbridge for Noetic; port this file to
rospy (Publisher/Subscriber with std_msgs/String) - the JSON is identical.
"""

import json
import threading
import time

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class HandshakeNode(Node):
    def __init__(self):
        super().__init__("handshake_node")
        self.declare_parameter("demo", False)
        self.demo = bool(self.get_parameter("demo").value)
        self.results = self.create_publisher(String, "handshake/result", 10)
        self.percepts = self.create_publisher(String, "handshake/percept", 10)
        self.create_subscription(String, "handshake/intent", self.on_intent, 10)
        mode = "DEMO (log only)" if self.demo else "live"
        self.get_logger().info(f"Handshake contract node ready [{mode}]")

    # ------------------------------------------------------------ plumbing

    def on_intent(self, msg: String) -> None:
        try:
            intent = json.loads(msg.data)
        except ValueError:
            self.get_logger().warning(f"ignoring malformed intent: {msg.data[:80]}")
            return
        # Work happens off the executor thread so percepts keep flowing while
        # a long behaviour (speech, navigation) is running.
        threading.Thread(target=self.run_intent, args=(intent,), daemon=True).start()

    def run_intent(self, intent: dict) -> None:
        capability = intent.get("executed_as") or intent.get("capability", "")
        args = intent.get("args", {}) or {}
        handler = getattr(self, "do_" + capability.lower(), None)
        self.get_logger().info(f"{capability} {json.dumps(args)}")
        if handler is None:
            ok, achieved, detail = False, {}, f"no handler for {capability}"
        else:
            try:
                ok, achieved, detail = handler(args)
            except Exception as exc:  # report, never crash the node mid-session
                ok, achieved, detail = False, {}, f"{type(exc).__name__}: {exc}"
        out = String()
        out.data = json.dumps({"id": intent.get("id", ""), "ok": bool(ok),
                               "achieved": achieved, "detail": detail})
        self.results.publish(out)

    def percept(self, label: str) -> None:
        """Call this from your perception code (or a callback) when something is observed."""
        out = String()
        out.data = label
        self.percepts.publish(out)

    def not_implemented(self, name: str, args: dict):
        if self.demo:
            return True, dict(args), f"demo: {name} logged, not executed"
        return False, {}, f"{name} is not implemented on this robot - edit do_{name.lower()}"

    # ------------------------------------------------- fill these in -----
    # Each returns (ok, achieved, detail). Block until the behaviour is done.

    def do_speak(self, args: dict):
        # e.g. call your TTS service with args["text"] and measure duration.
        return self.not_implemented("SPEAK", args)

    def do_gaze(self, args: dict):
        # e.g. send a head/pan-tilt goal toward args["target"]; hold args["hold_ms"].
        result = self.not_implemented("GAZE", args)
        if self.demo:
            time.sleep(0.2)
            self.percept("gaze_reciprocated")
        return result

    def do_gesture(self, args: dict):
        return self.not_implemented("GESTURE", args)

    def do_approach(self, args: dict):
        # Behavioural intent only: compute a goal that stops args["stop_distance_m"]
        # from the person and hand it to your navigation stack (e.g. a Nav2
        # NavigateToPose action client). Report the distance you actually reached.
        return self.not_implemented("APPROACH", args)

    def do_orient(self, args: dict):
        return self.not_implemented("ORIENT", args)

    def do_express(self, args: dict):
        return self.not_implemented("EXPRESS", args)

    def do_display(self, args: dict):
        return self.not_implemented("DISPLAY", args)

    def do_idle(self, args: dict):
        time.sleep(float(args.get("hold_ms", 0)) / 1000.0)
        return True, {}, "held"


def main() -> None:
    rclpy.init()
    node = HandshakeNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
