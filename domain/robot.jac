"""Robot profiles: how a researcher's lab reaches a robot.

A profile is configuration, never behaviour. It names a connector kind and
holds the capability bindings that translate Handshake's behavioural
capabilities into whatever the robot already understands (ROS topics,
services, actions, or an HTTP API). Protocols never reference a profile;
sessions record which profile they ran on.

Connector kinds:
    sim        built-in simulated robot (no hardware, the CI target)
    rosbridge  any ROS 1 or ROS 2 system via rosbridge_suite's WebSocket,
               which also covers ROS-connected simulators (Gazebo, Webots,
               Isaac Sim, CoppeliaSim, ...)
    http       a robot that exposes its own REST API
    plugin     a custom RobotAdapter subclass living under adapters/

Bindings and percept rules are stored as JSON text so the schema can grow
without migrations; adapters/bindings.jac owns parsing and validation.
"""

glob CONNECTOR_KINDS: list[str] = ["sim", "rosbridge", "http", "plugin"];

node RobotProfile {
    has name: str,
        kind: str = "sim",
        url: str = "",
        ros_version: str = "2",
        bindings_json: str = "{}",
        percepts_json: str = "[]",
        notes: str = "",
        created_at: str = "",
        updated_at: str = "";
}
