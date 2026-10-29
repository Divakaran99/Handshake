cl import from ....components.AppShell { AppShell }
cl import from ....components.SessionPage { SessionPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><SessionPage/></AppShell>;
    }
}
