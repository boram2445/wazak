# 마켓플레이스: 이미 등록된 항목 다운로드 시 안내

## Context

마켓플레이스 탭은 각 행 우측에 다운로드 버튼이 있어 항목을 하나씩 받을 수 있다(이미 구현됨). 하지만 **이미 "내 말랑이"에 등록되어 있는 항목**의 다운로드 버튼을 눌러도 그냥 "다운로드 완료"라고 떠서, 새로 받은 건지 이미 있던 건지 구분되지 않는다. 사용자가 이미 등록된 항목을 누르면 **"이미 추가됨"** 같은 안내가 뜨도록 한다.

## 배경 (확인된 데이터 구조)

- 마켓플레이스 목록 = `defaultCatalog`(.builtIn) + `marketplaceMalangis`(.shared) (`Settings.swift:138`).
- 내 등록 목록 = `registrations: [StoredMalangi]` (`Settings.swift:79`).
- **기본(.builtIn)** 항목 등록 여부: `StoredMalangi.remoteId`로 매칭. `hiddenDefaults`에 없으면 `registrations`에 존재함.
- **공유(.shared)** 항목 등록 여부: `addMarketplaceMalangi`의 중복 판정과 동일하게 `imagePath == imageURL` 또는 `name` 일치로 판단(`main.swift:1223-1225`). 다운로드된 `StoredMalangi`는 marketplace `id`/`remoteId`를 저장하지 않으므로 id로는 매칭 불가.

## 구현 (Sources/Wazak/Settings.swift)

### 1) VM: 등록 여부 판정 함수 추가 (`download(_ item:)` 근처 ~320)
```swift
func isDownloaded(_ item: MarketplaceItem) -> Bool {
    switch item {
    case .builtIn(let m):
        return registrations.contains { $0.remoteId == m.remoteId }
    case .shared(let mk):
        return registrations.contains { $0.imagePath == mk.imageURL || $0.name == mk.name }
    }
}
```

### 2) `download(_ item:)` 진입 시 이미 등록된 경우 조기 반환 (`Settings.swift:320`)
```swift
func download(_ item: MarketplaceItem) {
    if isDownloaded(item) {
        marketplaceStatusText = "이미 추가됨"
        return
    }
    switch item {
    case .builtIn(let m):
        if let rid = m.remoteId { MalangiSettings.unhideDefault(remoteId: rid) }
    case .shared(let mk):
        MalangiSettings.addMarketplaceMalangi(mk)
    }
    reload()
    marketplaceStatusText = "다운로드 완료"
}
```

기존 "다운로드 완료"와 동일하게 상단 액션 바의 `marketplaceStatusText`로 안내(일관된 패턴). 별도 alert/팝업은 추가하지 않음.

## 영향 / 엣지
- 숨겼던(hidden) 기본 말랑이 → `registrations`에 없으므로 `isDownloaded == false` → 정상적으로 `unhideDefault`로 복구됨.
- 보이는 기본 말랑이 / 이미 받은 공유 말랑이 → "이미 추가됨" 표시 후 변경 없음.
- `reload()`가 매번 `registrations`를 최신화하므로 판정은 항상 현재 상태 기준.

## 검증
1. `swift build` 성공.
2. 실행 → 메뉴 바 `와` → 설정 → "마켓플레이스" 탭.
3. 현재 "내 말랑이"에 보이는 항목의 다운로드 버튼 클릭 → 상단에 "이미 추가됨" 표시, 목록 변화 없음.
4. 한 번 다운로드한 공유 항목을 다시 클릭 → "이미 추가됨".
5. 삭제(숨김)했던 기본 말랑이 클릭 → "다운로드 완료" + "내 말랑이"에 복귀.
