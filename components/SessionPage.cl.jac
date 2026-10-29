"""One session: the trail the walker left, the Godspeed form, provenance."""

import from "@jac/runtime" { Link, useParams, useNavigate }
import from .ui { Badge, Empty, fmt_ms, fmt_when, confirm_action }
import from .Trail { Trail }
import from .csv { events_csv, download_text }

sv import from ..api.views { SessionDetail, SessionSummary, InstrumentView, SaveResult }
sv import from ..api.sessions { get_session, delete_session, godspeed_instrument, record_godspeed }

def:pub SessionPage -> JsxElement {
    has detail: SessionDetail | None = None,
        missing: bool = False,
        instrument: InstrumentView | None = None,
        answers: dict[str, int] = {},
        saving: bool = False,
        note: str = "";

    params: any = useParams();
    nav = useNavigate();
    page_id = str(params["id"] or "");

    async def load {
        session_id = page_id;
        got: SessionDetail | None = None;
        got = await get_session(session_id);
        if got is None {
            missing = True;
        }
        detail = got;
    }

    async can with entry {
        await load();
        instrument = await godspeed_instrument();
    }

    def answer(key: str, value: int) {
        merged: dict[str, int] = {k: v for (k, v) in answers.items()};
        merged[key] = value;
        answers = merged;
    }

    async def save_godspeed {
        session_id = page_id;
        responses: dict[str, int] = answers;
        saving = True;
        await record_godspeed(session_id, responses);
        saving = False;
        note = "Response recorded on the session.";
        await load();
    }

    async def remove {
        if not confirm_action("Delete this session and all its events? Use this for pilot runs; to honour a withdrawal, withdraw the participant instead.") {
            return;
        }
        session_id = page_id;
        await delete_session(session_id);
        nav("/sessions");
    }

    def export_one {
        if detail is not None {
            d = detail as SessionDetail;
            download_text(d.summary.code + ".csv", events_csv(d.events));
        }
    }

    if missing {
        return <Empty title="This session does not exist in your account"><Link className="btn" to="/sessions">Back to sessions</Link></Empty>;
    }
    if detail is None {
        return <p className="muted">Loading…</p>;
    }
    d = detail as SessionDetail;
    s = d.summary;

    return
        <>
            <header className="page-head">
                <div>
                    <p className="small"><Link to="/sessions">Sessions</Link></p>
                    <h1 className="mono" style={{"fontFamily": "var(--mono)", "fontSize": "var(--step-3)"}}>{s.code}</h1>
                    <div className="row" style={{"marginTop": "8px"}}>
                        <Badge value={s.status}/>
                        <span>{s.study_title} <span className="mono muted">v{s.protocol_version}</span></span>
                    </div>
                </div>
                <div className="row">
                    <button className="btn" onClick={lambda e: MouseEvent { export_one(); }}>Export this session</button>
                    <button className="btn danger" onClick={remove}>Delete session</button>
                </div>
            </header>

            <div className="split split-aside">
                <section className="panel">
                    <div className="panel-head">
                        <h2>What happened</h2>
                        <span className="small muted">{str(s.n_events)} events over {fmt_ms(s.duration_ms)}</span>
                    </div>
                    <Trail stops={d.trail}/>
                </section>

                <aside className="stack">
                    <div className="panel">
                        <dl className="kv" style={{"display": "grid", "gridTemplateColumns": "max-content 1fr", "gap": "6px 14px", "margin": "0"}}>
                            <dt className="muted">Condition</dt><dd style={{"margin": "0"}}>{s.condition_label}</dd>
                            <dt className="muted">Robot</dt><dd style={{"margin": "0"}}>{s.robot_profile}</dd>
                            <dt className="muted">Participant</dt><dd className="mono" style={{"margin": "0"}}>{s.participant_code}</dd>
                            <dt className="muted">Started (UTC)</dt><dd style={{"margin": "0"}}>{fmt_when(s.started_at)}</dd>
                            <dt className="muted">Steps</dt><dd style={{"margin": "0"}}>{s.n_steps}</dd>
                            <dt className="muted">Percepts</dt><dd style={{"margin": "0"}}>{s.n_percepts}</dd>
                            <dt className="muted">Failed calls</dt><dd style={{"margin": "0"}}>{s.capability_failures}</dd>
                        </dl>
                    </div>

                    {if instrument is not None {
                        <GodspeedForm form={instrument} answers={answers} score={s.godspeed}
                            saving={saving} onAnswer={answer} onSave={save_godspeed}/>
                    }}
                    {note and <div className="notice good" role="status">{note}</div>}

                    <details className="panel">
                        <summary><strong>Protocol as it ran</strong></summary>
                        <p className="small muted" style={{"marginTop": "8px"}}>Frozen copy of the condition taken when the session started.</p>
                        <pre className="block">{d.protocol_snapshot or "Not recorded (session created outside the app)."}</pre>
                    </details>
                </aside>
            </div>
        </>;
}

def:pub GodspeedForm(
    form: InstrumentView,
    answers: dict[str, int],
    score: float,
    saving: bool,
    onAnswer: Callable[[str, int], None],
    onSave: Callable[[], None]
) -> JsxElement {
    points = [i + 1 for i in range(form.points)];
    return
        <div className="panel stack">
            <div>
                <h3>Godspeed: anthropomorphism</h3>
                <p className="small muted">{form.citation}. Record the participant's paper or tablet answers here.</p>
            </div>
            {score >= 0 and <p><strong>{f"{score:.2f}"}</strong> <span className="muted small">latest score (mean of answered items)</span></p>}
            {for item in form.items {
                <fieldset key={item.key} style={{"border": "0", "padding": "0", "margin": "0"}}>
                    <legend className="sr-only">{item.anchor_low} to {item.anchor_high}</legend>
                    <div className="row" style={{"gap": "4px", "flexWrap": "nowrap"}}>
                        <span className="small muted" style={{"width": "84px", "textAlign": "right"}}>{item.anchor_low}</span>
                        {for p in points {
                            <label key={str(p)} style={{"display": "flex", "flexDirection": "column", "alignItems": "center", "fontSize": "0.75rem"}}>
                                <input type="radio" name={item.key} value={str(p)}
                                    checked={item.key in answers and answers[item.key] == p}
                                    onChange={lambda e: ChangeEvent { onAnswer(item.key, p); }}/>
                                {p}
                            </label>
                        }}
                        <span className="small muted" style={{"width": "84px"}}>{item.anchor_high}</span>
                    </div>
                </fieldset>
            }}
            <button className="btn" disabled={saving or len(answers) == 0} onClick={lambda e: MouseEvent { onSave(); }}>
                {"Recording…" if saving else "Record response"}
            </button>
        </div>;
}
