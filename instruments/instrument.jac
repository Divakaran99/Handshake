"""Typed measurement instruments.

A scale is data, not a form. Because it is typed, a response can be joined to a
session and scored without anyone re-keying a spreadsheet.
"""

obj ScaleItem {
    has key: str,
        anchor_low: str,
        anchor_high: str,
        reverse: bool = False;
}

obj Scale {
    has name: str,
        citation: str = "",
        points: int = 5,
        items: list[ScaleItem] = [];

    def item_keys -> list[str] {
        return [it.key for it in self.items];
    }

    def score(responses: dict[str, int]) -> float {
        total: int = 0;
        n: int = 0;
        for it in self.items {
            if it.key in responses {
                v: int = responses[it.key];
                if it.reverse {
                    v = (self.points + 1) - v;
                }
                total += v;
                n += 1;
            }
        }
        if n == 0 {
            return 0.0;
        }
        return total / n;
    }
}
