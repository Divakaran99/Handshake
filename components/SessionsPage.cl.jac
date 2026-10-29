"""Sessions: every run, filterable by study, with CSV export of all events."""

import from .ui { Empty }
import from .SessionTable { SessionTable }
import from .csv { events_csv, download_text }

sv import from ..api.views { SessionSummary, StudySummary, EventRow }
sv import from ..api.sessions { list_sessions, export_events }
sv import from ..api.studies { list_studies }

def:pub SessionsPage -> JsxElement {
    has sessions: list[SessionSummary] = [],
        studies: list[StudySummary] = [],
        filter_id: str = "",
        loaded: bool = False,
        exporting: bool = False,
        note: str = "";

    async def load(study_id: str) {
        sessions = await list_sessions(study_id);
        loaded = True;
    }

    async can with entry {
        studies = await list_studies();
        await load("");
    }

    async def pick(e: ChangeEvent) {
        filter_id = str(e.target.value);
        await load(filter_id);
    }

    async def export_csv {
        exporting = True;
        study_id = filter_id;
        rows: list[EventRow] = [];
        rows = await export_events(study_id);
        name = "handshake-events.csv";
        for s in studies {
            if s.id == study_id {
                name = "handshake-" + s.title.lower().replace(" ", "-")[:40] + "-v" + s.version + ".csv";
            }
        }
        download_text(name, events_csv(rows));
        note = f"Exported {len(rows)} events.";
        exporting = False;
    }

    return
        <>
            <header className="page-head">
                <div>
                    <h1>Sessions</h1>
                    <p>
                        Each session keeps every event with a monotonic timestamp, the exact payload sent
                        to the robot, and commanded next to achieved values. Export is one row per event.
                    </p>
                </div>
                <div className="row">
                    <select className="select" style={{"width": "auto"}} value={filter_id} onChange={pick} aria-label="Filter by study">
                        <option value="">All studies</option>
                        {for s in studies {
                            <option key={s.id} value={s.id}>{s.title} (v{s.version})</option>
                        }}
                    </select>
                    <button className="btn primary" onClick={export_csv} disabled={exporting or len(sessions) == 0}>
                        {"Exporting…" if exporting else "Export events as CSV"}
                    </button>
                </div>
            </header>
            {note and <div className="notice good" role="status" style={{"marginBottom": "16px"}}>{note}</div>}
            {if loaded and len(sessions) == 0 {
                <Empty title="No sessions to show">
                    <p>Open a study and run a session on the simulator. It takes a second.</p>
                </Empty>
            } elif len(sessions) > 0 {
                <div className="panel"><SessionTable rows={sessions}/></div>
            }}
        </>;
}
