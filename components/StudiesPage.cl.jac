"""Studies: list protocols, start a new one, or load the reference example."""

import from "@jac/runtime" { Link, useNavigate }
import from .ui { Badge, Problems, Empty }
import from .wire { study_draft }

sv import from ..api.views { StudySummary, StudyDraft, SaveResult }
sv import from ..api.studies { list_studies, create_study, create_example_study }

def:pub StudiesPage -> JsxElement {
    has studies: list[StudySummary] = [],
        loaded: bool = False,
        title: str = "",
        version: str = "0.1.0",
        prereg: str = "",
        problems: list[str] = [],
        busy: bool = False;

    nav = useNavigate();

    async can with entry {
        studies = await list_studies();
        loaded = True;
    }

    async def create(e: FormEvent) {
        e.preventDefault();
        busy = True;
        draft = study_draft(title, version, prereg);
        result: SaveResult | None = None;
        result = await create_study(draft);
        busy = False;
        if result is not None and result.ok {
            nav("/studies/" + result.id);
        } elif result is not None {
            problems = result.problems;
        }
    }

    async def add_example {
        busy = True;
        result: SaveResult | None = None;
        result = await create_example_study();
        busy = False;
        if result is not None and result.ok {
            nav("/studies/" + result.id);
        }
    }

    return
        <>
            <header className="page-head">
                <div>
                    <h1>Studies</h1>
                    <p>
                        A study is a versioned protocol with one or more conditions. Each condition is a
                        sequence of capability steps that can branch on what the robot perceives.
                    </p>
                </div>
                <button className="btn" onClick={add_example} disabled={busy}>Add the example study</button>
            </header>

            <div className="split">
                <form className="panel stack" onSubmit={create}>
                    <h2>New study</h2>
                    <label className="field">
                        <span>Title</span>
                        <input className="input" value={title} placeholder="e.g. Proxemics and trust"
                            onChange={lambda e: ChangeEvent { title = e.target.value; }}/>
                    </label>
                    <label className="field">
                        <span>Protocol version</span>
                        <input className="input mono" value={version}
                            onChange={lambda e: ChangeEvent { version = e.target.value; }}/>
                        <small>A version freezes once it has produced sessions.</small>
                    </label>
                    <label className="field">
                        <span>Pre-registered hypotheses and analysis plan</span>
                        <textarea className="textarea" rows={5} value={prereg}
                            placeholder="H1: …"
                            onChange={lambda e: ChangeEvent { prereg = e.target.value; }}/>
                        <small>Stored with the protocol version. Anything computed later is exploratory.</small>
                    </label>
                    <Problems items={problems}/>
                    <button className="btn primary" type="submit" disabled={busy}>Create study</button>
                </form>

                <section>
                    {if loaded and len(studies) == 0 {
                        <Empty title="No studies yet">
                            <p>Create one, or add the example: a two-condition greeting study that branches on gaze.</p>
                            <button className="btn" onClick={add_example} disabled={busy}>Add the example study</button>
                        </Empty>
                    } elif len(studies) > 0 {
                        <div className="panel table-wrap">
                            <table className="data">
                                <thead>
                                    <tr>
                                        <th>Study</th>
                                        <th>Version</th>
                                        <th className="num">Conditions</th>
                                        <th className="num">Sessions</th>
                                        <th>Status</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {for s in studies {
                                        <tr key={s.id}>
                                            <td><Link to={"/studies/" + s.id}>{s.title}</Link></td>
                                            <td className="mono">{s.version}</td>
                                            <td className="num">{s.n_conditions}</td>
                                            <td className="num">{s.n_sessions}</td>
                                            <td>{<Badge value="frozen" text="version frozen"/> if s.frozen else <Badge value="plain" text="editable"/>}</td>
                                        </tr>
                                    }}
                                </tbody>
                            </table>
                        </div>
                    }}
                </section>
            </div>
        </>;
}
