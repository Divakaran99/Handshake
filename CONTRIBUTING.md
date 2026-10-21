# Contributing

## Ground rules

1. **No motion or safety code.** This platform commands behavioural intent and
   records evidence. Trajectories, joint commands, collision avoidance and
   e-stop belong to the robot's own certified stack. A pull request that adds a
   motion primitive to the capability taxonomy will be declined. Binding a
   capability to a robot's *goal-level* interface (a Nav2 goal, a TTS service)
   is fine; publishing velocity or joint commands is not.
2. **Protocols never name a robot.** If a change makes a study protocol depend
   on a specific platform, the capability abstraction has failed. Fix the
   abstraction, not the protocol.
3. **Everything runs with no hardware.** `SimAdapter` and
   `tools/mock_rosbridge.jac` are the CI targets. If your change cannot be
   exercised by them, add a simulated path for it.
4. **The repository is also a teaching artifact.** People will read this code to
   learn Jac. Prefer the natural construct over the clever one, and keep
   interop boundaries visible rather than hidden.
5. **Endpoints live in `api/` and are `def:priv`.** A `def:pub` endpoint runs
   anonymous callers on a shared graph; research data never goes there.

## Adding a robot

Most robots need no code: add a profile in the app (Robots → preset) and edit
its bindings. Write code only when the robot has no ROS or HTTP interface.

**A custom adapter.** Create `adapters/<platform>.jac`, subclass
`RobotAdapter`, and implement `capabilities`, `execute` and `raw`; override
`connect`, `close`, `await_percept` and `probe` if the robot has a transport or
perception. Declare degradation honestly: a capability your platform cannot
perform is `Support.UNAVAILABLE`, not silently approximated. Register it in the
app as a *Custom adapter* profile with the path `adapters.<platform>:<Class>`.
See `adapters/sim.jac` for the minimal shape and `adapters/rosbridge.jac` for a
transport.

**A new connector kind** (another protocol family) goes in
`adapters/registry.jac` plus one module next to it, a preset in
`adapters/presets.jac`, and tests in `verify/run_all.jac`.

## Before opening a PR

```bash
bash scripts/check.sh
jac run verify/run_all.jac
jac run verify/api_e2e.jac
jac run examples/proxemics/build_study.jac
```

For UI changes, also run `jac start main.jac` and click through the flow you
changed (or drive it with `jac browse`). Server-side changes need a server
restart; `--dev` only hot-reloads `.cl.jac` files.
