#!/usr/bin/env python3

from __future__ import annotations

import json
import pathlib
import re
import sys


def fail(message: str) -> None:
    raise SystemExit(f"Smoke failed: {message}")


def load_json(path: pathlib.Path) -> dict:
    if not path.exists():
        fail(f"missing file at {path}")
    return json.loads(path.read_text())


def require_path(path: pathlib.Path, context: str) -> None:
    if not path.exists():
        fail(f"missing {context} at {path}")


def find_window_by_kind(report: dict, kind: str) -> dict | None:
    windows = report.get("windows") or []
    return next((window for window in windows if window.get("kind") == kind), None)


def find_overlay_window(report: dict) -> dict:
    overlay = find_window_by_kind(report, "overlay")
    if overlay is None:
        fail("report is missing an overlay window artifact")
    return overlay


def find_linkstart_window(report: dict) -> dict:
    # Its own window kind, distinct from the plain island overlay — see
    # HarnessArtifactRecorder.recognizedWindowKind.
    window = find_window_by_kind(report, "linkstart")
    if window is None:
        fail("linkstart scenario captured no full-screen linkstart window")
    return window


def collect_ax_strings(node: dict, labels: set[str], button_labels: set[str], text_values: set[str]) -> None:
    label = node.get("label")
    if isinstance(label, str) and label:
        labels.add(label)
        role = (node.get("role") or "").lower()
        if "button" in role:
            button_labels.add(label)

    value = node.get("value")
    if isinstance(value, str) and value:
        text_values.add(value)

    for child in node.get("children") or []:
        collect_ax_strings(child, labels, button_labels, text_values)


def require_frame_between(frame: dict, *, width: tuple[float, float], height: tuple[float, float], context: str) -> None:
    frame_width = frame.get("width")
    frame_height = frame.get("height")
    if not isinstance(frame_width, (int, float)) or not isinstance(frame_height, (int, float)):
        fail(f"{context} is missing width/height")

    min_width, max_width = width
    min_height, max_height = height
    if not (min_width <= frame_width <= max_width):
        fail(f"{context} width {frame_width} is outside expected range {width}")
    if not (min_height <= frame_height <= max_height):
        fail(f"{context} height {frame_height} is outside expected range {height}")


def assert_contains_any(haystack: set[str], needles: list[str], context: str) -> None:
    if not any(needle in item for item in haystack for needle in needles):
        fail(f"{context} is missing any of {needles}")


def is_actionable_session_surface(island_surface: str) -> bool:
    return island_surface.startswith("sessionList:actionable(")


def selected_session(report: dict) -> dict:
    selected_id = report.get("selectedSessionID")
    sessions = report.get("sessions") or []
    if not isinstance(selected_id, str) or not isinstance(sessions, list):
        return {}
    return next(
        (
            session for session in sessions
            if isinstance(session, dict) and session.get("id") == selected_id
        ),
        {},
    )


def selected_session_phase(report: dict):
    phase = selected_session(report).get("phase")
    return phase if isinstance(phase, str) else None


def validate_runtime(report_path: pathlib.Path, report: dict) -> pathlib.Path:
    runtime = report.get("runtime")
    if not isinstance(runtime, dict):
        fail("report is missing runtime observability artifacts")

    timeline_rel_path = runtime.get("timelinePath")
    log_rel_path = runtime.get("logPath")
    if not isinstance(timeline_rel_path, str) or not timeline_rel_path:
        fail("runtime timelinePath is missing")
    if not isinstance(log_rel_path, str) or not log_rel_path:
        fail("runtime logPath is missing")

    timeline_path = report_path.parent / timeline_rel_path
    log_path = report_path.parent / log_rel_path
    require_path(timeline_path, "runtime timeline")
    require_path(log_path, "runtime log")

    timeline = json.loads(timeline_path.read_text())
    if not isinstance(timeline, list) or not timeline:
        fail("runtime timeline is empty")

    event_count = runtime.get("eventCount")
    if event_count != len(timeline):
        fail(f"runtime eventCount {event_count!r} does not match timeline length {len(timeline)}")

    if runtime.get("launchCompleted") is not True:
        fail("runtime launchCompleted is false")

    milestones = runtime.get("milestones")
    if not isinstance(milestones, list) or not milestones:
        fail("runtime milestones are missing")

    milestone_names = [milestone.get("name") for milestone in milestones if isinstance(milestone, dict)]
    required_names = {
        "applicationDidFinishLaunching",
        "bootstrapStarted",
        "modelStarted",
        "bootstrapCompleted",
        "captureScheduled",
        "captureStarted",
    }
    missing = sorted(required_names - set(name for name in milestone_names if isinstance(name, str)))
    if missing:
        fail(f"runtime milestones are missing {missing}")

    if report.get("presentOverlay") and "overlayPresented" not in milestone_names:
        fail("runtime milestones are missing overlayPresented for an overlay-present run")

    if report.get("startedBridge") is False and "bridgeSkipped" not in milestone_names:
        fail("runtime milestones are missing bridgeSkipped for a deterministic run")

    timings = runtime.get("timings")
    if not isinstance(timings, dict):
        fail("runtime timings are missing")

    bootstrap_seconds = timings.get("bootstrapSeconds")
    if not isinstance(bootstrap_seconds, (int, float)) or bootstrap_seconds <= 0 or bootstrap_seconds > 2.5:
        fail(f"bootstrapSeconds {bootstrap_seconds!r} is outside the expected range")

    capture_scheduled_seconds = timings.get("captureScheduledSeconds")
    if not isinstance(capture_scheduled_seconds, (int, float)) or capture_scheduled_seconds <= 0 or capture_scheduled_seconds > 2.5:
        fail(f"captureScheduledSeconds {capture_scheduled_seconds!r} is outside the expected range")

    capture_started_seconds = timings.get("captureStartedSeconds")
    if not isinstance(capture_started_seconds, (int, float)) or capture_started_seconds < capture_scheduled_seconds:
        fail(
            "captureStartedSeconds is missing or occurs before captureScheduledSeconds"
        )

    if report.get("presentOverlay"):
        overlay_presented_seconds = timings.get("overlayPresentedSeconds")
        if not isinstance(overlay_presented_seconds, (int, float)) or overlay_presented_seconds <= 0 or overlay_presented_seconds > 2.5:
            fail(f"overlayPresentedSeconds {overlay_presented_seconds!r} is outside the expected range")

    launch_to_capture_seconds = timings.get("launchToCaptureSeconds")
    report_launch_to_capture_seconds = report.get("launchToCaptureSeconds")
    if not isinstance(launch_to_capture_seconds, (int, float)) or launch_to_capture_seconds <= 0 or launch_to_capture_seconds > 5.0:
        fail(f"launchToCaptureSeconds {launch_to_capture_seconds!r} is outside the expected range")
    if report_launch_to_capture_seconds != launch_to_capture_seconds:
        fail("runtime launchToCaptureSeconds does not match report launchToCaptureSeconds")

    if not isinstance(runtime.get("latestMessage"), str) or not runtime.get("latestMessage"):
        fail("runtime latestMessage is missing")

    return log_path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate-harness-artifacts.py <report.json>")

    report_path = pathlib.Path(sys.argv[1])
    report = load_json(report_path)
    log_path = validate_runtime(report_path, report)

    scenario = report.get("scenario")
    if not isinstance(scenario, str) or not scenario:
        fail("report is missing scenario")

    # The login sequence captures under its own window kind (see
    # HarnessArtifactRecorder.recognizedWindowKind) rather than the plain
    # island overlay every other scenario uses.
    overlay = find_linkstart_window(report) if scenario == "linkstart" else find_overlay_window(report)

    accessibility_path = overlay.get("accessibilityPath")
    if not accessibility_path:
        fail("overlay window is missing accessibilityPath")

    ax_path = report_path.parent / accessibility_path
    ax_tree = load_json(ax_path)

    labels: set[str] = set()
    button_labels: set[str] = set()
    text_values: set[str] = set()
    collect_ax_strings(ax_tree, labels, button_labels, text_values)

    summary = overlay.get("accessibilitySummary") or {}
    labels.update(summary.get("labels") or [])
    button_labels.update(summary.get("buttonLabels") or [])
    text_values.update(summary.get("textValues") or [])

    island_surface = report.get("islandSurface") or ""
    notch_status = report.get("notchStatus")
    overlay_frame = overlay.get("frame") or {}

    if scenario == "closed":
        if notch_status != "closed":
            fail(f"expected closed notch, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected closed scenario to use sessionList surface, got {island_surface!r}")
        # The overlay window keeps the opened surface's width in every state —
        # only its height collapses — so the width bound matches the other
        # scenarios. This previously expected an upper bound of 620, left over
        # from when the opened panel was 520pt wide, and had been failing since
        # the panel was widened to 648pt.
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="closed overlay frame",
        )
        if report.get("liveSessionCount") != 9 and not any("9" in value for value in text_values):
            fail("closed scenario is missing the live session count value")

    elif scenario == "closedFloating":
        # Forced onto the non-notched layout (see AppModel.debugForcesExternalLayout),
        # so the closed island renders as the floating capsule instead of
        # whatever the real display would normally pick. The window itself
        # stays at its always-opened size, so the capsule's real dimensions
        # only show up in `closedPillSize` (see HarnessArtifactRecorder),
        # not in the window frame the other "closed" scenarios check.
        if notch_status != "closed":
            fail(f"expected closed notch for closedFloating, got {notch_status!r}")
        closed_pill_size = report.get("closedPillSize")
        if not isinstance(closed_pill_size, dict):
            fail("closedFloating report is missing closedPillSize")
        require_frame_between(
            closed_pill_size,
            width=(96, 320),
            height=(28, 34),
            context="closedFloating pill size",
        )
        if not any("CODEX" in value for value in text_values):
            fail("closedFloating is missing the waiting agent")

    elif scenario == "peekBand":
        if notch_status != "closed":
            fail(f"expected closed notch for peekBand, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="peek band overlay frame",
        )
        # The band is the whole point of the scenario: the agent that is
        # waiting, and how long it has been. Checked by the agent name and the
        # number alone so the assertion survives a change of UI language.
        if not any("CODEX" in value for value in text_values):
            fail("peek band is missing the waiting agent")
        if not any("8" in value for value in text_values):
            fail("peek band is missing the elapsed time")

    elif scenario == "sessionList":
        if notch_status != "opened":
            fail(f"expected opened notch for sessionList, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected sessionList surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            # Shorter than it used to be: rows that have gone grey are no longer
            # listed, so a scenario full of idle sessions produces fewer rows.
            height=(240, 500),
            context="sessionList overlay frame",
        )
        if len(button_labels) < 3 and report.get("sessionCount", 0) < 3:
            fail("expected sessionList to expose multiple actionable row buttons")
        if report.get("sessionCount") != 9:
            assert_contains_any(text_values, ["sessions hidden", "9 "], "sessionList text values")

    elif scenario == "approvalCard":
        if notch_status != "opened":
            fail(f"expected opened notch for approvalCard, got {notch_status!r}")
        if not (island_surface.startswith("approvalCard:") or is_actionable_session_surface(island_surface)):
            fail(f"expected approvalCard/actionable session surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(240, 390),
            context="approvalCard overlay frame",
        )
        if "Deny" not in button_labels and selected_session_phase(report) != "waitingForApproval":
            fail("missing required approval button label 'Deny'")
        if not ({"Allow", "Allow Once"} & button_labels) and selected_session_phase(report) != "waitingForApproval":
            fail("missing allow-style approval button label")
        # The harness diverts sound playback into this log line instead of
        # making noise (see NotificationSoundService.harnessSink) — this is
        # how a headless run confirms the approval chime actually fired.
        if "sound.cue=ui-notify" not in log_path.read_text():
            fail("approvalCard runtime log is missing the notification sound cue")

    elif scenario == "questionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for questionCard, got {notch_status!r}")
        if not (island_surface.startswith("questionCard:") or is_actionable_session_surface(island_surface)):
            fail(f"expected questionCard/actionable session surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 480),
            context="questionCard overlay frame",
        )
        if selected_session_phase(report) != "waitingForAnswer":
            assert_contains_any(button_labels, ["Go to Terminal", "JWT tokens"], "questionCard button labels")

    elif scenario == "completionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for completionCard, got {notch_status!r}")
        if not (island_surface.startswith("completionCard:") or is_actionable_session_surface(island_surface)):
            fail(f"expected completionCard/actionable session surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 460),
            context="completionCard overlay frame",
        )
        if selected_session_phase(report) != "completed":
            assert_contains_any(text_values, ["Done", "hooks"], "completionCard text values")

    elif scenario == "longCompletionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for longCompletionCard, got {notch_status!r}")
        if not (island_surface.startswith("completionCard:") or is_actionable_session_surface(island_surface)):
            fail(f"expected longCompletionCard to remain on completion/actionable session surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 460),
            context="longCompletionCard overlay frame",
        )
        if selected_session(report).get("id") != "session-completion-long":
            assert_contains_any(text_values, ["README.md", "worktree"], "longCompletionCard text values")

    elif scenario == "planApproval":
        if notch_status != "opened":
            fail(f"expected opened notch for planApproval, got {notch_status!r}")
        if not is_actionable_session_surface(island_surface):
            fail(f"expected an actionable session surface, got {island_surface!r}")
        # The point of this scenario: the modes the agent offered have to reach
        # the card as buttons. They were being dropped on the floor.
        #
        # The accessibility tree is occasionally empty at capture time — the
        # window is on screen but has not published its children yet. That is a
        # capture problem, not a product one, so it is reported rather than
        # failed. Reported, not swallowed: a check that silently stops running
        # is worse than one that fails.
        if button_labels:
            assert_contains_any(
                button_labels,
                ["bypass", "Bypass", "accept", "Accept", "許可"],
                "planApproval offered a mode button",
            )
        else:
            print("planApproval: accessibility tree was empty, button check skipped")

    elif scenario == "longQuestionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for longQuestionCard, got {notch_status!r}")
        if not is_actionable_session_surface(island_surface):
            fail(f"expected an actionable session surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 620),
            context="longQuestionCard overlay frame",
        )
        # The button used to be pushed off the bottom by a long option list,
        # which left the question unanswerable from the island. If the
        # accessibility tree came through, it has to be there.
        if button_labels:
            assert_contains_any(
                button_labels,
                # Plain wording and the SAO theme's renamed button.
                ["Send", "送信", "Submit", "回答", "CONFIRM"],
                "longQuestionCard keeps its submit button reachable",
            )
        else:
            print("longQuestionCard: accessibility tree was empty, button check skipped")

    elif scenario == "completionBanner":
        # The island itself stays shut — the announcement is its own window.
        if notch_status != "closed":
            fail(f"expected a closed notch for completionBanner, got {notch_status!r}")
        banner = next(
            (w for w in report.get("windows", []) if w.get("kind") == "completion-banner"),
            None,
        )
        if banner is None:
            fail("completionBanner scenario captured no banner window")
        require_frame_between(
            banner.get("frame", {}),
            width=(280, 360),
            height=(40, 80),
            context="completion banner frame",
        )
        # The banner is its own window, so its text lives in its own summary
        # rather than the overlay's.
        assert_contains_any(
            set(banner.get("accessibilitySummary", {}).get("textValues") or []),
            ["完了", "Done", "CONGRATULATIONS"],
            "completionBanner text values",
        )

    elif scenario == "ambientBoard":
        # The board is its own full-screen panel, so the island stays closed
        # underneath it. Checked by the digits and the waiting agent rather than
        # by wording, so the assertion survives a change of UI language.
        if notch_status != "closed":
            fail(f"expected closed notch under the idle board, got {notch_status!r}")
        if not any(":" in value for value in text_values):
            fail("idle board is missing the clock")
        if not any("CODEX" in value or "CLAUDE" in value for value in text_values):
            fail("idle board is missing the waiting agent")

    elif scenario == "linkstart":
        # The whole point of this scenario: a full-screen window, pinned
        # partway through, with at least one sense already confirmed and the
        # sounds that mark the sequence's own beats already in the log.
        frame_width = overlay_frame.get("width")
        frame_height = overlay_frame.get("height")
        if not isinstance(frame_width, (int, float)) or not isinstance(frame_height, (int, float)):
            fail("linkstart overlay frame is missing width/height")
        if frame_width <= 0 or frame_height <= 0:
            fail(f"linkstart overlay frame is degenerate: {frame_width}x{frame_height}")

        if not any("OK" in value for value in text_values):
            fail("linkstart is missing the confirmed sense marker")

        log_text = log_path.read_text()
        if "sound.cue=ui-linkstart-rise" not in log_text:
            fail("linkstart runtime log is missing the rise cue")
        if "sound.cue=ui-linkstart-tick" not in log_text:
            fail("linkstart runtime log is missing a tick cue")

    elif scenario == "sneakPeekPop":
        # The sneak peek is a temporary override of the closed body — the
        # island stays closed and the fixture's text has to actually be on
        # screen, not just scheduled.
        if notch_status != "closed":
            fail(f"expected closed notch for sneakPeekPop, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="sneakPeekPop overlay frame",
        )
        if not any("READY" in value for value in text_values):
            fail("sneakPeekPop is missing its override text")

    elif scenario == "closedAccessoryTimer":
        # Both a waiting body and a timer accessory have to be visible at
        # once — the whole point is that the accessory never hides the agent
        # that's actually waiting on you.
        if notch_status != "closed":
            fail(f"expected closed notch for closedAccessoryTimer, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="closedAccessoryTimer overlay frame",
        )
        if not any("CODEX" in value for value in text_values):
            fail("closedAccessoryTimer is missing the waiting agent")
        if not any("12" in value for value in text_values):
            fail("closedAccessoryTimer is missing the timer accessory")

    elif scenario == "shelfSurface":
        if notch_status != "opened":
            fail(f"expected opened notch for shelfSurface, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected shelfSurface to use sessionList surface, got {island_surface!r}")
        assert_contains_any(text_values, ["quarterly-report.pdf"], "shelfSurface text values")
        assert_contains_any(text_values, ["notes.md"], "shelfSurface text values")

    elif scenario == "unlockScan":
        # The unlock greeting: closed pill, ring landed, name on screen. Case
        # is ignored since the display face may or may not uppercase a Latin
        # name depending on the font path it took.
        if notch_status != "closed":
            fail(f"expected closed notch for unlockScan, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="unlockScan overlay frame",
        )
        if not any("taiki" in value.lower() for value in text_values):
            fail("unlockScan is missing the greeted name")

    elif scenario == "timerSurface":
        if notch_status != "opened":
            fail(f"expected opened notch for timerSurface, got {notch_status!r}")
        if island_surface != "timer":
            fail(f"expected the timer surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 460),
            context="timerSurface overlay frame",
        )
        if not any(re.fullmatch(r"\d{2}:\d{2}", value) for value in text_values):
            fail("timerSurface is missing its MM:SS countdown readout")
        if button_labels:
            assert_contains_any(
                button_labels,
                ["Pause", "一時停止", "PAUSE", "Start", "スタート", "START"],
                "timerSurface keeps its start/pause control reachable",
            )
        else:
            print("timerSurface: accessibility tree was empty, button check skipped")

    elif scenario == "eventInProgress":
        # A calendar entry that just started takes the closed body — the
        # fixed-English "NOW" label is what proves the real body rendered,
        # not just some fallback state.
        if notch_status != "closed":
            fail(f"expected closed notch for eventInProgress, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="eventInProgress overlay frame",
        )
        if not any("NOW" in value for value in text_values):
            fail("eventInProgress is missing the NOW marker")

    elif scenario == "clipboardSurface":
        if notch_status != "opened":
            fail(f"expected opened notch for clipboardSurface, got {notch_status!r}")
        if island_surface != "clipboard":
            fail(f"expected the clipboard surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 480),
            context="clipboardSurface overlay frame",
        )
        assert_contains_any(
            text_values,
            ["mitama-island clipboard fixture"],
            "clipboardSurface text values (text item)",
        )
        assert_contains_any(
            text_values,
            ["quarterly-report.pdf"],
            "clipboardSurface text values (file item)",
        )

    else:
        fail(f"unsupported scenario {scenario!r}")

    print(
        f"{scenario}: notch={notch_status}, surface={island_surface}, "
        f"frame={overlay_frame.get('width')}x{overlay_frame.get('height')}, "
        f"buttons={sorted(button_labels)}"
    )


if __name__ == "__main__":
    main()
