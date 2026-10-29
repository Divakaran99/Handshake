"""Client-runtime settings applied once, when the bundle loads.

jaclang 0.16.7 classifies endpoint side effects only for `def:pub` functions.
Every `def:priv` endpoint therefore defaults to "reader", and the client would
serve repeat calls (run_session, test_robot, get_session after an edit) from a
60-second cache. Handshake's endpoints are all private, so the read cache is
turned off here; identical concurrent calls are still de-duplicated.
"""

def _disable_read_cache -> bool {
    g: any = globalThis;
    if not g.__jacCacheState__ {
        g.__jacCacheState__ = {
            "cache": {},
            "order": [],
            "pending": {},
            "config": {"maxEntries": 500, "defaultTtlMs": 0}
        };
    } else {
        g.__jacCacheState__.config.defaultTtlMs = 0;
    }
    return True;
}

glob READ_CACHE_DISABLED: bool = _disable_read_cache();
