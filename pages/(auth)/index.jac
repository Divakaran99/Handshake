cl import from ...components.AppShell { AppShell }
cl import from ...components.OverviewPage { OverviewPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><OverviewPage/></AppShell>;
    }
}
