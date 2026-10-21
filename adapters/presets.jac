"""Starting points for robot profiles.

Each preset is a complete, valid profile a researcher can save as-is and then
edit. Presets are suggestions, not drivers: topic names, message types and
API paths must be checked against the actual robot (the "Test connection"
button lists what the ROS graph really offers).
"""

import json;

obj RobotPreset {
    has key: str,
        title: str,
        kind: str,
        summary: str,
        url: str = "",
        ros_version: str = "2",
        bindings_json: str = "{}",
        percepts_json: str = "[]";
}

def _pretty(value: object) -> str {
    return json.dumps(value, indent=2);
}

def _contract_bindings -> dict[str, object] {
    out: dict[str, object] = {};
    for cap in ["SPEAK", "GAZE", "GESTURE", "APPROACH", "ORIENT", "EXPRESS", "DISPLAY"] {
        out[cap] = {"op": "intent", "wait_result": True};
    }
    return out;
}

def _contract_percepts(ros_version: str) -> list[object] {
    t = "std_msgs/String" if ros_version == "1" else "std_msgs/msg/String";
    return [{"label_from": "data", "topic": "/handshake/percept", "type": t}];
}

def robot_presets -> list[RobotPreset] {
    return [
        RobotPreset(
            key="sim",
            title="Built-in simulator",
            kind="sim",
            summary="No hardware. Declares APPROACH unavailable and renders EXPRESS on its screen, so degradation paths are exercised. Use it to dry-run every protocol."
        ),
        RobotPreset(
            key="ros2-contract",
            title="ROS 2 robot - Handshake contract",
            kind="rosbridge",
            url="ws://localhost:9090",
            ros_version="2",
            summary="Recommended for real robots and simulators. Handshake publishes each step as a JSON intent on /handshake/intent; a small node on the robot (ros/handshake_node.py) carries it out with the robot's own stack and answers on /handshake/result and /handshake/percept.",
            bindings_json=_pretty(_contract_bindings()),
            percepts_json=_pretty(_contract_percepts("2"))
        ),
        RobotPreset(
            key="ros2-topics",
            title="ROS 2 - direct topics (no robot-side code)",
            kind="rosbridge",
            url="ws://localhost:9090",
            ros_version="2",
            summary="Maps capabilities straight onto existing std_msgs/String topics. Nothing to install on the robot besides rosbridge; rename the topics to the ones your robot already listens to.",
            bindings_json=_pretty({
                "SPEAK": {"op": "publish", "topic": "/hri/speak", "type": "std_msgs/msg/String",
                          "msg": {"data": "{text}"}, "hold_ms": "{hold_ms|2000}"},
                "GAZE": {"op": "publish", "topic": "/hri/gaze_target", "type": "std_msgs/msg/String",
                         "msg": {"data": "{target}"}, "hold_ms": "{hold_ms|0}"},
                "GESTURE": {"op": "publish", "topic": "/hri/gesture", "type": "std_msgs/msg/String",
                            "msg": {"data": "{name}"}, "hold_ms": "{hold_ms|1500}"},
                "EXPRESS": {"op": "publish", "topic": "/hri/expression", "type": "std_msgs/msg/String",
                            "msg": {"data": "{affect}"}},
                "DISPLAY": {"op": "publish", "topic": "/hri/display", "type": "std_msgs/msg/String",
                            "msg": {"data": "{media}"}},
                "APPROACH": {"op": "unavailable",
                             "note": "bind to your navigation stack, or use the Handshake contract"},
                "ORIENT": {"op": "unavailable", "note": "no orientation interface configured"}
            }),
            percepts_json=_pretty([
                {"label": "gaze_reciprocated", "topic": "/hri/gaze_on_robot",
                 "type": "std_msgs/msg/Bool", "field": "data", "equals": True}
            ])
        ),
        RobotPreset(
            key="ros2-nav2",
            title="Mobile robot with Nav2 (Gazebo, Isaac Sim, Webots, real base)",
            kind="rosbridge",
            url="ws://localhost:9090",
            ros_version="2",
            summary="APPROACH sends a Nav2 NavigateToPose goal and ORIENT a Nav2 Spin goal; Nav2 plans, avoids obstacles and stops. Nav2 needs a pose, so APPROACH steps must carry x and y (metres, map frame) - there is deliberately no default.",
            bindings_json=_pretty({
                "APPROACH": {
                    "op": "action",
                    "action": "/navigate_to_pose",
                    "type": "nav2_msgs/action/NavigateToPose",
                    "goal": {"pose": {"header": {"frame_id": "{frame|map}"},
                                      "pose": {"position": {"x": "{x}", "y": "{y}", "z": 0.0},
                                               "orientation": {"z": "{qz|0.0}", "w": "{qw|1.0}"}}}}
                },
                "ORIENT": {"op": "action", "action": "/spin", "type": "nav2_msgs/action/Spin",
                           "goal": {"target_yaw": "{yaw}"}},
                "SPEAK": {"op": "publish", "topic": "/hri/speak", "type": "std_msgs/msg/String",
                          "msg": {"data": "{text}"}, "hold_ms": "{hold_ms|2000}"},
                "GAZE": {"op": "unavailable", "note": "no head"},
                "EXPRESS": {"op": "unavailable", "note": "no face"}
            }),
            percepts_json="[]"
        ),
        RobotPreset(
            key="ros1-contract",
            title="ROS 1 (Noetic) robot - Handshake contract",
            kind="rosbridge",
            url="ws://localhost:9090",
            ros_version="1",
            summary="Same contract as the ROS 2 preset over rosbridge for ROS 1. Rosbridge actions are ROS 2 only, so on ROS 1 everything goes through intents.",
            bindings_json=_pretty(_contract_bindings()),
            percepts_json=_pretty(_contract_percepts("1"))
        ),
        RobotPreset(
            key="http",
            title="Robot with a REST API",
            kind="http",
            url="http://192.168.1.50:8080",
            summary="For robots that expose HTTP endpoints. The paths below are placeholders - replace them with your robot's documented API. HTTP robots have no percept channel, so percept branches take their timeout path.",
            bindings_json=_pretty({
                "SPEAK": {"op": "http", "method": "POST", "path": "/api/speak",
                          "body": {"text": "{text}"}},
                "GESTURE": {"op": "http", "method": "POST", "path": "/api/gesture",
                            "body": {"name": "{name}"}},
                "DISPLAY": {"op": "http", "method": "POST", "path": "/api/display",
                            "body": {"media": "{media}"}},
                "EXPRESS": {"op": "substitute", "with": "DISPLAY",
                            "args": {"media": "faces/{affect}.png"}},
                "_probe": "/api/health"
            })
        ),
        RobotPreset(
            key="plugin",
            title="Custom adapter (Python/Jac class)",
            kind="plugin",
            url="adapters.sim:SimAdapter",
            summary="For vendor SDKs (NAOqi, proprietary APIs): subclass RobotAdapter in a module under adapters/ and give its path as module:Class. The bindings field is passed to the adapter's configure(config) method if it has one."
        )
    ];
}
