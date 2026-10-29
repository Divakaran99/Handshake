#!/usr/bin/env bash
# Set up Handshake on Ubuntu 24.04 (recommended) or 22.04.
#
#   bash scripts/setup_ubuntu.sh              # Handshake only: web app, simulator, mock ROS
#   bash scripts/setup_ubuntu.sh --with-ros   # also ROS 2 + rosbridge on this machine
#                                             #   (Jazzy on 24.04, Humble on 22.04)
#   bash scripts/setup_ubuntu.sh --with-ros --ros-distro humble
#   bash scripts/setup_ubuntu.sh --skip-tests # do not run the self-test at the end
#
# Safe to re-run. Everything Python lives in ./.venv; ROS goes to /opt/ros/<distro>.
set -euo pipefail
cd "$(dirname "$0")/.."

WITH_ROS=0
RUN_TESTS=1
ROS_DISTRO_WANTED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with-ros) WITH_ROS=1 ;;
    --skip-tests) RUN_TESTS=0 ;;
    --ros-distro) ROS_DISTRO_WANTED="${2:?--ros-distro needs a name}"; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*"; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

. /etc/os-release
UBUNTU="${VERSION_ID:-unknown}"
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
case "$UBUNTU" in
  24.04) ROS_DEFAULT="jazzy" ;;
  22.04) ROS_DEFAULT="humble" ;;
  *) ROS_DEFAULT="jazzy"; warn "tested on Ubuntu 22.04 and 24.04; you have ${PRETTY_NAME:-$UBUNTU}" ;;
esac

step "System packages"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq curl git ca-certificates python3-venv >/dev/null

step "Python 3.12 or newer (the Jac stack requires it)"
PY=""
for candidate in python3.13 python3.12 python3; do
  if command -v "$candidate" >/dev/null 2>&1 \
     && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'; then
    PY="$(command -v "$candidate")"; break
  fi
done
if [ -z "$PY" ]; then
  # Ubuntu 22.04 ships Python 3.10. ROS keeps using the system Python;
  # Handshake gets its own 3.12 from the deadsnakes PPA.
  echo "Installing Python 3.12 from the deadsnakes PPA (system python3 is untouched)"
  $SUDO apt-get install -y -qq software-properties-common >/dev/null
  $SUDO add-apt-repository -y ppa:deadsnakes/ppa
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq python3.12 python3.12-venv >/dev/null
  PY="$(command -v python3.12)"
fi
PYV="$(basename "$PY")"
if ! "$PY" -c 'import ensurepip' 2>/dev/null; then
  $SUDO apt-get install -y -qq "${PYV}-venv" >/dev/null || $SUDO apt-get install -y -qq python3-venv >/dev/null
fi
echo "using $PY ($("$PY" --version))"

step "Handshake environment in .venv"
if [ ! -x .venv/bin/python ]; then
  "$PY" -m venv .venv
fi
.venv/bin/python -m pip install -q --upgrade pip
.venv/bin/python -m pip install -q "jaseci==2.3.28"
.venv/bin/jac --version

step "Web UI dependencies (a project-local bun is downloaded if needed)"
.venv/bin/jac install

if [ "$WITH_ROS" -eq 1 ]; then
  DISTRO="${ROS_DISTRO_WANTED:-$ROS_DEFAULT}"
  step "ROS 2 $DISTRO + rosbridge"
  if [ -f "/opt/ros/$DISTRO/setup.bash" ]; then
    echo "ROS 2 $DISTRO is already installed"
  else
    # Official route since 2025: the ros2-apt-source package installs the
    # repository and its signing key, and keeps the key up to date.
    if ! locale | grep -qi 'utf-8'; then
      $SUDO apt-get install -y -qq locales >/dev/null
      $SUDO locale-gen en_US en_US.UTF-8 >/dev/null
      $SUDO update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
      export LANG=en_US.UTF-8
    fi
    $SUDO apt-get install -y -qq software-properties-common >/dev/null
    $SUDO add-apt-repository -y universe >/dev/null
    if ! dpkg -s ros2-apt-source >/dev/null 2>&1; then
      VERSION="$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
                 | grep -F '"tag_name"' | awk -F'"' '{print $4}')"
      if [ -z "$VERSION" ]; then
        echo "Could not read the latest ros-apt-source release from GitHub (rate limit or offline)." >&2
        echo "Install ROS 2 by hand: https://docs.ros.org/en/$DISTRO/Installation/Ubuntu-Install-Debs.html" >&2
        exit 1
      fi
      curl -fsSL -o /tmp/ros2-apt-source.deb \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${VERSION}/ros2-apt-source_${VERSION}.${CODENAME}_all.deb"
      $SUDO dpkg -i /tmp/ros2-apt-source.deb
    fi
    $SUDO apt-get update -qq
    $SUDO apt-get install -y "ros-$DISTRO-ros-base"
  fi
  $SUDO apt-get install -y -qq "ros-$DISTRO-rosbridge-suite" >/dev/null
  echo "rosbridge installed: /opt/ros/$DISTRO/share/rosbridge_server"
fi

if [ "$RUN_TESTS" -eq 1 ]; then
  step "Self-test (simulator, bindings and the full ROS path against the mock)"
  .venv/bin/jac run verify/run_all.jac | tail -n 1
fi

cat <<EOF

Done. Start Handshake with one of:

  bash scripts/start_lab.sh                 # web app + built-in simulator
  bash scripts/start_lab.sh --mock          # + a stand-in ROS robot (no ROS needed)
EOF
if [ "$WITH_ROS" -eq 1 ]; then
cat <<EOF
  bash scripts/start_lab.sh --ros --demo    # + rosbridge + contract node in log-only mode
  bash scripts/start_lab.sh --ros           # + rosbridge + contract node with your handlers
EOF
fi
cat <<EOF

Then open http://localhost:8000 and create an account.
EOF
