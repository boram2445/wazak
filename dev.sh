#!/usr/bin/env bash
# dev.sh — Wazak 개발용 자동 재시작 스크립트
# Sources/*.swift 저장 시 자동 재빌드+재실행합니다.
# 더 빠른 감시를 원하면: brew install watchexec

set -uo pipefail  # -e 제외: pkill/SIGPIPE 등이 스크립트를 죽이지 않게

# ── 경로 설정 ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 환경 변수 로드 ─────────────────────────────────────────────────────────
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

# ── 종료 시 정리 ───────────────────────────────────────────────────────────
cleanup() {
  echo ""
  echo "▶ Wazak 종료 중..."
  pkill -f '\.build/.*/Wazak$' 2>/dev/null || true
  wait 2>/dev/null || true
  echo "  종료 완료."
}
trap cleanup EXIT INT TERM

# ── 재시작 함수 ────────────────────────────────────────────────────────────
WAZAK_PID=""

restart() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ 변경 감지 — 재빌드 중..."

  # 기존 인스턴스 종료
  if [[ -n "$WAZAK_PID" ]] && kill -0 "$WAZAK_PID" 2>/dev/null; then
    kill "$WAZAK_PID" 2>/dev/null || true
    wait "$WAZAK_PID" 2>/dev/null || true
  fi
  pkill -f '\.build/.*/Wazak$' 2>/dev/null || true

  # 재빌드 + 재실행 (백그라운드, swift 출력은 그대로 콘솔에 표시)
  swift run Wazak &
  WAZAK_PID=$!
  echo "▶ 빌드 중... (PID $WAZAK_PID) — 저장하면 자동으로 다시 빌드됩니다."
}

# ── 최초 실행 ──────────────────────────────────────────────────────────────
echo "Wazak dev watch 시작"
echo "감시 대상: Sources/"
restart

# ── 감시 방식 자동 선택 ────────────────────────────────────────────────────
if command -v watchexec &>/dev/null; then
  echo "▶ watchexec 사용"
  pkill -f '\.build/.*/Wazak$' 2>/dev/null || true
  watchexec -w Sources -e swift -r -- bash -c \
    "set -a; [[ -f '$SCRIPT_DIR/.env' ]] && source '$SCRIPT_DIR/.env'; set +a; swift run Wazak"

elif command -v fswatch &>/dev/null; then
  echo "▶ fswatch 사용"
  fswatch -o Sources --include='\.swift$' --exclude='.*' | while read -r; do
    restart
  done

else
  # ── 순수 bash 폴링 (mtime 감시) ──────────────────────────────────────────
  echo "▶ bash 폴링 사용 (watchexec/fswatch 미설치)"
  echo "  (brew install watchexec 로 더 빠른 감시 가능)"

  # Sources/ 하위 .swift 파일들의 최신 mtime
  latest_mtime() {
    find Sources -name '*.swift' -exec stat -f '%m' {} \; 2>/dev/null \
      | sort -rn 2>/dev/null | head -1 || true
  }

  last_mtime="$(latest_mtime)"

  while true; do
    sleep 1
    current_mtime="$(latest_mtime)"
    if [[ "$current_mtime" != "$last_mtime" ]]; then
      last_mtime="$current_mtime"
      restart
    fi
  done
fi
