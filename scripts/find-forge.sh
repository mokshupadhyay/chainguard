#!/usr/bin/env bash
# Prints the path of a real Foundry `forge`. Another tool named `forge` (Atlassian Forge CLI,
# npm @forge/cli) can shadow it on PATH; this skips any binary that is not Foundry.
# Usage: FORGE=$(./scripts/find-forge.sh) && "$FORGE" test
is_foundry() { "$1" --version 2>/dev/null | grep -qi 'forge Version'; }
{ type -aP forge 2>/dev/null; ls /opt/homebrew/Cellar/foundry/*/bin/forge "$HOME/.foundry/bin/forge" 2>/dev/null; } | while read -r f; do
  is_foundry "$f" && { echo "$f"; break; }
done | head -n1 | grep . || { echo "No Foundry forge found (a different 'forge' may shadow it). Install: https://getfoundry.sh" >&2; exit 1; }
