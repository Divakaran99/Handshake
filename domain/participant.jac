"""Participants are pseudonymous. No direct identifiers ever enter the graph."""

node Participant {
    has code: str,
        enrolled_at: str = "",
        notes: str = "";
}

node ConsentRecord {
    has scope: str,
        granted_at: str = "",
        revoked_at: str = "";

    def active -> bool {
        return self.granted_at != "" and self.revoked_at == "";
    }
}

edge Consented: Participant --> ConsentRecord {}
