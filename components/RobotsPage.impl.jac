"""Handlers for RobotsPage. `has` state is read and written bare."""

impl RobotsPage.load(select_first: bool) {
    fetched: list[RobotView] = [];
    fetched = await list_robots();
    robots = fetched;
    if len(presets) == 0 {
        presets = await robot_presets();
    }
    loaded = True;
    if select_first and len(fetched) > 0 and not editing {
        open_robot(fetched[0]);
    }
}

impl RobotsPage.open_robot(r: RobotView) {
    selected_id = r.id;
    editing = True;
    f_name = r.name;
    f_kind = r.kind;
    f_url = r.url;
    f_ros = r.ros_version;
    f_bindings = r.bindings_json;
    f_percepts = r.percepts_json;
    f_notes = r.notes;
    rows = r.capabilities;
    problems = r.problems;
    probe = None;
    saved_note = "";
    preset_note = "";
}

impl RobotsPage.start_new(preset_key: str) {
    for p in presets {
        if p.key == preset_key {
            selected_id = "";
            editing = True;
            f_name = "";
            f_kind = p.kind;
            f_url = p.url;
            f_ros = p.ros_version;
            f_bindings = p.bindings_json;
            f_percepts = p.percepts_json;
            f_notes = "";
            preset_note = p.summary;
            rows = [];
            problems = [];
            probe = None;
            saved_note = "";
        }
    }
    recheck();
}

impl RobotsPage.make_draft -> RobotDraft {
    return robot_draft(selected_id, f_name, f_kind, f_url, f_ros, f_bindings,
                       f_percepts, f_notes);
}

impl RobotsPage.recheck {
    draft = make_draft();
    checked: RobotView | None = None;
    checked = await check_robot(draft);
    if checked is not None {
        rows = checked.capabilities;
        found: list[str] = checked.problems;
        problems = [p for p in found if p != "name is required"];
    }
}

impl RobotsPage.save {
    busy = "save";
    saved_note = "";
    draft = make_draft();
    result: SaveResult | None = None;
    result = await save_robot(draft);
    busy = "";
    if result is None {
        return;
    }
    if not result.ok {
        problems = result.problems;
        return;
    }
    problems = [];
    selected_id = result.id;
    saved_note = "Saved. Run a study on it from the study page.";
    await load(False);
}

impl RobotsPage.remove {
    if not confirm_action(f"Delete the robot profile '{f_name}'? Sessions already run on it are kept.") {
        return;
    }
    robot_id = selected_id;
    busy = "delete";
    await delete_robot(robot_id);
    busy = "";
    editing = False;
    selected_id = "";
    await load(True);
}

impl RobotsPage.run_probe {
    busy = "probe";
    probe = None;
    draft = make_draft();
    report_: ProbeView | None = None;
    report_ = await test_robot(draft);
    probe = report_;
    if report_ is not None and len(report_.capabilities) > 0 {
        rows = report_.capabilities;
    }
    busy = "";
}
