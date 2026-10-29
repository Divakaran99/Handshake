cl import from ...components.AppShell { AppShell }
cl import from ...components.ParticipantsPage { ParticipantsPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><ParticipantsPage/></AppShell>;
    }
}
