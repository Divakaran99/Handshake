"""Small shared pieces: badges, problem lists, the brand mark, empty states."""

def:pub BrandMark -> JsxElement {
    return
        <svg className="brand-mark" viewBox="0 0 28 28" aria-hidden="true">
            <circle cx="6" cy="14" r="4.5" fill="none" stroke="currentColor" strokeWidth="2.5"/>
            <circle cx="22" cy="14" r="4.5" fill="currentColor"/>
            <path d="M10.5 14h7" stroke="var(--action)" strokeWidth="3" strokeLinecap="round"/>
        </svg>;
}

"""Capability support (NATIVE / SUBSTITUTED / UNAVAILABLE) or a session status."""
def:pub Badge(value: str, text: str = "") -> JsxElement {
    label = text or value.lower();
    return <span className={"badge " + value}>{label}</span>;
}

"""A list of problems or warnings; renders nothing when the list is empty."""
def:pub Problems(items: list[str], tone: str = "error", title: str = "") -> JsxElement {
    if len(items) == 0 {
        return <></>;
    }
    return
        <div className={"notice " + tone} role={"alert" if tone == "error" else "status"}>
            {title and <strong>{title}</strong>}
            <ul>
                {for (i, item) in enumerate(items) {
                    <li key={str(i)}>{item}</li>
                }}
            </ul>
        </div>;
}

def:pub Empty(title: str, children: any = None) -> JsxElement {
    return
        <div className="empty">
            <strong>{title}</strong>
            {children}
        </div>;
}

"""Milliseconds as a short human duration."""
def:pub fmt_ms(ms: int) -> str {
    if ms < 1000 {
        return str(ms) + " ms";
    }
    return f"{ms / 1000.0:.1f} s";
}

"""An ISO timestamp as 'YYYY-MM-DD HH:MM' (UTC)."""
def:pub fmt_when(iso: str) -> str {
    if not iso {
        return "";
    }
    return iso[:10] + " " + iso[11:16];
}

"""Ask the browser for a yes/no confirmation before a destructive action."""
def:pub confirm_action(message: str) -> bool {
    win: any = window;
    return bool(win.confirm(message));
}

"""Join strings with a separator.

The client runtime in jaclang 0.16.7 does not support `sep.join(items)` on
strings, so client code uses this helper instead.
"""
def:pub join_text(items: list[str], sep: str) -> str {
    out = "";
    for (i, item) in enumerate(items) {
        out = out + (sep if i > 0 else "") + item;
    }
    return out;
}

"""Lines of machine text (traces, topic lists) in a scrollable block."""
def:pub LineBlock(lines: list[str]) -> JsxElement {
    return
        <pre className="block">
            {for (i, line) in enumerate(lines) {
                <span key={str(i)} style={{"display": "block"}}>{line}</span>
            }}
        </pre>;
}
