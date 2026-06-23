# Conventions

- Existing code favors a small number of large concrete types over many abstractions; match the current style unless extracting is clearly useful.
- User-facing strings are primarily Korean; keep new UI/status copy in Korean.
- Supabase errors are surfaced with localized `NSLocalizedDescriptionKey` messages.
- Environment variables: prefer `SUPABASE_PUBLISHABLE_KEY`; legacy `SUPABASE_ANON_KEY` is still accepted.
- Do not assume a test target exists; use `swift build` as the default verification.