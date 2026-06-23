# Core

- macOS AppKit/SwiftUI floating companion app (`Wazak`) with a menu bar item labeled `와`.
- Main app logic is concentrated in `Sources/Wazak/main.swift`; settings/marketplace UI is in `Sources/Wazak/Settings.swift`.
- Product requirements and Supabase schema notes live in `docs/PRD.md`.
- Local data is stored under `~/Library/Application Support/Wazak/`; user/session caches are in `UserDefaults`.
- Supabase is optional: without `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`/legacy `SUPABASE_ANON_KEY`, app runs local-only.
- Read `mem:tech_stack` for build/runtime stack, `mem:suggested_commands` for common commands, `mem:conventions` for local style, and `mem:task_completion` before wrapping coding work.