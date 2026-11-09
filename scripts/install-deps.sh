#!/usr/bin/env bash
# Installs the pinned Reactive library WITHOUT vendoring it into this repo's history.
# (reactive-lib-omni carries no LICENSE; see docs/DEPLOYMENT.md "Dependency licensing".)
set -euo pipefail
cd "$(dirname "$0")/../contracts"
REPO=https://github.com/Reactive-Network/reactive-lib-omni
SHA=3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8   # tag v0.1.0
DEST=lib/reactive-lib-omni
if [ -d "$DEST/src" ]; then echo "present: $DEST"; exit 0; fi
git clone --quiet "$REPO" "$DEST" && git -C "$DEST" checkout --quiet "$SHA"
echo "installed $DEST @ $SHA"
