"""Adapter for robots that expose their own REST API.

Many social robots ship an HTTP interface next to (or instead of) ROS. A
binding names a method and a path; `query` and `body` are templates rendered
from the step arguments:

    "SPEAK": {"op": "http", "method": "POST", "path": "/api/speak",
              "body": {"text": "{text}"}}

The adapter reports ok for any 2xx response and records the decoded JSON
body (when there is one) as the achieved values. HTTP robots have no
perception channel here, so percept branches fall through to their timeout.

Interop boundary: only the standard library (`urllib.request`) is used.
"""

import json;
import from urllib.request { Request, urlopen }
import from urllib.error { HTTPError, URLError }
import from urllib.parse { urlencode }
import from domain.capability { CapabilityCall, CapabilityResult }
import from adapters.adapter { ProbeReport }
import from adapters.bindings { Binding, render, as_dict }
import from adapters.bound { BoundAdapter, check_host, now_ms }

obj HttpAdapter(BoundAdapter) {
    has url: str = "http://localhost:8080",
        headers: dict[str, str] = {};

    def endpoint(path: str, query: object) -> str {
        base = self.url.rstrip("/");
        full = base + ("" if path.startswith("/") else "/") + path;
        params = as_dict(query);
        if len(params) > 0 {
            full = full + "?" + urlencode({k: str(v) for (k, v) in params.items()});
        }
        return full;
    }

    """Perform one request; returns (status, decoded body or text)."""
    def request(method: str, url: str, body: object, timeout_s: float) -> tuple[int, object] {
        check_host(url);
        data: bytes | None = None;
        hdrs: dict[str, str] = {"Accept": "application/json"};
        hdrs.update(self.headers);
        if body is not None {
            data = json.dumps(body).encode("utf-8");
            hdrs["Content-Type"] = "application/json";
        }
        req = Request(url, data=data, method=method, headers=hdrs);
        text: str = "";
        status: int = 0;
        try {
            resp = urlopen(req, timeout=timeout_s);
            try {
                text = str(resp.read().decode("utf-8", "replace"));
                status = int(resp.status);
            } finally {
                resp.close();
            }
        } except HTTPError as e {
            return (int(e.code), e.read().decode("utf-8", "replace"));
        }
        try {
            return (status, json.loads(text) if text.strip() != "" else None);
        } except ValueError {
            return (status, text);
        }
    }

    override def dispatch(b: Binding, args: dict[str, object], call: CapabilityCall) -> CapabilityResult {
        res = CapabilityResult(ok=False, capability=call.capability);
        query = render(b.query, args) if b.query is not None else None;
        body = render(b.template, args) if b.template is not None else None;
        target = self.endpoint(b.target, query);
        res.wire = {"method": b.method, "url": target, "body": body};
        try {
            (status, payload) = self.request(b.method, target, body,
                                             max(0.5, call.timeout_ms / 1000.0));
        } except URLError as e {
            res.detail = f"robot unreachable: {str(e.reason)}";
            return res;
        }
        res.ok = 200 <= status and status < 300;
        decoded = as_dict(payload);
        res.achieved = decoded if len(decoded) > 0 else {"http_status": status};
        res.detail = f"HTTP {status}" if res.ok else f"HTTP {status}: {str(payload)[:200]}";
        return res;
    }

    override def probe -> ProbeReport {
        report_ = ProbeReport(ok=False, profile=self.profile_name, kind="http",
                              capabilities=self.capability_summary());
        target = self.endpoint(self.table.probe_path or "/", None);
        t0 = now_ms();
        try {
            (status, _payload) = self.request("GET", target, None, 4.0);
            report_.latency_ms = now_ms() - t0;
            report_.ok = status < 500;
            report_.detail = f"GET {target} -> HTTP {status}";
            if status >= 400 {
                report_.warnings.append(
                    "the robot answered but not with 2xx; set \"_probe\" in bindings to a health path"
                );
            }
        } except Exception as e {
            report_.detail = f"could not reach {target}: {type(e).__name__}: {str(e)}";
        }
        return report_;
    }
}
