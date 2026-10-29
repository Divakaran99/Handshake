#!/usr/bin/env bash
# Start Handshake, and optionally the ROS side, with one command. Ctrl+C stops everything.
#
#   bash scripts/start_lab.sh                  # web app + built-in simulator
#   bash scripts/start_lab.sh --mock           # + mock rosbridge on :9090 (no ROS needed)
#   bash scripts/start_lab.sh --ros --demo     # + rosbridge + contract node (log-only, always succeeds)
#   bash scripts/start_lab.sh --ros            # + rosbridge + contract node with your handlers
#   bash scripts/start_lab.sh --ros --no-node  # + rosbridge only (the node runs on the robot)
#
# Options: --port 8000 (web app), --ros-distro jazzy, --namespace /robot1 (contract node)
# Logs of the background processes go to .jac/logs/.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="sim"
DEMO=0
NODE=1
PORT=8000
DISTRO=""
NS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mock) MODE="mock" ;;
    --ros) MODE="ros" ;;
    --demo) DEMO=1 ;;
    --no-node) NODE=0 ;;
    --port) PORT="${2:?}"; shift ;;
    --ros-distro) DISTRO="${2:?}"; shift ;;
    --namespace) NS="${2:?}"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

JAC="jac"
[ -x .venv/bin/jac ] && JAC=".venv/bin/jac"
command -v "$JAC" >/dev/null 2>&1 || { echo "jac not found - run: bash scripts/setup_ubuntu.sh" >&2; exit 1; }
mkdir -p .jac/logs

PIDS=()
cleanup() {
  trap - INT TERM EXIT
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup INT TERM EXIT

wait_for_port() {  # host port seconds
  for _ in $(seq 1 "$3"); do
    (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

if [ "$MODE" = "mock" ]; then
  if port_busy 9090; then
    echo "port 9090 is already in use (a rosbridge or mock is running) - using it"
  else
    "$JAC" run tools/mock_rosbridge.jac > .jac/logs/mock_rosbridge.log 2>&1 &
    PIDS+=($!)
    wait_for_port 127.0.0.1 9090 30 || { echo "mock rosbridge did not start; see .jac/logs/mock_rosbridge.log" >&2; exit 1; }
    echo "mock rosbridge  ws://localhost:9090   (it also plays the robot-side contract node)"
  fi
fi

if [ "$MODE" = "ros" ]; then
  if [ -z "$DISTRO" ]; then
    DISTRO="${ROS_DISTRO:-}"
    if [ -z "$DISTRO" ]; then
      for d in /opt/ros/*/setup.bash; do
        [ -f "$d" ] && DISTRO="$(basename "$(dirname "$d")")"
      done
    fi
  fi
  SETUP="/opt/ros/$DISTRO/setup.bash"
  [ -n "$DISTRO" ] && [ -f "$SETUP" ] || { echo "ROS 2 not found in /opt/ros - run: bash scripts/setup_ubuntu.sh --with-ros" >&2; exit 1; }
  [ -d "/opt/ros/$DISTRO/share/rosbridge_server" ] || { echo "rosbridge missing - sudo apt install ros-$DISTRO-rosbridge-suite" >&2; exit 1; }

  if port_busy 9090; then
    echo "port 9090 is already in use - assuming rosbridge is already running"
  else
    # ROS setup scripts read unset variables, so `set -u` is relaxed inside the subshell.
    # shellcheck source=/dev/null
    ( set +u; source "$SETUP"; exec ros2 launch rosbridge_server rosbridge_websocket_launch.xml ) \
      > .jac/logs/rosbridge.log 2>&1 &
    PIDS+=($!)
    wait_for_port 127.0.0.1 9090 45 || { echo "rosbridge did not start; see .jac/logs/rosbridge.log" >&2; exit 1; }
    echo "rosbridge       ws://localhost:9090   (ROS 2 $DISTRO)"
  fi

  if [ "$NODE" -eq 1 ]; then
    NODE_ARGS=(--ros-args -p "demo:=$([ "$DEMO" -eq 1 ] && echo true || echo false)")
    [ -n "$NS" ] && NODE_ARGS+=(-r "__ns:=$NS")
    # The node uses the system Python that ROS was built for, not .venv.
    # shellcheck source=/dev/null
    ( set +u; source "$SETUP"; exec /usr/bin/python3 ros/handshake_node.py "${NODE_ARGS[@]}" ) \
      > .jac/logs/handshake_node.log 2>&1 &
    PIDS+=($!)
    sleep 2
    kill -0 "${PIDS[-1]}" 2>/dev/null || { echo "contract node exited; see .jac/logs/handshake_node.log" >&2; exit 1; }
    echo "contract node   $([ "$DEMO" -eq 1 ] && echo 'demo mode (log-only)' || echo 'live handlers')${NS:+, namespace $NS}"
  fi
fi

echo "web app         http://localhost:$PORT   (Ctrl+C stops everything)"
echo
"$JAC" start main.jac --port "$PORT"
