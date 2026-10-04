// Review fixture only. This module is not imported by the installed runtime.
const readTools = ['get_agent_status', 'list_agents', 'list_pending_permissions'];
const knownLayers = new Set([
  'packagedDefaults', 'user', 'project', 'system', 'mdm', 'sessionFlags',
  'enterpriseManaged', 'legacyManagedConfigTomlFromFile', 'legacyManagedConfigTomlFromMdm',
]);
const record = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};

export function mergeReadOnlyPaseoTrust(config, { explicitMode, modeId, readResult }) {
  const server = record(config?.mcp_servers).paseo;
  if (!explicitMode || modeId !== 'full-access' || !server) return config;
  if (!Array.isArray(readResult?.layers) || !readResult.origins) return config;
  const activeLayers = readResult.layers.filter(layer => !layer.disabledReason);
  if (activeLayers.some(layer => !knownLayers.has(layer.name?.type))) return config;
  const layers = activeLayers.filter(layer => layer.name.type !== 'packagedDefaults');
  const explicitServers = layers.map(layer => record(record(layer.config).mcp_servers).paseo).filter(Boolean);
  const effective = record(record(readResult.config).mcp_servers).paseo;
  const next = structuredClone(config);
  const target = next.mcp_servers.paseo;
  target.tools = { ...record(target.tools) };
  for (const tool of readTools) {
    // An explicit server-wide prompt or per-tool policy is a user/managed choice.
    if (explicitServers.some(value => value.default_tools_approval_mode != null
      || record(record(value.tools)[tool]).approval_mode != null)) continue;
    if (record(record(server.tools)[tool]).approval_mode != null) continue;
    if (record(record(effective?.tools)[tool]).approval_mode != null) continue;
    if (server.enabled === false || record(server.tools)[tool]?.enabled === false
      || server.disabled_tools?.includes(tool)
      || (Array.isArray(server.enabled_tools) && !server.enabled_tools.includes(tool))) continue;
    target.tools[tool] = { ...record(target.tools[tool]), approval_mode: 'approve' };
  }
  return next;
}
