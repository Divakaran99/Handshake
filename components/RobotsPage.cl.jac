"""Robots: register a robot, map capabilities onto it, and test the connection.

Stateful shell - this component owns the page state; handler bodies are in
RobotsPage.impl.jac.
"""

import from .ui { Badge, Problems, Empty, confirm_action, LineBlock }
import from .CapabilityMatrix { CapabilityMatrix }
import from .wire { robot_draft }

sv import from ..api.views { RobotView, RobotDraft, PresetView, ProbeView, SaveResult, CapabilityRow }
sv import from ..api.robots {
    list_robots, robot_presets, check_robot, save_robot, delete_robot, test_robot
}

glob KINDS: list[dict[str, str]] = [
    {"key": "sim", "label": "Simulator"},
    {"key": "rosbridge", "label": "ROS (rosbridge)"},
    {"key": "http", "label": "HTTP API"},
    {"key": "plugin", "label": "Custom adapter"}
];

glob KIND_LABEL: dict[str, str] = {
    "sim": "Built-in simulator",
    "rosbridge": "ROS via rosbridge",
    "http": "HTTP API",
    "plugin": "Custom adapter"
};

glob URL_HELP: dict[str, str] = {
    "sim": "The built-in simulator needs no address.",
    "rosbridge": "The rosbridge WebSocket, e.g. ws://192.168.1.20:9090. Start it on the robot with: ros2 launch rosbridge_server rosbridge_websocket_launch.xml",
    "http": "Base URL of the robot's REST API, e.g. http://192.168.1.50:8080",
    "plugin": "module:Class of a RobotAdapter subclass under adapters/, e.g. adapters.my_robot:MyRobotAdapter"
};

def:pub RobotsPage -> JsxElement {
    has robots: list[RobotView] = [],
        presets: list[PresetView] = [],
        loaded: bool = False,
        selected_id: str = "",
        editing: bool = False,
        f_name: str = "",
        f_kind: str = "sim",
        f_url: str = "",
        f_ros: str = "2",
        f_bindings: str = "{}",
        f_percepts: str = "[]",
        f_notes: str = "",
        rows: list[CapabilityRow] = [],
        problems: list[str] = [],
        probe: ProbeView | None = None,
        busy: str = "",
        saved_note: str = "",
        preset_note: str = "";

    async can with entry {
        await load(True);
    }

    async def load(select_first: bool);
    def open_robot(r: RobotView);
    def start_new(preset_key: str);
    def make_draft -> RobotDraft;
    async def recheck;
    async def save;
    async def remove;
    async def run_probe;

    def on_kind(k: str) {
        f_kind = k;
        probe = None;
        recheck();
    }

    def on_preset(e: ChangeEvent) {
        key = str(e.target.value);
        if key != "" {
            start_new(key);
        }
    }

    return
        <>
            <header className="page-head">
                <div>
                    <h1>Robots</h1>
                    <p>
                        A robot profile says how to reach a robot and which capabilities it can perform.
                        Protocols never name a robot, so any study runs on any profile.
                    </p>
                </div>
                <label className="field" style={{"minWidth": "260px"}}>
                    <span>Add a robot from a preset</span>
                    <select className="select" value="" onChange={on_preset}>
                        <option value="">Choose a starting point…</option>
                        {for p in presets {
                            <option key={p.key} value={p.key}>{p.title}</option>
                        }}
                    </select>
                </label>
            </header>

            <div className="split">
                <aside className="pick-list" aria-label="Robot profiles">
                    {if not loaded {
                        <p className="muted">Loading…</p>
                    }}
                    {for r in robots {
                        <button key={r.id} className={"pick on" if r.id == selected_id else "pick"}
                            onClick={lambda e: MouseEvent { open_robot(r); }}>
                            <strong>{r.name}</strong>
                            <small>{KIND_LABEL[r.kind] if r.kind in KIND_LABEL else r.kind}</small>
                            {r.url and <small className="mono">{r.url}</small>}
                            {len(r.problems) > 0 and <small style={{"color": "var(--unavailable)"}}>needs attention</small>}
                        </button>
                    }}
                </aside>

                {if not editing {
                    <Empty title="Pick a robot or start from a preset">
                        <p>Presets cover the built-in simulator, ROS 2 and ROS 1 robots, Nav2 mobile bases in Gazebo or Isaac Sim, HTTP robots and custom adapters.</p>
                    </Empty>
                } else {
                    <section className="stack">
                        <div className="panel stack">
                            <div className="panel-head">
                                <h2>{f_name or "New robot"}</h2>
                                <div className="row">
                                    <button className="btn" onClick={run_probe} disabled={busy != ""}>
                                        {"Testing…" if busy == "probe" else "Test connection"}
                                    </button>
                                    <button className="btn primary" onClick={save} disabled={busy != ""}>
                                        {"Saving…" if busy == "save" else "Save robot"}
                                    </button>
                                </div>
                            </div>
                            {preset_note and <div className="notice info">{preset_note}</div>}
                            {saved_note and <div className="notice good" role="status">{saved_note}</div>}
                            <Problems items={problems} title="Fix these before saving"/>

                            <div className="field">
                                <span>Connection</span>
                                <div className="segmented" role="group" aria-label="Connection type">
                                    {for k in KINDS {
                                        <button key={k["key"]} type="button"
                                            className={"on" if f_kind == k["key"] else ""}
                                            aria-pressed={f_kind == k["key"]}
                                            onClick={lambda e: MouseEvent { on_kind(k["key"]); }}>
                                            {k["label"]}
                                        </button>
                                    }}
                                </div>
                            </div>
                            <label className="field">
                                <span>Name</span>
                                <input className="input" value={f_name} placeholder="e.g. Pepper in lab 2"
                                    onChange={lambda e: ChangeEvent { f_name = e.target.value; }}/>
                            </label>

                            {if f_kind != "sim" {
                                <div className="cols-2">
                                    <label className="field">
                                        <span>{"Adapter class" if f_kind == "plugin" else "Address"}</span>
                                        <input className="input mono" value={f_url}
                                            onChange={lambda e: ChangeEvent { f_url = e.target.value; }}
                                            onBlur={lambda e: FocusEvent { recheck(); }}/>
                                        <small>{URL_HELP[f_kind]}</small>
                                    </label>
                                    {if f_kind == "rosbridge" {
                                        <div className="field">
                                            <span>ROS version</span>
                                            <div className="segmented" role="group" aria-label="ROS version">
                                                <button type="button" className={"on" if f_ros == "2" else ""}
                                                    onClick={lambda e: MouseEvent { f_ros = "2"; recheck(); }}>ROS 2</button>
                                                <button type="button" className={"on" if f_ros == "1" else ""}
                                                    onClick={lambda e: MouseEvent { f_ros = "1"; recheck(); }}>ROS 1</button>
                                            </div>
                                            <small>Actions (Nav2 goals) need ROS 2; on ROS 1 use intents or topics.</small>
                                        </div>
                                    }}
                                </div>
                            }}

                            {if f_kind == "rosbridge" or f_kind == "http" or f_kind == "plugin" {
                                <div className={"cols-2" if f_kind == "rosbridge" else ""}>
                                    <label className="field">
                                        <span>{"Adapter configuration (JSON)" if f_kind == "plugin" else "Capability bindings (JSON)"}</span>
                                        <textarea className="textarea" rows={16} spellCheck={False} value={f_bindings}
                                            onChange={lambda e: ChangeEvent { f_bindings = e.target.value; }}
                                            onBlur={lambda e: FocusEvent { recheck(); }}/>
                                        <small>One entry per capability: publish, service, action, intent or http. Use "{"{arg}"}" to insert a step argument, "{"{arg|default}"}" for a fallback.</small>
                                    </label>
                                    {if f_kind == "rosbridge" {
                                        <label className="field">
                                            <span>Percept rules (JSON)</span>
                                            <textarea className="textarea" rows={16} spellCheck={False} value={f_percepts}
                                                onChange={lambda e: ChangeEvent { f_percepts = e.target.value; }}
                                                onBlur={lambda e: FocusEvent { recheck(); }}/>
                                            <small>Turn ROS messages into percept labels that protocol steps can branch on.</small>
                                        </label>
                                    }}
                                </div>
                            }}

                            <label className="field">
                                <span>Notes</span>
                                <input className="input" value={f_notes} placeholder="Location, firmware, quirks…"
                                    onChange={lambda e: ChangeEvent { f_notes = e.target.value; }}/>
                            </label>
                        </div>

                        {if probe is not None {
                            <ProbePanel result={probe}/>
                        }}

                        <div className="panel">
                            <div className="panel-head">
                                <h3>What this robot can do</h3>
                                <span className="small muted">Unavailable steps are logged as failures, never skipped silently.</span>
                            </div>
                            <CapabilityMatrix rows={rows}/>
                        </div>

                        {if selected_id != "" {
                            <div className="row">
                                <span className="spacer"></span>
                                <button className="btn danger" onClick={remove} disabled={busy != ""}>Delete robot</button>
                            </div>
                        }}
                    </section>
                }}
            </div>
        </>;
}

def:pub ProbePanel(result: ProbeView) -> JsxElement {
    return
        <div className="panel stack" aria-live="polite">
            <div className="panel-head">
                <h3>Connection test</h3>
                <Badge value={"ok" if result.ok else "bad"} text={"reachable" if result.ok else "not reachable"}/>
            </div>
            <p>{result.detail}{result.latency_ms > 0 and f" ({result.latency_ms} ms)"}</p>
            <Problems items={result.warnings} tone="warn"/>
            {if len(result.topics) > 0 {
                <details>
                    <summary className="small muted">{str(len(result.topics))} topics on the ROS graph</summary>
                    <LineBlock lines={result.topics}/>
                </details>
            }}
        </div>;
}
