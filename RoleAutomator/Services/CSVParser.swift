import Foundation
import Combine

class CSVParser: ObservableObject {
    @Published var classicAPIRoles: [APIRole] = []
    @Published var jamfProAPIRoles: [APIRole] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadAPIRoles() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Load Classic API roles
                let classicRoles = try self.parseClassicAPICSV()
                
                // Load Jamf Pro API roles
                let jamfProRoles = try self.parseJamfProAPICSV()
                
                DispatchQueue.main.async {
                    self.classicAPIRoles = classicRoles
                    self.jamfProAPIRoles = jamfProRoles
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load API roles: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func parseClassicAPICSV() throws -> [APIRole] {
        guard let url = Bundle.main.url(forResource: "ClassicAPIRoles", withExtension: "csv") else {
            throw CSVParserError.fileNotFound("ClassicAPIRoles.csv")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var roles: [APIRole] = []
        
        for (index, line) in lines.enumerated() {
            if index == 0 || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue // Skip header and empty lines
            }
            
            let components = line.components(separatedBy: ",")
            guard components.count >= 3 else { continue }
            
            let endpoint = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let operation = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let privileges = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Handle multiple privileges separated by newlines
            let privilegeList = privileges.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            let role = APIRole(
                endpoint: endpoint,
                operation: operation,
                requiredPrivileges: privilegeList,
                apiType: .classic
            )
            
            roles.append(role)
        }
        
        return roles
    }
    
    private func parseJamfProAPICSV() throws -> [APIRole] {
        guard let url = Bundle.main.url(forResource: "JamfProAPIRoles", withExtension: "csv") else {
            throw CSVParserError.fileNotFound("JamfProAPIRoles.csv")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var roles: [APIRole] = []
        
        for (index, line) in lines.enumerated() {
            if index == 0 || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue // Skip header and empty lines
            }
            
            let components = line.components(separatedBy: ",")
            guard components.count >= 3 else { continue }
            
            let endpoint = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let operation = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let privileges = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let deprecationDate = components.count > 3 ? components[3].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            
            // Handle multiple privileges separated by newlines
            let privilegeList = privileges.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            let role = APIRole(
                endpoint: endpoint,
                operation: operation,
                requiredPrivileges: privilegeList,
                deprecationDate: deprecationDate,
                apiType: .jamfPro
            )
            
            roles.append(role)
        }
        
        return roles
    }
}

enum CSVParserError: Error, LocalizedError {
    case fileNotFound(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Could not find file: \(filename)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
} 