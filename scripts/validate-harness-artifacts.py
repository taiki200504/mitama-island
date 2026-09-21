#!/usr/bin/env python3

from __future__ import annotations

import json
import pathlib
import re
import struct
import sys
import zlib


def fail(message: str) -> None:
    raise SystemExit(f"Smoke failed: {message}")


def load_json(path: pathlib.Path) -> dict:
    if not path.exists():
        fail(f"missing file at {path}")
    return json.loads(path.read_text())


def require_path(path: pathlib.Path, context: str) -> None:
    if not path.exists():
        fail(f"missing {context} at {path}")


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# Bytes per pixel for 8-bit samples, keyed by PNG colour type.
PNG_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def _unfilter_row(kind: int, payload: bytes, prev: bytes, bpp: int) -> bytes:
    if kind == 0:
        return payload
    # Rows that encode "same as the row above" are the common case in a blank
    # capture; skip the byte loop for them.
    if not any(payload):
        if kind == 1:
            return payload
        if kind == 2 or (kind == 4 and prev[:bpp] * (len(prev) // bpp) == prev):
            return prev
    row = bytearray(payload)
    for i in range(len(row)):
        left = row[i - bpp] if i >= bpp else 0
        up = prev[i]
        if kind == 1:
            row[i] = (row[i] + left) & 0xFF
        elif kind == 2:
            row[i] = (row[i] + up) & 0xFF
        elif kind == 3:
            row[i] = (row[i] + ((left + up) >> 1)) & 0xFF
        elif kind == 4:
            upper_left = prev[i - bpp] if i >= bpp else 0
            row[i] = (row[i] + _paeth(left, up, upper_left)) & 0xFF
        else:
            raise ValueError(f"unknown PNG filter type {kind}")
    return bytes(row)


def png_blank_reason(data: bytes) -> str | None:
    """Why a capture holds no picture, or None when it has content.

    A locked screen hands back a window image with every pixel transparent,
    which the rest of the smoke checks happily accept. Formats this decoder
    does not cover (palette, interlaced, sub-byte depths) are never reported
    as blank.
    """
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG file")

    offset = len(PNG_SIGNATURE)
    header = None
    compressed = bytearray()
    while offset + 8 <= len(data):
        length, chunk_type = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if chunk_type == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif chunk_type == b"IDAT":
            compressed += body
        elif chunk_type == b"IEND":
            break
        offset += 12 + length

    if header is None:
        raise ValueError("PNG is missing IHDR")
    width, height, depth, colour, _, _, interlace = header
    if colour not in PNG_CHANNELS or depth not in (8, 16) or interlace:
        return None

    bpp = PNG_CHANNELS[colour] * depth // 8
    stride = width * bpp
    raw = zlib.decompress(bytes(compressed))
    has_alpha = colour in (4, 6)
    alpha_width = depth // 8

    first_pixel = None
    any_visible = not has_alpha
    single_colour = True
    prev = bytes(stride)
    for y in range(height):
        start = y * (stride + 1)
        row = _unfilter_row(raw[start], raw[start + 1:start + 1 + stride], prev, bpp)
        prev = row
        if first_pixel is None:
            first_pixel = row[:bpp]
        if single_colour and row != first_pixel * width:
            single_colour = False
        if has_alpha and not any_visible:
            any_visible = any(
                row[x + bpp - alpha_width:x + bpp] != bytes(alpha_width)
                for x in range(0, stride, bpp)
            )
        if any_visible and not single_colour:
            return None

    if not any_visible:
        return "every pixel is fully transparent"
    return "the whole image is a single solid colour"


def validate_capture_image(report_path: pathlib.Path, window: dict) -> None:
    image_path = window.get("imagePath")
    if not image_path:
        fail(f"{window.get('kind')} window is missing imagePath")
    path = report_path.parent / image_path
    require_path(path, "window capture")
    try:
        reason = png_blank_reason(path.read_bytes())
    except (ValueError, zlib.error, struct.error) as error:
        fail(f"{image_path} is not a readable PNG: {error}")
    if reason:
        fail(f"{image_path} captured nothing ({reason}); is the screen locked?")


def find_window_by_kind(report: dict, kind: str) -> dict | None:
    windows = report.get("windows") or []
    return next((window for window in windows if window.get("kind") == kind), None)


def find_overlay_window(report: dict) -> dict:
    overlay = find_window_by_kind(report, "overlay")
    if overlay is None:
        fail("report is missing an overlay window artifact")
    return overlay


# Full-screen scenarios capture under their own window kind (see
# HarnessArtifactRecorder.recognizedWindowKind), not the plain island overlay.
FULL_SCREEN_KINDS = {
    "linkstart": "linkstart",
    "ambientBoard": "ambient-board",
    "ambientBoardNight": "ambient-board",
}


def find_full_screen_window(report_path: pathlib.Path, report: dict, kind: str) -> dict:
    # One panel per display, but only one may carry the content; the others
    # can be a dimmed backdrop, a legitimately single colour. Validate the
    # one that drew.
    windows = [w for w in report.get("windows") or [] if w.get("kind") == kind]
    if not windows:
        fail(f"captured no full-screen {kind} window (a key press or click dismisses it)")
    for window in windows:
        path = report_path.parent / (window.get("imagePath") or "")
        try:
            if path.is_file() and png_blank_reason(path.read_bytes()) is None:
                return window
        except (ValueError, zlib.error, struct.error):
            continue
    return windows[0]


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

    full_screen_kind = FULL_SCREEN_KINDS.get(scenario)
    overlay = (
        find_full_screen_window(report_path, report, full_screen_kind)
        if full_screen_kind
        else find_overlay_window(report)
    )
    validate_capture_image(report_path, overlay)

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
            height=(240, 440),
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

    elif scenario == "ambientBoardNight":
        # Same full-screen idle board, pinned to a fixed hour so the backdrop
        # is deterministic — checked by the clock rather than the gradient
        # itself, since colour isn't something the accessibility tree carries.
        if notch_status != "closed":
            fail(f"expected closed notch under the idle board, got {notch_status!r}")
        if not any(":" in value for value in text_values):
            fail("idle board is missing the clock")

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
        # Each row is one button whose label reads "<preview>, <time>", so
        # the preview text lives in labels rather than in a text value.
        assert_contains_any(
            text_values | labels,
            ["mitama-island clipboard fixture"],
            "clipboardSurface text values (text item)",
        )
        assert_contains_any(
            text_values | labels,
            ["quarterly-report.pdf"],
            "clipboardSurface text values (file item)",
        )

    elif scenario == "nowPlayingClosed":
        # Same shape as closedAccessoryTimer: a waiting body and the
        # now-playing accessory both visible at once.
        if notch_status != "closed":
            fail(f"expected closed notch for nowPlayingClosed, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="nowPlayingClosed overlay frame",
        )
        if not any("CODEX" in value for value in text_values):
            fail("nowPlayingClosed is missing the waiting agent")

    elif scenario == "nowPlayingSurface":
        if notch_status != "opened":
            fail(f"expected opened notch for nowPlayingSurface, got {notch_status!r}")
        if island_surface != "nowPlaying":
            fail(f"expected the nowPlaying surface, got {island_surface!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 460),
            context="nowPlayingSurface overlay frame",
        )
        assert_contains_any(text_values, ["Demo Track"], "nowPlayingSurface text values")
        assert_contains_any(text_values, ["Demo Artist"], "nowPlayingSurface text values")
        if not any(re.fullmatch(r"\d:\d{2}", value) for value in text_values):
            fail("nowPlayingSurface is missing its M:SS elapsed/duration readout")

    elif scenario == "hudVolume":
        # The HUD gauge overrides the closed body just like sneakPeekPop —
        # the fixture's percentage text has to actually be on screen.
        if notch_status != "closed":
            fail(f"expected closed notch for hudVolume, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="hudVolume overlay frame",
        )
        if not any("56%" in value for value in text_values):
            fail("hudVolume is missing its gauge percentage")

    elif scenario == "automationLamp":
        # The lamp is a glyph with no text of its own, so the accessibility
        # label is what proves it was drawn. Any of the four languages will
        # do — the harness runs in whatever the app is set to.
        if notch_status != "closed":
            fail(f"expected closed notch for automationLamp, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(35, 500),
            context="automationLamp overlay frame",
        )
        assert_contains_any(
            labels | text_values,
            ["Driving", "自動操作中", "自动操作中"],
            "automationLamp accessibility labels",
        )

    elif scenario == "automationSignals":
        # All three lines at once: the browser being driven, the job queue and
        # the failing gate. The fixture's own nouns are language-independent,
        # which is what makes them worth asserting on.
        if notch_status != "opened":
            fail(f"expected opened notch for automationSignals, got {notch_status!r}")
        require_frame_between(
            overlay_frame,
            width=(520, 780),
            height=(180, 520),
            context="automationSignals overlay frame",
        )
        # Codex の行は押せるボタンなので、文字は buttonLabels 側に入る。
        # 3 本とも出ていることを見たいので、3 つまとめて探す。
        spoken = labels | button_labels | text_values
        assert_contains_any(spoken, ["Gugen"], "automationSignals の自動操作の行")
        assert_contains_any(spoken, ["mitama-island"], "automationSignals の Codex の行")
        if not any("12" in value for value in spoken):
            fail("automationSignals is missing the job counts")

    else:
        fail(f"unsupported scenario {scenario!r}")

    print(
        f"{scenario}: notch={notch_status}, surface={island_surface}, "
        f"frame={overlay_frame.get('width')}x{overlay_frame.get('height')}, "
        f"buttons={sorted(button_labels)}"
    )


if __name__ == "__main__":
    main()
