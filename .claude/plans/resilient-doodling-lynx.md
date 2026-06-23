# 구글 로그인(OAuth) 전환 + 닉네임 입력/수정 + 마켓 표시

## Context

현재 로그인은 이메일+비밀번호 방식(`signIn`/`signUp`, `main.swift:350-379`)이라 비번 관리가 번거롭고, OTP 방식은 무료 플랜에서 메일 템플릿이 잠겨 SMTP 설정이 필요했다. 사용자는 **구글 로그인(OAuth)** 으로 전환하기로 결정 — SMTP/메일/비번이 전부 불필요하고, 구글 프로필에서 이름·이메일이 자동으로 따라온다.

요구사항:
1. 로그인 창에서 **"Google로 로그인"** → 브라우저에서 구글 인증 → 앱으로 복귀해 세션 획득.
2. 로그인 후 **닉네임을 입력/수정**할 수 있게 한다(구글 이름이 기본값, 사용자가 바꿀 수 있음). 마켓에 표시될 이름.
3. 마켓 목록 작성자를 **이메일 대신 닉네임**으로 표시(`Settings.swift:62`, 현재 `ownerEmail ?? "unknown"`).

데스크톱 앱이라 OAuth 콜백을 받기 위해 **로컬 루프백 서버 + PKCE** 흐름을 쓴다(딥링크/번들 불필요, `swift run`에서 동작).

## 사전 작업 (사용자가 직접 1회)

### 1. Google Cloud Console — OAuth 자격증명
- console.cloud.google.com → 프로젝트 생성/선택.
- **OAuth 동의 화면** 구성. (권장: External + Testing, 본인 이메일을 테스트 사용자로 추가. 또는 goyoai.com 전용이면 Internal.)
- **사용자 인증 정보 → OAuth 클라이언트 ID 만들기 → 유형: 웹 애플리케이션**.
  - **승인된 리디렉션 URI**: `https://<PROJECT-REF>.supabase.co/auth/v1/callback` (Supabase 콜백 — 구글은 이 주소만 알면 됨).
- 발급된 **Client ID / Client Secret** 복사.

### 2. Supabase 대시보드
- **Authentication → Providers → Google**: Enable, 위 Client ID/Secret 입력, Save.
- **Authentication → URL Configuration → Redirect URLs**: `http://localhost:8765` 와 `http://localhost:8765/` 추가(루프백 콜백 허용).
- **SQL Editor**: `alter table marketplace_malangis add column owner_name text;`

> SMTP/메일 템플릿 설정은 전혀 필요 없음.

## 변경 사항

### A. `Sources/Wazak/main.swift`

1. **유저 메타데이터** (`SupabaseUser`, `main.swift:169`) — 구글 이름 + 우리 닉네임 디코드
   ```swift
   struct SupabaseUserMetadata: Codable {
       let nickname: String?      // 우리가 저장한 닉네임 (우선)
       let fullName: String?      // 구글 full_name
       let name: String?          // 구글 name
       private enum CodingKeys: String, CodingKey {
           case nickname; case fullName = "full_name"; case name
       }
       var displayName: String? { nickname ?? fullName ?? name }
   }
   struct SupabaseUser: Codable {
       let id: String
       let email: String?
       let userMetadata: SupabaseUserMetadata?
       private enum CodingKeys: String, CodingKey { case id, email; case userMetadata = "user_metadata" }
   }
   ```

2. **PKCE 유틸 + 루프백 서버** (신규, `import CryptoKit`/`import Network`)
   - `PKCE`: `verifier`(랜덤 base64url) + `challenge`(SHA256 → base64url).
   - `LoopbackAuthServer`(고정 포트 8765): `NWListener`로 TCP 수신 → 첫 GET 요청 줄에서 `code` 쿼리 파싱 → 간단한 HTML("로그인 완료, 창을 닫으세요") 응답 → 콜백으로 code 전달. 타임아웃/취소 시 정리.

3. **구글 로그인 오케스트레이션** (`SupabaseMalangiClient`, `signIn` 근처) — 기존 `makeRequest`/`perform`/`saveAuthSession` 재사용
   ```swift
   func signInWithGoogle(completion: @escaping (Result<SupabaseAuthSession, Error>) -> Void)
   ```
   흐름: PKCE 생성 → 루프백 서버 start → authorize URL을 기본 브라우저로 open(`NSWorkspace.shared.open`):
   `https://<ref>.supabase.co/auth/v1/authorize?provider=google&redirect_to=http://localhost:8765&code_challenge=<c>&code_challenge_method=s256`
   → 콜백으로 받은 code를 교환:
   ```swift
   // POST /auth/v1/token?grant_type=pkce  body:{auth_code, code_verifier}
   func exchangeCodeForSession(authCode: String, codeVerifier: String) throws -> SupabaseAuthSession
   ```
   → `saveAuthSession` 후 메인스레드 completion. (서버 참조는 완료까지 보관, 120s 타임아웃.)

4. **닉네임 저장** (PUT)
   ```swift
   func updateNickname(_ nickname: String) throws {
       guard let session = authSession else { return }
       struct Body: Codable { let data: [String: String] }
       var req = try makeRequest(path: "/auth/v1/user", accessToken: session.accessToken)
       req.httpMethod = "PUT"; req.httpBody = try encoder.encode(Body(data: ["nickname": nickname]))
       req.setValue("application/json", forHTTPHeaderField: "Content-Type")
       let user: SupabaseUser = try perform(req)
       saveAuthSession(SupabaseAuthSession(accessToken: session.accessToken,
           refreshToken: session.refreshToken, user: user))
   }
   ```

5. **마켓 모델/페이로드에 `owner_name`**
   - `MarketplaceMalangi`(`204`)·`MarketplaceMalangiPayload`(`228`)에 `let ownerName: String?` + CodingKey `owner_name`.
   - `fetchMarketplace`(`385`)·`publishToMarketplace`(`396`)의 `select` 두 곳에 `owner_name` 추가.
   - publish 페이로드: `ownerName: session.user.userMetadata?.displayName`.

6. **정리**: 미사용된 `signIn`/`signUp`/`SignUpOutcome`/`SupabaseSignUpResponse` 제거(빌드 확인 후).

### B. `Sources/Wazak/Settings.swift`

1. **ViewModel 상태** (현재 `authEmail`/`authPassword` `93-95` 교체)
   - 추가: `@Published var isAuthenticating = false`, `@Published var nicknameStage = false`, `@Published var authNickname = ""`.
   - `authEmail`/`authPassword` 제거.

2. **메서드** (현재 `signIn`/`signUp`/`authenticate` `354-436` 교체)
   - `openLogin()`(`349`): `nicknameStage=false; isAuthenticating=false; authStatusText=""; pendingUpload=false; showLoginSheet=true`.
   - `signInWithGoogle()`: `isAuthenticating=true`, 안내 "브라우저에서 로그인을 완료해 주세요" → `client.signInWithGoogle { ... }` (메인): 성공 시 `isAuthenticating=false`, `authNickname = user.displayName ?? ""`; 닉네임(metadata.nickname)이 비어 있으면 `nicknameStage=true`(입력 유도), 이미 있으면 `finishLogin()`. 실패 시 alert.
   - `saveNickname()`: 빈값 검증 → 백그라운드 `client.updateNickname(authNickname)` → 성공 시 `finishLogin()`.
   - `editNickname()`(로그인 상태에서 닉네임 재수정): `authNickname = 현재 displayName; nicknameStage=true; showLoginSheet=true`.
   - `finishLogin()`: `showLoginSheet=false; reload(); if pendingUpload { pendingUpload=false; upload() }`.
   - `upload()` 비로그인 분기(`293-298`): `pendingUpload=true; nicknameStage=false; showLoginSheet=true`.
   - `updateAuthStatus()`(`461`): `로그인됨: \(displayName ?? email)`.

3. **`LoginSheetView` 단계별 UI** (`547-583`)
   - `isAuthenticating`: 스피너 + "브라우저에서 로그인을 완료해 주세요" + [취소].
   - `nicknameStage`: 닉네임 `TextField`(구글 이름 프리필) + 헬퍼 "마켓에 표시될 이름이에요" + [취소] [저장(primary)→saveNickname].
   - 그 외(기본): "🔑 로그인" + **[Google로 로그인](primary)→signInWithGoogle** + [취소].

4. **로그인 상태 액션바** (`MarketplaceTabView.actionsBar`, `817-825`): 로그인 상태일 때 "로그아웃" 옆에 **"닉네임 변경"** 버튼(→ `editNickname()`) 추가.

5. **마켓 작성자 표기** (`MarketplaceItem.subtitle`, `Settings.swift:62`): `"\(m.soundURLs.count) sounds · \(m.ownerName ?? "익명")"`.

6. **기본 말랑이는 "마켓에 올리기" 버튼 숨김** (`LocalTabView`, `Settings.swift:776-785`): 업로드 버튼을 보여주는 `if` 조건에 `!viewModel.selectedIsDefault`(이미 존재, `133`) 추가 → 기본 말랑이(remoteId != nil) 선택 시 버튼 자체가 안 나옴. (땅콩 크런치처럼 로컬화된 말랑이는 `remoteId=nil`이라 정상적으로 버튼이 보임.)

## 재사용 포인트

- HTTP/세션: `makeRequest`·`perform`·`performRaw`·`saveAuthSession`·`authSession`(`main.swift:471-558`).
- 로그인 시트: 기존 `showLoginSheet` + `.sheet`(`Settings.swift:498`), 업로드 이어받기 `pendingUpload`(`105`).
- 마켓 목록/썸네일/미리듣기 UI는 그대로 — `subtitle` 한 줄만 닉네임으로 교체.
- macOS 13에서 `CryptoKit`(SHA256)·`Network`(NWListener)·`NSWorkspace.open` 모두 사용 가능.

## 검증

위 **사전 작업 3건**(구글 자격증명 / Supabase Provider+Redirect URL / 컬럼) 완료 후 `./dev.sh` 실행.

1. **첫 로그인**: 마켓 탭 → "로그인" → "Google로 로그인" → 브라우저 구글 인증 → 앱 복귀 → 닉네임 입력(구글 이름 프리필) → 저장 → 로그인됨(닉네임 표시).
2. **닉네임 변경**: 로그인 상태에서 "닉네임 변경" → 다른 이름으로 저장 → 반영.
3. **마켓 표시**: 말랑이 "마켓에 올리기" → 새로고침 → 작성자에 닉네임 노출(이메일 아님).
4. **재로그인**: 로그아웃 후 다시 Google 로그인 → 닉네임 유지(입력 단계 건너뜀).
5. **취소/실패**: 브라우저 안 돌아오거나 취소 시 깔끔히 종료(서버 정리, 타임아웃).
6. `swift build` 경고/에러 없음.

## 재설계 — 루프백 서버 → ASWebAuthenticationSession + 커스텀 스킴

### 진짜 원인 (확정)
- "Google로 로그인" 취소 시 앱 경고: **`Network.NWError 48 — Address already in use`** = **포트 8765 바인드 실패**. 루프백 서버가 애초에 안 떠 있었음 → 콜백을 받을 수 없어 (3)단계가 한 번도 성공 못 함.
- **루프백 생명주기 버그**: `signInWithGoogle`이 만든 `LoopbackAuthServer`를 ViewModel이 참조 안 함 → 시트 "취소"로 못 멈춤 → 포트를 최대 120초 점유 → 재시도 시 `EADDRINUSE`. 디버깅 중 Wazak 인스턴스 다중 실행도 가중.
- 결론: **구글/Supabase 설정 문제가 아니라, 콜백 수신 구현(루프백)의 구조 문제.** 포트·생명주기 이슈가 없는 **`ASWebAuthenticationSession`(AuthenticationServices)** 로 교체. (Apple 권장 방식, `swift run` 비번들 앱에서도 `callbackURLScheme:`을 세션이 내부에서 가로채므로 Info.plist 스킴 등록 불필요.)
- 참고: `s256` vs `S256`는 원인 아님 — GoTrue가 소문자 정규화. PKCE 흐름(`exchangeCodeForSession`)은 그대로 재사용.

### 사용자 사전작업 (Supabase, 1회)
- **Authentication → URL Configuration → Redirect URLs** 에 **`wazak://auth/callback`** 추가. (`http://localhost:8765`는 제거해도 됨.)
- 구글 OAuth 클라이언트/동의 화면은 **변경 없음** (리디렉션 URI는 여전히 Supabase 콜백, 동의 화면은 이미 In production).

### 변경 — `Sources/Wazak/main.swift`
1. import 교체: `import Network` 제거, **`import AuthenticationServices`** 추가.
2. **`LoopbackAuthServer` 클래스 + 관련 진단 로그 전부 삭제.**
3. **`WebAuthCoordinator`** 신규 (`NSObject, ASWebAuthenticationPresentationContextProviding`):
   ```swift
   final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
       private var session: ASWebAuthenticationSession?
       func start(url: URL, scheme: String, completion: @escaping (Result<URL, Error>) -> Void) {
           let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { cb, err in
               if let cb { completion(.success(cb)) } else { completion(.failure(err ?? ...)) }
           }
           s.presentationContextProvider = self
           s.prefersEphemeralWebBrowserSession = false   // Safari 세션 공유(UX). 문제 시 true로
           session = s
           if !s.start() { completion(.failure(...)) }    // 메인스레드에서 호출
       }
       func cancel() { session?.cancel(); session = nil }
       func presentationAnchor(for s: ASWebAuthenticationSession) -> ASPresentationAnchor {
           NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
       }
   }
   ```
4. `SupabaseMalangiClient`에 `private var webAuth: WebAuthCoordinator?`(플로우 동안 retain) + **`cancelGoogleSignIn()`**(`webAuth?.cancel()`).
5. **`signInWithGoogle` 재작성**: PKCE 생성 → authorize URL(`redirect_to=wazak://auth/callback`, `code_challenge`, `code_challenge_method=s256`) → `webAuth.start(url:, scheme:"wazak")`. 콜백 URL에서 `code` 파싱 → **백그라운드 큐에서** `exchangeCodeForSession` 호출(세션 완료는 메인스레드라 동기 네트워크는 dispatch) → 메인 completion.
   - 취소(`ASWebAuthenticationSessionError.canceledLogin`)는 **에러 alert 없이** 조용히 종료.
   - `NSWorkspace.shared.open` 호출 제거(세션이 브라우저를 띄움).
6. 시작 가이드 출력(`main.swift:18-27`): `[2]` Supabase Redirect URL을 **`wazak://auth/callback`** 로 수정.

### 변경 — `Sources/Wazak/Settings.swift`
- ViewModel `signInWithGoogle()`(`446`): 거의 그대로(`client.signInWithGoogle{...}`). 단 실패 케이스에서 **취소(canceledLogin)면 alert 생략**하고 상태만 리셋.
- 로그인 시트 `isAuthenticating` 단계의 "취소"(`657-659`): `SupabaseMalangiClient.shared.cancelGoogleSignIn()` 호출 추가 후 상태 리셋.

### 검증
1. Supabase Redirect URLs에 `wazak://auth/callback` 추가 저장.
2. **떠 있는 Wazak 인스턴스 전부 종료** 후 `./dev.sh` 1개만 실행.
3. 마켓 탭 → "로그인" → "Google로 로그인" → **ASWebAuthenticationSession 창**에서 구글 인증 → 자동으로 앱 복귀(닉네임 입력 단계 or 로그인됨).
4. 취소 동작: 인증 창 닫기/취소 → 에러 alert 없이 시트 원상복귀, **포트 점유/`error 48` 없음**(재시도 즉시 가능).
5. `swift build` 클린.

> 리스크: 비번들 `swift run`에서 `ASWebAuthenticationSession` presentation anchor가 필요(설정 창이 anchor 역할). 만약 구글 단계에서 여전히 "문제가 발생했습니다"가 재현되면 그건 별개의 구글 설정/전파 이슈 → `prefersEphemeralWebBrowserSession = true`로 깨끗한 세션 테스트.

## 핵심 정리

- **무엇을/왜**: 이메일+비번 로그인을 **구글 OAuth**로 전환(비번·메일·SMTP 불필요). 로그인 후 **닉네임 입력/수정** 가능(구글 이름 기본값), 마켓에 이메일 대신 닉네임 표시. **기본 말랑이는 "마켓에 올리기" 버튼 숨김**.
- **로그인 방식**: "Google로 로그인" → 브라우저 인증 → 앱이 `localhost:8765` 루프백 서버로 콜백 수신 → PKCE 코드 교환으로 세션 획득.
- **주요 변경**:
  - `main.swift`: 구글 OAuth(PKCE+`NWListener` 루프백)·코드↔세션 교환·닉네임 PUT·유저 메타데이터 디코드·마켓 `owner_name`. 비번 메서드 제거.
  - `Settings.swift`: 로그인 시트 단계별 UI(구글 버튼→닉네임 입력), "닉네임 변경" 버튼, 기본 말랑이 업로드 버튼 숨김, 작성자 닉네임 표기.
- **사용자 사전작업 3가지** (코드만으로 안 됨): ①Google Cloud OAuth 클라이언트 ID(웹, 리디렉션=Supabase `/auth/v1/callback`) ②Supabase Google Provider + Redirect URL `http://localhost:8765` ③SQL `add column owner_name text`. (SMTP 불필요)
- **검증**: 첫 로그인→닉네임 저장→마켓에 닉네임 노출, 닉네임 변경, 재로그인 시 닉네임 유지, 취소/타임아웃 정리, `swift build` 클린.
- **진짜 원인 & 재설계 (최종)**: 로그인 실패의 근본 원인은 **루프백 서버 포트 8765 점유(`NWError 48`, Address already in use)** — 서버가 안 떠서 콜백을 못 받았음. 생명주기 관리도 불가(취소 시 못 멈춤). **해결: 루프백 제거 → `ASWebAuthenticationSession` + 커스텀 스킴 `wazak://auth/callback`** 으로 교체(Apple 권장, 포트·생명주기 문제 원천 제거). PKCE 코드 교환은 그대로 재사용. **사용자 작업: Supabase Redirect URLs에 `wazak://auth/callback` 추가**(구글 설정은 변경 없음). 구글 "문제가 발생했습니다"가 재발하면 그건 별개의 전파/설정 이슈로 분리 대응.
