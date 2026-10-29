cl import from "@jac/runtime" { Link }

cl {
    def:pub page -> JsxElement {
        return
            <div className="main">
                <h1>Page not found</h1>
                <p className="muted" style={{"margin": "12px 0 20px"}}>This address does not exist in Handshake.</p>
                <Link className="btn" to="/">Go to the overview</Link>
            </div>;
    }
}
