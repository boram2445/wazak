import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import CoreImage
import AuthenticationServices
import UniformTypeIdentifiers
import Vision
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlayWindow: OverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Wazak is running. Look near the center of your screen, or click the menu bar item labeled '와'.")
        let client = SupabaseMalangiClient.shared
        if let googleRedirectURI = client.googleRedirectURI {
            print("""
            ── Google OAuth 설정 가이드 ──────────────────────────────────────────
            [1] Google Cloud Console → OAuth 클라이언트 ID → 승인된 리디렉션 URI:
                \(googleRedirectURI)
            [2] Supabase → Authentication → URL Configuration → Redirect URLs:
                wazak://auth/callback
            ─────────────────────────────────────────────────────────────────────
            """)
        }
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            self.configureStatusItem()
            MalangiSettings.refreshRemoteRegistrations()
            self.showOverlay()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "와"
        item.button?.toolTip = "Wazak"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Wazak", action: #selector(showOverlayFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func showOverlay() {
        let window = OverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window
    }

    @objc private func showOverlayFromMenu() {
        if overlayWindow == nil {
            showOverlay()
        }
        overlayWindow?.orderFrontRegardless()
    }

    @objc private func showSettings() {
        SettingsPresenter.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

struct Malangi {
    let name: String
    let badge: String
    let primaryColor: NSColor
    let secondaryColor: NSColor
    let soundFrequency: Double
    let imageName: String?
    let soundNames: [String]
}

struct StoredMalangi: Codable {
    let remoteId: String?
    let name: String
    let imagePath: String
    let imageFileName: String?
    let soundPaths: [String]
    let soundFileNames: [String]
    // not persisted — set true only for remote-only "기본 말랑이" entries
    var isDefault: Bool = false
    // marketplace_malangis row id — nil if not published yet
    var marketplaceId: String? = nil

    private enum CodingKeys: String, CodingKey {
        case remoteId
        case name
        case imagePath
        case imageFileName
        case soundPaths
        case soundFileNames
        case marketplaceId
    }

    init(remoteId: String? = nil, name: String, imagePath: String, imageFileName: String? = nil, soundPaths: [String], soundFileNames: [String]? = nil, marketplaceId: String? = nil) {
        self.remoteId = remoteId
        self.name = name
        self.imagePath = imagePath
        self.imageFileName = imageFileName
        self.soundPaths = soundPaths
        self.soundFileNames = soundFileNames ?? soundPaths.map { ResourceLocator.displayName(for: $0) }
        self.marketplaceId = marketplaceId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remoteId = try container.decodeIfPresent(String.self, forKey: .remoteId)
        name = try container.decode(String.self, forKey: .name)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        soundPaths = try container.decode([String].self, forKey: .soundPaths)
        soundFileNames = try container.decodeIfPresent([String].self, forKey: .soundFileNames)
            ?? soundPaths.map { ResourceLocator.displayName(for: $0) }
        marketplaceId = try container.decodeIfPresent(String.self, forKey: .marketplaceId)
    }

    func asMalangi() -> Malangi {
        Malangi(
            name: name,
            badge: name,
            primaryColor: NSColor(calibratedRed: 0.66, green: 0.78, blue: 0.92, alpha: 1),
            secondaryColor: NSColor(calibratedRed: 0.94, green: 0.82, blue: 0.54, alpha: 1),
            soundFrequency: 587.33,
            imageName: imagePath,
            soundNames: soundPaths
        )
    }
}

struct SoundDraft {
    let url: URL
    let displayName: String
}

struct SupabaseMalangiRow: Codable {
    let id: String
    let name: String
    let imagePath: String
    let imageFileName: String?
    let soundPaths: [String]
    let soundFileNames: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case imagePath = "image_path"
        case imageFileName = "image_file_name"
        case soundPaths = "sound_paths"
        case soundFileNames = "sound_file_names"
    }

    var storedMalangi: StoredMalangi {
        StoredMalangi(remoteId: id, name: name, imagePath: imagePath, imageFileName: imageFileName, soundPaths: soundPaths, soundFileNames: soundFileNames)
    }
}

struct SupabaseMalangiPayload: Codable {
    let name: String
    let imagePath: String
    let imageFileName: String?
    let soundPaths: [String]
    let soundFileNames: [String]

    private enum CodingKeys: String, CodingKey {
        case name
        case imagePath = "image_path"
        case imageFileName = "image_file_name"
        case soundPaths = "sound_paths"
        case soundFileNames = "sound_file_names"
    }
}

struct SupabaseUserMetadata: Codable {
    let nickname: String?   // 우리가 저장한 닉네임 (우선)
    let fullName: String?   // 구글 full_name
    let name: String?       // 구글 name (fallback)
    let avatarURL: String?  // 구글 avatar_url
    let picture: String?    // 구글 picture (fallback)

    private enum CodingKeys: String, CodingKey {
        case nickname
        case fullName = "full_name"
        case name
        case avatarURL = "avatar_url"
        case picture
    }

    /// 마켓/UI에 표시할 최종 이름: 닉네임 > 구글 full_name > 구글 name
    var displayName: String? { nickname ?? fullName ?? name }
    /// 구글 프로필 사진 URL: avatar_url → picture 순서 폴백
    var avatarURLString: String? { avatarURL ?? picture }
}

struct SupabaseUser: Codable {
    let id: String
    let email: String?
    let userMetadata: SupabaseUserMetadata?

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }
}

struct SupabaseAuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let user: SupabaseUser

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct MarketplaceMalangi: Codable {
    let id: String
    let ownerId: String
    let ownerEmail: String?
    let ownerName: String?
    let name: String
    let imageURL: String
    let imageFileName: String?
    let soundURLs: [String]
    let soundFileNames: [String]
    let downloadsCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case ownerEmail = "owner_email"
        case ownerName = "owner_name"
        case name
        case imageURL = "image_url"
        case imageFileName = "image_file_name"
        case soundURLs = "sound_urls"
        case soundFileNames = "sound_file_names"
        case downloadsCount = "downloads_count"
    }
}

struct MarketplaceMalangiPayload: Codable {
    let ownerId: String
    let ownerEmail: String?
    let ownerName: String?
    let name: String
    let imageURL: String
    let imageFileName: String?
    let soundURLs: [String]
    let soundFileNames: [String]
    let isPublic: Bool

    private enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case ownerEmail = "owner_email"
        case ownerName = "owner_name"
        case name
        case imageURL = "image_url"
        case imageFileName = "image_file_name"
        case soundURLs = "sound_urls"
        case soundFileNames = "sound_file_names"
        case isPublic = "is_public"
    }
}

final class SupabaseMalangiClient {
    static let shared = SupabaseMalangiClient()
    static let assetBucket = "malangi-assets"

    private let baseURL: URL?
    private let publishableKey: String?
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let authSessionKey = "supabase.authSession"
    private var webAuth: WebAuthCoordinator?

    private var isConfigured: Bool {
        baseURL != nil && publishableKey?.isEmpty == false
    }

    var canSync: Bool {
        isConfigured
    }

    /// Google Cloud Console의 "승인된 리디렉션 URI"에 입력해야 하는 주소 (SUPABASE_URL 기반).
    var googleRedirectURI: String? {
        guard let baseURL else { return nil }
        return baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/auth/v1/callback"
    }

    var authSession: SupabaseAuthSession? {
        guard let data = UserDefaults.standard.data(forKey: authSessionKey) else { return nil }
        return try? decoder.decode(SupabaseAuthSession.self, from: data)
    }

    private init(session: URLSession = .shared) {
        let environment = ProcessInfo.processInfo.environment
        let bundledURLString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String
        let bundledKey = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String
        let urlString = environment["SUPABASE_URL"] ?? bundledURLString ?? ""
        let key = environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? environment["SUPABASE_ANON_KEY"]
            ?? bundledKey
            ?? ""

        self.baseURL = URL(string: urlString)
        self.publishableKey = key
        self.session = session
    }

    func fetchAll() throws -> [StoredMalangi] {
        guard isConfigured else { return [] }

        var request = try makeRequest(path: "/rest/v1/malangis", queryItems: [
            URLQueryItem(name: "select", value: "id,name,image_path,image_file_name,sound_paths,sound_file_names"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ])
        request.httpMethod = "GET"

        let rows: [SupabaseMalangiRow] = try perform(request)
        return rows.map(\.storedMalangi)
    }

    func upsert(_ malangi: StoredMalangi) throws -> StoredMalangi {
        guard isConfigured else { return malangi }

        let payload = SupabaseMalangiPayload(
            name: malangi.name,
            imagePath: malangi.imagePath,
            imageFileName: malangi.imageFileName,
            soundPaths: malangi.soundPaths,
            soundFileNames: malangi.soundFileNames
        )

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,name,image_path,image_file_name,sound_paths,sound_file_names")
        ]
        if let remoteId = malangi.remoteId {
            queryItems.append(URLQueryItem(name: "id", value: "eq.\(remoteId)"))
        }

        var request = try makeRequest(path: "/rest/v1/malangis", queryItems: queryItems)
        request.httpMethod = malangi.remoteId == nil ? "POST" : "PATCH"
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let rows: [SupabaseMalangiRow] = try perform(request)
        return rows.first?.storedMalangi ?? malangi
    }

    func delete(id: String) throws {
        guard isConfigured else { return }

        var request = try makeRequest(path: "/rest/v1/malangis", queryItems: [
            URLQueryItem(name: "id", value: "eq.\(id)")
        ])
        request.httpMethod = "DELETE"
        _ = try performRaw(request)
    }

    func uploadAsset(fileURL: URL, objectPath: String, contentType: String, accessToken: String? = nil) throws -> String {
        guard isConfigured else { return fileURL.path }

        var request = try makeRequest(path: "/storage/v1/object/\(Self.assetBucket)/\(objectPath)", accessToken: accessToken)
        request.httpMethod = "POST"
        request.httpBody = try Data(contentsOf: fileURL)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        _ = try performRaw(request)

        return try publicAssetURL(objectPath: objectPath).absoluteString
    }

    // MARK: - Google OAuth (PKCE + loopback)

    /// ASWebAuthenticationSession으로 구글 로그인 → wazak://auth/callback 콜백 수신 → PKCE 세션 교환.
    /// 메인스레드에서 호출해야 합니다.
    func signInWithGoogle(completion: @escaping (Result<SupabaseAuthSession, Error>) -> Void) {
        guard isConfigured, let baseURL else {
            completion(.failure(NSError(domain: "Wazak", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Supabase 환경변수가 설정되지 않았어요."])))
            return
        }

        let pkce = PKCE()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/auth/v1/authorize"
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: "wazak://auth/callback"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]

        guard let authorizeURL = components?.url else {
            completion(.failure(NSError(domain: "Wazak", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "구글 로그인 URL을 만들 수 없어요."])))
            return
        }

        cancelGoogleSignIn()
        let coordinator = WebAuthCoordinator()
        webAuth = coordinator

        // ASWebAuthenticationSession은 메인스레드에서 시작해야 함
        DispatchQueue.main.async {
            coordinator.start(url: authorizeURL, scheme: "wazak") { [weak self] result in
            // ASWebAuthenticationSession completion은 메인스레드로 옴
            guard let self else { return }
            self.webAuth = nil

            switch result {
            case .failure(let error):
                // 사용자가 창을 닫아 취소한 경우 — 에러 없이 조용히 종료
                let code = (error as? ASWebAuthenticationSessionError)?.code
                if code == .canceledLogin {
                    completion(.failure(error))
                    return
                }
                completion(.failure(error))

            case .success(let callbackURL):
                guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    let desc = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "error_description" })?.value
                    completion(.failure(NSError(domain: "Wazak", code: 12,
                        userInfo: [NSLocalizedDescriptionKey: desc ?? "콜백 URL에서 code를 찾을 수 없어요."])))
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let session = try self.exchangeCodeForSession(authCode: code, codeVerifier: pkce.verifier)
                        DispatchQueue.main.async { completion(.success(session)) }
                    } catch {
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                }
            }
            } // coordinator.start closure
        } // DispatchQueue.main.async
    }

    func cancelGoogleSignIn() {
        webAuth?.cancel()
        webAuth = nil
    }

    private func exchangeCodeForSession(authCode: String, codeVerifier: String) throws -> SupabaseAuthSession {
        struct PKCEPayload: Codable {
            let authCode: String
            let codeVerifier: String
            private enum CodingKeys: String, CodingKey {
                case authCode = "auth_code"
                case codeVerifier = "code_verifier"
            }
        }

        var request = try makeRequest(path: "/auth/v1/token", queryItems: [
            URLQueryItem(name: "grant_type", value: "pkce")
        ])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(PKCEPayload(authCode: authCode, codeVerifier: codeVerifier))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let session: SupabaseAuthSession = try perform(request)
        saveAuthSession(session)
        print("[OAuth] 세션 교환 성공 — user: \(session.user.id)")
        return session
    }

    /// DB에서 최신 user 정보(avatar_url 등)를 가져와 저장된 세션을 갱신합니다.
    func refreshUserSession() throws {
        guard let session = authSession else { return }
        var request = try makeRequest(path: "/auth/v1/user", accessToken: session.accessToken)
        request.httpMethod = "GET"
        let freshUser: SupabaseUser = try perform(request)
        // PUT 응답이 avatar 등을 누락할 수 있으므로 기존 값으로 보완
        let prev = session.user.userMetadata
        let merged = SupabaseUserMetadata(
            nickname: freshUser.userMetadata?.nickname ?? prev?.nickname,
            fullName: freshUser.userMetadata?.fullName ?? prev?.fullName,
            name: freshUser.userMetadata?.name ?? prev?.name,
            avatarURL: freshUser.userMetadata?.avatarURL ?? prev?.avatarURL,
            picture: freshUser.userMetadata?.picture ?? prev?.picture
        )
        saveAuthSession(SupabaseAuthSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            user: SupabaseUser(id: freshUser.id, email: freshUser.email ?? session.user.email, userMetadata: merged)
        ))
    }

    /// 닉네임을 Supabase user_metadata에 저장합니다.
    func updateNickname(_ nickname: String) throws {
        guard let session = authSession else { return }
        struct Body: Codable { let data: [String: String] }
        var request = try makeRequest(path: "/auth/v1/user", accessToken: session.accessToken)
        request.httpMethod = "PUT"
        request.httpBody = try encoder.encode(Body(data: ["nickname": nickname]))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let user: SupabaseUser = try perform(request)
        // PUT 응답이 Google avatar 등 OAuth 메타데이터를 누락할 수 있으므로 기존 값 보존
        let prev = session.user.userMetadata
        let merged = SupabaseUserMetadata(
            nickname: user.userMetadata?.nickname ?? prev?.nickname,
            fullName: user.userMetadata?.fullName ?? prev?.fullName,
            name: user.userMetadata?.name ?? prev?.name,
            avatarURL: user.userMetadata?.avatarURL ?? prev?.avatarURL,
            picture: user.userMetadata?.picture ?? prev?.picture
        )
        saveAuthSession(SupabaseAuthSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            user: SupabaseUser(id: user.id, email: user.email ?? session.user.email, userMetadata: merged)
        ))
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: authSessionKey)
    }

    func fetchMarketplace() throws -> [MarketplaceMalangi] {
        guard isConfigured else { return [] }
        var request = try makeRequest(path: "/rest/v1/marketplace_malangis", queryItems: [
            URLQueryItem(name: "select", value: "id,owner_id,owner_email,owner_name,name,image_url,image_file_name,sound_urls,sound_file_names,downloads_count"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ])
        request.httpMethod = "GET"
        return try perform(request)
    }

    /// 현재 로그인 사용자의 포인트 잔액을 조회합니다. 미로그인/미설정 시 nil.
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

    /// 공유 말랑이 다운로드 — 1포인트 차감 후 남은 포인트를 반환합니다.
    /// 포인트 부족 시 "INSUFFICIENT_POINTS" 를 포함한 에러를 던집니다.
    func downloadMarketplaceMalangi(id: String, session: SupabaseAuthSession) throws -> Int {
        struct Body: Codable { let p_malangi_id: String }
        var request = try makeRequest(
            path: "/rest/v1/rpc/download_marketplace_malangi",
            accessToken: session.accessToken
        )
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(Body(p_malangi_id: id))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try perform(request)
    }

    func unpublishMarketplaceMalangi(id: String, session: SupabaseAuthSession) throws {
        guard isConfigured else {
            throw NSError(domain: "Wazak", code: 20, userInfo: [NSLocalizedDescriptionKey: "Supabase 환경변수가 필요해요."])
        }

        var request = try makeRequest(path: "/rest/v1/marketplace_malangis", queryItems: [
            URLQueryItem(name: "id", value: "eq.\(id)")
        ], accessToken: session.accessToken)
        request.httpMethod = "DELETE"
        _ = try performRaw(request)
    }

    func publishToMarketplace(_ malangi: StoredMalangi, session: SupabaseAuthSession) throws -> MarketplaceMalangi {
        guard isConfigured else {
            throw NSError(domain: "Wazak", code: 20, userInfo: [NSLocalizedDescriptionKey: "Supabase 환경변수가 필요해요."])
        }

        let assetFolder = "marketplace/\(session.user.id)/\(UUID().uuidString)"
        let imageURL = try marketplaceAssetURL(
            reference: malangi.imagePath,
            objectPath: "\(assetFolder)/image.png",
            contentType: "image/png",
            accessToken: session.accessToken
        )
        let soundURLs = try malangi.soundPaths.enumerated().map { index, path in
            try marketplaceAssetURL(
                reference: path,
                objectPath: "\(assetFolder)/sounds/sound-\(index + 1)-\(UUID().uuidString).\(soundExtension(for: path))",
                contentType: contentType(for: path),
                accessToken: session.accessToken
            )
        }

        let payload = MarketplaceMalangiPayload(
            ownerId: session.user.id,
            ownerEmail: session.user.email,
            ownerName: session.user.userMetadata?.displayName,
            name: malangi.name,
            imageURL: imageURL,
            imageFileName: malangi.imageFileName,
            soundURLs: soundURLs,
            soundFileNames: malangi.soundFileNames,
            isPublic: true
        )

        let selectQuery = URLQueryItem(name: "select", value: "id,owner_id,owner_email,owner_name,name,image_url,image_file_name,sound_urls,sound_file_names,downloads_count")

        var request: URLRequest
        // marketplaceId가 nil이더라도 서버에 이미 같은 owner+name 행이 있으면 PATCH 경로 사용 (중복 방지)
        let resolvedMarketplaceId: String? = malangi.marketplaceId ?? {
            let checkRequest = try? makeRequest(
                path: "/rest/v1/marketplace_malangis",
                queryItems: [
                    URLQueryItem(name: "owner_id", value: "eq.\(session.user.id)"),
                    URLQueryItem(name: "name", value: "eq.\(malangi.name)"),
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                accessToken: session.accessToken
            )
            if let req = checkRequest,
               let existing: [[String: String]] = try? perform(req),
               let firstId = existing.first?["id"] {
                return firstId
            }
            return nil
        }()

        if let existingId = resolvedMarketplaceId {
            // 이미 게시된 말랑이 → PATCH로 갱신
            request = try makeRequest(path: "/rest/v1/marketplace_malangis", queryItems: [
                URLQueryItem(name: "id", value: "eq.\(existingId)"),
                selectQuery
            ], accessToken: session.accessToken)
            request.httpMethod = "PATCH"
        } else {
            // 첫 게시 → POST로 insert
            request = try makeRequest(path: "/rest/v1/marketplace_malangis", queryItems: [
                selectQuery
            ], accessToken: session.accessToken)
            request.httpMethod = "POST"
        }
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let rows: [MarketplaceMalangi] = try perform(request)
        guard let row = rows.first else {
            throw NSError(domain: "Wazak", code: 21, userInfo: [NSLocalizedDescriptionKey: "마켓 등록 결과를 확인할 수 없어요."])
        }
        return row
    }

    func publicAssetURL(objectPath: String) throws -> URL {
        guard let baseURL else {
            throw NSError(domain: "Wazak", code: 12, userInfo: [NSLocalizedDescriptionKey: "Supabase URL이 설정되지 않았어요."])
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/storage/v1/object/public/\(Self.assetBucket)/\(objectPath)"

        guard let url = components?.url else {
            throw NSError(domain: "Wazak", code: 13, userInfo: [NSLocalizedDescriptionKey: "Supabase Storage URL을 만들 수 없어요."])
        }

        return url
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = [], accessToken: String? = nil) throws -> URLRequest {
        guard let baseURL, let publishableKey else {
            throw NSError(domain: "Wazak", code: 10, userInfo: [NSLocalizedDescriptionKey: "Supabase 환경변수가 설정되지 않았어요."])
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw NSError(domain: "Wazak", code: 11, userInfo: [NSLocalizedDescriptionKey: "Supabase URL을 만들 수 없어요."])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? publishableKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func saveAuthSession(_ session: SupabaseAuthSession) {
        let data = try? encoder.encode(session)
        UserDefaults.standard.set(data, forKey: authSessionKey)
    }

    private func marketplaceAssetURL(reference: String, objectPath: String, contentType: String, accessToken: String) throws -> String {
        if let url = URL(string: reference),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return reference
        }

        guard let sourceURL = ResourceLocator.url(for: reference) else {
            throw NSError(domain: "Wazak", code: 22, userInfo: [NSLocalizedDescriptionKey: "\(reference) 파일을 찾을 수 없어요."])
        }
        return try uploadAsset(fileURL: sourceURL, objectPath: objectPath, contentType: contentType, accessToken: accessToken)
    }

    private func contentType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "m4a":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "aif", "aiff":
            return "audio/aiff"
        default:
            return "audio/mpeg"
        }
    }

    private func soundExtension(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        return ext.isEmpty ? "mp3" : String(ext)
    }

    private func perform<T: Decodable>(_ request: URLRequest) throws -> T {
        let data = try performRaw(request)
        return try decoder.decode(T.self, from: data)
    }

    private func performRaw(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?

        session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response ?? URLResponse()))
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()

        let (data, response) = try result?.get() ?? (Data(), URLResponse())
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Supabase 요청에 실패했어요."
            throw NSError(domain: "Wazak", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return data
    }
}

extension Notification.Name {
    static let malangiSettingsChanged = Notification.Name("malangiSettingsChanged")
}

enum MalangiNotificationKey {
    static let selectedRemoteId = "selectedRemoteId"
    static let selectedName = "selectedName"
}

final class OverlayWindow: NSPanel {
    init() {
        let size = NSSize(width: 220, height: 260)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        contentView = MalangiOverlayView(frame: NSRect(origin: .zero, size: size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MalangiOverlayView: NSView {
    private let defaultMalangis: [Malangi] = [
        Malangi(
            name: "사과 슬랑이",
            badge: "사과 슬랑이",
            primaryColor: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.76, alpha: 1),
            secondaryColor: NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.64, alpha: 1),
            soundFrequency: 523.25,
            imageName: "malangi-green.png",
            soundNames: [
                "apple_1sec.mp3",
                "apple_1sec_2.mp3",
                "apple_1sec_3.mp3",
                "apple_2sec.mp3",
                "apple_2sec_1.mp3",
                "apple_2sec_3.mp3",
                "apple_2sec_4.mp3",
                "apple_2sec_5.mp3",
                "apple_3sec.mp3"
            ]
        )
    ]

    private let imageView = MalangiImageView(frame: .zero)
    private let badgeLabel = BadgeLabel(frame: .zero)
    private let leftButton = ArrowButton(direction: .left)
    private let rightButton = ArrowButton(direction: .right)
    private let settingsButton = OverlaySymbolButton(symbolName: "gearshape.fill", toolTip: "설정")
    private let quitButton = OverlaySymbolButton(symbolName: "xmark", toolTip: "앱 종료")
    private let soundPlayer = SoundPlayer()
    private var trackingAreaRef: NSTrackingArea?
    private var currentIndex = 0
    private var isHovering = false
    private var isImageHovering = false

    private var malangis: [Malangi] {
        let registered = MalangiSettings.registeredMalangis
        let registeredNames = Set(registered.map(\.name))
        let visibleDefaults = defaultMalangis.filter { !registeredNames.contains($0.name) }
        return visibleDefaults + registered
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(imageView)
        addSubview(badgeLabel)
        addSubview(leftButton)
        addSubview(rightButton)
        addSubview(settingsButton)
        addSubview(quitButton)

        leftButton.target = self
        leftButton.action = #selector(previousMalangi)
        rightButton.target = self
        rightButton.action = #selector(nextMalangi)
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        quitButton.target = self
        quitButton.action = #selector(quitApp)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .malangiSettingsChanged,
            object: nil
        )

        updateMalangi(animated: false)
        updateHoverState()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        let imageSide: CGFloat = 164
        imageView.frame = NSRect(
            x: (bounds.width - imageSide) / 2,
            y: 58,
            width: imageSide,
            height: imageSide
        )

        let badgeWidth = min(bounds.width - 72, max(96, badgeLabel.preferredWidth + 24))
        badgeLabel.frame = NSRect(
            x: (bounds.width - badgeWidth) / 2,
            y: 26,
            width: badgeWidth,
            height: 24
        )

        leftButton.frame = NSRect(x: 6, y: 122, width: 34, height: 34)
        rightButton.frame = NSRect(x: bounds.width - 40, y: 122, width: 34, height: 34)
        quitButton.frame = NSRect(x: bounds.width - 42, y: bounds.height - 42, width: 28, height: 28)
        settingsButton.frame = NSRect(x: bounds.width - 72, y: bounds.height - 42, width: 28, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateImageHover(with: event)
        updateHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        setImageHovering(false)
        updateHoverState()
    }

    override func mouseMoved(with event: NSEvent) {
        updateImageHover(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if imageView.frame.contains(point) {
            imageView.playTapAnimation()
            soundPlayer.playRandomSound(for: resolvedMalangi(at: currentIndex))
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        updateImageHover(with: event)
    }

    private func updateHoverState() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            leftButton.animator().alphaValue = isHovering ? 1 : 0
            rightButton.animator().alphaValue = isHovering ? 1 : 0
            settingsButton.animator().alphaValue = isHovering ? 1 : 0
            quitButton.animator().alphaValue = isHovering ? 1 : 0
        }
    }

    @objc private func previousMalangi() {
        currentIndex = (currentIndex - 1 + malangis.count) % malangis.count
        updateMalangi(animated: true)
    }

    @objc private func nextMalangi() {
        currentIndex = (currentIndex + 1) % malangis.count
        updateMalangi(animated: true)
    }

    @objc private func handleSettingsChanged(_ notification: Notification) {
        if let remoteId = notification.userInfo?[MalangiNotificationKey.selectedRemoteId] as? String,
           let index = MalangiSettings.registrations.firstIndex(where: { $0.remoteId == remoteId }) {
            currentIndex = defaultOffset + index
        } else if let name = notification.userInfo?[MalangiNotificationKey.selectedName] as? String,
                  let index = malangis.firstIndex(where: { $0.name == name }) {
            currentIndex = index
        } else {
            currentIndex = max(0, malangis.count - 1)
        }
        updateMalangi(animated: true)
    }

    @objc private func showSettings() {
        SettingsPresenter.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func resolvedMalangi(at index: Int) -> Malangi {
        malangis[index]
    }

    private var defaultOffset: Int {
        let registeredNames = Set(MalangiSettings.registeredMalangis.map(\.name))
        return defaultMalangis.filter { !registeredNames.contains($0.name) }.count
    }

    private func updateImageHover(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setImageHovering(imageView.frame.contains(point))
    }

    private func setImageHovering(_ isHovering: Bool) {
        guard isImageHovering != isHovering else { return }
        isImageHovering = isHovering
        imageView.setHovered(isHovering)
    }

    private func updateMalangi(animated: Bool) {
        let malangi = resolvedMalangi(at: currentIndex)
        let updates = {
            self.imageView.malangi = malangi
            self.badgeLabel.stringValue = malangi.badge
            self.badgeLabel.toolTip = malangi.name
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                imageView.animator().alphaValue = 0.35
            } completionHandler: {
                updates()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    self.imageView.animator().alphaValue = 1
                }
            }
        } else {
            updates()
        }
    }
}

final class MalangiImageView: NSView {
    var malangi: Malangi? {
        didSet {
            needsDisplay = true
        }
    }
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow?.shadowOffset = NSSize(width: 0, height: -8)
        shadow?.shadowBlurRadius = 18
        toolTip = "Click to play sound"
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setHovered(_ isHovered: Bool) {
        self.isHovered = isHovered
        needsDisplay = true
    }

    func playTapAnimation() {
        let baseFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 0.72
            animator().frame = baseFrame.insetBy(dx: 5, dy: 5)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                self.animator().alphaValue = 1
                self.animator().frame = baseFrame
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let malangi else { return }

        if let imageName = malangi.imageName,
           let image = ResourceLocator.image(for: imageName) {
            image.draw(in: image.aspectFitRect(in: bounds))
            return
        }

        let blobRect = bounds.insetBy(dx: 12, dy: 10)
        let path = NSBezierPath(ovalIn: blobRect)
        malangi.primaryColor.setFill()
        path.fill()

        let shine = NSBezierPath(ovalIn: NSRect(
            x: blobRect.minX + 32,
            y: blobRect.maxY - 52,
            width: 42,
            height: 24
        ))
        malangi.secondaryColor.withAlphaComponent(0.78).setFill()
        shine.fill()

        drawEye(x: blobRect.midX - 34, y: blobRect.midY + 10)
        drawEye(x: blobRect.midX + 34, y: blobRect.midY + 10)
        drawMouth(in: blobRect)
    }

    private func drawEye(x: CGFloat, y: CGFloat) {
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 6, y: y - 7, width: 12, height: 14)).fill()
    }

    private func drawMouth(in rect: NSRect) {
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: rect.midX - 15, y: rect.midY - 18))
        mouth.curve(
            to: NSPoint(x: rect.midX + 15, y: rect.midY - 18),
            controlPoint1: NSPoint(x: rect.midX - 7, y: rect.midY - 34),
            controlPoint2: NSPoint(x: rect.midX + 7, y: rect.midY - 34)
        )
        mouth.lineWidth = 4
        mouth.lineCapStyle = .round
        NSColor(calibratedWhite: 0.18, alpha: 1).setStroke()
        mouth.stroke()
    }
}

final class BadgeLabel: NSView {
    var stringValue = "" {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }

    var preferredWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont
        ]
        return ceil((stringValue as NSString).size(withAttributes: attributes).width)
    }

    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
        capsule.fill()

        NSColor(calibratedWhite: 0, alpha: 0.08).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
            .paragraphStyle: paragraph
        ]

        let textRect = bounds.insetBy(dx: 10, dy: 0)
        let textHeight = ceil(Self.labelFont.boundingRectForFont.height)
        let centeredTextRect = NSRect(
            x: textRect.minX,
            y: bounds.midY - textHeight / 2 - 1,
            width: textRect.width,
            height: textHeight + 2
        )
        (stringValue as NSString).draw(in: centeredTextRect, withAttributes: attributes)
    }
}

final class ArrowButton: NSButton {
    enum Direction { case left, right }
    private let direction: Direction

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        title = ""
        bezelStyle = .shadowlessSquare
        isBordered = false
        focusRingType = .none
        alphaValue = 0
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        toolTip = direction == .left ? "이전 말랑이" : "다음 말랑이"
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 1, dy: 1)
        let circle = NSBezierPath(ovalIn: circleRect)
        NSColor(calibratedWhite: 1, alpha: isHighlighted ? 0.98 : 0.88).setFill()
        circle.fill()
        NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let chevron = NSBezierPath()
        let midX = bounds.midX, midY = bounds.midY
        let spread: CGFloat = 5.2, reach: CGFloat = 3.8
        if direction == .left {
            chevron.move(to: NSPoint(x: midX + reach, y: midY + spread))
            chevron.line(to: NSPoint(x: midX - reach, y: midY))
            chevron.line(to: NSPoint(x: midX + reach, y: midY - spread))
        } else {
            chevron.move(to: NSPoint(x: midX - reach, y: midY + spread))
            chevron.line(to: NSPoint(x: midX + reach, y: midY))
            chevron.line(to: NSPoint(x: midX - reach, y: midY - spread))
        }
        chevron.lineWidth = 2.0
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        NSColor(calibratedWhite: 0.12, alpha: 0.94).setStroke()
        chevron.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class OverlaySymbolButton: NSButton {
    private let tintColor: NSColor

    init(symbolName: String, toolTip: String, tintColor: NSColor = NSColor(calibratedWhite: 0.5, alpha: 1)) {
        self.tintColor = tintColor
        super.init(frame: .zero)
        title = ""
        bezelStyle = .shadowlessSquare
        isBordered = false
        focusRingType = .none
        alphaValue = 0
        wantsLayer = true
        layer?.shadowOpacity = 0
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)) {
            img.isTemplate = true
            image = img
        }
        imagePosition = .imageOnly
        contentTintColor = tintColor
        self.toolTip = toolTip
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { contentTintColor = tintColor.withAlphaComponent(isHighlighted ? 1 : 0.85) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

enum MalangiSettings {
    private static let imagePathKey = "malangi.imagePath"
    private static let soundPathsKey = "malangi.soundPaths"
    private static let registeredMalangisKey = "malangi.registeredMalangis"
    private static let remoteMalangisKey = "malangi.remoteMalangis"
    private static let hiddenDefaultsKey = "malangi.hiddenDefaults"
    private static let didMigrateLegacyKey = "malangi.didMigrateLegacy"

    static var registeredMalangis: [Malangi] {
        migrateLegacyRegistrationIfNeeded()
        return mergedRegistrations.map { $0.asMalangi() }
    }

    static var registrations: [StoredMalangi] {
        migrateLegacyRegistrationIfNeeded()
        return mergedRegistrations
    }

    static var supportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseURL.appendingPathComponent("Wazak", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    static func saveMalangi(name: String, editingIndex: Int?, image sourceURL: URL?, sounds sourceDrafts: [SoundDraft]?) throws -> StoredMalangi {
        var stored = storedMalangis
        let existing = editingIndex.flatMap { registrations.indices.contains($0) ? registrations[$0] : nil }
        let assetFolder = existing?.remoteId ?? UUID().uuidString
        let registrationDirectory = localRegistrationDirectory(for: existing, fallbackFolder: assetFolder)

        try FileManager.default.createDirectory(at: registrationDirectory, withIntermediateDirectories: true)

        let imagePath: String
        let imageFileName: String?
        if let sourceURL {
            let outputURL = registrationDirectory.appendingPathComponent("malangi.png")
            try BackgroundRemover.writeTransparentPNG(from: sourceURL, to: outputURL)
            imageFileName = sourceURL.lastPathComponent
            imagePath = outputURL.path
        } else if let existing {
            imagePath = existing.imagePath
            imageFileName = existing.imageFileName
        } else {
            throw NSError(domain: "Wazak", code: 5, userInfo: [NSLocalizedDescriptionKey: "새 말랑이를 등록하려면 사진이 필요해요."])
        }

        let soundPaths: [String]
        let soundFileNames: [String]
        if let sourceDrafts {
            let savedSounds = try saveSounds(sourceDrafts, in: registrationDirectory, assetFolder: assetFolder)
            soundPaths = savedSounds.paths
            soundFileNames = savedSounds.fileNames
        } else {
            soundPaths = existing?.soundPaths ?? []
            soundFileNames = existing?.soundFileNames ?? soundPaths.map { ResourceLocator.displayName(for: $0) }
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedMalangi = StoredMalangi(
            remoteId: existing?.remoteId,
            name: trimmedName.isEmpty ? "말랑이 \(stored.count + 1)" : trimmedName,
            imagePath: imagePath,
            imageFileName: imageFileName,
            soundPaths: soundPaths,
            soundFileNames: soundFileNames,
            marketplaceId: existing?.marketplaceId
        )

        if let localIndex = localIndex(for: existing, in: stored) {
            stored[localIndex] = storedMalangi
        } else {
            stored.append(storedMalangi)
        }

        saveStoredMalangis(stored)
        notifyChanged(selecting: storedMalangi)
        return storedMalangi
    }

    static func deleteMalangi(at index: Int) throws {
        let allRegistrations = registrations
        guard allRegistrations.indices.contains(index) else { return }

        let removed = allRegistrations[index]

        if removed.isDefault {
            // 기본 말랑이: 서버 행 유지, 로컬에서 숨기기만 함
            guard let remoteId = removed.remoteId else { return }
            var hidden = hiddenDefaults
            hidden.insert(remoteId)
            saveHiddenDefaults(hidden)
            notifyChanged()
        } else {
            // 개인/마켓 다운로드 말랑이: 로컬 파일 + UserDefaults에서 완전 삭제
            var stored = storedMalangis
            if let localIndex = localIndex(for: removed, in: stored) {
                stored.remove(at: localIndex)
            }
            if ResourceLocator.isLocalFileReference(removed.imagePath) {
                let directory = URL(fileURLWithPath: removed.imagePath).deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: directory.path) {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            saveStoredMalangis(stored)
            refreshRemoteRegistrations()
            notifyChanged()
        }
    }

    static func addMarketplaceMalangi(_ marketplaceMalangi: MarketplaceMalangi) {
        var stored = storedMalangis
        let alreadyExists = stored.contains {
            $0.imagePath == marketplaceMalangi.imageURL || $0.name == marketplaceMalangi.name
        }
        let downloaded = StoredMalangi(
            name: marketplaceMalangi.name,
            imagePath: marketplaceMalangi.imageURL,
            imageFileName: marketplaceMalangi.imageFileName,
            soundPaths: marketplaceMalangi.soundURLs,
            soundFileNames: marketplaceMalangi.soundFileNames
        )

        if !alreadyExists {
            stored.append(downloaded)
            saveStoredMalangis(stored)
        }

        notifyChanged(selecting: downloaded)
    }

    static func refreshRemoteRegistrations() {
        DispatchQueue.global(qos: .utility).async {
            guard let remoteMalangis = try? SupabaseMalangiClient.shared.fetchAll() else {
                return
            }

            saveRemoteMalangis(remoteMalangis)
            notifyChanged()
        }
    }

    /// 로컬에 저장된 말랑이의 marketplaceId를 갱신합니다 (업로드/재업로드 후 호출).
    static func setMarketplaceId(_ id: String?, for malangi: StoredMalangi) {
        var stored = storedMalangis
        var didUpdate = false
        for idx in stored.indices where sameLocalMalangi(stored[idx], malangi) {
            let existing = stored[idx]
            stored[idx] = StoredMalangi(
                remoteId: existing.remoteId,
                name: existing.name,
                imagePath: existing.imagePath,
                imageFileName: existing.imageFileName,
                soundPaths: existing.soundPaths,
                soundFileNames: existing.soundFileNames,
                marketplaceId: id
            )
            didUpdate = true
        }
        if didUpdate {
            saveStoredMalangis(stored)
        }
    }

    private static func saveSounds(_ sourceDrafts: [SoundDraft], in registrationDirectory: URL) throws -> (paths: [String], fileNames: [String]) {
        try saveSounds(sourceDrafts, in: registrationDirectory, assetFolder: UUID().uuidString)
    }

    private static func saveSounds(_ sourceDrafts: [SoundDraft], in registrationDirectory: URL, assetFolder: String) throws -> (paths: [String], fileNames: [String]) {
        let soundDirectory = registrationDirectory.appendingPathComponent("Sounds", isDirectory: true)
        let temporaryDirectory = registrationDirectory
            .appendingPathComponent("TempSounds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let remoteDrafts = sourceDrafts.filter { !$0.url.isFileURL }
        let localDrafts = sourceDrafts.filter { $0.url.isFileURL }
        let stagedDrafts = try localDrafts.enumerated().map { index, draft in
            let fileName = storageSafeFileName(draft.displayName, fallbackExtension: draft.url.pathExtension, index: index)
            let stagedURL = temporaryDirectory.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: draft.url, to: stagedURL)
            return SoundDraft(url: stagedURL, displayName: draft.displayName)
        }

        if FileManager.default.fileExists(atPath: soundDirectory.path) {
            try FileManager.default.removeItem(at: soundDirectory)
        }
        try FileManager.default.createDirectory(at: soundDirectory, withIntermediateDirectories: true)

        let savedPaths = try stagedDrafts.map { draft in
            let stagedURL = draft.url
            let fileName = stagedURL.lastPathComponent
            let destinationURL = soundDirectory.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
            return destinationURL.path
        }

        try? FileManager.default.removeItem(at: temporaryDirectory)
        return (
            paths: remoteDrafts.map { $0.url.absoluteString } + savedPaths,
            fileNames: remoteDrafts.map(\.displayName) + localDrafts.map(\.displayName)
        )
    }

    private static func storageSafeFileName(_ displayName: String, fallbackExtension: String, index: Int) -> String {
        let extensionName = sanitizedExtension(fallbackExtension, defaultValue: "mp3")
        return "sound-\(index + 1)-\(UUID().uuidString).\(extensionName)"
    }

    private static func storageSafeImageFileName() -> String {
        "image-\(UUID().uuidString).png"
    }

    private static func sanitizedExtension(_ extensionName: String, defaultValue: String) -> String {
        let allowed = extensionName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return allowed.isEmpty ? defaultValue : String(allowed)
    }

    private static func localRegistrationDirectory(for existing: StoredMalangi?, fallbackFolder: String) -> URL {
        if let existing,
           ResourceLocator.isLocalFileReference(existing.imagePath) {
            return URL(fileURLWithPath: existing.imagePath).deletingLastPathComponent()
        }

        return supportDirectory
            .appendingPathComponent("Registered", isDirectory: true)
            .appendingPathComponent(fallbackFolder, isDirectory: true)
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "m4a":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "aif", "aiff":
            return "audio/aiff"
        default:
            return "audio/mpeg"
        }
    }

    private static var storedMalangis: [StoredMalangi] {
        guard let data = UserDefaults.standard.data(forKey: registeredMalangisKey) else {
            return []
        }

        let decoded = (try? JSONDecoder().decode([StoredMalangi].self, from: data)) ?? []
        let normalized = normalizedMarketplaceIds(decoded)
        if normalized.map(\.marketplaceId) != decoded.map(\.marketplaceId) {
            saveStoredMalangis(normalized)
        }
        return normalized
    }

    private static var remoteMalangis: [StoredMalangi] {
        guard let data = UserDefaults.standard.data(forKey: remoteMalangisKey) else {
            return []
        }

        return (try? JSONDecoder().decode([StoredMalangi].self, from: data)) ?? []
    }

    private static var mergedRegistrations: [StoredMalangi] {
        let local = storedMalangis
        let localRemoteIds = Set(local.compactMap(\.remoteId))
        let localImagePaths = Set(local.map(\.imagePath))
        let hidden = hiddenDefaults

        let remoteOnly = remoteMalangis.filter { remote in
            // 숨겨진 기본 말랑이는 목록에서 제외
            if let remoteId = remote.remoteId, hidden.contains(remoteId) { return false }
            if let remoteId = remote.remoteId {
                return !localRemoteIds.contains(remoteId)
            }
            return !localImagePaths.contains(remote.imagePath)
        }

        // local + remote-only 합친 뒤, remoteId != nil 이면 기본 말랑이로 마킹
        // 숨겨진 local(remoteId 있음) 항목도 제거
        let combined = (local.filter { m in
            guard let rid = m.remoteId else { return true }
            return !hidden.contains(rid)
        }) + remoteOnly

        return combined.map { m -> StoredMalangi in
            var x = m
            x.isDefault = (m.remoteId != nil)
            return x
        }
    }

    private static func localIndex(for malangi: StoredMalangi?, in stored: [StoredMalangi]) -> Int? {
        guard let malangi else { return nil }
        if let remoteId = malangi.remoteId,
           let index = stored.firstIndex(where: { $0.remoteId == remoteId }) {
            return index
        }

        return stored.firstIndex { $0.imagePath == malangi.imagePath }
    }

    private static func sameLocalMalangi(_ lhs: StoredMalangi, _ rhs: StoredMalangi) -> Bool {
        if lhs.imagePath == rhs.imagePath { return true }
        return lhs.name == rhs.name && lhs.imageFileName == rhs.imageFileName
    }

    private static func normalizedMarketplaceIds(_ malangis: [StoredMalangi]) -> [StoredMalangi] {
        malangis.map { malangi in
            guard malangi.marketplaceId == nil,
                  let inheritedId = malangis.first(where: {
                      $0.marketplaceId != nil && sameLocalMalangi($0, malangi)
                  })?.marketplaceId
            else {
                return malangi
            }

            return StoredMalangi(
                remoteId: malangi.remoteId,
                name: malangi.name,
                imagePath: malangi.imagePath,
                imageFileName: malangi.imageFileName,
                soundPaths: malangi.soundPaths,
                soundFileNames: malangi.soundFileNames,
                marketplaceId: inheritedId
            )
        }
    }

    private static func saveStoredMalangis(_ malangis: [StoredMalangi]) {
        let data = try? JSONEncoder().encode(malangis)
        UserDefaults.standard.set(data, forKey: registeredMalangisKey)
    }

    private static func saveRemoteMalangis(_ malangis: [StoredMalangi]) {
        let data = try? JSONEncoder().encode(malangis)
        UserDefaults.standard.set(data, forKey: remoteMalangisKey)
    }

    static func updateRemoteCatalog(_ malangis: [StoredMalangi]) {
        saveRemoteMalangis(malangis)
    }

    private static var hiddenDefaults: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: hiddenDefaultsKey) ?? []
        return Set(arr)
    }

    private static func saveHiddenDefaults(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: hiddenDefaultsKey)
    }

    /// 숨김 해제: 마켓플레이스에서 기본 말랑이를 다시 받을 때 호출.
    static func unhideDefault(remoteId: String) {
        var hidden = hiddenDefaults
        hidden.remove(remoteId)
        saveHiddenDefaults(hidden)
        notifyChanged()
    }

    /// 마켓플레이스 탭에서 표시할 기본 말랑이 카탈로그 (malangis 테이블 전체).
    static var defaultCatalog: [StoredMalangi] {
        return remoteMalangis.map { remote -> StoredMalangi in
            var m = remote
            m.isDefault = true
            return m
        }
    }

    private static func migrateLegacyRegistrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didMigrateLegacyKey) else {
            return
        }

        UserDefaults.standard.set(true, forKey: didMigrateLegacyKey)

        guard let imagePath = UserDefaults.standard.string(forKey: imagePathKey) else {
            return
        }

        let soundPaths = UserDefaults.standard.stringArray(forKey: soundPathsKey) ?? []
        var stored = storedMalangis
        let alreadyExists = stored.contains { $0.imagePath == imagePath }

        if !alreadyExists {
            stored.append(StoredMalangi(name: "등록 말랑이", imagePath: imagePath, soundPaths: soundPaths))
            saveStoredMalangis(stored)
        }
    }

    private static func notifyChanged(selecting malangi: StoredMalangi? = nil) {
        var userInfo: [String: Any] = [:]
        if let remoteId = malangi?.remoteId {
            userInfo[MalangiNotificationKey.selectedRemoteId] = remoteId
        }
        if let name = malangi?.name {
            userInfo[MalangiNotificationKey.selectedName] = name
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .malangiSettingsChanged,
                object: nil,
                userInfo: userInfo.isEmpty ? nil : userInfo
            )
        }
    }
}

final class SettingsPresenter {
    static let shared = SettingsPresenter()
    private var settingsWindow: SettingsWindow?

    private init() {}

    func show() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
            settingsWindow?.isReleasedWhenClosed = false
        }

        settingsWindow?.resetForPresentation()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsWindow: NSWindow {
    let viewModel = SettingsViewModel()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Wazak 설정"
        center()

        let rootView = SettingsRootView(viewModel: viewModel)
        contentViewController = NSHostingController(rootView: rootView)

        viewModel.onRequestClose = { [weak self] in self?.close() }
    }

    func resetForPresentation() {
        viewModel.resetForPresentation()
    }
}

final class SoundPlayer {
    private var audioPlayer: AVAudioPlayer?

    func playRandomSound(for malangi: Malangi) {
        if let soundName = malangi.soundNames.randomElement() {
            playSound(named: soundName)
            return
        }

        let data = makeToneData(frequency: malangi.soundFrequency, duration: 0.22)
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }

    /// 원격 URL 포함 사운드를 백그라운드에서 미리 재생합니다 (마켓 리스트 미리듣기용).
    func preview(_ soundName: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.playSound(named: soundName)
        }
    }

    private func playSound(named soundName: String) {
        guard let url = ResourceLocator.url(for: soundName) else {
            return
        }

        if url.isFileURL {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
        } else if let data = try? Data(contentsOf: url) {
            audioPlayer = try? AVAudioPlayer(data: data)
        }
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }

    private func makeToneData(frequency: Double, duration: Double) -> Data {
        let sampleRate = 44_100
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data()

        for index in 0..<sampleCount {
            let progress = Double(index) / Double(sampleCount)
            let envelope = sin(.pi * progress)
            let sample = sin(2 * .pi * frequency * Double(index) / Double(sampleRate)) * envelope
            var value = Int16(sample * 18_000)
            pcm.append(Data(bytes: &value, count: MemoryLayout<Int16>.size))
        }

        return wavData(fromPCM: pcm, sampleRate: sampleRate)
    }

    private func wavData(fromPCM pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let blockAlign: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let chunkSize = UInt32(36 + pcm.count)
        let subchunk2Size = UInt32(pcm.count)

        data.appendASCII("RIFF")
        data.appendLE(chunkSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.appendASCII("data")
        data.appendLE(subchunk2Size)
        data.append(pcm)
        return data
    }
}

private extension NSImage {
    func aspectFitRect(in bounds: NSRect) -> NSRect {
        let imageSize = size
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale

        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}

enum BackgroundRemover {
    static func writeTransparentPNG(from inputURL: URL, to outputURL: URL) throws {
        guard let image = NSImage(contentsOf: inputURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "Wazak", code: 1, userInfo: [NSLocalizedDescriptionKey: "이미지를 읽을 수 없어요."])
        }

        if #available(macOS 14.0, *), writeVisionForegroundPNG(from: cgImage, to: outputURL) {
            return
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "Wazak", code: 2, userInfo: [NSLocalizedDescriptionKey: "이미지를 처리할 수 없어요."])
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        removeConnectedLightBackground(from: &pixels, width: width, height: height, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel)

        guard let outputContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let outputImage = outputContext.makeImage(),
           let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Wazak", code: 3, userInfo: [NSLocalizedDescriptionKey: "투명 PNG를 만들 수 없어요."])
        }

        CGImageDestinationAddImage(destination, outputImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "Wazak", code: 4, userInfo: [NSLocalizedDescriptionKey: "파일을 저장할 수 없어요."])
        }
    }

    @available(macOS 14.0, *)
    private static func writeVisionForegroundPNG(from cgImage: CGImage, to outputURL: URL) -> Bool {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return false
            }

            let selectedInstances = try bestForegroundInstances(from: observation, handler: handler)
            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: selectedInstances,
                from: handler
            )

            let originalImage = CIImage(cgImage: cgImage)
            let maskImage = CIImage(cvPixelBuffer: maskBuffer).cropped(to: originalImage.extent)
            let transparentBackground = CIImage(color: .clear).cropped(to: originalImage.extent)

            guard let filter = CIFilter(name: "CIBlendWithAlphaMask") else {
                return false
            }

            filter.setValue(originalImage, forKey: kCIInputImageKey)
            filter.setValue(transparentBackground, forKey: kCIInputBackgroundImageKey)
            filter.setValue(maskImage, forKey: kCIInputMaskImageKey)

            guard let outputImage = filter.outputImage else {
                return false
            }

            let context = CIContext()
            guard let outputCGImage = context.createCGImage(outputImage, from: originalImage.extent),
                  let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return false
            }

            CGImageDestinationAddImage(destination, outputCGImage, nil)
            return CGImageDestinationFinalize(destination)
        } catch {
            return false
        }
    }

    @available(macOS 14.0, *)
    private static func bestForegroundInstances(
        from observation: VNInstanceMaskObservation,
        handler: VNImageRequestHandler
    ) throws -> IndexSet {
        let instances = observation.allInstances
        guard instances.count > 1 else {
            return instances
        }

        var bestInstances = instances
        var bestScore = -Double.infinity

        for instance in instances {
            let instanceSet = IndexSet(integer: instance)
            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: instanceSet, from: handler)
            let score = scoreMask(maskBuffer)

            if score > bestScore {
                bestScore = score
                bestInstances = instanceSet
            }
        }

        return bestInstances
    }

    private static func scoreMask(_ maskBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return -Double.infinity
        }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let format = CVPixelBufferGetPixelFormatType(maskBuffer)
        var count = 0
        var sumX = 0.0
        var sumY = 0.0

        if format == kCVPixelFormatType_OneComponent8 {
            for y in 0..<height {
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width where row[x] > 24 {
                    count += 1
                    sumX += Double(x)
                    sumY += Double(y)
                }
            }
        } else if format == kCVPixelFormatType_OneComponent32Float {
            let floatsPerRow = bytesPerRow / MemoryLayout<Float>.size
            for y in 0..<height {
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                for x in 0..<width where row[x] > 0.1 {
                    count += 1
                    sumX += Double(x)
                    sumY += Double(y)
                }
            }

            _ = floatsPerRow
        }

        guard count > 0 else {
            return -Double.infinity
        }

        let centerX = sumX / Double(count * max(width - 1, 1))
        let centerY = sumY / Double(count * max(height - 1, 1))
        let targetX = 0.5
        let targetY = 0.68
        let distance = hypot(centerX - targetX, centerY - targetY)
        let centerBonus = max(0.0, 1.0 - distance)
        let lowerFrameBonus = 0.75 + centerY * 0.5

        return Double(count) * centerBonus * lowerFrameBonus
    }

    private static func removeConnectedLightBackground(
        from pixels: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int
    ) {
        func offset(_ x: Int, _ y: Int) -> Int {
            y * bytesPerRow + x * bytesPerPixel
        }

        func isBackground(_ index: Int, threshold: Double) -> Bool {
            let r = Double(pixels[index])
            let g = Double(pixels[index + 1])
            let b = Double(pixels[index + 2])
            let dr = r - 246
            let dg = g - 243
            let db = b - 238
            return sqrt(dr * dr + dg * dg + db * db) < threshold
        }

        var background = [Bool](repeating: false, count: width * height)
        var queue: [(Int, Int)] = []
        var head = 0

        func enqueue(_ x: Int, _ y: Int, threshold: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let maskIndex = y * width + x
            guard !background[maskIndex], isBackground(offset(x, y), threshold: threshold) else { return }
            background[maskIndex] = true
            queue.append((x, y))
        }

        for x in 0..<width {
            enqueue(x, 0, threshold: 46)
            enqueue(x, height - 1, threshold: 46)
        }

        for y in 0..<height {
            enqueue(0, y, threshold: 46)
            enqueue(width - 1, y, threshold: 46)
        }

        while head < queue.count {
            let (x, y) = queue[head]
            head += 1
            enqueue(x + 1, y, threshold: 52)
            enqueue(x - 1, y, threshold: 52)
            enqueue(x, y + 1, threshold: 52)
            enqueue(x, y - 1, threshold: 52)
        }

        let featherRadius = 8
        var alpha = [UInt8](repeating: 255, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let maskIndex = y * width + x
                if background[maskIndex] {
                    alpha[maskIndex] = 0
                    continue
                }

                var nearestBackground = featherRadius + 1
                for dy in -featherRadius...featherRadius {
                    for dx in -featherRadius...featherRadius {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        if background[ny * width + nx] {
                            let distance = Int(sqrt(Double(dx * dx + dy * dy)))
                            nearestBackground = min(nearestBackground, distance)
                        }
                    }
                }

                if nearestBackground <= featherRadius {
                    let value = max(0.0, min(1.0, Double(nearestBackground) / Double(featherRadius)))
                    alpha[maskIndex] = UInt8(value * 255)
                }
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                pixels[offset(x, y) + 3] = alpha[y * width + x]
            }
        }
    }
}

enum ResourceLocator {
    static func image(for reference: String) -> NSImage? {
        guard let url = url(for: reference) else { return nil }
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    static func url(for filename: String) -> URL? {
        if let remoteURL = URL(string: filename),
           ["http", "https"].contains(remoteURL.scheme?.lowercased()) {
            return remoteURL
        }

        let filenameURL = URL(fileURLWithPath: filename)
        if filename.hasPrefix("/"), FileManager.default.fileExists(atPath: filenameURL.path) {
            return filenameURL
        }

        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil) {
            return bundleURL
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        return nil
    }

    static func isLocalFileReference(_ value: String) -> Bool {
        if let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return false
        }

        return value.hasPrefix("/")
    }

    static func displayName(for value: String) -> String {
        if let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        }

        return URL(fileURLWithPath: value).lastPathComponent
    }

    static func displayName(for url: URL) -> String {
        if ["http", "https"].contains(url.scheme?.lowercased()) {
            return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        }

        return url.lastPathComponent
    }
}

// MARK: - OAuth Helpers

/// PKCE(Proof Key for Code Exchange) — code_verifier + code_challenge 생성
struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// ASWebAuthenticationSession을 감싸 wazak:// 스킴 콜백을 받아 반환하는 코디네이터.
/// 포트 점유·생명주기 문제가 없고, 취소 시 즉시 정리됩니다.
/// 모든 메서드는 메인스레드(UI)에서 호출됩니다.
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// 메인스레드에서 호출해야 합니다.
    func start(url: URL, scheme: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
            DispatchQueue.main.async {
                if let callbackURL {
                    completion(.success(callbackURL))
                } else {
                    completion(.failure(error ?? NSError(domain: "Wazak", code: 34,
                        userInfo: [NSLocalizedDescriptionKey: "로그인 창에서 응답이 없어요."])))
                }
            }
        }
        s.presentationContextProvider = self
        // false = Safari 쿠키 공유(계정 선택 편리). 구글 에러 재발 시 true로 시도.
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    func cancel() {
        session?.cancel()
        session = nil
    }

    // ASWebAuthenticationPresentationContextProviding — 항상 메인스레드에서 호출됨
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? ASPresentationAnchor()
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii) ?? Data())
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<T>.size))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
