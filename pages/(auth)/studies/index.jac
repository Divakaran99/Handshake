cl import from ....components.AppShell { AppShell }
cl import from ....components.StudiesPage { StudiesPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><StudiesPage/></AppShell>;
    }
}
