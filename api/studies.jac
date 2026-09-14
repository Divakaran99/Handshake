"""The only module in the repository carrying access modifiers.

Auditing the network surface of this project means reading this one file.
walker:priv runs on the authenticated researcher's own root, so per-researcher
isolation is enforced by the runtime rather than by a query filter.
"""

import from domain.capability { Capability }
import from domain.protocol { StudyProtocol, Condition, Step, HasCondition, Starts, Next }
import from domain.participant { Participant, ConsentRecord, Consented }
import from domain.session { Session, Ran }
import from adapters.sim { SimAdapter }
import from runtime.clock { Clock }
import from runtime.session_runtime { RunSession }
import from insights.metrics { ComputeMetrics, SessionMetrics }

walker:priv create_study {
    has title: str,
        version: str = "0.1.0",
        prereg: str = "",
        reports: list[StudyProtocol] = [];

    can run with Root entry {
        p = here ++> StudyProtocol(title=self.title, version=self.version,
                                   prereg=self.prereg);
        report p[0];
    }
}

walker:priv list_studies {
    has found: list[StudyProtocol] = [],
        reports: list[list[StudyProtocol]] = [];

    can run with Root entry {
        self.found = [here -->[?:StudyProtocol]];
        report self.found;
    }
}

walker:priv enroll_participant {
    has code: str,
        consent_scope: str = "audio+video",
        granted_at: str = "",
        reports: list[Participant] = [];

    can run with Root entry {
        p = (here ++> Participant(code=self.code, enrolled_at=self.granted_at))[0];
        p +>: Consented() :+> ConsentRecord(scope=self.consent_scope,
                                            granted_at=self.granted_at);
        report p;
    }
}

walker:priv withdraw_participant {
    has code: str,
        reports: list[dict] = [];

    can run with Root entry {
        removed: int = 0;
        for p in [here -->[?:Participant, code == self.code]] {
            for s in [p ->:Ran:->] {
                del s;
            }
            del p;
            removed += 1;
        }
        report {"withdrawn": self.code, "removed": removed};
    }
}

walker:priv session_metrics {
    has session_code: str,
        reports: list[SessionMetrics] = [];

    can run with Root entry {
        for s in [here -->[?:Session, code == self.session_code]] {
            m = s spawn ComputeMetrics();
            for row in m.reports {
                report row;
            }
        }
    }
}
