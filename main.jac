"""Handshake - application entry point.

    jac start main.jac            # API + web app on http://localhost:8000
    jac start main.jac --dev      # same, with hot reload for the UI

Server side: every endpoint is imported here so it is served even when no
page references it (REST clients, lab scripts, notebooks). All of them live in
api/ and are def:priv - each researcher works on their own isolated graph.

Client side: pages/ is the router (file-based routing); components/ holds the
UI. See docs/BUILD_GUIDE.md for the full tour.
"""

import from api.robots {
    list_robots, get_robot, robot_presets, check_robot, save_robot, delete_robot,
    test_robot
}
import from api.studies {
    list_studies, create_study, update_study, delete_study, get_study,
    save_condition, delete_condition, capability_catalog, create_example_study
}
import from api.sessions {
    run_session, list_sessions, get_session, delete_session, export_events,
    godspeed_instrument, record_godspeed, list_participants, withdraw_participant,
    dashboard
}

cl import "./assets/global.css";

cl {
    import from .components.runtime_fixes { READ_CACHE_DISABLED }

    def:pub app(children: any = None) -> JsxElement {
        return <>{children}</>;
    }
}
