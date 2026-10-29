"""The signed-in frame: navigation rail on the left, the page on the right.

Pages under pages/(auth)/ are already guarded by the router (the (auth) group
gets an AuthGuard), so the shell only draws the frame around its children.
"""

import from "@jac/runtime" { Link, useLocation, useNavigate, jacLogout }
import from "react-error-boundary" { ErrorBoundary }
import from .ui { BrandMark }
import from .runtime_fixes { READ_CACHE_DISABLED }

glob NAV: list[dict[str, str]] = [
    {"to": "/", "label": "Overview"},
    {"to": "/robots", "label": "Robots"},
    {"to": "/studies", "label": "Studies"},
    {"to": "/sessions", "label": "Sessions"},
    {"to": "/participants", "label": "Participants"}
];

def:pub AppShell(children: any = None) -> JsxElement {
    location: any = useLocation();
    nav = useNavigate();
    path = str(location.pathname);

    def is_active(target: str) -> bool {
        if target == "/" {
            return path == "/";
        }
        return path.startswith(target);
    }

    def sign_out(e: MouseEvent) {
        e.preventDefault();
        jacLogout();
        nav("/login");
    }

    return
        <div className="shell">
            <nav className="rail-nav" aria-label="Main">
                <Link to="/" className="brand">
                    <BrandMark/>
                    <span className="brand-name">Handshake</span>
                </Link>
                {for item in NAV {
                    <Link
                        key={item["to"]}
                        to={item["to"]}
                        className={"nav-link active" if is_active(item["to"]) else "nav-link"}
                        aria-current={"page" if is_active(item["to"]) else None}
                    >
                        {item["label"]}
                    </Link>
                }}
                <div className="nav-foot">
                    <a href="/docs" target="_blank" rel="noreferrer">API reference</a>
                    <button className="btn quiet small" onClick={sign_out}>Sign out</button>
                </div>
            </nav>
            <main className="main">
                <ErrorBoundary FallbackComponent={PageError} resetKeys={[path]}>
                    {children}
                </ErrorBoundary>
            </main>
        </div>;
}

"""Shown instead of a page that crashed, with the real error so it can be reported.

The runtime's own fallback (jaclang 0.16.7) dereferences the error wrongly and
hides the original message, so every page gets this boundary instead.
"""
def:pub PageError(error: any = None, resetErrorBoundary: any = None) -> JsxElement {
    message = str(error.message) if error else "Unknown error";
    stack = str(error.stack) if error and error.stack else "";
    return
        <div className="panel stack" role="alert">
            <h2>This page hit an error</h2>
            <p className="muted">Nothing was lost on the server. Try again, and if it repeats, include the details below in a bug report.</p>
            <pre className="block">{message}{chr(10)}{stack[:1200]}</pre>
            <div className="row">
                <button className="btn primary" onClick={lambda e: MouseEvent { resetErrorBoundary(); }}>Try again</button>
            </div>
        </div>;
}
