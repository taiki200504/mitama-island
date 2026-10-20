# MainActor executor-check crash mitigation — 2026-10-20

## Evidence and confidence

Three DiagnosticReports were read as JSON after skipping their first header line.
All faulting threads are thread 0, queue `com.apple.main-thread`, on macOS
27.0.1 (26A434). The reports show EXC_BAD_ACCESS / SIGSEGV:

| Report | Address | Entry below executor check |
| --- | --- | --- |
| OpenIslandApp-2026-10-19-233559.ips | 0x1e | SwiftUI `NSViewResponder.containsGlobalPoints`, `MainActor.assumeIsolated` (tooltip timer) |
| OpenIslandApp-2026-10-20-000037.ips | 0x40 | `@objc NotchHostingView.viewDidMoveToWindow` (AppKit layout) |
| OpenIslandApp-2026-10-20-124059.ips | 0x0 | `@objc NotchHostingView.hitTest`, `_checkExpectedExecutor` (cursor tracking) |

High confidence: the immediate failure is dereferencing an invalid executor
identity during the runtime check, before the hosting-view override body runs.
Medium confidence: a Swift runtime / OS interoperability defect is involved.
Low confidence about the origin of the invalid identity: these stacks do not
exclude earlier memory corruption in the app or framework. Merely running
outside a Swift task is not sufficient to explain the crash.

The [Swift 6.2 ExecutorImpl.cpp source](https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/ExecutorImpl.cpp)
shows `swift_task_isMainExecutorImpl` calling `swift_getObjectType(identity)`
when an executor witness table is present. The matching
[ExecutorChecks.cpp](https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/ExecutorChecks.cpp)
handles execution outside concurrency explicitly: it tests `isMainExecutor()`
before the main-thread fallback. Thus a main thread can still fault while
examining an invalid executor reference.

[SE-0423](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0423-dynamic-actor-isolation.md)
specifies dynamic checks for synchronous Objective-C entry thunks and the
`-disable-dynamic-actor-isolation` escape hatch. Related first-hand reports
include [MainActor.assumeIsolated crashes on main thread](https://forums.swift.org/t/mainactor-assumeisolated-crashes-on-main-thread/80624)
and [Crash when running in Swift 6 language mode](https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431).
These establish related interoperability failure modes, not proof of an
identical macOS 27 bug. There is no confirmed upstream fix identified here.

## AppKit entry-point inventory

These classes inherit AppKit main-actor isolation (they need no explicit
`@MainActor` annotation). Inventory covers all NSView/NSWindow descendants
under Sources/OpenIslandApp, including NSPanel and NSTextField.

| File / subclass | Overrides callable from Objective-C (excluding initializers) |
| --- | --- |
| OverlayPanelController.swift / NotchHostingView | isOpaque, acceptsFirstMouse, mouseDown, hitTest, viewDidMoveToWindow, layout |
| OverlayPanelController.swift / NotchPanel | canBecomeKey, canBecomeMain |
| Views/UnifiedBars.swift / LayerView | layout |
| Ambient/AmbientVideoLayerView.swift / PlayerLayerView | viewDidMoveToWindow, viewDidHide, viewDidUnhide |
| Views/ShelfItemDragSource.swift / ShelfDragSourceView | acceptsFirstMouse, mouseDown, mouseUp, mouseDragged, menu |
| Views/Island/ReplyTextField.swift / ReplyField | acceptsFirstMouse |
| FullScreenOverlayPanel.swift / FullScreenOverlayPanel | canBecomeKey, canBecomeMain, keyDown, mouseDown |

NotchHostingView is constructed by OverlayPanelController; its lifecycle and
input overrides are called by AppKit, not explicit application call sites.
`interactiveRect` is shared with cursor/monitor paths and mutates
`stableOpenedContentHeight` or resets measurements. A nonisolated override
cannot safely read a single immutable snapshot without redesigning that flow;
it also calls actor-isolated superclass implementations. Adding unsafe aliases
across the model/controller/view graph would weaken more source-level safety.
For that reason this round chooses candidate (b), rather than attempting (a).

## Mitigation and limits

Package.swift adds `-Xfrontend -disable-dynamic-actor-isolation` only to
OpenIslandApp, in debug and release. This removes compiler-inserted dynamic
actor checks from our Objective-C entry thunks, including both reported
NotchHostingView entry paths and sibling AppKit subclasses. Static Swift 6
isolation checking remains enabled; no actor annotations, state synchronization,
layout logic, hit-test geometry, or authorization behavior are changed.

Tradeoff: runtime detection of isolation violations is reduced across the app
target, not just these overrides. OpenIslandCore, hooks, setup, dependencies,
and Apple frameworks do not receive the flag. This is a temporary mitigation,
not a repair of the invalid reference or a guarantee against future crashes.
Explicit `MainActor.assumeIsolated` and checks compiled into Apple SwiftUI
remain a risk. In particular, the 23:35 tooltip stack cannot be fixed by this
package flag. Record recurrences by stack category and OS build, and reassess
after OS/runtime updates. If either self-owned stack recurs with a freshly
built binary, inspect generated thunks and investigate memory corruption.
Remove the flag after an upstream fix is identified and comparable extended
soak runs with dynamic checks enabled no longer reproduce the failure.

## Reproduction / soak procedure

**Unreproduced** in this implementation session; the three reports are historical
evidence. No synthetic regression test is claimed to reproduce the bad pointer.

On a freshly built app, repeatedly open/close the island while sweeping the
mouse across its edges and buttons. Resize content by switching sessions and
expanding/collapsing cards. Hover controls long enough to trigger tooltips;
drag a file across the closed island to exercise closed drop targeting.
Repeat for at least 30 minutes, then leave normal operation running for at
least 24 hours (baseline: three crashes in roughly 13 hours). Record build
commit, mitigation enabled/disabled, OS build, start/end times and uptime.
Do not send real approvals as part of stress testing.

Use a fresh build of OpenIslandApp; an already-running installed app does not
acquire this flag. Bundle refresh/deployment is left to the parent integration
round. To count reports for the exact observation interval (local time), run:

```bash
python3 - <<'PYCOUNT'
import collections, datetime, json, pathlib
start = datetime.datetime.fromisoformat("2026-10-20T13:00:00+09:00")
end = datetime.datetime.fromisoformat("2026-10-21T13:00:00+09:00")
counts = collections.Counter()
for path in pathlib.Path.home().joinpath("Library/Logs/DiagnosticReports").glob("OpenIslandApp-*.ips"):
    try:
        header, body = path.read_text().split("\n", 1)
        meta, report = json.loads(header), json.loads(body)
        timestamp = meta.get("timestamp") or report["captureTime"]
        when = datetime.datetime.fromisoformat(timestamp.replace(" +", "+").replace(" -", "-"))
        if not start <= when < end:
            continue
        frames = report["threads"][report["faultingThread"]]["frames"]
        stack = "\n".join(frame.get("symbol", "") for frame in frames)
        category = "other"
        if "swift_task_isMainExecutorImpl" in stack:
            category = next((name for name in ("NotchHostingView.hitTest", "NotchHostingView.viewDidMoveToWindow", "NSViewResponder.containsGlobalPoints") if name in stack), "other executor check")
        counts[category] += 1
        print(path.name, category, report.get("osVersion", {}).get("build"))
    except (ValueError, KeyError, OSError, IndexError) as error:
        print("UNREADABLE", path.name, type(error).__name__)
print("TOTAL", sum(counts.values()), dict(counts))
PYCOUNT
```

Replace both interval boundaries for each run. Preserve the reports: compare
counts per observed app-running hour, separating self-owned entry checks from
Apple SwiftUI and unrelated crashes. A short zero-crash run is not evidence
that the rare crash has been eliminated.

## Verification

Changed files: Package.swift (app-only compiler mitigation), docs/index.md
(document index), and this investigation. No commits or delegation were made.

- `swift build --jobs 2`: initially blocked by nested `sandbox-exec` in this
  execution environment. Re-run with `--disable-sandbox --cache-path
  /tmp/island-swift-cache -Xswiftc -module-cache-path -Xswiftc
  /tmp/island-module-cache` passed (66.24 seconds). Existing warnings remain.
- `swift test --jobs 2` with the same environment flags: completed all 673
  tests in 109 suites, exit 1, eight issues. Full log:
  `/tmp/island-crash-test.log`.
- Full `swift test --jobs 2 --no-parallel` with the same environment flags:
  completed all 673 tests in 109 suites, exit 1, six issues. Full log:
  `/tmp/island-crash-test-serial.log`. The two timer-dependent failures in
  ShelfDragHoldTests and OverlayUICoordinatorSneakPeekTests passed serially.
- Remaining serial failures: CompletionBannerTests.swift:52, :65, :86
  (banner not presenting / no hosting window), :197 and :202 (handoff banner
  not presenting), and OverlayPanelControllerTests.swift:18 (file URL on the
  drag pasteboard not detected). These paths were not changed. Missing screen
  / pasteboard access in the restricted environment is suspected; an unmodified
  baseline comparison was not run, so they are not proven pre-existing.
  The complete suite is **not green**. Parent must rerun in a normal macOS
  graphical execution environment before treating integration as verified.
- `bash scripts/harness.sh lint`: passed (including five capability checks).
- `bash scripts/check-docs.sh`: passed with the new index entry.
- `git diff --check`: passed.
- Historical report-counting snippet above: tested against the interval
  2026-10-19 23:00 through 2026-10-20 13:00 JST; counted exactly three,
  one per documented category.
- `otool -tvV` on the freshly compiled OverlayPanelController.o: the
  Objective-C thunks for NotchHostingView.hitTest, viewDidMoveToWindow,
  layout, mouseDown, isOpaque and acceptsFirstMouse contain no calls to
  `swift_task_isCurrentExecutor` or `_checkExpectedExecutor`. This verifies
  removal of the self-owned check path, not long-term crash prevention.

Build/test processes were sequential, with two compilation jobs. Load was
sampled every 60 seconds while above eight; heavy invocations began below
eight. Waiting totaled approximately 17 minutes. Process inventory (`ps`) and
swap inspection were denied by the environment, so cross-session concurrency
could not be independently checked. No background process is left running.
No installed application was replaced or restarted; the parent must deploy
this build before starting the observation interval.
