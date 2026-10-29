"""The protocol editor: a condition drawn as a rail of steps.

Each station is one capability step. Where a step waits for a percept, its
branches hang off it as spurs. Stateless: every edit is reported upward and
the page (StudyPage) owns the list.
"""

sv import from ..api.views { StepSpec, BranchSpec, CapabilityInfo }

def:pub StepRail(
    steps: list[StepSpec],
    catalog: list[CapabilityInfo],
    locked: bool,
    onField: Callable[[int, str, str], None],
    onAdd: Callable[[int], None],
    onRemove: Callable[[int], None],
    onMove: Callable[[int, int], None],
    onAddBranch: Callable[[int], None],
    onBranch: Callable[[int, int, str, str], None],
    onRemoveBranch: Callable[[int, int], None]
) -> JsxElement {
    targets = [s.label for s in steps if s.label != ""];
    branch_targets = [b.target for s in steps for b in s.branches];

    return
        <div>
            <div className="rail-head" aria-hidden="true">
                <span>Step</span><span>Capability</span><span>Arguments (JSON)</span><span>Timeout ms</span><span></span>
            </div>
            <ol className="rail numbered" aria-label="Protocol steps">
            {for (i, s) in enumerate(steps) {
                <li key={"st" + str(i)}
                    className={"station" + (" branch-target" if s.label in branch_targets else "") + (" end-station" if s.next == "END" or (i == len(steps) - 1 and s.next == "") else "")}>
                    <fieldset className="station-card" disabled={locked}>
                        <legend className="sr-only">{"Step " + str(i + 1) + " " + s.label}</legend>
                        <div className="station-top">
                            <input className="input" value={s.label} aria-label="Step label"
                                onChange={lambda e: ChangeEvent { onField(i, "label", e.target.value); }}/>
                            <select className="select" value={s.capability} aria-label="Capability"
                                onChange={lambda e: ChangeEvent { onField(i, "capability", e.target.value); }}>
                                {for c in catalog {
                                    <option key={c.name} value={c.name} title={c.description}>{c.name}</option>
                                }}
                            </select>
                            <input className="input mono" value={s.args_json} spellCheck={False} aria-label="Arguments as JSON"
                                onChange={lambda e: ChangeEvent { onField(i, "args_json", e.target.value); }}/>
                            <input className="input mono" type="number" min="100" step="100" value={str(s.timeout_ms)}
                                aria-label="Timeout in milliseconds"
                                onChange={lambda e: ChangeEvent { onField(i, "timeout_ms", e.target.value); }}/>
                            <div className="row station-tools">
                                <button type="button" className="btn quiet small" aria-label={"Move step " + str(i + 1) + " up"}
                                    disabled={i == 0} onClick={lambda e: MouseEvent { onMove(i, -1); }}>Up</button>
                                <button type="button" className="btn quiet small" aria-label={"Move step " + str(i + 1) + " down"}
                                    disabled={i == len(steps) - 1} onClick={lambda e: MouseEvent { onMove(i, 1); }}>Down</button>
                                <button type="button" className="btn quiet small" aria-label={"Remove step " + str(i + 1)}
                                    onClick={lambda e: MouseEvent { onRemove(i); }}>Remove</button>
                            </div>
                        </div>
                        <div className="station-flow">
                            {for (j, b) in enumerate(s.branches) {
                                <span key={"b" + str(j)} className="spur">
                                    <span>When</span>
                                    <input className="input mono" value={b.percept} placeholder="percept label"
                                        aria-label="Percept label" size={18}
                                        onChange={lambda e: ChangeEvent { onBranch(i, j, "percept", e.target.value); }}/>
                                    <span>go to</span>
                                    <select className="select" value={b.target} aria-label="Branch target"
                                        onChange={lambda e: ChangeEvent { onBranch(i, j, "target", e.target.value); }}>
                                        <option value="">choose a step…</option>
                                        {for t in targets {
                                            <option key={t} value={t}>{t}</option>
                                        }}
                                    </select>
                                    <button type="button" className="btn quiet small" aria-label="Remove branch"
                                        onClick={lambda e: MouseEvent { onRemoveBranch(i, j); }}>Remove</button>
                                </span>
                            }}
                            <label className="row" style={{"gap": "6px"}}>
                                <span>{"If nothing is perceived, go to" if len(s.branches) > 0 else "Then"}</span>
                                <select className="select" style={{"width": "auto"}} value={s.next}
                                    onChange={lambda e: ChangeEvent { onField(i, "next", e.target.value); }}>
                                    <option value="">{"the next step" if i < len(steps) - 1 else "end the session"}</option>
                                    {for t in targets {
                                        if t != s.label {
                                            <option key={t} value={t}>{t}</option>
                                        }
                                    }}
                                    <option value="END">end the session</option>
                                </select>
                            </label>
                            <button type="button" className="btn quiet small" onClick={lambda e: MouseEvent { onAddBranch(i); }}>
                                Branch on a percept
                            </button>
                            <span className="spacer"></span>
                            <button type="button" className="btn quiet small insert-step" disabled={locked}
                                onClick={lambda e: MouseEvent { onAdd(i); }}>Insert a step below</button>
                        </div>
                    </fieldset>
                </li>
            }}
            </ol>
        </div>;
}
