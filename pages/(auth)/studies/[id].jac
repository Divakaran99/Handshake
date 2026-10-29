cl import from ....components.AppShell { AppShell }
cl import from ....components.StudyPage { StudyPage }

cl {
    def:pub page -> JsxElement {
        return <AppShell><StudyPage/></AppShell>;
    }
}
