import Foundation

/// Payload for creating a role from template (passed into sheet so privileges are not empty).
struct TemplateCreatePayload: Identifiable {
    let id = UUID()
    let roleName: String
    let privileges: [String]
}

/// Security Cloud UEM Setup template: privilege sets for Jamf Pro ↔ UEM integration.
/// Privilege names must match exactly what Jamf Pro API expects (see api-role-privileges).
struct UEMTemplate: Identifiable {
    let id: String
    let title: String
    let subtitle: String // Required / Optional
    let privileges: [String]
    
    static let securityCloudUEMSetup: [UEMTemplate] = [
        UEMTemplate(
            id: "device-lifecycle",
            title: "Device Lifecycle Management",
            subtitle: "Required",
            privileges: [
                "Read Computers",
                "Read Mobile Devices",
                "Read Smart Computer Groups",
                "Read Smart Mobile Device Groups",
                "Create Smart Computer Groups",
                "Create Static Mobile Device Groups",
                "Read Static Mobile Device Groups",
                "Delete Static Mobile Device Groups"
            ]
        ),
        UEMTemplate(
            id: "device-risk-signaling",
            title: "Device Risk UEM Signaling",
            subtitle: "Optional",
            privileges: [
                "Create Computer Extension Attributes",
                "Read Computer Extension Attributes",
                "Update Computer Extension Attributes",
                "Delete Computer Extension Attributes",
                "Create Mobile Device Extension Attributes",
                "Read Mobile Device Extension Attributes",
                "Update Mobile Device Extension Attributes",
                "Delete Mobile Device Extension Attributes",
                "Update Mobile Devices",
                "Update Computers"
            ]
        ),
        UEMTemplate(
            id: "config-profile-deployment",
            title: "Configuration Profile Deployment",
            subtitle: "Optional",
            privileges: [
                "Update Smart Mobile Device Groups",
                "Update Smart Computer Groups"
            ]
        )
    ]
}
