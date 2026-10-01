import Foundation

/// Minimal Supabase REST client for UI tests: plays the *other* family member (a parent on another phone) so the
/// app under test can be exercised end to end against the real backend.
struct LiveBackendClient {
    let baseURL: URL
    let key: String
    var token: String?

    init?(bundle: Bundle) {
        guard let host = bundle.object(forInfoDictionaryKey: "KinSupabaseHost") as? String, !host.isEmpty, !host.contains("$("),
              let key = bundle.object(forInfoDictionaryKey: "KinSupabaseKey") as? String, !key.isEmpty,
              let url = URL(string: "https://\(host)") else { return nil }
        baseURL = url
        self.key = key
    }

    mutating func signUp(email: String, password: String) async throws {
        let json = try await post("auth/v1/signup", body: ["email": email, "password": password], schema: nil)
        token = (json as? [String: Any])?["access_token"] as? String
    }

    func rpc(_ name: String, _ body: [String: Any] = [:]) async throws -> Any {
        try await post("rest/v1/rpc/\(name)", body: body, schema: "kinbeacon")
    }

    func select(_ table: String, query: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: URL(string: "\(baseURL.absoluteString)/rest/v1/\(table)?\(query)")!)
        authorize(&request, schema: "kinbeacon", write: false)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try (JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func post(_ path: String, body: [String: Any], schema: String?) async throws -> Any {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        authorize(&request, schema: schema, write: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw NSError(
                domain: "LiveBackend",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: String(bytes: data, encoding: .utf8) ?? ""]
            )
        }
        return data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    private func authorize(_ request: inout URLRequest, schema: String?, write: Bool) {
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let schema {
            request.setValue(schema, forHTTPHeaderField: write ? "Content-Profile" : "Accept-Profile")
        }
    }
}
