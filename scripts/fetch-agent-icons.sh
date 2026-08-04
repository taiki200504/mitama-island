#!/usr/bin/env zsh
# Fetches each agent's official logo from that vendor's own distribution.
#
# The images are NOT part of this repository. They are other companies'
# trademarks, and redistributing them from a GPLv3 fork is not something this
# project should do. Run this once if you want brand marks; without it the
# island uses its own pixel marks, which is a finished look, not a fallback.
#
# Usage: zsh scripts/fetch-agent-icons.sh
set -euo pipefail

DEST="${HOME}/Library/Application Support/MitamaIsland/AgentIcons"
mkdir -p "$DEST"

# One line per agent: <AgentTool raw value> <URL>
# The stem must match AgentTool.rawValue — AgentIconLibrary looks it up by name.
typeset -a SOURCES=(
  "claudeCode https://claude.ai/favicon.ico"
  "codex https://openai.com/favicon.ico"
  "geminiCLI https://www.google.com/favicon.ico"
  "cursor https://cursor.com/favicon.ico"
  "openCode https://opencode.ai/favicon.ico"
)

fetched=0
for entry in "${SOURCES[@]}"; do
  stem="${entry%% *}"
  url="${entry#* }"
  # A vendor moving its favicon must not fail the whole run — the agents that
  # did resolve are still worth having.
  if curl -fsSL --max-time 15 -o "${DEST}/${stem}.png" "$url" 2>/dev/null; then
    print "fetched ${stem}"
    (( fetched += 1 ))
  else
    print "skipped ${stem} (${url} did not respond)" >&2
    rm -f "${DEST}/${stem}.png"
  fi
done

print ""
print "${fetched} icon(s) in ${DEST}"
print "Turn them on under Settings › Display › Agent icons."
