# 땅콩 크런치 마켓 중복 + 썸네일 잘못된 이미지 수정

## Context

마켓 탭에서 두 가지 버그:
1. **전체 탭에 땅콩 크런치 2개** — 같은 말랑이가 두 번 업로드돼 `marketplace_malangis`에 동일 내용 행이
   2개 존재 (`9be777f6` 04:59 / `53dd83d3` 05:28, 이미지·소리·owner 100% 동일). 1개만 있어야 함.
2. **마켓 탭에서 같은 땅콩이 다른 사진** — DB상 두 행 모두 같은 peanut 이미지를 가리킴(데이터 정상).
   화면에서 사과 이미지 + 땅콩 이름으로 보이는 건 **썸네일 뷰 재사용 버그**.

근본 원인:
- 썸네일: `ForEach(Array(filteredItems.enumerated()), id: \.offset)`(`Settings.swift:1251`)가 offset을
  identity로 써서 필터 전환 시 다른 아이템에 같은 뷰를 재사용. `MarketplaceThumbnail`의
  `.task(id: urlString) { guard image == nil else { return } ... }`(`:1356-1357`)가 재사용된 뷰의
  이미지를 다시 로드하지 않아 옛 이미지(사과)가 남음.
- 중복 업로드: `publishToMarketplace`(`main.swift:574-633`)는 `marketplaceId` 있으면 PATCH, 없으면 POST.
  로컬 `marketplaceId` 저장(`setMarketplaceId`→`localIndex` imagePath 매칭, `main.swift:1432/1578`)이 실패하면
  재업로드 시 또 POST insert → 중복. DB 측 dedup(unique/merge) 없음.

## 변경 사항

### 1. 중복 마켓 행 삭제 (즉시 정리)
새 행 `53dd83d3-43fa-4846-8f18-b85b90e52b80` 삭제, 원본 `9be777f6` 유지. REST DELETE 시도:
```sh
set -a; source .env; set +a
KEY="${SUPABASE_PUBLISHABLE_KEY:-$SUPABASE_ANON_KEY}"
curl -sS -X DELETE "${SUPABASE_URL}/rest/v1/marketplace_malangis?id=eq.53dd83d3-43fa-4846-8f18-b85b90e52b80" \
  -H "apikey: ${KEY}" -H "Authorization: Bearer ${KEY}" -H "Prefer: return=representation"
```
RLS로 막히면(owner 전용 정책) Supabase 대시보드 SQL 에디터에서:
`delete from public.marketplace_malangis where id = '53dd83d3-43fa-4846-8f18-b85b90e52b80';`

### 2. 썸네일 stale 버그 — `Settings.swift`
- ForEach identity를 안정적으로: `id: \.offset` → `id: \.element.id`
  (`MarketplaceItem.id`는 `"shared-<id>"`/`"builtin-..."`로 유일, `Settings.swift:35-40`). index는 `enumerated()`
  유지(선택 하이라이트용).
- `MarketplaceThumbnail`(`:1356-1357`): `.task(id: urlString)`에서 `guard image == nil` 제거하고
  로드 시작 시 `image = nil`로 리셋 → urlString 변경 시 항상 새로 로드.

### 3. 재업로드 중복 방지 — `main.swift` `publishToMarketplace` (`:609-623`)
POST insert 직전(else 브랜치)에 owner_id+name으로 기존 행을 조회해, 있으면 그 id로 PATCH:
- `marketplaceId`가 nil일 때 GET `/rest/v1/marketplace_malangis?owner_id=eq.<uid>&name=eq.<name>&select=id`
  (기존 `makeRequest`/`perform` 재사용) → 결과 있으면 첫 행 id로 PATCH 경로 사용, 없으면 기존대로 POST.
- 결과 row의 id는 기존 `setMarketplaceId`로 로컬 저장(이미 `upload()`에서 호출, `Settings.swift:348`).

## 검증
1. `swift build` 통과.
2. 중복 삭제 확인: `GET marketplace_malangis?name=eq.땅콩 크런치` → 1개만.
3. 재시작 후 마켓 탭:
   - 전체/마켓 필터 전환 시 각 행 이미지가 이름과 일치(사과↔땅콩 섞임 없음). 새로고침/스크롤에도 유지.
   - 땅콩 크런치 1개만 표시.
4. 재업로드 테스트: 로컬 땅콩을 다시 "마켓 갱신/올리기" → 행이 새로 생기지 않고 기존 행 갱신.

## 재시작 (CLAUDE.md 규칙)
`pkill -x Wazak` 후 `set -a; source .env; set +a && swift run Wazak`.
