# Suggested Commands

- Dev auto-restart: `./dev.sh`.
- Manual run with environment: `set -a; source .env; set +a; swift run Wazak`.
- Build check: `swift build`.
- Tests: no test target currently exists.
- Fast code search: `rg <pattern> Sources Package.swift docs`.
- Warning: `.build/` may be present in git state/history; avoid touching or staging build artifacts unless explicitly requested.