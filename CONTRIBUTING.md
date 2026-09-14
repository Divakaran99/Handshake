# Contributing

## Ground rules

1. **No motion or safety code.** This platform commands behavioural intent and
   records evidence. Trajectories, joint commands, collision avoidance and
   e-stop belong to the robot's own certified stack. A pull request that adds a
   motion primitive to the capability taxonomy will be declined.
2. **Protocols never name a robot.** If a change makes a study protocol depend
   on a specific platform, the capability abstraction has failed. Fix the
   abstraction, not the protocol.
3. **Everything runs with no hardware.** `SimAdapter` is the reference
   implementation and the CI target. If your change cannot be exercised by the
   simulator, add a simulated path for it.
4. **The repository is also a teaching artifact.** People will read this code to
   learn Jac. Prefer the natural construct over the clever one, and keep
   interop boundaries visible rather than hidden.

## Adding a robot adapter

Create `adapters/<platform>.jac`, subclass `RobotAdapter`, and implement
`capabilities`, `execute` and `raw`. Declare degradation honestly: a capability
your platform cannot perform should be `Support.UNAVAILABLE`, not silently
approximated. See `adapters/sim.jac` for the reference shape.

## Before opening a PR

```bash
for f in $(find domain adapters runtime instruments insights api examples verify -type f -name '*.jac'); do jac check "$f"; done
jac run verify/run_all.jac
jac run examples/proxemics/build_study.jac
```
