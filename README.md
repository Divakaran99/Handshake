# Handshake

**An open-source platform for designing, running and analysing human-robot
interaction studies — built entirely in [Jac](https://www.jac-lang.org).**

> Status: **v1 application.** A full-stack Jac app (API + web UI) that connects
> to the built-in simulator, any ROS 1 or ROS 2 system through rosbridge
> (including Gazebo, Webots, Isaac Sim and other ROS-connected simulators),
> robots with an HTTP API, and custom Python/Jac adapters. Everything runs and
> is tested with no hardware. See [docs/BUILD_GUIDE.md](docs/BUILD_GUIDE.md).

HRI research has a tooling gap. ROS is excellent at control and has no concept
of an experiment. PsychoPy and jsPsych are excellent at experiments and have no
concept of an embodied agent in shared physical space. Most labs bridge that gap
with a Wizard-of-Oz GUI, a separate recording rig, a spreadsheet of condition
assignments, and glue scripts only one student understands.

Handshake is the missing experiment layer: **design once, run on any robot, and
get a reproducible dataset instead of a folder of videos.**

*The name is doubly apt: a handshake is the canonical human-robot interaction,
and it is also what two systems do to agree on a protocol before exchanging
anything meaningful.*

---

## The idea in one line

> **A study protocol is a graph. A session is a walker traversing it. The
> transcript is the trail the walker leaves behind.**

That is not a metaphor. A protocol *is* a directed graph with conditional
branches and timeouts. Running a participant through it *is* a stateful agent
moving through that topology. Jac's object-spatial model expresses this
directly, so the protocol is the data structure and the walker is the runtime.

---

## Try it

On Ubuntu 24.04 or 22.04:

```bash
git clone https://github.com/Divakaran99/Handshake.git && cd Handshake
bash scripts/setup_ubuntu.sh          # add --with-ros to also install ROS 2 + rosbridge
bash scripts/start_lab.sh --mock      # web app + a stand-in ROS robot; open http://localhost:8000
```

Create an account, open **Studies → Add the example study**, and run a session
on the built-in simulator. Then add a robot from the *ROS 2 robot — Handshake
contract* preset (it points at `ws://localhost:9090`), press *Test connection*,
and run the same study on it. With ROS installed, `bash scripts/start_lab.sh
--ros --demo` starts real rosbridge and the robot-side contract node instead.

Elsewhere (Python 3.12+):

```bash
pip install jaseci==2.3.28 && jac install && jac start main.jac
```

The original command-line demo still works and needs nothing but jaclang:

```bash
jac run examples/proxemics/build_study.jac
```

---

## Connect your robot

| Your robot | Connector | What you run on the robot side |
|---|---|---|
| Nothing yet | Built-in simulator | nothing |
| ROS 2 robot (Humble, Jazzy, …) | rosbridge | `ros2 launch rosbridge_server rosbridge_websocket_launch.xml` |
| ROS 1 robot (Noetic) | rosbridge | `roslaunch rosbridge_server rosbridge_websocket.launch` |
| Gazebo, Webots, Isaac Sim, CoppeliaSim | rosbridge | the simulator's ROS 2 bridge + rosbridge |
| Robot with a REST API | HTTP | nothing (Handshake calls its API) |
| Vendor SDK (NAOqi, proprietary) | Custom adapter | a `RobotAdapter` subclass in `adapters/` |

Each robot profile maps the eight behavioural capabilities onto what the robot
already understands — a ROS topic, service or action, an HTTP endpoint, or a
**Handshake intent** handled by the small reference node in
[`ros/handshake_node.py`](ros/handshake_node.py). Percept rules turn ROS
messages into labels a protocol can branch on. The **Test connection** button
lists the topics actually on the ROS graph and warns when nothing is listening.
Full walkthrough: [docs/BUILD_GUIDE.md](docs/BUILD_GUIDE.md#connecting-robots).

---

## Design commitments

These are load-bearing. Changing them changes the project.

### 1. Behavioural authority only

| Authority | Meaning | Owner |
|---|---|---|
| **Behavioural** | *what* the robot does and when | **Handshake** |
| Motion | *how* a goal is achieved — trajectory, joints | Robot stack |
| Safety | collision, force limits, e-stop | **Never Handshake** |

Protocols express intent — `approach(stop_distance=1.2, speed=0.4)`,
`gaze(target=face, hold_ms=1800)` — which is exactly what HRI researchers
manipulate as independent variables. The robot's own certified stack executes
it. Handshake records **commanded vs. achieved** and the exact payload sent, so
"we set approach speed to 0.4 m/s" becomes "commanded 0.4; achieved median
0.31" — a methods contribution most HRI papers cannot currently make.

### 2. Protocols are authored against capabilities, never robots

A robot profile declares which capabilities it supports, and how it degrades
when it cannot. The simulated robot deliberately declares `APPROACH` as
`UNAVAILABLE` and `EXPRESS` as `SUBSTITUTED` by `DISPLAY`, so the degradation
path is exercised on every CI run rather than only on exotic hardware.

### 3. Everything runs with no robot

`SimAdapter` is the reference implementation and `tools/mock_rosbridge.jac`
stands in for a ROS system, so the whole ROS path is CI-tested without ROS.

### 4. Analysis plans are versioned with the protocol

`StudyProtocol.prereg` is part of the versioned protocol. A version that has
produced sessions is **frozen**: changing its steps or pre-registration
requires a new version number, and every session stores a snapshot of the exact
condition it ran.

---

## Architecture

```
Handshake/
├── main.jac        entry: imports every endpoint, mounts the web app
├── domain/         nodes, edges, enums — knows nothing about HTTP or robots
│   ├── capability.jac      the capability taxonomy (start here)
│   ├── protocol.jac        StudyProtocol, Condition, Step, Next
│   ├── participant.jac     Participant, ConsentRecord
│   ├── session.jac         Session, Event, EventKind
│   └── robot.jac           RobotProfile (connection + bindings)
├── adapters/       the robot seam
│   ├── adapter.jac         abstract RobotAdapter interface
│   ├── sim.jac             reference simulated robot
│   ├── bindings.jac        capability bindings + percept rules (parse, validate, render)
│   ├── bound.jac           shared machinery for binding-driven adapters
│   ├── rosbridge.jac       ROS 1 / ROS 2 over rosbridge WebSocket
│   ├── http.jac            robots with a REST API
│   ├── registry.jac        profile -> adapter (the only place that knows every kind)
│   └── presets.jac         starting profiles (sim, ROS 2, Nav2, ROS 1, HTTP, plugin)
├── runtime/
│   ├── clock.jac           single monotonic reference + per-source offsets
│   └── session_runtime.jac the session walker + run_condition
├── instruments/    typed scales (Godspeed included)
├── insights/       descriptive metrics off the session subgraph
├── api/            the ONLY server modules with access modifiers (all def:priv)
├── components/     the web UI (.cl.jac), one stateful shell per page
├── pages/          file-based routes; (auth)/ pages require sign-in
├── assets/         global CSS (design tokens)
├── ros/            robot-side reference node for the Handshake ROS contract
├── tools/          mock rosbridge server
├── examples/       runnable reference study
└── verify/         assertion suite + end-to-end API check
```

Conventions worth keeping:

- **`api/` is the only place server endpoints are declared.** Auditing the
  network surface means reading four files. Every endpoint is `def:priv`, so it
  runs on the authenticated researcher's own root.
- **`domain/` never imports from `api/` or `adapters/`.** The domain does not
  know a server or a robot exists.
- **`adapters/registry.jac` is the only module that knows every connector.**
  Adding a robot kind never touches a protocol, the runtime or the UI.

---

## What Jac gives us for free

| Capability | Mechanism |
|---|---|
| Persistence, no ORM or migrations | reachability from `root` |
| Per-researcher isolation | `def:priv` runs on the caller's own root |
| Typed API + generated client stubs | `sv import` from `.cl.jac` components |
| React UI written in Jac | `.cl.jac` components compiled by jac-client |
| Participant withdrawal (IRB / GDPR) | `withdraw_participant` deletes events, sessions, consent |
| Production deploy | `jac start --scale` (jac-scale: MongoDB, Redis, Kubernetes) |

---

## Roadmap

**v0 — walking skeleton.** Capability taxonomy, protocol graph, session walker,
sim adapter with degradation and telemetry, instruments, metrics. *Done.*

**v1 — the application (current).** Web UI, per-researcher accounts, robot
registry, rosbridge adapter for ROS 1/2 and ROS-connected simulators, HTTP and
plugin adapters, robot-side contract node, protocol editor with percept
branches, run console, session trail, Godspeed entry, CSV export, version
freezing with protocol snapshots, mock rosbridge, end-to-end tests.

**v1.x — live operation.** Streamed session progress, Wizard-of-Oz console
(`wizard_gated` steps), voice pipeline (VAD → ASR → TTS), vision percepts
(face presence, gaze-on-robot, distance), session replay against recordings.

**v2 — the platform claim.** Annotation studio with inter-rater reliability,
AI-assisted pre-annotation via `by llm()`, condition contrasts with effect
sizes, protocol sharing between labs, adapter plugin ecosystem.

---

## Known issues in the toolchain

Found while building this, on jaclang 0.16.7 / jac-client 0.3.25. Documented
because this repo also serves as a real-world Jac showcase.

| Issue | Workaround |
|---|---|
| `round(x, n)` runs fine but fails `jac check` (stub gap) | fixed-point arithmetic; see `adapters/sim.jac` |
| A node named `Protocol` collides with ambient `typing.Protocol` | named `StudyProtocol` |
| `jac test` fails with a bytecode-cache error in some environments | assertion suites in `verify/` |
| Edge entry/exit abilities compile but never fire (documented Jac limitation) | edge logic lives in walker node abilities |
| `report` also prints to stdout | expected; read `result.reports` |
| Untyped `dict` fields make `.get()` return `any` and trip the strict-any rule | type the field, or narrow with `as_dict` (`adapters/bindings.jac`) |
| Endpoint effects are classified only for `def:pub`; every `def:priv` call is cached by the client for 60 s | `components/runtime_fixes.cl.jac` turns the read cache off |
| An `sv import`-ed type is an RPC stub on the client, so `StepSpec(...)` calls the server | `components/wire.cl.jac` builds request objects |
| Some Python string methods (`join`, `isdigit`, `isalpha`, `ljust`, …) are missing in the browser runtime; calls pass `jac check`, then fail silently inside click handlers | `join_text` in `components/ui.cl.jac`, logic moved to the server; `scripts/check.sh` flags them |
| `dict(obj)` in client code compiles to `Object.fromEntries` and throws on objects | dict comprehension copy |
| Top-level `def`s in a client `.impl.jac` annex are not emitted to the bundle | helpers live in the `.cl.jac` file |
| A `layout.jac` inside `pages/(auth)/` becomes the root layout for every route | `AppShell` wraps each auth page instead |
| The runtime's error fallback dereferences the error wrongly and hides the message | `PageError` boundary in `components/AppShell.cl.jac` |
| `jac start --faux` prints the API, then exits with `server_close` AttributeError | harmless |

## Development

```bash
bash scripts/check.sh                 # jac check every module
jac run verify/run_all.jac            # 54 assertions, includes ROS via the mock
jac run verify/api_e2e.jac            # 28 end-to-end assertions against `jac start`
jac run examples/proxemics/build_study.jac
jac start main.jac --dev              # UI hot reload (restart for server changes)
```

## License

Apache-2.0 — chosen over MIT for the explicit patent grant, which matters in
robotics.

## Citation

If Handshake supports published work, please cite the repository and the
original instruments you used (e.g. Godspeed: Bartneck et al., 2009).
