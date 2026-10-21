cl import from ...components.AppShell { AppShell }
cl import from ...components.RobotsPage { RobotsPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><RobotsPage/></AppShell>;
    }
}
