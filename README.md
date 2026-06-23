# Wazak

macOS용 플로팅 컴패니언 앱 (말랑이 캐릭터). 자세한 제품 요구사항은 [`docs/PRD.md`](docs/PRD.md)를 참고하세요.

## 요구사항

- macOS 13+
- Swift 5.9 / SwiftPM (외부 SPM 의존성 없음 — Supabase는 raw HTTP로 통신)

## 실행

### 개발 중 (권장 — 자동 재시작)

```sh
./dev.sh
```

`Sources/` 하위 `.swift` 파일이 저장될 때마다 자동으로 재빌드하고 앱을 재실행합니다.  
`Ctrl-C`로 종료하면 실행 중인 Wazak도 함께 정리됩니다.

더 빠른 감시를 원하면 `brew install watchexec` 후 동일하게 `./dev.sh`를 실행하면 자동으로 활용됩니다 (`fswatch`도 지원).

### 수동 실행

```sh
set -a; source .env; set +a   # .env의 SUPABASE_* 환경 변수 내보내기
swift run Wazak
```

Wazak이 이미 실행 중이라면, 메뉴 바의 `와` 항목에서 먼저 종료한 뒤 다시 실행하세요.

### 빌드만

```sh
swift build   # 테스트 타겟 없음
```

### 배포용 앱 패키징

```sh
./scripts/package-app.sh
```

위 명령은 `swift build -c release` 후 macOS 앱 번들을 만들고 zip으로 묶습니다.

생성물:

```txt
dist/Wazak.app
dist/Wazak.zip
```

`Wazak.zip`을 공유하면 사용자는 압축을 풀고 `Wazak.app`을 실행할 수 있습니다.  
패키징 시 `.env`의 `SUPABASE_URL`과 `SUPABASE_PUBLISHABLE_KEY` 값이 앱의 `Info.plist`에 포함되어, 더블클릭 실행에서도 로그인과 마켓플레이스 기능이 동작합니다.

OAuth redirect를 위해 Supabase Dashboard → Authentication → URL Configuration → Redirect URLs에 아래 값을 추가해야 합니다.

```txt
wazak://auth/callback
```

기본 패키징은 ad-hoc 서명입니다. 외부 사용자에게 경고를 줄여 배포하려면 Apple Developer ID 인증서로 서명하세요.

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-app.sh
```

---

## 환경 변수 (`.env`)

Supabase 연동 시 프로젝트 루트에 `.env` 파일을 생성하세요 (`.env.example` 참고):

```txt
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

- 레거시 변수명 `SUPABASE_ANON_KEY`도 폴백으로 허용됩니다.
- `.env`가 없거나 변수가 비어 있으면 **로컬 전용 모드**로 동작합니다 (동기화·마켓플레이스 기능 비활성).

---

## 주요 기능

### 플로팅 오버레이

- 항상 최상단에 말랑이 캐릭터 이미지와 이름 뱃지가 표시됩니다.
- 호버 시 좌우 화살표와 설정(⚙) 아이콘이 나타납니다.
  - 화살표: 이전/다음 말랑이로 전환 (페이드 전환).
  - 설정 아이콘: 설정 창 열기.
- 말랑이를 클릭하면 등록된 소리 중 하나가 **랜덤 재생**되고 탭 애니메이션이 실행됩니다.
- 기본 번들 말랑이: `사과 슬랑이`.

### 설정 창 — 내 말랑이 탭

메뉴 바 `Settings`(⌘,) 또는 오버레이 설정 아이콘으로 열 수 있습니다.

- 이름, 이미지, 여러 소리로 커스텀 말랑이를 **등록/편집/삭제**.
- 이미지 선택 시 자동 배경 제거(macOS 14+는 Vision 기반, 이전 버전은 엣지 플러드필 방식).
- 저장 후 즉시 플로팅 오버레이에서 해당 말랑이가 선택됩니다.

### 설정 창 — 마켓플레이스 탭

- **Google OAuth 로그인** 후 말랑이를 업로드하거나 다운로드할 수 있습니다.
- 기본 제공 말랑이는 로그인 없이 무료 다운로드 가능.
- 공유 말랑이 다운로드는 포인트 1개 차감 (포인트 부족 시 차단).
- 포인트 지급: 가입 시 +5p, 마켓플레이스 신규 업로드 시 +3p.
- 다운로드한 말랑이는 즉시 로컬 목록에 추가되어 오버레이에서 사용 가능.

### 데이터 저장

| 저장소 | 내용 |
|---|---|
| `~/Library/Application Support/Wazak/` | 등록된 말랑이 이미지·소리 파일 |
| `UserDefaults` | 등록된 말랑이 목록, 원격 캐시, 인증 세션 등 |
| Supabase Storage (`malangi-assets`) | 동기화 설정 시 이미지·소리 업로드 |

---

## 에셋 교체

번들 에셋은 `Sources/Wazak/Resources/`에 있습니다 (`.process`로 번들에 포함).  
실제 에셋을 연결하려면 이미지나 소리 파일을 해당 경로에 추가하고 `Sources/Wazak/main.swift`에서 `imageName`/`soundName`을 설정하세요.
