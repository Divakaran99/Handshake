cl import from ....components.AppShell { AppShell }
cl import from ....components.SessionsPage { SessionsPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><SessionsPage/></AppShell>;
    }
}
