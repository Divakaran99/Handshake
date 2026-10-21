# Robot side

`handshake_node.py` is the robot-side half of the Handshake ROS contract
(ROS 2, rclpy). It receives intents on `handshake/intent`, runs your
`do_<capability>` handlers, and answers on `handshake/result`; your perception
code publishes labels on `handshake/percept`.

```bash
ros2 launch rosbridge_server rosbridge_websocket_launch.xml
python3 handshake_node.py --ros-args -p demo:=true   # prove the link first
python3 handshake_node.py                            # then with your handlers
```

In Handshake, add the robot with the *ROS 2 robot — Handshake contract* preset.
Full details: [docs/BUILD_GUIDE.md](../docs/BUILD_GUIDE.md#connecting-robots).
