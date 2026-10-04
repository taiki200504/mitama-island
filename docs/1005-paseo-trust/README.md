# Review fixture: exact read-only Paseo MCP trust

This is a specification and isolated merge fixture, not an installed runtime patch. No app archive, global Codex config, pending permission or live agent was changed.

## Canonical source

Installed entry: `/Applications/Paseo.app/Contents/Resources/app.asar` → `node_modules/@getpaseo/server/dist/server/server/agent/providers/codex-app-server-agent.js`.

Read copy: `/tmp/paseo-router-source/` plus the same entry path. Byte equality was rechecked on 2026-10-05. Both SHA256: `da3a578f881d2813d850c218f6089cb493c18155e0aab19b5a3f94b4ea720c6e`; size: 235514 bytes. The older `~/.paseo/_src/full/` is not the canonical current installed source. Recheck the archive entry hash before any later patch because another task is working on Paseo.

## Verified native API boundaries

Generated local Codex experimental app-server schemas confirm:

- `config/read` accepts `cwd` and `includeLayers`. Response contains `config`, `origins`, and optional `layers`; each layer has `name.type`, raw `config`, `version`, optional `disabledReason`.
- Sources include packagedDefaults, user (including selected profile), project, system, mdm, enterpriseManaged, sessionFlags and legacy managed sources. Disabled layers do not contribute. Unknown sources or failed/missing layer reads must retain prompts.
- Tool approval enum is `auto | prompt | writes | approve`. A literal `deny` is not an accepted value. Tool/server disabled flags and allow/deny lists represent explicit restrictions and must remain unchanged.
- Read-only live `config/read` in the task cwd returned user/system layers, no Paseo server policy. Only structural facts were emitted; secret values were not printed. The temporary reader process was terminated afterward.
- `thread/start` and `thread/resume` accept arbitrary `config` overrides. Native `turn/start` has no `config` property in its generated schema. Paseo adds a config map to turn requests, but that unsupported field cannot establish that MCP trust changes apply to a loaded native thread.

## Fixed merge contract

Only an explicitly selected Codex `full-access` mode and an existing injected Paseo server are eligible. Claude bypass uses a different provider and requires its own verified policy integration; do not treat a string named bypass as a Codex mode.

Preserve the connection (URL/command/arguments/headers/env), approval policy, sandbox, other servers, existing tools, enabled/disabled tools and default policy. Add per-tool `approval_mode: approve` only for `get_agent_status`, `list_agents`, `list_pending_permissions`. Do not create a new server or preapprove `send_agent_prompt` or other mutation tools.

Any explicit per-tool approval setting or explicit server default supplied by user/project/session/managed layers wins. Existing provider grants also win. A missing policy is eligible only after a successful layered read; unknown provenance fails closed. Treat restrictions like disabled tools independently; adding trust must not restore availability.

The existing `applyCodexToolPolicy` creates `enabled_tools` from grants and replaces a server's tools table. Do not use it as the three-tool broad-catalog merge. The review helper accepts the final existing injected config plus a verified layered read and merges without mutating either. It should run after existing explicit provider policy construction, with no changes to transport generation.

## Runtime integration and acceptance

Cache the relevant layered policy inside the provider after `config/read` in the existing connection initialization (`loadResolvedWorkspaceWrite`, currently line 2637), requesting `includeLayers: true`. Do not log raw config or credentials. Re-read before native start/resume when provenance could be stale. Failure leaves original config unchanged.

Consume the merge when `buildCodexInnerConfig` is used for native `thread/start` and `thread/resume`. Mode changes to full-access become eligible for the next supported thread config application; changes to any other mode must stop synthesizing these grants. Already pending elicitation requests remain pending and require their own authorized resolution. Never imply that a disk patch clears existing requests.

The installed daemon has already loaded the provider ES module. There is no verified lifecycle/plugin route to replace that in-memory method without reload: providerOptions has a strict schema that excludes arbitrary MCP config; MCP server conversion keeps transport fields only; session-open plugin hooks may change env only. An archive-only edit would not affect even new agents in the same daemon. With no restart authorization, prepare the patch and defer activation until a normal daemon reload. Do not stop user sessions to activate it.

Acceptance cases are in `merge-fixture.test.mjs`: exact three-tool addition, unchanged transport/catalog/mode, immutable inputs, no server creation, mode gating, explicit prompts/restrictions preserved, unknown provenance unchanged. Additional adapter tests must verify native start/resume config delivery and confirm that ordinary turn/start alone is not treated as proof of activation.

Prepared test command: `node --test docs/1005-paseo-trust/merge-fixture.test.mjs`. Root owns execution scheduling.
