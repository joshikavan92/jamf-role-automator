//
//  GitHubRoleService.swift
//  RoleAutomator
//
//  Created by Kavan Joshi on 10/10/2025.
//  Fetches Jamf role definitions from GitHub repository
//

import Foundation
import Combine

// MARK: - GitHub Configuration
struct GitHubConfig {
    static let owner = "joshikavan92"
    static let repo = "roleAutomatorRoles"
    static let branch = "main"
    
    // Raw GitHub URLs for role files
    static let baseURL = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)"
    static let rolesURL = "\(baseURL)/roles/jamf-roles.json"

    /// If set (e.g. via UserDefaults "RoleAutomatorRolesURL"), use this URL instead of rolesURL.
    /// Use when your network cannot reach raw.githubusercontent.com (e.g. corporate firewall).
    static var effectiveRolesURL: String {
        if let custom = UserDefaults.standard.string(forKey: "RoleAutomatorRolesURL"),
           !custom.isEmpty,
           URL(string: custom) != nil {
            return custom
        }
        return rolesURL
    }
    static let classicAPIURL = "\(baseURL)/roles/classic-api-roles.json"
    static let jamfProAPIURL = "\(baseURL)/roles/jamf-pro-api-roles.json"
    static let privilegeCategoriesURL = "\(baseURL)/roles/privilege-categories.json"
}

// MARK: - Role Models for GitHub JSON
struct RoleDatabase: Codable {
    let version: String
    let lastUpdated: String
    let metadata: Metadata
    let privilegeCategories: [String: [String]]
    let allPrivileges: [String]
    let classicApi: APISection
    let jamfProApi: APISection
    
    enum CodingKeys: String, CodingKey {
        case version
        case lastUpdated = "last_updated"
        case metadata
        case privilegeCategories = "privilege_categories"
        case allPrivileges = "all_privileges"
        case classicApi = "classic_api"
        case jamfProApi = "jamf_pro_api"
    }
    
    struct Metadata: Codable {
        let description: String
        let source: String
        let documentationUrls: [String]
        
        enum CodingKeys: String, CodingKey {
            case description, source
            case documentationUrls = "documentation_urls"
        }
    }
    
    struct APISection: Codable {
        let description: String
        let endpoints: [Endpoint]
    }
    
    struct Endpoint: Codable {
        let endpoint: String
        let operation: String
        let privileges: [String]
        let deprecationDate: String?
        
        enum CodingKeys: String, CodingKey {
            case endpoint, operation, privileges
            case deprecationDate = "deprecation_date"
        }
    }
}

// MARK: - Cache Manager
class RoleCacheManager {
    static let shared = RoleCacheManager()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("RoleAutomator")
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func cacheURL(for filename: String) -> URL {
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    func saveToCache(data: Data, filename: String) {
        let url = cacheURL(for: filename)
        try? data.write(to: url)
        print("✅ Cached \(filename)")
    }
    
    func loadFromCache(filename: String) -> Data? {
        let url = cacheURL(for: filename)
        return try? Data(contentsOf: url)
    }
    
    func getCacheAge(filename: String) -> TimeInterval? {
        let url = cacheURL(for: filename)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return Date().timeIntervalSince(modificationDate)
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("🗑️ Cache cleared")
    }
}

// MARK: - GitHub Role Service
@MainActor
class GitHubRoleService: ObservableObject {
    static let shared = GitHubRoleService()
    
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?
    @Published var cacheStatus: String = "Not loaded"
    @Published var errorMessage: String?
    
    private let cache = RoleCacheManager.shared
    private let maxCacheAge: TimeInterval = 86400 // 24 hours
    
    private init() {}
    
    // MARK: - Fetch Role Database
    func fetchRoleDatabase(forceRefresh: Bool = false) async throws -> RoleDatabase {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let filename = "jamf-roles.json"
        
        // Check cache first if not forcing refresh
        if !forceRefresh,
           let cachedData = cache.loadFromCache(filename: filename),
           let cacheAge = cache.getCacheAge(filename: filename),
           cacheAge < maxCacheAge {
            
            print("📦 Using cached data (age: \(Int(cacheAge/3600)) hours)")
            cacheStatus = "Loaded from cache (\(Int(cacheAge/3600))h old)"
            
            let database = try JSONDecoder().decode(RoleDatabase.self, from: cachedData)
            if let updateDate = ISO8601DateFormatter().date(from: database.lastUpdated) {
                lastUpdateTime = updateDate
            }
            return database
        }
        
        // Fetch from configured URL (GitHub or custom mirror)
        let urlString = GitHubConfig.effectiveRolesURL
        print("🌐 Fetching from \(urlString)...")
        cacheStatus = "Downloading..."
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Cache the data
        cache.saveToCache(data: data, filename: filename)
        
        let database = try JSONDecoder().decode(RoleDatabase.self, from: data)
        if let updateDate = ISO8601DateFormatter().date(from: database.lastUpdated) {
            lastUpdateTime = updateDate
        }
        
        cacheStatus = "Loaded from GitHub"
        print("✅ Fetched \(database.classicApi.endpoints.count + database.jamfProApi.endpoints.count) endpoints")
        
        return database
    }
    
    // MARK: - Fetch Classic API Roles Only
    func fetchClassicAPIRoles(forceRefresh: Bool = false) async throws -> [APIRole] {
        let database = try await fetchRoleDatabase(forceRefresh: forceRefresh)
        return database.classicApi.endpoints.map { endpoint in
            APIRole(
                endpoint: endpoint.endpoint,
                operation: endpoint.operation,
                requiredPrivileges: endpoint.privileges,
                deprecationDate: endpoint.deprecationDate,
                apiType: .classic
            )
        }
    }
    
    // MARK: - Fetch Jamf Pro API Roles Only
    func fetchJamfProAPIRoles(forceRefresh: Bool = false) async throws -> [APIRole] {
        let database = try await fetchRoleDatabase(forceRefresh: forceRefresh)
        return database.jamfProApi.endpoints.map { endpoint in
            APIRole(
                endpoint: endpoint.endpoint,
                operation: endpoint.operation,
                requiredPrivileges: endpoint.privileges,
                deprecationDate: endpoint.deprecationDate,
                apiType: .jamfPro
            )
        }
    }
    
    // MARK: - Fetch All Roles
    func fetchAllRoles(forceRefresh: Bool = false) async throws -> [APIRole] {
        let database = try await fetchRoleDatabase(forceRefresh: forceRefresh)
        
        var allRoles: [APIRole] = []
        
        // Add Classic API roles
        allRoles += database.classicApi.endpoints.map { endpoint in
            APIRole(
                endpoint: endpoint.endpoint,
                operation: endpoint.operation,
                requiredPrivileges: endpoint.privileges,
                deprecationDate: endpoint.deprecationDate,
                apiType: .classic
            )
        }
        
        // Add Jamf Pro API roles
        allRoles += database.jamfProApi.endpoints.map { endpoint in
            APIRole(
                endpoint: endpoint.endpoint,
                operation: endpoint.operation,
                requiredPrivileges: endpoint.privileges,
                deprecationDate: endpoint.deprecationDate,
                apiType: .jamfPro
            )
        }
        
        return allRoles
    }
    
    // MARK: - Get Privilege Categories
    func fetchPrivilegeCategories(forceRefresh: Bool = false) async throws -> [String: [String]] {
        let database = try await fetchRoleDatabase(forceRefresh: forceRefresh)
        return database.privilegeCategories
    }
    
    // MARK: - Check for Updates
    func checkForUpdates() async throws -> Bool {
        _ = try await fetchRoleDatabase(forceRefresh: true)
        return true // Successfully fetched new data
    }
    
    // MARK: - Clear Cache
    func clearCache() {
        cache.clearCache()
        cacheStatus = "Cache cleared"
        lastUpdateTime = nil
    }
    
    // MARK: - Get Cache Info
    func getCacheInfo() -> String {
        let filename = "jamf-roles.json"
        if let cacheAge = cache.getCacheAge(filename: filename) {
            let hours = Int(cacheAge / 3600)
            let minutes = Int((cacheAge.truncatingRemainder(dividingBy: 3600)) / 60)
            return "Cache age: \(hours)h \(minutes)m"
        }
        return "No cache"
    }
}

// MARK: - Preview Helpers
extension GitHubRoleService {
    static func mock() -> GitHubRoleService {
        let service = GitHubRoleService()
        service.cacheStatus = "Mock data loaded"
        service.lastUpdateTime = Date()
        return service
    }
}

