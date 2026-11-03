#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Tests/QuotaTests.swift -o build/quota-tests
build/quota-tests "$PWD/Tests/fake-codex"
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Sources/RefreshCoordinator.swift Tests/RefreshCoordinatorTests.swift -o build/refresh-tests
build/refresh-tests
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Sources/AppSettings.swift Sources/NoticeService.swift Tests/NoticeServiceTests.swift -o build/notice-tests
build/notice-tests

swiftc -module-cache-path "$PWD/build/module-cache" Widget/SharedSnapshot.swift Tests/WidgetSnapshotTests.swift -o build/widget-snapshot-tests
build/widget-snapshot-tests
swiftc -D CODEXBAR_DEVELOPMENT -module-cache-path "$PWD/build/module-cache" Widget/SharedSnapshot.swift Tests/WidgetSnapshotTests.swift -o build/widget-snapshot-development-tests
build/widget-snapshot-development-tests

if [ ! -d build/CodexBar-Development.app/Contents/Frameworks/Lottie.framework ]; then
    ./build.sh
fi
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" \
    -F build/CodexBar-Development.app/Contents/Frameworks -framework Lottie \
    -Xlinker -rpath -Xlinker "$PWD/build/CodexBar-Development.app/Contents/Frameworks" \
    Sources/Activity.swift Tests/ActivityTests.swift -o build/activity-tests
build/activity-tests
/usr/bin/python3 Tests/activity-hooks-tests.py
