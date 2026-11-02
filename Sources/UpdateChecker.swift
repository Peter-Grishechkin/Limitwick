import Foundation

struct AppVersion: Comparable {
    let parts: [Int]
    init?(_ string: String) {
        let text = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3, components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0) != nil }) else { return nil }
        parts = components.map { Int($0)! }
    }
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
private struct GitHubRelease: Decodable { let tag_name: String }
enum UpdateCheckError: LocalizedError {
    case invalidResponse, invalidVersion
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub returned an unexpected response. Please try again later."
        case .invalidVersion: return "The release version could not be read. Please check GitHub."
        }
    }
}
final class UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/frankydzoro/codex-bar/releases/latest")!
    func check(currentVersion: String, completion: @escaping (Result<String?, Error>) -> Void) {
        guard let current = AppVersion(currentVersion) else { completion(.failure(UpdateCheckError.invalidVersion)); return }
        let url = URL(string: "https://api.github.com/repos/frankydzoro/codex-bar/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, let data = data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { completion(.failure(UpdateCheckError.invalidResponse)); return }
            guard let latest = AppVersion(release.tag_name) else { completion(.failure(UpdateCheckError.invalidVersion)); return }
            completion(.success(latest > current ? release.tag_name : nil))
        }.resume()
    }
}
