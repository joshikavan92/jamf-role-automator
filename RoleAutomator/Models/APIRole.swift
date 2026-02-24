import Foundation

struct APIRole: Identifiable, Codable {
    let id: UUID
    let endpoint: String
    let operation: String
    let requiredPrivileges: [String]
    let deprecationDate: String?
    let apiType: APIType
    
    enum APIType: String, Codable, CaseIterable {
        case classic = "Classic API"
        case jamfPro = "Jamf Pro API"
    }
    
    init(id: UUID = UUID(), endpoint: String, operation: String, requiredPrivileges: [String], deprecationDate: String? = nil, apiType: APIType) {
        self.id = id
        self.endpoint = endpoint
        self.operation = operation.uppercased()
        self.requiredPrivileges = requiredPrivileges
        self.deprecationDate = deprecationDate
        self.apiType = apiType
    }
}

struct ScriptAnalysis: Identifiable {
    let id = UUID()
    let fileName: String
    let fileType: ScriptType
    let detectedEndpoints: [DetectedEndpoint]
    let authenticationMethod: AuthenticationMethod
    let requiredRoles: [APIRole]
    let analysisDate: Date
    
    enum ScriptType: String, CaseIterable {
        case bash = "Bash"
        case zsh = "Zsh"
        case shell = "Shell"
        case python = "Python"
        case swift = "Swift"
        case powershell = "PowerShell"
        case applescript = "AppleScript"
        case text = "Text file"
        case unknown = "Unknown"
    }
    
    enum AuthenticationMethod: String, CaseIterable {
        case clientCredentials = "Client ID & Secret"
        case usernamePassword = "Username & Password"
        case unknown = "Unknown"
    }
}

struct DetectedEndpoint: Identifiable {
    let id = UUID()
    let endpoint: String
    let operation: String
    let lineNumber: Int
    let context: String
} 