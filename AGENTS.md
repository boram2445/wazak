# Wazak

AppKit + SwiftPM으로 만든 macOS 플로팅 컴패니언 앱 (말랑이 캐릭터).

## 문서

- PRD: `docs/PRD.md` — 기능 범위, 데이터 모델, 마일스톤 등 제품 요구사항 전체.

## 실행

**개발 중 (자동 재시작):**
```sh
./dev.sh
```
`Sources/` 하위 `.swift` 파일 저장 시 자동 재빌드+재실행. `Ctrl-C`로 앱까지 정리됨.
`brew install watchexec` 설치 시 더 빠르게 동작 (스크립트가 자동 감지).

**수동 실행:**
```sh
set -a; source .env; set +a   # SUPABASE_* 환경 변수 내보내기
swift run Wazak
```

메뉴 바의 `와` 항목으로 실행됩니다. 이미 실행 중이라면 해당 메뉴에서 종료 후 재실행하세요.
`.env`에 `SUPABASE_URL`과 `SUPABASE_PUBLISHABLE_KEY`가 없으면 로컬 전용으로 동작합니다 (`.env.example` 참고).

## 빌드 / 테스트

- `swift build` — 컴파일만
- 테스트 타겟 없음.

## 아키텍처

앱 전체가 파일 하나에 있음: `Sources/Wazak/main.swift` (~2,500줄). 주요 타입:

- `AppDelegate` — 메뉴 바 상태 항목(`와`)과 오버레이 윈도우 초기화.
- `OverlayWindow` / `MalangiOverlayView` / `MalangiImageView` / `BadgeLabel` — 플로팅 패널: 말랑이 + 뱃지 표시, 호버 시 화살표, 클릭 시 소리 재생.
- `MalangiSettings` — 로컬 데이터 영속성.
- `SupabaseMalangiClient` — Supabase 인증, 행 동기화, 에셋 업로드.
- `SettingsWindow` / `SettingsView` — 등록/관리 UI.
- `BackgroundRemover`, `ResourceLocator` — 이미지 배경 제거 + 번들 리소스 조회.

## 데이터 & 저장소

- 로컬 파일: `~/Library/Application Support/Wazak/` (말랑이별 이미지 + 소리).
- `UserDefaults`: 등록된 말랑이, 원격 말랑이 캐시, Supabase 인증 세션.
- Supabase Storage 버킷: `malangi-assets` (동기화 설정 시 이미지·소리 업로드).

## 에셋

임시 에셋은 `Sources/Wazak/Resources/`에 있음 (`.process`로 번들에 포함).
실제 에셋을 쓰려면 파일을 해당 경로에 추가하고 `main.swift`에서 `imageName` / `soundName`을 설정하세요.

## 주의사항

- **`.build/`가 git에 커밋되어 있음** — `.gitignore`에 없어서 빌드할 때마다 2,600개 이상의 파일이 diff에 잡힘. 정리하려면:
  `git rm -r --cached .build && echo '.build/' >> .gitignore`
- `work/make-transparent.swift`는 독립 스크립트로 SwiftPM 타겟에 포함되지 않음.
- Supabase 키 환경 변수는 구버전 이름 `SUPABASE_ANON_KEY`도 허용.
