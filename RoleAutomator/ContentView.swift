//
//  ContentView.swift
//  RoleAutomator
//
//  Created by Kavan Joshi on 6/28/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: RoleAutomatorAppState
    @StateObject private var csvParser = CSVParser()
    @StateObject private var githubService = GitHubRoleService.shared
    @StateObject private var jamfProService = JamfProService()
    @StateObject private var scriptAnalyzer: ScriptAnalyzer
    @State private var selectedFileURL: URL?
    @State private var showingFilePicker = false
    @State private var showingRoleBrowser = false
    @State private var showingJamfCredentials = false
    @State private var showingCreateInJamfPro = false
    @State private var useGitHub = true // Toggle between GitHub and local CSV
    @State private var selectedUEMTemplateIds: Set<String> = []
    @State private var expandedUEMTemplateIds: Set<String> = []
    @State private var templateCreatePayload: TemplateCreatePayload?
    
    init() {
        let parser = CSVParser()
        self._csvParser = StateObject(wrappedValue: parser)
        self._scriptAnalyzer = StateObject(wrappedValue: ScriptAnalyzer(csvParser: parser))
    }
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            mainBody
        }
        #else
        mainBody
        #endif
    }
    
    private var mainBody: some View {
        VStack(spacing: 0) {
            headerView
            
            if let analysis = scriptAnalyzer.analysisResult {
                analysisResultView(analysis)
            } else {
                mainContentView
            }
            
            Spacer(minLength: 0)
            
            footerView
        }
        .onAppear {
            Task {
                do {
                    _ = try await githubService.fetchRoleDatabase(forceRefresh: false)
                    let classicRoles = try await githubService.fetchClassicAPIRoles()
                    let jamfProRoles = try await githubService.fetchJamfProAPIRoles()
                    csvParser.classicAPIRoles = classicRoles
                    csvParser.jamfProAPIRoles = jamfProRoles
                } catch {
                    print("⚠️ Failed to load roles from GitHub: \(error.localizedDescription)")
                    await MainActor.run {
                        githubService.errorMessage = "GitHub unreachable (check network/VPN). Could not load role data."
                        csvParser.errorMessage = "Failed to load roles from GitHub. Please check your network or Git configuration."
                        csvParser.isLoading = false
                        csvParser.classicAPIRoles = []
                        csvParser.jamfProAPIRoles = []
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            FilePicker(selectedFileURL: $selectedFileURL)
        }
        .sheet(isPresented: $showingRoleBrowser) {
            RoleBrowserView(csvParser: csvParser)
        }
        .sheet(isPresented: $showingJamfCredentials) {
            JamfProCredentialsSheet(jamfProService: jamfProService)
        }
        .sheet(isPresented: $showingCreateInJamfPro) {
            if let analysis = scriptAnalyzer.analysisResult, !analysis.requiredRoles.isEmpty {
                CreateRoleInJamfSheet(
                    jamfProService: jamfProService,
                    defaultRoleName: "RoleAutomator - \(analysis.fileName)",
                    privilegeNames: uniquePrivilegeNames(from: analysis.requiredRoles),
                    onDismiss: { showingCreateInJamfPro = false }
                )
            }
        }
        .sheet(item: $templateCreatePayload) { payload in
            CreateRoleInJamfSheet(
                jamfProService: jamfProService,
                defaultRoleName: payload.roleName,
                privilegeNames: payload.privileges,
                onDismiss: { templateCreatePayload = nil }
            )
        }
        .onChange(of: selectedFileURL) { _, url in
            if let url = url {
                scriptAnalyzer.analyzeScript(fileURL: url)
            }
        }
        .sheet(isPresented: $appState.showAbout) {
            AboutRoleAutomatorView()
        }
        .sheet(isPresented: $appState.showTips) {
            RoleAutomatorTipsView()
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                #if os(macOS)
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                #else
                Image(systemName: "shield.checkered")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                #endif
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("RoleAutomator")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Jamf Pro API Role Analysis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if scriptAnalyzer.analysisResult != nil {
                    Button(action: {
                        scriptAnalyzer.analysisResult = nil
                        selectedFileURL = nil
                    }) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tint)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Return to home")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 18) {
                welcomeSection
                actionButtonsSection
                templatesSection
                roleDatabaseSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
    
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                HStack(spacing: 12) {
                    Button {
                        appState.showAbout = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12, weight: .medium))
                            Text("About")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        appState.showTips = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 12, weight: .medium))
                            Text("Tips")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("RoleAutomator for Jamf Pro")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("© 2026 Kavan Joshi")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private var welcomeSection: some View {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 6) {
                Text("Analyze Your Scripts")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Upload your Bash, Zsh, Shell, Python, Swift, AppleScript, PowerShell, or text-based scripts to automatically identify required Jamf Pro API roles and privileges.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 16)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                showingFilePicker = true
            }) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)
                        .frame(width: 28, alignment: .center)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload Script")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Analyze Bash, Zsh, Shell, Python, Swift, AppleScript, PowerShell, or text files")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button(action: {
                showingRoleBrowser = true
            }) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)
                        .frame(width: 28, alignment: .center)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse Roles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text("View available API roles and privileges")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Templates")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            DisclosureGroup(isExpanded: Binding(
                get: { expandedUEMTemplateIds.contains("security-cloud") },
                set: { if $0 { expandedUEMTemplateIds.insert("security-cloud") } else { expandedUEMTemplateIds.remove("security-cloud") } }
            )) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(UEMTemplate.securityCloudUEMSetup) { template in
                        uemTemplateRow(template)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cloud.connected.arrow.up.down")
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)
                    Text("Security Cloud UEM Setup")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            if !selectedUEMTemplateIds.isEmpty {
                Button(action: {
                    let privileges = aggregatedTemplatePrivileges()
                    guard !privileges.isEmpty else { return }
                    templateCreatePayload = TemplateCreatePayload(roleName: "Security Cloud UEM Setup", privileges: privileges)
                }) {
                    Label("Create Role on Jamf Pro", systemImage: "arrow.up.doc")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Link(destination: URL(string: "mailto:joshikavan92@gmail.com?subject=RoleAutomator%20Template%20Suggestion")!) {
                Label("Suggest a template", systemImage: "envelope.badge")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func uemTemplateRow(_ template: UEMTemplate) -> some View {
        let isExpanded = expandedUEMTemplateIds.contains(template.id)
        let isSelected = selectedUEMTemplateIds.contains(template.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedUEMTemplateIds.contains(template.id) {
                        expandedUEMTemplateIds.remove(template.id)
                    } else {
                        expandedUEMTemplateIds.insert(template.id)
                    }
                }
            }) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: {
                        if selectedUEMTemplateIds.contains(template.id) {
                            selectedUEMTemplateIds.remove(template.id)
                        } else {
                            selectedUEMTemplateIds.insert(template.id)
                        }
                    }) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.body)
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text(template.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(template.privileges, id: \.self) { privilege in
                        Text("• \(privilege)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
    
    private func aggregatedTemplatePrivileges() -> [String] {
        let selected = UEMTemplate.securityCloudUEMSetup.filter { selectedUEMTemplateIds.contains($0.id) }
        let all = selected.flatMap(\.privileges)
        return Array(Set(all)).sorted()
    }
    
    private var roleDatabaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Role Database Status")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if useGitHub {
                    Button(action: {
                        Task {
                            do {
                                _ = try await githubService.fetchRoleDatabase(forceRefresh: true)
                                let classicRoles = try await githubService.fetchClassicAPIRoles()
                                let jamfProRoles = try await githubService.fetchJamfProAPIRoles()
                                csvParser.classicAPIRoles = classicRoles
                                csvParser.jamfProAPIRoles = jamfProRoles
                            } catch {
                                print("⚠️ Failed to refresh: \(error.localizedDescription)")
                            }
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundStyle(.tint)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(githubService.isLoading)
                }
                
                if csvParser.isLoading || githubService.isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
            }
            
            if let error = csvParser.errorMessage ?? githubService.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        Image(systemName: useGitHub ? "cloud.fill" : "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(useGitHub ? .accentColor : .orange)
                        Text(useGitHub ? "GitHub" : "Local CSV")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if useGitHub {
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(githubService.cacheStatus)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Classic API Roles")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("\(csvParser.classicAPIRoles.count) roles loaded")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Jamf Pro API Roles")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("\(csvParser.jamfProAPIRoles.count) roles loaded")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let updateTime = githubService.lastUpdateTime {
                        HStack(alignment: .center) {
                            Text("Last updated:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(updateTime, style: .relative)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
    }
    
    private func analysisResultView(_ analysis: ScriptAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                analysisSummaryView(analysis)
                requiredRolesView(analysis)
                detectedEndpointsView(analysis)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
    
    private func analysisSummaryView(_ analysis: ScriptAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Analysis Results")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button("New Analysis") {
                    scriptAnalyzer.analysisResult = nil
                    selectedFileURL = nil
                }
                .font(.system(size: 13))
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            
            VStack(spacing: 2) {
                AnalysisInfoRow(title: "File", value: analysis.fileName, icon: "doc.text")
                AnalysisInfoRow(title: "Type", value: analysis.fileType.rawValue, icon: "doc.badge")
                AnalysisInfoRow(title: "Authentication", value: analysis.authenticationMethod.rawValue, icon: "key.fill")
                AnalysisInfoRow(title: "Endpoints Found", value: "\(analysis.detectedEndpoints.count)", icon: "network")
                AnalysisInfoRow(title: "Required Roles", value: "\(analysis.requiredRoles.count)", icon: "shield.checkered")
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    private func detectedEndpointsView(_ analysis: ScriptAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected API Endpoints")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            if analysis.detectedEndpoints.isEmpty {
                Text("No API endpoints detected in the script.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
            } else {
                ForEach(analysis.detectedEndpoints) { endpoint in
                    EndpointRow(endpoint: endpoint)
                }
            }
        }
    }
    
    private func requiredRolesView(_ analysis: ScriptAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Required API Roles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    copyRolesToClipboard(analysis.requiredRoles)
                }) {
                    Label("Copy Output", systemImage: "doc.on.doc")
                        .font(.system(size: 12))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if analysis.requiredRoles.isEmpty {
                Text("No specific roles identified. Check the detected endpoints manually.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
            } else {
                TableOfRoles(roles: analysis.requiredRoles)
                
                Button(action: {
                    showingCreateInJamfPro = true
                }) {
                    Label("Create in Jamf Pro", systemImage: "arrow.up.doc")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(analysis.requiredRoles.isEmpty)
            }
        }
    }

    @State private var userAssignments: [UUID: String] = [:]

    private func copyRolesToClipboard(_ roles: [APIRole]) {
        let header = "Endpoint,Operation,Privileges,User"
        let rows = roles.map { role in
            let user = userAssignments[role.id] ?? ""
            let privileges = role.requiredPrivileges.joined(separator: "; ")
            return "\(role.endpoint),\(role.operation),\(privileges),\(user)"
        }
        let csv = ([header] + rows).joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        #endif
    }

    private func uniquePrivilegeNames(from roles: [APIRole]) -> [String] {
        let all = roles.flatMap(\.requiredPrivileges)
        return Array(Set(all)).sorted()
    }

    struct TableOfRoles: View {
        let roles: [APIRole]
        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Endpoint")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Operation")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text("Privileges")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.08))
                ForEach(roles) { role in
                    HStack(alignment: .top, spacing: 12) {
                        Text(role.endpoint)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(role.operation)
                            .font(.system(size: 11))
                            .frame(width: 80, alignment: .leading)
                        Text(role.requiredPrivileges.joined(separator: "; "))
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(role.id.hashValue % 2 == 0 ? Color(NSColor.controlBackgroundColor) : Color(NSColor.windowBackgroundColor))
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
}

struct AnalysisInfoRow: View {
    let title: String
    let value: String
    let icon: String
    @State private var isExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.tint)
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if isExpanded {
                Divider()
                Text("\(title): \(value)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

struct EndpointRow: View {
    let endpoint: DetectedEndpoint
    @State private var isExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(endpoint.endpoint)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(endpoint.operation)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.tint)
                    .cornerRadius(6)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if isExpanded {
                HStack(alignment: .top, spacing: 10) {
                    Text("Line \(endpoint.lineNumber)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(endpoint.context)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

struct RoleRow: View {
    let role: APIRole
    @State private var isExpanded = false
    @Binding var userAssignment: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(role.endpoint)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(role.operation)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(4)
                TextField("Assign user", text: $userAssignment)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 120)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Privileges:")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    ForEach(role.requiredPrivileges, id: \.self) { privilege in
                        Text("• \(privilege)")
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    if let deprecationDate = role.deprecationDate, deprecationDate != "N/A" {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("Deprecated: \(deprecationDate)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - About & Tips sheets

struct AboutRoleAutomatorView: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty {
            return "Version \(version)"
        } else {
            return "Version \(version) (\(build))"
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            #if os(macOS)
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .cornerRadius(16)
            #else
            Image(systemName: "shield.checkered")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            #endif
            
            Text("RoleAutomator")
                .font(.system(size: 22, weight: .semibold))
            
            Text("Analyze Jamf Pro automation scripts and map them to the exact API roles and privileges required on your Jamf Pro server.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Text(versionString)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Text("© 2026 Kavan Joshi")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 13))
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 32)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 260)
    }
}

struct RoleAutomatorTipsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How to Use RoleAutomator")
                    .font(.system(size: 18, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Analyze a script")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click “Upload Script” and select a Bash, Zsh, Shell, Python, Swift, AppleScript, PowerShell, or text file that calls the Jamf Classic API (JSSResource/…) or Jamf Pro API (/api/…). RoleAutomator scans for those endpoints and determines the required roles.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("2. Review detected endpoints and roles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("On the results screen you’ll see the endpoints found in your script, along with the Jamf Pro API roles and privileges needed to run it safely.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("3. Browse the role database")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Use “Browse Roles” from the home screen to explore all Classic and Jamf Pro API endpoints and their required privileges, powered by the Git-hosted role database.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("4. Create roles in Jamf Pro")
                        .font(.system(size: 14, weight: .semibold))
                    Text("From the analysis results, click “Create in Jamf Pro” to push a new API role with exactly the privileges your script needs. You’ll be prompted once to store Jamf Pro URL and credentials in the system Keychain.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("5. Use templates")
                        .font(.system(size: 14, weight: .semibold))
                    Text("In the Templates section on the home screen, select pre-defined UEM setup templates and create Jamf Pro roles for common scenarios in a single click.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 32)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

// MARK: - Jamf Pro credentials (Keychain-backed)
struct JamfProCredentialsSheet: View {
    @ObservedObject var jamfProService: JamfProService
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var saveError: String?
    @State private var savedMessage = false
    @State private var connectionMessage: String?
    @State private var isTestingConnection = false

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .center) {
                Text("Jamf Pro credentials")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 13))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Text("Stored securely in the system Keychain. Used only to create API roles on your Jamf Pro server.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 14) {
                Text("Jamf Pro URL")
                    .font(.system(size: 13, weight: .medium))
                TextField("https://your-instance.jamfcloud.com", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                Text("Username")
                    .font(.system(size: 13, weight: .medium))
                TextField("API or admin username", text: $username)
                    .textFieldStyle(.roundedBorder)
                Text("Password")
                    .font(.system(size: 13, weight: .medium))
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(24)

            if let err = saveError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }
            if let conn = connectionMessage {
                Text(conn)
                    .font(.system(size: 12))
                    .foregroundColor(conn.hasPrefix("Connection successful") ? .green : .red)
                    .padding(.horizontal, 24)
            }
            if savedMessage {
                Text("Credentials saved.")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 14) {
                Button("Clear saved") {
                    saveError = nil
                    connectionMessage = nil
                    try? jamfProService.clearCredentials()
                    baseURL = ""
                    username = ""
                    password = ""
                    savedMessage = false
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(minHeight: 44)
                Button("Test connection") {
                    connectionMessage = nil
                    isTestingConnection = true
                    Task {
                        let err = await jamfProService.testConnection(baseURL: baseURL.isEmpty ? nil : baseURL, username: username.isEmpty ? nil : username, password: password.isEmpty ? nil : password)
                        connectionMessage = err ?? "Connection successful."
                        isTestingConnection = false
                    }
                }
                .font(.system(size: 12))
                .disabled(isTestingConnection)
                .frame(minHeight: 44)
                Spacer()
                Button("Save to Keychain") {
                    saveError = nil
                    connectionMessage = nil
                    savedMessage = false
                    do {
                        try jamfProService.saveCredentials(baseURL: baseURL, username: username, password: password)
                        savedMessage = true
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .font(.system(size: 13))
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 420, minHeight: 440)
        .onAppear {
            if let c = jamfProService.loadCredentials() {
                baseURL = c.baseURL
                username = c.username
                password = ""
            }
        }
    }
}

// MARK: - Create role in Jamf Pro
struct CreateRoleInJamfSheet: View {
    @ObservedObject var jamfProService: JamfProService
    let defaultRoleName: String
    let privilegeNames: [String]
    let onDismiss: () -> Void
    @State private var roleName: String = ""
    @State private var created = false
    @State private var showingCredentials = false

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .center) {
                Text("Create role in Jamf Pro")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done") { onDismiss() }
                    .font(.system(size: 13))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Text("Creates one API role with the required privileges from this script.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)

            HStack(alignment: .center) {
                Label("Jamf Pro credentials", systemImage: "key.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Set up or edit credentials") {
                    showingCredentials = true
                }
                .font(.system(size: 13))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("Role name")
                    .font(.system(size: 13, weight: .medium))
                TextField("Role name", text: $roleName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 24)

            if let err = jamfProService.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }
            if let msg = jamfProService.lastSuccessMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                    .padding(.horizontal, 24)
            }

            Text("\(privilegeNames.count) privileges will be added.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            Spacer()
            Button(action: createRole) {
                if jamfProService.isCreating {
                    ProgressView()
                        .scaleEffect(0.9)
                        .frame(minWidth: 140, minHeight: 44)
                } else {
                    Text("Create role")
                        .font(.system(size: 14, weight: .medium))
                        .frame(minWidth: 140, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(roleName.isEmpty || jamfProService.isCreating)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 400, minHeight: 400)
        .sheet(isPresented: $showingCredentials) {
            JamfProCredentialsSheet(jamfProService: jamfProService)
        }
        .onAppear {
            if roleName.isEmpty { roleName = defaultRoleName }
            // Clear any stale status messages from previous create operations
            jamfProService.lastError = nil
            jamfProService.lastSuccessMessage = nil
        }
    }

    private func createRole() {
        Task {
            await jamfProService.createRole(displayName: roleName, privilegeNames: privilegeNames)
        }
    }
}

#Preview {
    ContentView()
}
