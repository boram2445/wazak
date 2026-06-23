# Task Completion

- Run `swift build` after Swift code changes.
- If UI behavior changed, run the app with `set -a; source .env; set +a; swift run Wazak` or `./dev.sh` when interactive verification is needed.
- No repository test target is currently available.
- Check `git status --short` before finalizing; ignore unrelated user/build artifact changes.