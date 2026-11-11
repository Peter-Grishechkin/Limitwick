#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/ClaudeClient.swift Tests/ClaudeTests.swift -o build/claude-tests
build/claude-tests "$PWD/Tests/fake-claude"
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Tests/QuotaTests.swift -o build/quota-tests
build/quota-tests "$PWD/Tests/fake-codex"
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Sources/RefreshCoordinator.swift Tests/RefreshCoordinatorTests.swift -o build/refresh-tests
build/refresh-tests
swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/ClaudeClient.swift Sources/P1Support.swift Sources/AppSettings.swift Sources/NoticeService.swift Tests/NoticeServiceTests.swift -o build/notice-tests
build/notice-tests
swiftc -module-cache-path "$PWD/build/module-cache" Sources/Sessions.swift Tests/SessionTests.swift -o build/session-tests
build/session-tests

swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -parse-as-library Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Sources/QuotaCard.swift Tests/CardTests.swift -o build/card-tests
build/card-tests

swiftc -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Widget/SharedSnapshot.swift Tests/WidgetSnapshotTests.swift -o build/widget-snapshot-tests
build/widget-snapshot-tests
swiftc -D LIMITWICK_DEVELOPMENT -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Widget/SharedSnapshot.swift Tests/WidgetSnapshotTests.swift -o build/widget-snapshot-development-tests
build/widget-snapshot-development-tests

if [ ! -d build/Limitwick-Development.app/Contents/Frameworks/Lottie.framework ]; then
    ./build.sh
fi
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" \
    -F build/Limitwick-Development.app/Contents/Frameworks -framework Lottie \
    -Xlinker -rpath -Xlinker "$PWD/build/Limitwick-Development.app/Contents/Frameworks" \
    Sources/Sessions.swift Sources/Activity.swift Tests/ActivityTests.swift -o build/activity-tests
build/activity-tests
/usr/bin/python3 Tests/activity-hooks-tests.py
