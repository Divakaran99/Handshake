"""Handlers for StudyPage. `has` state is read and written bare.

Step edits mutate the StepSpec in place and then rebind `steps` to a new list,
which is what tells React to re-render.
"""

impl StudyPage.reload(select_label: str) {
    study_id = page_id;
    got: StudyDetail | None = None;
    got = await get_study(study_id);
    if got is None {
        missing = True;
        return;
    }
    detail = got;
    m_title = got.study.title;
    m_version = got.study.version;
    m_prereg = got.study.prereg;
    if len(catalog) == 0 {
        catalog = await capability_catalog();
    }
    fetched_robots: list[RobotView] = [];
    fetched_robots = await list_robots();
    robots = fetched_robots;
    if run_robot == "" and len(fetched_robots) > 0 {
        run_robot = fetched_robots[0].id;
    }
    sessions = await list_sessions(study_id);
    wanted = select_label or cond_original;
    opened = False;
    for c in got.conditions {
        if c.label == wanted or (wanted == "" and not opened) {
            open_condition(c);
            opened = True;
        }
    }
}

impl StudyPage.open_condition(c: ConditionSpec) {
    cond_original = c.label;
    cond_label = c.label;
    cond_factors = c.factors_json;
    steps = [copy_step(s) for s in c.steps];
    dirty = False;
    cond_problems = [];
    cond_note = "";
    run_choices = {};
}

impl StudyPage.new_condition(copy_current: bool) {
    taken: list[str] = [];
    d = detail;
    if d is not None {
        conds: list[ConditionSpec] = d.conditions;
        taken = [c.label for c in conds];
    }
    if copy_current {
        cond_label = _unique_label(cond_label + "_copy", taken);
        steps = [copy_step(s) for s in steps];
    } else {
        cond_label = _unique_label("condition", taken);
        cond_factors = "{}";
        steps = [step_spec("greet", "SPEAK", "{\"text\": \"Hello, thanks for joining the study.\"}")];
    }
    cond_original = "";
    dirty = True;
    cond_problems = [];
    cond_note = "";
}

impl StudyPage.set_field(i: int, key: str, value: str) {
    s = steps[i];
    if key == "label" {
        old = s.label;
        for other in steps {
            if other.next == old and old != "" {
                other.next = value;
            }
            for b in other.branches {
                if b.target == old and old != "" {
                    b.target = value;
                }
            }
        }
        s.label = value;
    } elif key == "capability" {
        old_example = "{}";
        new_example = "{}";
        for c in catalog {
            if c.name == s.capability {
                old_example = c.example_args;
            }
            if c.name == value {
                new_example = c.example_args;
            }
        }
        if s.args_json.strip() in ["", "{}", old_example] {
            s.args_json = new_example;
        }
        s.capability = value;
    } elif key == "args_json" {
        s.args_json = value;
    } elif key == "timeout_ms" {
        s.timeout_ms = int(value or "0");
    } elif key == "next" {
        s.next = value;
    }
    steps = [x for x in steps];
    dirty = True;
}

impl StudyPage.add_step(after: int) {
    taken = [s.label for s in steps];
    fresh = step_spec(_unique_label("step", taken), "IDLE", "{\"hold_ms\": 1000}");
    steps = steps[: after + 1] + [fresh] + steps[after + 1 :];
    dirty = True;
}

impl StudyPage.remove_step(i: int) {
    gone = steps[i].label;
    kept = [s for (k, s) in enumerate(steps) if k != i];
    for s in kept {
        if s.next == gone {
            s.next = "";
        }
        s.branches = [b for b in s.branches if b.target != gone];
    }
    steps = kept;
    dirty = True;
}

impl StudyPage.move_step(i: int, delta: int) {
    j = i + delta;
    if j < 0 or j >= len(steps) {
        return;
    }
    moved = [x for x in steps];
    tmp = moved[i];
    moved[i] = moved[j];
    moved[j] = tmp;
    steps = moved;
    dirty = True;
}

impl StudyPage.add_branch(i: int) {
    s = steps[i];
    s.branches = s.branches + [branch_spec("", "")];
    steps = [x for x in steps];
    dirty = True;
}

impl StudyPage.set_branch(i: int, j: int, key: str, value: str) {
    b = steps[i].branches[j];
    if key == "percept" {
        b.percept = value;
    } else {
        b.target = value;
    }
    steps = [x for x in steps];
    dirty = True;
}

impl StudyPage.remove_branch(i: int, j: int) {
    s = steps[i];
    s.branches = [b for (k, b) in enumerate(s.branches) if k != j];
    steps = [x for x in steps];
    dirty = True;
}

impl StudyPage.bump_version {
    parts: list[str] = m_version.split(".");
    last = parts[len(parts) - 1];
    if last.isdigit() {
        head: list[str] = parts[: len(parts) - 1];
        m_version = join_text(head + [str(int(last) + 1)], ".");
    } else {
        m_version = m_version + ".1";
    }
}

impl StudyPage.save_meta {
    study_id = page_id;
    draft = study_draft(m_title, m_version, m_prereg);
    busy = "meta";
    result: SaveResult | None = None;
    result = await update_study(study_id, draft);
    busy = "";
    meta_note = "";
    if result is not None and not result.ok {
        meta_problems = result.problems;
        return;
    }
    meta_problems = [];
    meta_note = "Saved.";
    await reload(cond_original);
}

impl StudyPage.save_cond {
    study_id = page_id;
    spec = condition_spec(cond_label, cond_factors, steps);
    original_label = cond_original;
    busy = "cond";
    result: SaveResult | None = None;
    result = await save_condition(study_id, spec, original_label);
    busy = "";
    cond_note = "";
    if result is not None and not result.ok {
        cond_problems = result.problems;
        return;
    }
    cond_problems = [];
    saved_as = cond_label.strip();
    cond_original = saved_as;
    await reload(saved_as);
    cond_note = "Condition saved. Run it below.";
}

impl StudyPage.remove_cond {
    if not confirm_action(f"Delete the condition '{cond_original}'?") {
        return;
    }
    study_id = page_id;
    label = cond_original;
    busy = "cond";
    await delete_condition(study_id, label);
    busy = "";
    cond_original = "";
    cond_label = "";
    steps = [];
    await reload("");
}

impl StudyPage.remove_study {
    if not confirm_action("Delete this study and its protocol? Studies that already have sessions are kept.") {
        return;
    }
    study_id = page_id;
    result: SaveResult | None = None;
    result = await delete_study(study_id);
    if result is not None and result.ok {
        nav("/studies");
    } elif result is not None {
        meta_problems = result.problems;
    }
}

impl StudyPage.run {
    study_id = page_id;
    choices_list = [percept_choice(k, v) for (k, v) in run_choices.items() if v != ""];
    req = run_request(study_id, cond_original, run_robot, run_participant.strip(),
                      run_consent, choices_list);
    busy = "run";
    run_result = None;
    outcome: RunResult | None = None;
    try {
        outcome = await run_session(req);
    } except Exception as e {
        outcome = failed_run("The server did not finish the run: " + str(e));
    }
    run_result = outcome;
    busy = "";
    await reload(cond_original);
}
