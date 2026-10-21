"""Participants: pseudonymous codes, consent, and withdrawal."""

import from .ui { Badge, Empty, confirm_action }

sv import from ..api.views { ParticipantView }
sv import from ..api.sessions { list_participants, withdraw_participant }

def:pub ParticipantsPage -> JsxElement {
    has people: list[ParticipantView] = [],
        loaded: bool = False,
        note: str = "";

    async def load {
        people = await list_participants();
        loaded = True;
    }

    async can with entry {
        await load();
    }

    async def withdraw(code: str) {
        if not confirm_action(f"Withdraw {code}? Their sessions, events and consent record are deleted permanently.") {
            return;
        }
        removed: int = 0;
        removed = await withdraw_participant(code);
        note = f"{code} withdrawn. {removed} sessions deleted.";
        await load();
    }

    return
        <>
            <header className="page-head">
                <div>
                    <h1>Participants</h1>
                    <p>
                        Participants are enrolled by code the first time they run a session, with the consent
                        scope you record. No names or other direct identifiers are stored.
                    </p>
                </div>
            </header>
            {note and <div className="notice good" role="status" style={{"marginBottom": "16px"}}>{note}</div>}
            {if loaded and len(people) == 0 {
                <Empty title="No participants yet">
                    <p>They appear here after their first session.</p>
                </Empty>
            } elif len(people) > 0 {
                <div className="panel table-wrap">
                    <table className="data">
                        <thead>
                            <tr>
                                <th>Code</th>
                                <th>Enrolled</th>
                                <th>Consent</th>
                                <th className="num">Sessions</th>
                                <th></th>
                            </tr>
                        </thead>
                        <tbody>
                            {for p in people {
                                <tr key={p.code}>
                                    <td className="mono">{p.code}</td>
                                    <td>{p.enrolled_at}</td>
                                    <td>
                                        {<Badge value="ok" text={p.consent_scope}/> if p.consent_active else <Badge value="bad" text="no active consent"/>}
                                    </td>
                                    <td className="num">{p.n_sessions}</td>
                                    <td className="num">
                                        <button className="btn danger small" onClick={lambda e: MouseEvent { withdraw(p.code); }}>Withdraw</button>
                                    </td>
                                </tr>
                            }}
                        </tbody>
                    </table>
                </div>
            }}
        </>;
}
