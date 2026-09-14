"""Single monotonic time reference for a session.

Every event in a session is stamped with milliseconds since this clock started.
Wall-clock time is recorded exactly once, at t0. This is the whole clock-
alignment model: one monotonic source, one wall anchor, per-source offsets
recorded when an external stream (robot, camera, mic) joins.
"""

import time;
import datetime;

obj Clock {
    has t0_mono_ns: int = 0,
        t0_wall_iso: str = "",
        offsets_ms: dict[str, int] = {};

    def start -> None {
        self.t0_mono_ns = time.monotonic_ns();
        self.t0_wall_iso = datetime.datetime.now(datetime.timezone.utc).isoformat();
    }

    def now_ms -> int {
        return (time.monotonic_ns() - self.t0_mono_ns) // 1000000;
    }

    def register_source(name: str, offset_ms: int) -> None {
        self.offsets_ms[name] = offset_ms;
    }

    def align(name: str, t_ms: int) -> int {
        return t_ms + self.offsets_ms.get(name, 0);
    }
}
