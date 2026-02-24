# Jamf Role Automator
<img width="512" height="512" alt="RANew-iOS-Default-512x512@1x" src="https://github.com/user-attachments/assets/b70d148d-f315-49cc-abd5-581c32375c25" />


[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue.svg)](https://github.com/joshikavan92/jamf-role-automator)
[![Downloads](https://img.shields.io/github/downloads/joshikavan92/jamf-role-automator/total.svg)](https://github.com/joshikavan92/jamf-role-automator/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

**Jamf Role Automator** is a macOS app that analyzes your Jamf automation scripts and tells you exactly which **Jamf Pro API roles and privileges** they need. It also lets you browse the full role database and create roles directly on your Jamf Pro server.

![Screenshot 2026-02-24 at 5 38 09 PM](https://github.com/user-attachments/assets/dd4163b5-2c57-4877-8029-83d67dcf0de6)
![Screenshot 2026-02-24 at 5 39 30 PM](https://github.com/user-attachments/assets/a538bdac-5e15-48bf-9703-ca95c706e540)
![Screenshot 2026-02-24 at 5 38 41 PM](https://github.com/user-attachments/assets/aecdff5d-e52f-449e-9a14-884c009c8e69)
![Screenshot 2026-02-24 at 5 38 56 PM](https://github.com/user-attachments/assets/bec3eaa7-c973-4c8d-83dd-9e29fab68ac8)

---

## Key features

- **Script analysis**
  - Upload Bash, Zsh, Shell, Python, Swift, AppleScript, PowerShell, or text files.
  - Detects Jamf Classic API (`JSSResource/...`) and Jamf Pro API (`/api/...`) endpoints.
  - Maps endpoints to required roles and privileges using a Git‑hosted role database.

- **Browse all roles**
  - Browse Classic API and Jamf Pro API endpoints in a single table.
  - See operation (GET/POST/PUT/DELETE) and required privileges.
  - Search by endpoint or privilege name.

- **Create roles in Jamf Pro**
  - Uses token auth (`/api/v1/auth/token`) with credentials stored in the macOS Keychain.
  - Creates a Jamf Pro API role with the privileges required by a script.
  - If some privileges are not available on your Jamf server, the app still creates the role with the **valid** ones and clearly lists the missing privileges so you can add them manually.
  - Reminds you to check Jamf Developer documentation to confirm that the privileges you’re using are still valid.

- **Templates**
  - Built‑in templates for common UEM / security setups.
  - Select multiple templates and push a combined role to Jamf Pro.

- **Offline‑friendly**
  - Caches the role database locally for offline use.
  - Fetches updates from a Git‑hosted JSON database when network is available.

---

## Requirements

- **Platform**: macOS 26.0+  
- **Jamf**: Jamf Pro with API access (account that can create roles)  
- **Network**: Access to `raw.githubusercontent.com` (or your own mirror of the role database)

---

## Installation

1. Go to the [**Releases**](https://github.com/joshikavan92/jamf-role-automator/releases) page.
2. Download the latest `RoleAutomator-*.pkg`.
3. Open the package and follow the installer prompts.
4. Launch **RoleAutomator** from `/Applications`.

---

## Quick start

### 1. Analyze a script

1. Open the app and click **Upload Script**.  
2. Select your Bash, Zsh, Shell, Python, Swift, AppleScript, PowerShell, or text script that calls Jamf APIs.  
3. Review:
   - Detected endpoints,
   - Required roles and privileges,
   - Authentication method.

### 2. Browse the role database

1. From the home screen, click **Browse Roles**.  
2. Filter by Classic vs Jamf Pro API.  
3. Search endpoints or privileges to see which roles you already have or need.

### 3. Create a role in Jamf Pro

1. On the analysis results screen, click **Create in Jamf Pro**.  
2. Set up your Jamf Pro URL and credentials (stored in the macOS Keychain).  
3. The app:
   - Fetches the list of valid privileges from Jamf (`/api/v1/api-role-privileges`),
   - Creates a role with all matching privileges,
   - Clearly lists any privileges that couldn’t be attached so you can add them manually.
4. Check Jamf Developer documentation to confirm that the privileges your script uses are still current and not deprecated.

---

## Building from source

1. Clone this repository:

   ```bash
   git clone https://github.com/joshikavan92/jamf-role-automator.git
   cd jamf-role-automator/RoleAutomator
   ```

2. Open the Xcode project:

   ```bash
   open RoleAutomator.xcodeproj
   ```

3. Select the **RoleAutomator** scheme and your Mac as the run destination.  
4. Press **⌘R** to build and run.

---

## License

This project is licensed under the **MIT License** – see [`LICENSE`](./LICENSE) for details.

---

## Support / feedback

For issues and feature requests, open an issue on GitHub:  
`https://github.com/joshikavan92/jamf-role-automator/issues`

