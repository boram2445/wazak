# Tech Stack

- Swift Package Manager project (`Package.swift`) targeting a macOS executable named `Wazak`.
- Uses AppKit for app/window/menu-bar integration and SwiftUI for settings/marketplace UI surfaces.
- Networking is direct `URLSession` calls to Supabase REST/Auth/Storage endpoints; no Supabase SDK dependency.
- OAuth login uses Supabase Auth Google provider with PKCE and a temporary localhost loopback callback server (`http://localhost:8765`).
- Bundled resources live under `Sources/Wazak/Resources/` and are included via SwiftPM `.process`.