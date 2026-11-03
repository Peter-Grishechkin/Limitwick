#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Tests/QuotaTests.swift -o build/quota-tests
build/quota-tests "$PWD/Tests/fake-codex"

swiftc -module-cache-path "$PWD/build/module-cache" Widget/SharedSnapshot.swift Tests/WidgetSnapshotTests.swift -o build/widget-snapshot-tests
build/widget-snapshot-tests
