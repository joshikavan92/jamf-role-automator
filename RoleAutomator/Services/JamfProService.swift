//
//  JamfProService.swift
//  RoleAutomator
//
//  Creates API roles on Jamf Pro using stored credentials (Keychain).
//

import Foundation
import Combine

struct JamfProCredentials {
    var baseURL: String
    var username: String
    var password: String

    var baseURLNormalized: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("https://") && !url.hasPrefix("http://") {
            url = "https://" + url
        }
        return url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

@MainActor
class JamfProService: ObservableObject {
    @Published var isCreating = false
    @Published var lastError: String?
    @Published var lastSuccessMessage: String?

    private let keychainURLKey = "jamfProURL"
    private let keychainUsernameKey = "jamfProUsername"
    private let keychainPasswordKey = "jamfProPassword"

    func loadCredentials() -> JamfProCredentials? {
        guard let url = try? KeychainHelper.load(forKey: keychainURLKey),
              let username = try? KeychainHelper.load(forKey: keychainUsernameKey),
              let password = try? KeychainHelper.load(forKey: keychainPasswordKey),
              !url.isEmpty, !username.isEmpty, !password.isEmpty else {
            return nil
        }
        return JamfProCredentials(baseURL: url, username: username, password: password)
    }

    func hasStoredCredentials() -> Bool {
        loadCredentials() != nil
    }

    func saveCredentials(baseURL: String, username: String, password: String) throws {
        try KeychainHelper.save(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keychainURLKey)
        try KeychainHelper.save(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keychainUsernameKey)
        try KeychainHelper.save(password, forKey: keychainPasswordKey)
    }

    func clearCredentials() throws {
        try KeychainHelper.delete(keychainURLKey)
        try KeychainHelper.delete(keychainUsernameKey)
        try KeychainHelper.delete(keychainPasswordKey)
    }

    /// Test connectivity and auth with the given credentials (or stored if nil). Returns nil on success, error message on failure.
    /// Uses Jamf Pro token auth: POST /api/v1/auth/token with Basic, then uses Bearer for API calls.
    func testConnection(baseURL: String? = nil, username: String? = nil, password: String? = nil) async -> String? {
        let creds: JamfProCredentials
        if let baseURL = baseURL, let username = username, let password = password, !baseURL.isEmpty, !username.isEmpty, !password.isEmpty {
            creds = JamfProCredentials(baseURL: baseURL, username: username, password: password)
        } else if let stored = loadCredentials() {
            creds = stored
        } else {
            return "No credentials. Enter URL, username, and password (or save first)."
        }
        let base = creds.baseURLNormalized
        guard !base.isEmpty else { return "Invalid Jamf Pro URL." }
        do {
            guard let token = try await fetchToken(baseURL: base, credentials: creds) else {
                return "Could not obtain token. Check URL and credentials."
            }
            guard let url = URL(string: "\(base)/api/v1/api-role-privileges?page-size=1") else { return "Invalid URL." }
            let (_, response) = try await request(url: url, bearerToken: token)
            if response.statusCode == 200 || response.statusCode == 201 {
                return nil
            }
            return "Server returned \(response.statusCode)."
        } catch {
            return error.localizedDescription
        }
    }

    /// Create a single API role in Jamf Pro with the given display name and privilege names (from script analysis).
    /// POST body uses privilege names as strings (per Jamf Pro API: displayName + privileges: [String]).
    func createRole(displayName: String, privilegeNames: [String]) async {
        lastError = nil
        lastSuccessMessage = nil
        guard let creds = loadCredentials() else {
            lastError = "No Jamf Pro credentials. Add them in Jamf Pro Settings."
            return
        }
        let base = creds.baseURLNormalized
        guard !base.isEmpty else {
            lastError = "Invalid Jamf Pro URL."
            return
        }
        guard !privilegeNames.isEmpty else {
            lastError = "No privileges to add. Run script analysis first."
            return
        }
        isCreating = true
        defer { isCreating = false }

        do {
            guard let token = try await fetchToken(baseURL: base, credentials: creds) else {
                lastError = "Could not obtain Jamf Pro token. Check URL and credentials."
                return
            }
            
            // Optionally filter to only privileges the server knows (if we can fetch the list).
            let privilegesToSend: [String]
            var skippedMessageSuffix: String = ""
            if let (valid, invalid) = try? await filterValidPrivileges(baseURL: base, bearerToken: token, requestedNames: privilegeNames) {
                if !valid.isEmpty {
                    // Create the role with all valid privileges Jamf reports
                    privilegesToSend = valid
                    
                    if !invalid.isEmpty {
                        skippedMessageSuffix = """
                        
                        The following privileges could not be attached automatically because they are not available on this Jamf Pro server. Add them (or their closest equivalents) manually if needed:
                        \(invalid.joined(separator: ", "))
                        """
                    }
                } else if !invalid.isEmpty {
                    // None of the requested privilege names exist on this Jamf server
                    lastError = """
                    None of the requested privileges exist on this Jamf Pro server.
                    
                    Missing privileges:
                    \(invalid.joined(separator: ", "))
                    """
                    return
                } else {
                    // Unexpected edge case; fall back to sending raw names
                    privilegesToSend = privilegeNames
                }
            } else {
                // Could not fetch or decode privilege list — send requested names and let server validate
                privilegesToSend = privilegeNames
            }
            
            try await postCreateRole(baseURL: base, bearerToken: token, displayName: displayName, privilegeNames: privilegesToSend)
            lastSuccessMessage = """
            Role \"\(displayName)\" was created in Jamf Pro with \(privilegesToSend.count) privileges.\(skippedMessageSuffix)
            
            If some privileges could not be attached automatically, edit the role manually in Jamf Pro to add them, and check the Jamf Developer documentation to confirm those privileges are still valid for the endpoints your script uses.
            """
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func basicAuthHeader(username: String, password: String) -> String {
        let data = "\(username):\(password)".data(using: .utf8)!
        return data.base64EncodedString()
    }

    /// POST /api/v1/auth/token with Basic auth; returns Bearer token for use with other endpoints.
    private func fetchToken(baseURL: String, credentials: JamfProCredentials) async throws -> String? {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/token") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Basic \(basicAuthHeader(username: credentials.username, password: credentials.password))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw JamfProError.invalidResponse }
        guard http.statusCode == 200 else {
            throw JamfProError.apiError(http.statusCode, String(data: data, encoding: .utf8))
        }
        let decoded = try? JSONDecoder().decode(JamfAuthTokenResponse.self, from: data)
        return decoded?.token
    }

    private func request(url: URL, bearerToken: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw JamfProError.invalidResponse
        }
        return (data, http)
    }

    /// Fetch the list of available privileges from Jamf Pro and return which requested names are valid.
    /// If the request or response decode fails, returns (requestedNames, []) so callers can still attempt create.
    private func filterValidPrivileges(baseURL: String, bearerToken: String, requestedNames: [String]) async throws -> (valid: [String], invalid: [String]) {
        guard let url = URL(string: "\(baseURL)/api/v1/api-role-privileges?page-size=1000") else {
            throw JamfProError.badURL
        }
        let (data, response) = try await request(url: url, bearerToken: bearerToken)
        guard response.statusCode == 200 || response.statusCode == 201 else {
            return (requestedNames, [])
        }
        guard let allPrivileges = try? decodePrivilegeList(from: data), !allPrivileges.isEmpty else {
            // Response format not recognized — don't throw; let create role use requested names and server will validate
            return (requestedNames, [])
        }
        
        // Normalize names to be resilient to punctuation / spacing / dash differences
        func normalize(_ s: String) -> String {
            let lower = s.lowercased()
                .replacingOccurrences(of: "–", with: " ") // en dash
                .replacingOccurrences(of: "-", with: " ")
            let components = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            return components.joined()
        }
        
        // Map normalized Jamf privilege names to the server's canonical displayName/name
        var serverByNormalized: [String: String] = [:]
        for p in allPrivileges {
            let canonical = p.displayNameOrName
            guard !canonical.isEmpty else { continue }
            let key = normalize(canonical)
            if serverByNormalized[key] == nil {
                serverByNormalized[key] = canonical
            }
        }
        
        let uniqueRequested = Array(Set(requestedNames))
        var valid: [String] = []
        var invalid: [String] = []
        
        for name in uniqueRequested {
            let key = normalize(name)
            if let canonical = serverByNormalized[key] {
                valid.append(canonical)
            } else {
                invalid.append(name)
            }
        }
        
        return (valid, invalid)
    }

    /// POST /api/v1/api-roles to create a role. Body: { displayName, privileges: [String] } per Jamf Pro API.
    private func postCreateRole(baseURL: String, bearerToken: String, displayName: String, privilegeNames: [String]) async throws {
        let urlString = "\(baseURL)/api/v1/api-roles"
        guard let url = URL(string: urlString) else { throw JamfProError.badURL }
        let body = CreateRoleRequest(displayName: displayName, privileges: privilegeNames)
        let bodyData = try JSONEncoder().encode(body)
        let (data, response) = try await request(url: url, bearerToken: bearerToken, method: "POST", body: bodyData)
        if response.statusCode == 200 || response.statusCode == 201 {
            return
        }
        let rawBody = String(data: data, encoding: .utf8)
        if let apiError = try? JSONDecoder().decode(JamfAPIErrorResponse.self, from: data),
           let first = apiError.errors.first, !first.description.isEmpty {
            throw JamfProError.apiError(response.statusCode, first.description)
        }
        // Fallback: try to extract any "description" or "message" from JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = json["errors"] as? [[String: Any]],
           let first = errors.first,
           let desc = first["description"] as? String ?? first["message"] as? String, !desc.isEmpty {
            throw JamfProError.apiError(response.statusCode, desc)
        }
        throw JamfProError.apiError(response.statusCode, rawBody ?? "HTTP \(response.statusCode)")
    }
}

// MARK: - API models (match Jamf Pro API shape)
private struct JamfAuthTokenResponse: Codable {
    let token: String
    let expires: String?
}

/// Decode GET api-role-privileges response; Jamf may return { results: [...] }, { privileges: [...] }, or a top-level array.
private func decodePrivilegeList(from data: Data) throws -> [JamfPrivilege] {
    let decoder = JSONDecoder()
    if let wrapper = try? decoder.decode(JamfPrivilegeListResponse.self, from: data) {
        return wrapper.all
    }
    if let topLevel = try? decoder.decode([JamfPrivilege].self, from: data) {
        return topLevel
    }
    if let parsed = parsePrivilegeListFromRawJSON(data: data) {
        return parsed
    }
    throw JamfProError.invalidResponse
}

/// Fallback: parse with JSONSerialization and extract id + displayName/name from any array structure.
private func parsePrivilegeListFromRawJSON(data: Data) -> [JamfPrivilege]? {
    guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
    var rawList: [[String: Any]]?
    if let topArray = raw as? [[String: Any]] {
        rawList = topArray
    } else if let obj = raw as? [String: Any] {
        rawList = obj["results"] as? [[String: Any]]
            ?? obj["privileges"] as? [[String: Any]]
            ?? obj["data"] as? [[String: Any]]
        if rawList == nil {
            for (_, value) in obj {
                if let arr = value as? [[String: Any]], !arr.isEmpty, arr[0]["id"] != nil || arr[0]["privilegeId"] != nil {
                    rawList = arr
                    break
                }
            }
        }
    }
    guard let list = rawList else { return nil }
    return list.compactMap(parsePrivilegeFromDict)
}

private func parsePrivilegeFromDict(_ item: [String: Any]) -> JamfPrivilege? {
    let idStr: String? = (item["id"] as? String)
        ?? (item["privilegeId"] as? String)
        ?? (item["id"] as? Int).map { String($0) }
    guard let id = idStr, !id.isEmpty else { return nil }
    let displayName = item["displayName"] as? String
    let name = item["name"] as? String
    return JamfPrivilege(id: id, displayName: displayName, name: name)
}

private struct JamfPrivilegeListResponse: Codable {
    let totalCount: Int?
    let results: [JamfPrivilege]?
    let privileges: [JamfPrivilege]?
    var all: [JamfPrivilege] {
        results ?? privileges ?? []
    }
}

private struct JamfPrivilege: Codable {
    let id: String
    let displayName: String?
    let name: String?
    var displayNameOrName: String {
        displayName ?? name ?? ""
    }
    init(id: String, displayName: String?, name: String?) {
        self.id = id
        self.displayName = displayName
        self.name = name
    }
    enum CodingKeys: String, CodingKey {
        case id, displayName, name
        case privilegeId = "privilegeId"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let s = try? c.decode(String.self, forKey: .privilegeId) {
            id = s
        } else if let n = try? c.decode(Int.self, forKey: .id) {
            id = String(n)
        } else {
            id = ""
        }
        displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(name, forKey: .name)
    }
}

/// Request body for POST /api/v1/api-roles (privileges are names as strings).
private struct CreateRoleRequest: Codable {
    let displayName: String
    let privileges: [String]
}

/// Jamf Pro error response shape for 400/4xx.
private struct JamfAPIErrorResponse: Codable {
    let httpStatus: Int?
    let errors: [JamfAPIErrorCause]
}

private struct JamfAPIErrorCause: Codable {
    let field: String?
    let description: String
    let code: String?
}

enum JamfProError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case apiError(Int, String?)
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .apiError(let code, let body): return "Jamf Pro API error \(code): \(body ?? "no body")"
        }
    }
}
