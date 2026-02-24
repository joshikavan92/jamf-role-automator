import Foundation
import Combine

class ScriptAnalyzer: ObservableObject {
    @Published var isAnalyzing = false
    @Published var analysisResult: ScriptAnalysis?
    @Published var errorMessage: String?
    
    private let csvParser: CSVParser
    
    init(csvParser: CSVParser) {
        self.csvParser = csvParser
    }
    
    func analyzeScript(fileURL: URL) {
        isAnalyzing = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let scriptContent = try String(contentsOf: fileURL, encoding: .utf8)
                let analysis = try self.performAnalysis(scriptContent: scriptContent, fileName: fileURL.lastPathComponent)
                
                DispatchQueue.main.async {
                    self.analysisResult = analysis
                    self.isAnalyzing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to analyze script: \(error.localizedDescription)"
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func performAnalysis(scriptContent: String, fileName: String) throws -> ScriptAnalysis {
        let lines = scriptContent.components(separatedBy: .newlines)
        let fileType = detectFileType(fileName: fileName, content: scriptContent)
        let authenticationMethod = detectAuthenticationMethod(content: scriptContent)
        let detectedEndpoints = detectAPIEndpoints(content: scriptContent, lines: lines)
        let requiredRoles = findRequiredRoles(endpoints: detectedEndpoints)
        
        return ScriptAnalysis(
            fileName: fileName,
            fileType: fileType,
            detectedEndpoints: detectedEndpoints,
            authenticationMethod: authenticationMethod,
            requiredRoles: requiredRoles,
            analysisDate: Date()
        )
    }
    
    private func detectFileType(fileName: String, content: String) -> ScriptAnalysis.ScriptType {
        let lowercasedFileName = fileName.lowercased()
        let lowercasedContent = content.lowercased()
        
        // Python
        if lowercasedFileName.hasSuffix(".py") ||
            lowercasedContent.contains("import requests") ||
            lowercasedContent.contains("import urllib") {
            return .python
        }
        
        // Zsh
        if lowercasedFileName.hasSuffix(".zsh") ||
            lowercasedContent.contains("#!/bin/zsh") {
            return .zsh
        }
        
        // Bash / sh
        if lowercasedFileName.hasSuffix(".sh") ||
            lowercasedFileName.hasSuffix(".bash") ||
            lowercasedContent.contains("#!/bin/bash") ||
            lowercasedContent.contains("#!/bin/sh") {
            return .bash
        }
        
        // Swift CLI tools that call Jamf APIs
        if lowercasedFileName.hasSuffix(".swift") ||
            (lowercasedContent.contains("urlsession") &&
             (lowercasedContent.contains("/jssresource/") || lowercasedContent.contains("/api/"))) {
            return .swift
        }
        
        // PowerShell (for cross-platform Jamf scripts)
        if lowercasedFileName.hasSuffix(".ps1") ||
            lowercasedContent.contains("invoke-restmethod") ||
            lowercasedContent.contains("invoke-webrequest") {
            return .powershell
        }
        
        // AppleScript that shells out to curl
        if lowercasedFileName.hasSuffix(".applescript") ||
            lowercasedContent.contains("do shell script") {
            return .applescript
        }
        
        // Generic shell scripts (curl / wget etc.)
        if lowercasedContent.contains("curl") || lowercasedContent.contains("wget") {
            return .shell
        }
        
        // Plain text files that still contain API endpoints
        if lowercasedFileName.hasSuffix(".txt") ||
            lowercasedFileName.hasSuffix(".log") ||
            lowercasedFileName.hasSuffix(".md") {
            return .text
        }
        
        return .unknown
    }
    
    private func detectAuthenticationMethod(content: String) -> ScriptAnalysis.AuthenticationMethod {
        let lowercasedContent = content.lowercased()
        
        // Check for client credentials
        if lowercasedContent.contains("client_id") || lowercasedContent.contains("client_secret") || lowercasedContent.contains("clientid") || lowercasedContent.contains("clientsecret") {
            return .clientCredentials
        }
        
        // Check for username/password
        if lowercasedContent.contains("username") || lowercasedContent.contains("password") || lowercasedContent.contains("user") || lowercasedContent.contains("pass") {
            return .usernamePassword
        }
        
        return .unknown
    }
    
    private func detectAPIEndpoints(content: String, lines: [String]) -> [DetectedEndpoint] {
        var endpoints: [DetectedEndpoint] = []
        // Only match Jamf Classic API (JSSResource) and Jamf Pro API (/api/)
        let apiPatterns = [
            #"JSSResource/[a-zA-Z0-9\-_/]+"#, // Classic API
            #"/api/[a-zA-Z0-9\-_/]+"# // Jamf Pro API
        ]
        for (lineIndex, line) in lines.enumerated() {
            for pattern in apiPatterns {
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: line.utf16.count)
                if let matches = regex?.matches(in: line, options: [], range: range) {
                    for match in matches {
                        if let range = Range(match.range, in: line) {
                            let endpoint = String(line[range])
                            let operation = detectHTTPMethod(line: line)
                            let detectedEndpoint = DetectedEndpoint(
                                endpoint: endpoint,
                                operation: operation,
                                lineNumber: lineIndex + 1,
                                context: line.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            endpoints.append(detectedEndpoint)
                        }
                    }
                }
            }
        }
        return endpoints
    }
    
    private func detectHTTPMethod(line: String) -> String {
        let lowercasedLine = line.lowercased()
        
        if lowercasedLine.contains("-x post") || lowercasedLine.contains("--request post") || lowercasedLine.contains(".post(") {
            return "POST"
        } else if lowercasedLine.contains("-x put") || lowercasedLine.contains("--request put") || lowercasedLine.contains(".put(") {
            return "PUT"
        } else if lowercasedLine.contains("-x delete") || lowercasedLine.contains("--request delete") || lowercasedLine.contains(".delete(") {
            return "DELETE"
        } else if lowercasedLine.contains("-x get") || lowercasedLine.contains("--request get") || lowercasedLine.contains(".get(") {
            return "GET"
        } else {
            return "GET" // Default to GET
        }
    }
    
    private func findRequiredRoles(endpoints: [DetectedEndpoint]) -> [APIRole] {
        var requiredRoles: [APIRole] = []
        let allRoles = csvParser.classicAPIRoles + csvParser.jamfProAPIRoles
        
        func normalizedPath(_ raw: String) -> String {
            var path = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            
            // Strip common API prefixes that are not present in the role database
            if path.hasPrefix("api/") {
                path.removeFirst("api/".count)
            }
            if path.hasPrefix("jssresource/") {
                path.removeFirst("jssresource/".count)
            }
            
            // Normalize numeric IDs to {id} so that:
            // - /categories/id/123  → /categories/id/{id}
            // - /computergroups/id/0 → /computergroups/id/{id}
            path = path.replacingOccurrences(
                of: #"/id/[^/]+"#,
                with: "/id/{id}",
                options: .regularExpression
            )
            
            return path
        }
        
        func endpointMatches(detected: String, role: String) -> Bool {
            let detectedClean = normalizedPath(detected)
            let roleClean = normalizedPath(role)
            
            if detectedClean == roleClean { return true }
            
            // Support "..." wildcard in role definitions like "/computerapplications/..."
            if roleClean.contains("...") {
                let base = roleClean.replacingOccurrences(of: "...", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !base.isEmpty, detectedClean.hasPrefix(base) {
                    return true
                }
            }
            
            // Segment-by-segment comparison, treating {id}, {idtype}, {status}, etc. as wildcards
            let detectedSegments = detectedClean.split(separator: "/")
            let roleSegments = roleClean.split(separator: "/")
            
            // Exact-length match with placeholders
            if detectedSegments.count == roleSegments.count {
                var allMatch = true
                for (roleSeg, detectedSeg) in zip(roleSegments, detectedSegments) {
                    if roleSeg == detectedSeg {
                        continue
                    }
                    // Any "{...}" in the role definition is treated as a wildcard
                    if roleSeg.hasPrefix("{"), roleSeg.hasSuffix("}") {
                        continue
                    }
                    // "..." segment in role definition matches anything
                    if roleSeg == "..." {
                        continue
                    }
                    allMatch = false
                    break
                }
                if allMatch {
                    return true
                }
            }
            
            // Example: detected "v1/computers-inventory/7" vs role "v1/computers-inventory"
            if detectedClean.hasPrefix(roleClean + "/") { return true }
            
            // Fallback: detected ends with role as a path segment
            if detectedClean.hasSuffix("/" + roleClean) { return true }
            
            return false
        }
        
        for endpoint in endpoints {
            let matchingRoles = allRoles.filter { role in
                let operationMatches = role.operation.lowercased() == endpoint.operation.lowercased()
                return operationMatches && endpointMatches(detected: endpoint.endpoint, role: role.endpoint)
            }
            requiredRoles.append(contentsOf: matchingRoles)
        }
        // Remove duplicates based on endpoint and operation
        return Array(Set(requiredRoles.map { "\($0.endpoint)-\($0.operation)" })).compactMap { key in
            requiredRoles.first { "\($0.endpoint)-\($0.operation)" == key }
        }
    }
} 