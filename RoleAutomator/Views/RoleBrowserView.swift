import SwiftUI

struct RoleBrowserView: View {
    @ObservedObject var csvParser: CSVParser
    @State private var searchText = ""
    @State private var selectedAPIType: APIRole.APIType = .classic
    @Environment(\.dismiss) private var dismiss

    private var currentRoles: [APIRole] {
        selectedAPIType == .classic ? csvParser.classicAPIRoles : csvParser.jamfProAPIRoles
    }

    var filteredRoles: [APIRole] {
        if searchText.isEmpty {
            return currentRoles
        }
        return currentRoles.filter { role in
            role.endpoint.localizedCaseInsensitiveContains(searchText) ||
            role.requiredPrivileges.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var hasAnyRolesLoaded: Bool {
        !csvParser.classicAPIRoles.isEmpty || !csvParser.jamfProAPIRoles.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            searchAndFilterBar
            contentArea
        }
        .frame(minWidth: 400, minHeight: 420)
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(alignment: .center) {
            Text("Browse API Roles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .font(.system(size: 14))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Search & filter
    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .center)
                TextField("Search endpoints or privileges…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            Text("API type")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Picker("API Type", selection: $selectedAPIType) {
                ForEach(APIRole.APIType.allCases, id: \.self) { apiType in
                    Text(apiType.rawValue).tag(apiType)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(18)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Content: list or empty/loading/error (Apple: layout fits screen, no horizontal scroll)
    private var contentArea: some View {
        Group {
            if csvParser.isLoading {
                loadingView
            } else if let error = csvParser.errorMessage {
                errorView(message: error)
            } else if !hasAnyRolesLoaded {
                emptyRolesView
            } else if filteredRoles.isEmpty {
                noSearchResultsView
            } else {
                roleListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.1)
            Text("Loading roles…")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyRolesView: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No roles loaded")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Text("Use the main screen to load roles from GitHub, or refresh the Role Database.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No matching roles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Text("Try different search terms.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table in a single rectangle box (same look and feel)
    private var roleListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader
                tableBox
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var sectionHeader: some View {
        HStack(alignment: .center) {
            Text("\(filteredRoles.count) \(selectedAPIType == .classic ? "Classic" : "Jamf Pro") endpoints · Endpoint → Required privileges")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var tableBox: some View {
        VStack(spacing: 0) {
            tableHeaderRow
            Divider()
            ForEach(filteredRoles) { role in
                tableDataRow(role: role)
                if role.id != filteredRoles.last?.id {
                    Divider()
                }
            }
        }
        .padding(0)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private var tableHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Endpoint")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Operation")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text("Required privileges")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func tableDataRow(role: APIRole) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(role.endpoint)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(role.operation)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(.tint)
                .cornerRadius(6)
                .frame(width: 80, alignment: .leading)
            Text(role.requiredPrivileges.joined(separator: "; "))
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 44)
    }
}

#Preview {
    RoleBrowserView(csvParser: CSVParser())
        .frame(width: 500, height: 560)
}
