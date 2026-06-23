# 기본 말랑이 편집 잠금 (로컬 탭)

## Context

로컬 탭에서 기본 제공 말랑이(`isDefault == true`)를 선택하면 편집 폼이 그대로 활성화돼, 저장되지도 않을 사진/사운드 등록·삭제·확인 버튼이 노출된다(확인 버튼은 `.disabled`만 걸려 회색으로 보임). 기본 말랑이는 온보딩 콘텐츠라 편집 대상이 아니므로, 선택 시 편집 컨트롤을 정리한다.

사용자 요청:
- **숨김(아예 안 뜨게)**: `사운드 삭제`, `확인` 버튼.
- **비활성화(회색으로 표시는 유지)**: `말랑이 사진 등록`, `사운드 여러 개 등록`.

기존에 `selectedIsDefault` 계산 프로퍼티가 있고(`Settings.swift:146`), 마켓 업로드 버튼은 이미 `!selectedIsDefault`로 숨기고 있어(`:989–991`) 동일 패턴을 재사용한다.

## 변경 범위 (모두 `Sources/Wazak/Settings.swift`, `LocalTabView`)

### A. 숨김 — `registrationFormCard` 하단 액션 (`:977–1013`)
- `사운드 삭제` 버튼(`:979–984`)을 `if !viewModel.selectedIsDefault { … }` 로 감싸 기본 말랑이일 땐 미표시.
- `확인` 버튼(`:1008–1012`)도 `if !viewModel.selectedIsDefault { … }` 로 감싸 미표시. (기본 말랑이는 저장할 게 없음 — 업로드 버튼도 이미 숨김.)

### B. 비활성화 — 등록 버튼 (`:911–933`)
- `말랑이 사진 등록`(`:913`)·`사운드 여러 개 등록`(`:927`) 버튼에 `.disabled(viewModel.selectedIsDefault)` 추가.

### C. 비활성화 시각 피드백 — `MalangiButton` (`:1392`)
- 현재 `.buttonStyle(.plain)`이라 `.disabled()`가 시각적으로 흐려지지 않음. `@Environment(\.isEnabled) private var isEnabled` 추가 후 `.opacity(isEnabled ? 1 : 0.4)` 적용(전 버튼 공통 개선). 이미 `.disabled(!canDelete)` 등에서 의존 중이라 부작용 없음.

## 가정 / 결정
- "확인" 숨김 시 기본 말랑이의 하단 액션 바는 비게 됨(업로드 버튼도 이미 숨김) — 의도된 동작. 별도 안내 문구는 요청에 없어 추가하지 않음.

## 검증
1. `swift build` — 경고/에러 없음. `./dev.sh` → 메뉴바 `와` → 설정 → 로컬 탭.
2. **기본 말랑이 선택**(목록에서 `기본` 뱃지 항목): `사운드 삭제`·`확인` 버튼이 사라지고, `말랑이 사진 등록`·`사운드 여러 개 등록`은 흐리게(비활성) 표시 + 클릭 무반응.
3. **일반 말랑이 선택**: 네 버튼 모두 정상 표시·동작(회귀 없음).

---

# 계정 칩 다듬기 (박스 제거 / 크기 확대 / @핸들 표기)

## Context

포인트제·계정 칩 작업 후 사용자가 칩(`주인장 · 🍬 5P`)을 보고 3가지 요청:

1. **칩 겉 박스 제거 + 너무 작음** → 칩을 감싼 회색 둥근 박스를 없애고, 아바타·이름·포인트 글자를 키워 답답함 해소.
2. **구글 프로필 이미지 사용** → **이미 구현돼 있음**(코드 확인 완료). 칩은 `AsyncImage(url:)`로 `viewModel.avatarURLString`(구글 `avatar_url`→`picture` 폴백)을 원형으로 표시하고, 못 불러오면 `person.crop.circle.fill`로 폴백 (`Settings.swift:1088–1102`, 모델 `main.swift:182–201`). **추가 작업 없음** — 아바타 프레임만 칩 확대에 맞춰 키움.
3. **`@주인장` 핸들 표기** → 마켓에서 소유자 이름이 `주인장`으로만 보임. 사용자 이름 앞에 `@`를 붙여 핸들처럼 표시.

## 변경 범위 (모두 `Sources/Wazak/Settings.swift`)

### A. 칩 박스 제거 + 확대 — `actionsBar` (`:1085–1124`)

- **박스 제거**: 칩 HStack의 `.background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))` (`:1124`) 삭제. 박스가 없어지므로 가로/세로 패딩(`.padding(.horizontal, 10).padding(.vertical, 5)`)도 줄이거나 제거.
- **확대**: 아바타 `16×16` → `24×24`(폴백 SF 심볼 `size:13` → `20`), 이름 `13` → `15`, 포인트 `12` → `14`. 칩 높이는 콘텐츠가 키우므로 자동 증가.
- ▾ 트리거 버튼(`:1127`)은 탭 타깃이라 작은 박스 유지 — 커진 칩에 맞춰 아이콘 `11`→`13` 정도로 소폭 키움.

### B. `@핸들` 표기

- **마켓 목록 소유자** — `MarketplaceItem.subtitle` (`:67–72`): 이름이 있으면 `@` 접두:
  ```swift
  case .shared(let m):
      let owner = m.ownerName.map { "@\($0)" } ?? "익명"
      return "\(m.soundURLs.count) sounds · \(owner)"
  ```
- **계정 칩 이름** — 일관성 위해 `accountName`(`:561`)에도 실제 이름일 때만 `@` 접두. 이메일/`내 계정` 폴백엔 미적용:
  ```swift
  var accountName: String {
      let u = SupabaseMalangiClient.shared.authSession?.user
      if let name = u?.userMetadata?.displayName { return "@\(name)" }
      return u?.email ?? "내 계정"
  }
  ```

## 가정 / 결정

- "너무 작아"는 (직전 턴에 창 높이를 480→640으로 이미 키웠고, 캡처가 칩만 잘려 있으므로) **칩 자체**를 가리키는 것으로 판단 — 칩 콘텐츠를 키움.
- `@`는 마켓 소유자 + 계정 칩 **양쪽**에 적용(같은 핸들 정체성). 폴백 텍스트(이메일/익명/내 계정)엔 미적용.

## 검증

1. `swift build` — 경고/에러 없음. `./dev.sh` → 메뉴바 `와` → 설정 → "마켓플레이스".
2. **박스/크기**: 계정 칩에 회색 박스가 사라지고, 아바타·이름·포인트가 이전보다 크게 보임.
3. **아바타**: 구글 프로필 사진이 원형으로 표시(로딩 실패 시 핑크 person 아이콘).
4. **@핸들**: 칩 이름이 `@주인장`, 마켓 공유 항목 부제도 `… · @주인장`.

---

# 설정 창 다듬기 (개수 라벨 문구 / 창 높이 / 포인트 표시)

## Context

계정 칩·액션바 정리(완료) 후 사용자 요청 3건:

1. **개수 라벨 문구** — 현재 "말랑이 N개" → **"총 N개"** 로 변경.
2. **목록 영역이 너무 작음** — 설정 창이 고정 `680×480`(비-resizable)이라 마켓 목록이 ~5개만 보이고 스크롤해야 함. → **창 높이를 키운다**(`480 → 640`).
3. **포인트 숫자가 안 뜸** — 진단 완료: Supabase에 **`profiles` 테이블이 없음**(REST `GET /rest/v1/profiles` → `404 PGRST205 "Could not find the table 'public.profiles'"`). `.env`엔 publishable 키만 있어 코드로 테이블 생성 불가(DDL 권한 없음). → **사용자가 SQL Editor에서 포인트제 SQL을 1회 실행**해야 숫자가 뜸. 추가로 코드 측: 설정 창 열 때 잔액이 자동 로드되도록 `resetForPresentation()`에 `refreshPoints()` 호출 추가.

## 변경 범위

### A. 개수 라벨 문구 — `Sources/Wazak/Settings.swift` `actionsBar`

```swift
Text("총 \(viewModel.marketplaceItems.count)개")   // was "말랑이 \(...)개"
```

### B. 창 높이 — `Sources/Wazak/main.swift:1650` `SettingsWindow.init()`

```swift
contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),   // was height: 480
```

(`center()` 가 뒤따르므로 화면 중앙 재배치는 자동.)

### C. 설정 열 때 포인트 자동 로드 — `Sources/Wazak/Settings.swift:519` `resetForPresentation()`

```swift
func resetForPresentation() {
    selectedIndex = nil
    clearDraft()
    reload()
    refreshPoints()     // 창 열 때 잔액 자동 표시 (수동 새로고침 불필요)
}
```

> `refreshPoints()`는 `isSignedIn` 가드가 있어 비로그인 시 안전(no-op).

### D. (사용자 선행 작업) Supabase SQL — 포인트제 테이블/트리거/RPC 생성

**결정: 대시보드 직접 실행** (자동 실행 수단 없음 — supabase CLI/psql 미설치, `.env`엔 DDL 불가한 publishable 키만, service 키/DB PW/PAT 없음).

사용자가 실행:

1. https://supabase.com/dashboard/project/trkosluefzdktseemquf/sql 열기
2. 아래 "말랑이 포인트제 도입" 섹션의 **A. SQL 6블록** 붙여넣기 → Run
3. 백필(블록 2)이 기존 로그인 계정에 `points = 5` 자동 부여

내가(실행 후) 검증:

```sh
curl -s -o /dev/null -w "%{http_code}\n" \
  "$SUPABASE_URL/rest/v1/profiles?select=points&limit=1" -H "apikey: $KEY"
```

→ `404`(PGRST205)가 아니라 `200`이면 테이블 생성 성공. 이후 앱 설정 창 다시 열면 `🍬 5P` 표시.

## 검증

1. `swift build` — 경고/에러 없음. `./dev.sh` → 메뉴바 `와` → 설정 → "마켓플레이스".
2. **문구**: 좌측 라벨이 "총 6개" 로 표시.
3. **창 높이**: 목록이 이전보다 더 많이(≈8~9개) 보임, 스크롤 줄어듦.
4. **포인트**: (SQL 실행 후) 설정 창을 열기만 해도 계정 칩에 `🍬 5P` 가 자동 표시. (SQL 미실행 시엔 `🍬 —` 유지 — 이때는 사용자에게 SQL 실행 안내.)

---

# 말랑이 포인트제 도입 (가입 +5 / 다운로드 -1 / 업로드 +3)

## Context

마켓플레이스는 누구나 로그인 없이 무료로 다운로드할 수 있어(현재 배너: "다운로드는 로그인 없이 가능합니다"), 소리를 **올릴 동기**가 약하다. 업로드를 장려하기 위해 포인트 경제를 도입한다:

- **신규 가입 시 +5포인트** — 처음 받는 시드.
- **공유 말랑이 다운로드 시 -1포인트** — 소비.
- **업로드 시 +3포인트** — 공급 보상.

결정된 정책(사용자 확인 완료):

1. **차감 범위**: 사용자가 올린 **공유 말랑이(.shared)만** 로그인 필수 + 1포인트 차감. 앱 기본 제공 말랑이(.builtIn)는 **무료·무로그인 유지**(온보딩 콘텐츠).
2. **0포인트**: 포인트 부족 시 다운로드를 **차단하고 안내**("말랑이를 올려 포인트를 모아보세요").
3. **구현**: **서버 강제** — Supabase `profiles` 테이블 + 가입 트리거 + 다운로드 RPC + 업로드 트리거. 포인트는 클라이언트에서 위조 불가(SECURITY DEFINER). `user_metadata` 방식은 위조 가능해 채택하지 않음.

기존 인증은 **Google OAuth 전용**이고 신규 가입은 첫 구글 로그인 시 자동 생성되므로(`Settings.swift:397` `signInWithGoogle`), 가입 보상은 DB 트리거로 거는 게 자연스럽다.

---

## A. Supabase SQL (사용자가 대시보드 SQL Editor에서 1회 실행)

> `owner_name` 컬럼 추가나 Google Provider 설정과 동일한 "사용자 사전작업" 패턴. 코드만으로는 안 됨.

```sql
-- 1) 프로필(포인트 잔액) 테이블
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  points     integer not null default 5,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
-- 본인 잔액 읽기만 허용. 쓰기는 아래 SECURITY DEFINER 함수/트리거로만.
create policy "read own profile" on public.profiles
  for select using (auth.uid() = id);

-- 2) 기존 사용자 백필(트리거 도입 전에 가입한 계정에 5포인트 시드)
insert into public.profiles (id, points)
  select id, 5 from auth.users on conflict (id) do nothing;

-- 3) 신규 가입 시 +5 (auth.users insert 트리거)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, points) values (new.id, 5)
  on conflict (id) do nothing;
  return new;
end; $$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4) 다운로드 원장(이중 차감 방지: 사용자×말랑이 1회만 과금)
create table public.downloads (
  user_id    uuid references auth.users(id) on delete cascade,
  malangi_id uuid references marketplace_malangis(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, malangi_id)
);
alter table public.downloads enable row level security;
create policy "read own downloads" on public.downloads
  for select using (auth.uid() = user_id);

-- 5) 공유 말랑이 다운로드 RPC: 원자적 차감 + downloads_count 증가 + 원장 기록
--    남은 포인트(integer)를 반환. 부족하면 INSUFFICIENT_POINTS 예외.
create or replace function public.download_marketplace_malangi(p_malangi_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_owner uuid; v_points integer;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select owner_id into v_owner from marketplace_malangis
    where id = p_malangi_id and is_public = true;
  if v_owner is null then raise exception 'NOT_FOUND'; end if;

  -- 본인이 올린 말랑이거나, 이미 받은 적 있으면 무료(재다운로드)
  if v_owner = v_uid
     or exists (select 1 from downloads where user_id = v_uid and malangi_id = p_malangi_id) then
    return (select points from profiles where id = v_uid);
  end if;

  select points into v_points from profiles where id = v_uid for update;
  if v_points is null then raise exception 'NO_PROFILE'; end if;
  if v_points < 1 then raise exception 'INSUFFICIENT_POINTS'; end if;

  update profiles set points = points - 1 where id = v_uid returning points into v_points;
  update marketplace_malangis set downloads_count = downloads_count + 1 where id = p_malangi_id;
  insert into downloads (user_id, malangi_id) values (v_uid, p_malangi_id);
  return v_points;
end; $$;

-- 6) 최초 업로드(insert) 시 +3. PATCH(갱신)에는 적용 안 됨 → 신규 게시당 1회.
create or replace function public.reward_upload()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set points = points + 3 where id = new.owner_id;
  return new;
end; $$;
create trigger on_marketplace_insert
  after insert on marketplace_malangis
  for each row execute function public.reward_upload();
```

> 어뷰징(반복 insert로 포인트 파밍)은 PRD §3 비목표("프로덕션 수준 어뷰징 방지")라 MVP에서는 막지 않음.

---

## B. `Sources/Wazak/main.swift` — `SupabaseMalangiClient`

기존 `makeRequest`(apikey+Bearer)·`perform`·`saveAuthSession`·`authSession`를 그대로 재사용. 인증 흐름이 OAuth로 통일돼 있어 RPC도 `accessToken`만 넘기면 됨.

1. **포인트 조회** (`fetchMarketplace` 근처 추가)

   ```swift
   /// 현재 로그인 사용자의 포인트 잔액. 미로그인/미설정 시 nil.
   func fetchMyPoints() throws -> Int? {
       guard isConfigured, let session = authSession else { return nil }
       struct Row: Codable { let points: Int }
       var request = try makeRequest(path: "/rest/v1/profiles", queryItems: [
           URLQueryItem(name: "select", value: "points"),
           URLQueryItem(name: "id", value: "eq.\(session.user.id)")
       ], accessToken: session.accessToken)
       request.httpMethod = "GET"
       let rows: [Row] = try perform(request)
       return rows.first?.points
   }
   ```

2. **다운로드 RPC** (공유 말랑이 전용)

   ```swift
   /// 공유 말랑이 다운로드 → 1포인트 차감. 남은 포인트 반환.
   /// 포인트 부족 시 NSError(메시지에 "INSUFFICIENT_POINTS" 포함)을 던짐.
   func downloadMarketplaceMalangi(id: String, session: SupabaseAuthSession) throws -> Int {
       struct Body: Codable { let p_malangi_id: String }
       var request = try makeRequest(path: "/rest/v1/rpc/download_marketplace_malangi",
                                     accessToken: session.accessToken)
       request.httpMethod = "POST"
       request.httpBody = try encoder.encode(Body(p_malangi_id: id))
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
       return try perform(request)   // PostgREST 스칼라 반환 → top-level Int 디코드(macOS 13 OK)
   }
   ```

   - 에러 식별: `performRaw`가 4xx 응답 본문(JSON)을 `NSError.localizedDescription`에 담아 던지므로, 호출부에서 `error.localizedDescription.contains("INSUFFICIENT_POINTS")`로 판별.

---

## C. `Sources/Wazak/Settings.swift` — `SettingsViewModel`

1. **상태 추가**: `@Published var points: Int? = nil`.

2. **포인트 갱신 헬퍼** (백그라운드, 기존 GCD 패턴)

   ```swift
   func refreshPoints() {
       guard isSignedIn else { points = nil; return }
       DispatchQueue.global(qos: .utility).async {
           let p = try? SupabaseMalangiClient.shared.fetchMyPoints()
           DispatchQueue.main.async { self.points = p }
       }
   }
   ```

   호출 지점: `finishLogin()`(로그인 직후), `signOut()`(→ nil), `refreshMarketplace()` 성공 시, 그리고 업로드 성공(`upload()`의 success) 직후(트리거로 +3 반영).

3. **`download(_ item:)` 수정** (`Settings.swift:346`)
   - `isDownloaded` 조기 반환("이미 추가됨")은 유지 — 과금/로그인 전에 먼저 검사.
   - `.builtIn`: **현행 유지**(무료·무로그인, `unhideDefault`).
   - `.shared`: 로그인 검사 → RPC 차감 → 성공 시 로컬 추가.

   ```swift
   case .shared(let mk):
       guard let session = SupabaseMalangiClient.shared.authSession else {
           marketplaceStatusText = "로그인이 필요해요"
           openLogin()                         // 공유 말랑이 다운로드엔 로그인 필수
           return
       }
       marketplaceStatusText = "다운로드 중…"
       DispatchQueue.global(qos: .userInitiated).async {
           let result = Result {
               try SupabaseMalangiClient.shared.downloadMarketplaceMalangi(id: mk.id, session: session)
           }
           DispatchQueue.main.async {
               switch result {
               case .success(let remaining):
                   self.points = remaining
                   MalangiSettings.addMarketplaceMalangi(mk)   // 차감 성공 후에만 로컬 추가
                   self.reload()
                   self.marketplaceStatusText = "다운로드 완료 (−1P)"
               case .failure(let error):
                   if error.localizedDescription.contains("INSUFFICIENT_POINTS") {
                       self.alert = SettingsAlert(title: "포인트가 부족해요",
                           detail: "말랑이를 마켓에 올리면 +3포인트를 받아요. 올려서 포인트를 모아보세요!")
                   } else {
                       self.alert = SettingsAlert(title: "다운로드 실패", detail: error.localizedDescription)
                   }
               }
           }
       }
   ```

   > `.builtIn`/`.shared` 분기를 위해 기존 `switch item`을 위와 같이 확장. `download()`(무인자, `:361`)는 그대로 `download(marketplaceItems[idx])` 위임.

4. **업로드 보상 반영**: `upload()` success 블록(`Settings.swift:324` 부근)에서 `self.reload()` 다음에 `self.refreshPoints()` 추가(트리거 +3을 UI에 반영).

---

## D. UI 텍스트 (`MarketplaceTabView`, `Settings.swift:882~`)

1. **포인트 뱃지** — `actionsBar`(`:899`)의 로그인 상태 블록에 잔액 표시:

   ```swift
   if let p = viewModel.points {
       Text("🍬 \(p)P")
           .font(.system(size: 12, weight: .bold, design: .rounded))
           .foregroundColor(MalangiTheme.accentPink)
   }
   ```

   (닉네임 변경/로그아웃 버튼 옆)

2. **안내 배너 문구 교체** (`listCard`, `:929`) — 현재 "다운로드는 로그인 없이 가능합니다." 를:
   `"기본 말랑이는 무료예요. 공유 말랑이 다운로드는 -1포인트, 업로드하면 +3포인트!"`

3. (선택) 각 행 다운로드 버튼: 공유 말랑이는 "−1P" 의미가 배너/뱃지로 전달되므로 버튼 자체는 그대로 둠.

---

## E. 문서 (`docs/PRD.md`)

- §4.4 마켓플레이스, §5 데이터 모델에 `profiles`/`downloads` 테이블과 포인트 규칙(가입 +5 / 공유 다운로드 −1 / 업로드 +3) 추가.
- §10 "다운로드 수 증가 플로우가 아직 없다" → RPC로 `downloads_count` 증가 구현됨으로 갱신.
- §3 비목표의 "유료 다운로드"는 그대로 유효(포인트는 결제 아님) — 혼동 없도록 한 줄 주석.

---

## 재사용 포인트

- HTTP/세션: `makeRequest`·`perform`·`performRaw`·`authSession`·`saveAuthSession` (`main.swift:271~`).
- 비동기 패턴: `DispatchQueue.global(...).async { ... DispatchQueue.main.async { ... } }` (VM 전반).
- 로컬 추가: `MalangiSettings.addMarketplaceMalangi(_:)` (`main.swift:1285`) — 차감 성공 후 호출.
- 중복 방지: 기존 `isDownloaded(_:)` (`Settings.swift:337`) + 서버 `downloads` 원장 이중 안전.
- 로그인 유도: 기존 `openLogin()` (`Settings.swift:379`).

## 검증

**사전**: 위 A의 SQL 6블록을 Supabase SQL Editor에서 실행. `.env`에 `SUPABASE_*` 설정.

1. `swift build` — 경고/에러 없음.
2. `./dev.sh` 실행 → 메뉴바 `와` → 설정 → "마켓플레이스".
3. **가입/잔액**: (테스트용 새 구글 계정으로) 첫 로그인 → 닉네임 저장 → 액션바에 "🍬 5P" 표시. (기존 계정은 백필로 5P.)
4. **다운로드 −1**: 다른 계정이 올린 공유 말랑이 다운로드 → "다운로드 완료 (−1P)", 뱃지 4P로 감소, 오버레이 전환. Supabase에서 `downloads`·`profiles.points`·`marketplace_malangis.downloads_count` 확인.
5. **재다운로드 무과금**: 같은 말랑이 다시(또는 로컬 삭제 후) → 원장 존재로 포인트 변화 없음. 이미 목록에 있으면 "이미 추가됨".
6. **기본 말랑이 무료**: 로그아웃 상태에서 "기본" 뱃지 말랑이 다운로드 → 로그인 요구 없이 "다운로드 완료", 포인트 무관.
7. **업로드 +3**: 로컬 말랑이 "마켓에 올리기" → 잔액 +3. (갱신/PATCH은 보상 없음.)
8. **0포인트 차단**: 포인트를 0까지 소진 후 공유 말랑이 다운로드 → "포인트가 부족해요" 안내, 목록 변화 없음.
9. **위조 불가 확인**: 클라이언트에서 임의로 포인트를 못 올림(profiles는 RLS read-only, 변경은 RPC/트리거만).
