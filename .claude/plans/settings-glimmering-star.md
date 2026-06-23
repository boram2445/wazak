# Plan: 설정 창 SwiftUI 마이그레이션 (말랑이 톤 스타일링)

## Context

설정 창(`SettingsWindow` + `SettingsView`, main.swift:1415–2070)은 현재 순수 AppKit으로
절대좌표(`NSRect`)를 써서 640×430에 컨트롤을 직접 배치한 구조다. 예쁜 커스텀 스타일링이
어렵고 코드도 방대하다. 설정 창 `contentView`만 `NSHostingView`로 SwiftUI 뷰로 교체해
말랑이 캐릭터 앱답게 귀엽고 부드러운 느낌으로 리디자인한다. 앱 나머지(메뉴바, 오버레이)는
AppKit 그대로 유지한다.

---

## 현황 파악

| 항목 | 내용 |
|---|---|
| 파일 | `Sources/Wazak/main.swift` (단일 파일, ~2,500줄) |
| 타겟 | macOS 13 (`Package.swift`) |
| 현재 설정 창 | SettingsWindow: NSWindow (1415–1429) + SettingsView: NSView (1431–2070) |
| 모드 전환 | NSSegmentedControl → isHidden 토글 (`localContentViews` 스냅샷 트릭) |
| 모델 레이어 | `MalangiSettings` (static), `SupabaseMalangiClient.shared` (싱글턴) — 재사용 |

**모델 API (재사용, 변경 없음)**
- `MalangiSettings.registrations: [StoredMalangi]`
- `MalangiSettings.saveMalangi(name:editingIndex:image:sounds:) throws`
- `MalangiSettings.deleteMalangi(at:) throws`
- `MalangiSettings.addMarketplaceMalangi(_:)`
- `SupabaseMalangiClient.shared.authSession: SupabaseAuthSession?`
- `SupabaseMalangiClient.shared.signIn/signUp/signOut`
- `SupabaseMalangiClient.shared.fetchMarketplace() throws -> [MarketplaceMalangi]`
- `SupabaseMalangiClient.shared.publishToMarketplace(_:session:) throws`
- 비동기 패턴: `DispatchQueue.global.async { ... DispatchQueue.main.async { ... } }`

---

## 파일 구성

새 파일 **`Sources/Wazak/Settings.swift`** 생성 (SwiftPM가 디렉터리 전체를 자동 컴파일 → `Package.swift` 수정 불필요).

| 위치 | 내용 |
|---|---|
| `Settings.swift` (신규) | `import SwiftUI` + `MalangiTheme`, `SettingsMode`, `SettingsAlert`, `SettingsViewModel`, `SettingsRootView`/`LocalTabView`/`MarketplaceTabView` |
| `main.swift` (수정) | `SettingsWindow` init 교체, `SettingsPresenter.show()` 수정, 기존 `SettingsView`(1431–2070) 삭제 |

`SettingsWindow`/`SettingsPresenter`는 모델·메뉴와 엮여 있어 `main.swift`에 유지. 기존 ~640줄 `SettingsView` 삭제로 `main.swift`는 오히려 가벼워짐.

---

## 구현 계획

### 1단계: `Settings.swift` 생성 + `import SwiftUI`
새 파일을 만들고 상단에 `import SwiftUI`, `import AppKit` 추가.

---

### 2단계: `SettingsViewModel` 추가 (ObservableObject)

```swift
final class SettingsViewModel: ObservableObject {
    // 로컬 탭 상태
    @Published var registrations: [StoredMalangi] = []
    @Published var selectedIndex: Int? = nil
    @Published var draftName: String = ""
    @Published var pendingImageURL: URL? = nil
    @Published var soundDrafts: [SoundDraft] = []
    @Published var isSaving: Bool = false

    // 마켓플레이스 탭 상태
    @Published var marketplaceMalangis: [MarketplaceMalangi] = []
    @Published var selectedMarketplaceIndex: Int? = nil
    @Published var authEmail: String = ""
    @Published var authPassword: String = ""
    @Published var authStatusText: String = ""
    @Published var marketplaceStatusText: String = ""

    // 공통
    @Published var errorMessage: String? = nil
    @Published var selectedTab: Tab = .local

    enum Tab { case local, marketplace }

    var authSession: SupabaseAuthSession? { SupabaseMalangiClient.shared.authSession }
    var previewImage: NSImage? { ... } // pendingImageURL 또는 selectedRegistration.imagePath
}
```

**추가 ViewModel 멤버**:
- `var onRequestClose: (() -> Void)?` — `SettingsWindow`이 `{ [weak self] in self?.close() }` 로 주입. VM의 `confirm()` 성공 시 호출 (현재 `self.window?.close()` 대체).
- `@Published var alert: SettingsAlert?` (`struct SettingsAlert: Identifiable { let id = UUID(); let title, detail: String }`) — 기존 `NSAlert.runModal()` 대체; SwiftUI `.alert(item:)` 로 표시.
- `@MainActor` 마킹. 비동기 패턴은 **기존 GCD 그대로** 유지 (`DispatchQueue.global + .main`). `async/await` 변환 안 함 — 동기 blocking 모델 메서드들의 스레딩 계약을 건드리지 않기 위해.

**메서드 매핑** (기존 @objc 핸들러 → ViewModel 메서드):

| 기존 (line) | ViewModel 메서드 | 비고 |
|---|---|---|
| `selectRegistration` (1863) | `selectRegistration(_ index:)` | soundDrafts 재구성 (ResourceLocator.url/displayName) |
| `newRegistration` (1884) | `newRegistration()` | |
| `deleteRegistration` (1894) | `deleteRegistration()` | |
| `confirmSettings` (1801) | `confirm()` | 성공 시 `onRequestClose?()` |
| `selectImage` (1694) | `selectImage()` | `NSOpenPanel` 그대로 (`.fileImporter` 아님) |
| `selectSounds` (1787) | `selectSounds()` | `NSOpenPanel` 다중 선택 |
| `deleteSelectedSound` (1906) | `deleteSound(at:)` | `min(row, count-1)` 가드 유지 |
| `signIn` (1712) | `signIn()` | |
| `signUp` (1716) | `signUp()` | |
| `signOut` (1720) | `signOut()` | |
| `refreshMarketplace` (1725) | `refreshMarketplace()` | |
| `uploadSelectedToMarketplace` (1750) | `upload()` | |
| `downloadSelectedMarketplaceMalangi` (1777) | `download()` | |
| `resetForPresentation` (1984) | `resetForPresentation()` | |
| `refreshStatus` (1833) | `reload()` | `MalangiSettings.registrations` 재pull |

---

### 3단계: SwiftUI 뷰 구조

```
SettingsRootView (VStack)
├── Header: 이모지 + 탭 피커 (귀여운 세그먼트)
├── if .local  → LocalTabView
└── if .marketplace → MarketplaceTabView
```

**LocalTabView**
```
HStack
├── 왼쪽 카드 (w:200)
│   ├── "등록된 말랑이" 레이블
│   ├── ForEach(Array(registrations.enumerated()), id: \.offset) — 탭으로 selectRegistration(index:) 호출
│   └── HStack: [새 말랑이 버튼] [삭제 버튼]
└── 오른쪽 카드 (flex)
    ├── TextField("말랑이 이름", text: $viewModel.name)
    ├── HStack: [사진 선택 버튼] [이미지 미리보기 Image(nsImage:) + 빈 상태 dashed RoundedRect]
    ├── HStack: [사운드 선택 버튼] [파일 수 표시]
    ├── ForEach soundDrafts + 사운드 삭제 버튼
    └── HStack trailing: [ProgressView if isSaving] [확인 버튼]
```
> List 선택을 index 기반으로 유지하는 이유: 모델 API(`saveMalangi(editingIndex:)`, `deleteMalangi(at:)`)가 index 기반이고 `StoredMalangi`가 `Identifiable`이 아님.

**MarketplaceTabView**
```
VStack
├── 인증 카드: email/password TextField + [로그인] [가입] [로그아웃] — 로그인 여부에 따라 전환
├── 상태 텍스트
├── HStack: [마켓에 올리기] [새로고침] [다운로드] + 상태
└── List (ForEach marketplaceMalangis) — 행: 이름 + 사운드 수 + 작성자
```

**스타일 — `enum MalangiTheme` + `cardStyle` ViewModifier**
```swift
enum MalangiTheme {
    static let background = Color(red: 1.0, green: 0.97, blue: 0.93)  // 크림
    static let card = Color.white
    // 앱 기존 색 재활용 (main.swift line 109-110)
    static let accentPink  = Color(red: 1.0, green: 0.71, blue: 0.76) // 연핑크
    static let accentBlue  = Color(red: 0.66, green: 0.78, blue: 0.92) // 앱 기존 파랑
    static let accentGold  = Color(red: 0.94, green: 0.82, blue: 0.54) // 앱 기존 노랑
}
// cardStyle modifier: .padding(14) → .background(white) → .cornerRadius(18) → .shadow(opacity:0.06, radius:8, y:3)
// 버튼: .buttonStyle(.borderless) + Capsule fill + white bold text; 확인은 accentPink, 보조는 pale tint
// 폰트: .font(.system(size:14, weight:.semibold, design:.rounded))
// 이미지 미리보기: RoundedRectangle(cornerRadius:14) clip + dashed border placeholder
```

---

### 4단계: `SettingsWindow` 교체

```swift
final class SettingsWindow: NSWindow {
    private let viewModel = SettingsViewModel()

    init() {
        let rootView = SettingsRootView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: rootView)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Wazak 설정"
        titlebarAppearsTransparent = true   // 타이틀바 투명 → 콘텐츠가 꽉 차게
        isMovableByWindowBackground = true
        center()
        contentViewController = hosting
    }

    func resetForPresentation() {
        (contentViewController as? NSHostingController<SettingsRootView>)?
            .rootView.viewModel.reset()   // 또는 viewModel 직접 참조
    }
}
```

`SettingsPresenter.show()` 는 현재 `(settingsWindow?.contentView as? SettingsView)?.resetForPresentation()` 를
`settingsWindow?.resetForPresentation()` 으로 교체.

---

### 5단계: 기존 AppKit 코드 제거

- `SettingsView` 전체 삭제 (lines 1431–2070)
- `SettingsWindow` init 내부 교체 (lines 1415–1429 → 위 4단계로 대체)
- 더 이상 필요 없는 임포트 정리

---

## 리스크 / 주의사항

| 이슈 | 대응 |
|---|---|
| `NSOpenPanel` | ViewModel 메서드에서 `NSOpenPanel().runModal()` 그대로 사용. `.fileImporter` 쓰지 말 것 — content-type 필터링과 샌드박스 동작이 바뀜 |
| `localContentViews` 스냅샷 트릭 | SwiftUI `mode` enum 기반 `if/else`로 대체. 스냅샷 개념 완전 제거 |
| 3-테이블 identity 분기 (1998-2049) | 각 `ForEach`가 자기 배열에 바인딩돼서 불필요해짐. `NSTableViewDataSource/Delegate` 삭제 |
| `confirm()` 창 닫기 | VM이 window 참조 없음 → `onRequestClose` 클로저로 위임 |
| `SupabaseMalangiClient.authSession` 옵저빙 | 계산 프로퍼티라 자동 감지 안 됨 — signIn/Out 후 `reload()` / `objectWillChange.send()` 명시 호출 |
| `notifyChanged` 사이드 이펙트 | 모델 메서드가 동일하게 `Notification`을 post하므로 오버레이 갱신 자동 유지 |
| `deleteSelectedSound` 인덱스 가드 | `min(row, count-1)`이 `-1`이 될 수 있음 — 포팅 시 가드 조건 그대로 유지 |

---

## 검증

```sh
# 1. 빌드 확인
swift build

# 2. 실행
set -a; source .env; set +a
swift run Wazak

# 3. 기능 테스트 체크리스트
# □ Settings 창이 뜨는가 (메뉴바 Settings 항목)
# □ 말랑이 목록이 표시되는가
# □ 새 말랑이 등록 (이름, 사진, 사운드 → 확인)
# □ 등록된 말랑이 선택 → 편집 후 저장
# □ 말랑이 삭제
# □ 마켓플레이스 탭 전환 → 목록 새로고침
# □ 로그인/가입/로그아웃 (Supabase 환경변수 있을 때)
# □ 창 재오픈 시 reset (선택 해제, draft 초기화)
# □ 다크모드 대응 (색상이 NSColor 기반이므로 자동)
```
