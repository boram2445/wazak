# 마켓플레이스 "이미 추가됨" 을 인라인 텍스트 → 알림창으로 변경

## Context

마켓플레이스에서 이미 "내 말랑이"에 있는 말랑이를 다운로드하려 하면, 현재는 상단 액션바에 작은 회색 텍스트로 "이미 추가됨"이 잠깐 표시된다. 눈에 잘 띄지 않아 사용자가 인지하기 어렵다. 이를 명확한 알림창(SwiftUI Alert)으로 바꿔 피드백을 분명히 한다.

## 현재 구조 (탐색 결과)

- `SettingsViewModel.download(_:)` (`Settings.swift:358-363`)에서 중복이면 조기 반환:
  ```swift
  if isDownloaded(item) {
      marketplaceStatusText = "이미 추가됨"
      return
  }
  ```
- `marketplaceStatusText`은 액션바에 임시 회색 텍스트로 렌더됨 (`Settings.swift:1050-1055`).
- 이미 알림창 인프라가 갖춰져 있음:
  - `SettingsAlert` 구조체 (`Settings.swift:23-28`) — `title`, `detail`, 선택적 `confirmAction`.
  - `@Published var alert: SettingsAlert?` (`Settings.swift:106`).
  - `.alert(item: $viewModel.alert)` 와이어링 (`Settings.swift:588-603`) — `confirmAction`이 없으면 "확인" 버튼만 있는 단순 알림.
  - 동일 패턴 사용 예: `download` 내부 "포인트가 부족해요" 케이스 (`Settings.swift:395-398`).

## 구현

`Sources/Wazak/Settings.swift` 한 파일, 한 군데만 변경.

`download(_:)` (`Settings.swift:360-363`)의 인라인 텍스트 할당을 알림창 할당으로 교체:

```swift
if isDownloaded(item) {
    alert = SettingsAlert(
        title: "이미 추가됨",
        detail: "이 말랑이는 이미 내 말랑이에 있어요."
    )
    return
}
```

- `confirmAction`을 안 넘기므로 기존 와이어링상 "확인" 버튼만 있는 단순 알림이 뜬다.
- `return`은 유지 (중복 시 과금/로그인 흐름 진입 방지).
- 인라인 `marketplaceStatusText` 텍스트 렌더(`1050-1055`)는 다운로드 진행/실패 등 다른 상태에도 쓰이므로 그대로 둔다.

## 검증

```sh
swift build
swift run Wazak    # 또는 ./dev.sh
```
1. 설정 → 마켓플레이스 탭.
2. 이미 "내 말랑이"에 있는 말랑이의 다운로드(↓) 버튼 클릭.
3. 작은 회색 텍스트 대신 "이미 추가됨" 제목의 알림창이 뜨고 "확인"으로 닫히는지 확인.
