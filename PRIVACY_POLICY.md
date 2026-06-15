# Privacy Policy

Effective date: 16 June 2026

pfSense Manager is an independent Android application for connecting to and managing pfSense systems configured by the user.

## Information processed by the app

The app may process and display information obtained directly from user-configured pfSense systems, including:

- firewall hostnames, addresses and profile names
- API credentials or keys
- system, firmware, interface and gateway information
- firewall rules, logs and connection states
- DHCP leases, VPN status and service status
- device-local preferences and app-lock settings

## How information is used

This information is used only to provide the app's firewall-management and monitoring functions.

The app connects directly from the user's device to the pfSense systems the user configures. The developer does not operate an intermediary service for these connections.

## Data collection by the developer

The developer does not collect, receive, sell or share firewall credentials, network information or app-usage data through this application.

The current app does not include developer-operated analytics, advertising, tracking or crash-reporting services.

## Local storage

Saved firewall profiles and credentials are stored on the user's device. Credentials are stored using Android secure storage where supported. Other preferences may be stored in normal application storage.

Data remains on the device until the user removes the relevant profile, clears the app's storage or uninstalls the app.

## Network security

The app requires HTTPS for pfSense connections. Users may choose to allow self-signed certificates for a profile. Enabling that option weakens normal certificate verification and should be used only on trusted networks where the certificate is understood and controlled by the user.

Users should avoid exposing the pfSense REST API directly to the public internet and should prefer a trusted local network or VPN.

## User control and deletion

Users can remove saved profiles and credentials from within the app. They can also delete all local app data through Android settings or by uninstalling the app.

## Third-party software

The app includes open-source dependencies. Their licences are described in THIRD_PARTY_NOTICES.md and may also be shown through Flutter's licence interface where available.

## Changes to this policy

This policy may be updated when the app's data practices or features change. Material changes will be committed to the repository and reflected by the effective date above.

## Contact

Privacy questions can be raised through the repository's GitHub Issues page.
