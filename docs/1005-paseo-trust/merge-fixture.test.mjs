import assert from 'node:assert/strict';
import test from 'node:test';
import { mergeReadOnlyPaseoTrust } from './merge-fixture.mjs';
const base = () => ({ mcp_servers: { paseo: {
  url: 'http://127.0.0.1:6767/mcp/agents', http_headers: { Authorization: 'fixture-only' },
  tools: { send_agent_prompt: { approval_mode: 'prompt' } },
}, other: { command: 'fixture' } }, approval_policy: 'never', sandbox_mode: 'danger-full-access' });
const context = extra => ({ explicitMode: true, modeId: 'full-access',
  readResult: { config: {}, origins: {}, layers: [] }, ...extra });
test('adds only three read tools, preserving transport, other tools and inputs', () => {
  const input = base(); const before = structuredClone(input); const result = mergeReadOnlyPaseoTrust(input, context());
  assert.deepEqual(input, before);
  for (const name of ['get_agent_status', 'list_agents', 'list_pending_permissions'])
    assert.equal(result.mcp_servers.paseo.tools[name].approval_mode, 'approve');
  const { tools, ...transport } = result.mcp_servers.paseo;
  const { tools: originalTools, ...originalTransport } = input.mcp_servers.paseo;
  assert.deepEqual(transport, originalTransport);
  assert.deepEqual(tools.send_agent_prompt, originalTools.send_agent_prompt);
  assert.deepEqual(result.mcp_servers.other, input.mcp_servers.other);
});
test('does not create a connection, expand a mode or act on unreadable layers', () => {
  assert.deepEqual(mergeReadOnlyPaseoTrust({}, context()), {});
  for (const options of [{ modeId: 'auto' }, { explicitMode: false }, { readResult: null },
    { readResult: { origins: {}, layers: [{ name: { type: 'unknown' }, config: {} }] } }]) {
    const input = base(); assert.deepEqual(mergeReadOnlyPaseoTrust(input, context(options)), input);
  }
});
test('preserves explicit user, project and managed prompt choices', () => {
  for (const type of ['user', 'project', 'system', 'mdm', 'enterpriseManaged']) {
    const readResult = { config: {}, origins: {}, layers: [{ name: { type }, config: {
      mcp_servers: { paseo: { tools: { get_agent_status: { approval_mode: 'prompt' } } } },
    } }] };
    const result = mergeReadOnlyPaseoTrust(base(), context({ readResult }));
    assert.equal(result.mcp_servers.paseo.tools.get_agent_status, undefined);
    assert.equal(result.mcp_servers.paseo.tools.list_agents.approval_mode, 'approve');
  }
});
test('preserves explicit defaults, existing policies and enabled/disabled lists', () => {
  const input = base(); input.mcp_servers.paseo.tools.get_agent_status = { approval_mode: 'prompt' };
  input.mcp_servers.paseo.enabled_tools = ['get_agent_status', 'list_agents', 'send_agent_prompt'];
  input.mcp_servers.paseo.disabled_tools = ['list_agents'];
  const result = mergeReadOnlyPaseoTrust(input, context());
  assert.deepEqual(result, input);
  const readResult = { config: {}, origins: {}, layers: [{ name: { type: 'user' }, config: {
    mcp_servers: { paseo: { default_tools_approval_mode: 'prompt' } },
  } }] };
  assert.deepEqual(mergeReadOnlyPaseoTrust(base(), context({ readResult })), base());
});
