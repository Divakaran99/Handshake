"""Sign in / create an account. Each account is one researcher's private lab."""

import from "@jac/runtime" { useNavigate, jacLogin, jacSignup }
import from .ui { BrandMark }

def:pub LoginPage -> JsxElement {
    has mode: str = "signin",
        username: str = "",
        password: str = "",
        error: str = "",
        busy: bool = False;

    nav = useNavigate();

    async def submit(e: FormEvent) {
        e.preventDefault();
        error = "";
        if username.strip() == "" or len(password) < 8 {
            error = "Enter a username and a password of at least 8 characters.";
            return;
        }
        busy = True;
        signup_result: dict | None = None;
        ok: bool = False;
        try {
            if mode == "signup" {
                signup_result = await jacSignup(username.strip(), password);
                if not signup_result["success"] {
                    error = "That username is taken. Sign in instead, or pick another.";
                    busy = False;
                    return;
                }
            }
            ok = await jacLogin(username.strip(), password);
            if ok {
                nav("/");
            } else {
                error = "Username or password is incorrect.";
            }
        } except Exception {
            error = "The Handshake server did not answer. Is `jac start` running?";
        }
        busy = False;
    }

    def switch_mode(e: MouseEvent) {
        e.preventDefault();
        mode = "signup" if mode == "signin" else "signin";
        error = "";
    }

    return
        <div className="auth">
            <section className="auth-side">
                <div className="row">
                    <BrandMark/>
                    <span className="brand-name">Handshake</span>
                </div>
                <div>
                    <h1>Design a study once. Run it on any robot.</h1>
                    <p>
                        Connect a simulator, a ROS 1 or ROS 2 robot, or anything with an HTTP API,
                        author your protocol against capabilities, and get a dataset with commanded
                        and achieved behaviour for every step.
                    </p>
                </div>
                <ol className="rail numbered auth-rail" aria-label="An example protocol">
                    <li className="station"><span className="mono">SPEAK</span> greet the participant</li>
                    <li className="station"><span className="mono">APPROACH</span> stop at 0.8 m</li>
                    <li className="station">
                        <span className="mono">GAZE</span> look at their face
                        <span className="spur" style={{"marginLeft": "10px"}}>when gaze is returned, smile</span>
                    </li>
                    <li className="station end-station"><span className="mono">SPEAK</span> thank them</li>
                </ol>
                <p className="small muted">Your robots, studies and participant data stay in your own account.</p>
            </section>
            <form className="auth-form" onSubmit={submit}>
                <h2>{"Sign in" if mode == "signin" else "Create your account"}</h2>
                <label className="field">
                    <span>Username</span>
                    <input className="input" autoComplete="username" value={username}
                        onChange={lambda e: ChangeEvent { username = e.target.value; }}/>
                </label>
                <label className="field">
                    <span>Password</span>
                    <input className="input" type="password"
                        autoComplete={"current-password" if mode == "signin" else "new-password"}
                        value={password}
                        onChange={lambda e: ChangeEvent { password = e.target.value; }}/>
                    {mode == "signup" and <small>At least 8 characters.</small>}
                </label>
                {error and <div className="notice error" role="alert">{error}</div>}
                <button className="btn primary" type="submit" disabled={busy}>
                    {("Signing in…" if mode == "signin" else "Creating account…") if busy else ("Sign in" if mode == "signin" else "Create account")}
                </button>
                <p className="small muted">
                    {"New to this server? " if mode == "signin" else "Already have an account? "}
                    <a href="#" onClick={switch_mode}>{"Create an account" if mode == "signin" else "Sign in"}</a>
                </p>
            </form>
        </div>;
}
