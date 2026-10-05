# Paseo isolated native harness

Run an already built harness executable, rather than `swift run`, with the following environment. No build is part of this procedure. Root operates the UI. Use a separate harness process, not the normal app.

```sh
OPEN_ISLAND_HARNESS_SCENARIO=paseoQuestionCard \
OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
OPEN_ISLAND_HARNESS_START_BRIDGE=0 \
OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 \
OPEN_ISLAND_PASEO_MOCK_VARIANT=long \
OPEN_ISLAND_PASEO_MOCK_FAIL_ONCE=true \
/path/to/already-built/OpenIslandApp
```

Do not set AUTO_EXIT for interactive inspection. Quit this harness process when finished.

- `long`: three questions: a long paragraph with eight described choices, a multiple-selection question, and a free-text question. Check wrapping, access to the eighth choice, completion of every question, keyboard focus, and scrolling to send. First send fails locally when FAIL_ONCE=true; verify answers remain, error is readable, retry succeeds, and stale card disappears.
- `child`: the same questions originate from `fixture-child`, whose label points to `fixture-parent`. Two exact native sessions are initially loaded, and mock status/list endpoints return their own IDs. Verify one parent row/card, child attribution, no duplicate child notification, and answers routed to the child request through the parent presentation. This needs the integrated parent-projection implementation.
- `unknown`: a question-kind request with an unsupported input schema. Verify the integrated unsupported-question handling offers Paseo/manual guidance rather than a fabricated permission grant.
- Unset VARIANT: original two-choice basic fixture. `paseoApprovalCard` also retains its original permission fixture.

The fixture owns `list_pending_permissions`, `list_agents`, `get_agent_status`, and `respond_to_permission`; all other calls throw. Status requires an exact fixture agent ID. Response requires the exact fixture agent and request IDs. No call forwards to PaseoMCPClient. Jump identity validation therefore stays inside the mock; do not use Teleport during this visual acceptance run, since OS app launching is outside the mock and the server identity intentionally comes from the current local file.

These are fixture instructions and acceptance criteria, not a claim that native UI inspection has passed.
