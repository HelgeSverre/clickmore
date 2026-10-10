#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build test-results
swiftc -O -D ROUTING_MEDIA_EXPORT \
  Sources/ClickMoreCore/Layout.swift Sources/ClickMoreCore/ConnectorRouter.swift \
  Tests/ClickMoreCoreTests/RoutingFixtures.swift script/export_routing_stress.swift \
  -o .build/export-routing-stress
.build/export-routing-stress test-results/routing-after.json test-results/demo-routing.json
"${CLICKMORE_MEDIA_PYTHON:-python3}" script/render_readme_media.py
