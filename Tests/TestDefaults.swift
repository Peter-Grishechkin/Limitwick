import Foundation

// A named suite leaves an empty plist in ~/Library/Preferences: removePersistentDomain only empties the domain, and
// cfprefsd may write that file after the test has deleted it. A suite named by an absolute path is stored at that path,
// so test suites live in the temporary folder and nothing they leave behind reaches Preferences.
func testSuite(_ prefix: String) -> String {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("limitwick-\(prefix)-\(UUID().uuidString)").path
}

func removeTestDefaults(_ suite: String) {
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(atPath: suite + ".plist")
}
