"""Descriptive metrics computed directly off the session subgraph.

Layer 1 of the insights engine: no inference, no p-values, just numbers whose
provenance is a path through the graph.
"""

import from domain.session { Session, Event, EventKind, Logged }

obj SessionMetrics {
    has session_code: str,
        condition_label: str,
        robot_profile: str,
        n_events: int = 0,
        n_steps: int = 0,
        n_percepts: int = 0,
        capability_failures: int = 0,
        duration_ms: int = 0;

    def failure_rate -> float {
        if self.n_steps == 0 {
            return 0.0;
        }
        return self.capability_failures / self.n_steps;
    }
}

walker ComputeMetrics {
    has metrics: SessionMetrics | None = None,
        reports: list[SessionMetrics] = [];

    can start with Session entry {
        self.metrics = SessionMetrics(
            session_code=here.code,
            condition_label=here.condition_label,
            robot_profile=here.robot_profile
        );
        visit [here ->:Logged:->];
    }

    can tally with Event entry {
        m = self.metrics;
        if m is None {
            skip;
        }
        m.n_events += 1;
        if here.t_mono_ms > m.duration_ms {
            m.duration_ms = here.t_mono_ms;
        }
        if here.kind == EventKind.STEP_ENTER {
            m.n_steps += 1;
        }
        if here.kind == EventKind.PERCEPT {
            m.n_percepts += 1;
        }
        if here.kind == EventKind.CAPABILITY_RESULT {
            if here.payload.get("ok") == False {
                m.capability_failures += 1;
            }
        }
    }

    can done with Session exit {
        if self.metrics is not None {
            report self.metrics;
        }
    }
}
