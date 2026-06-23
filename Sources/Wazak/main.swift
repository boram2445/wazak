import AppKit
import AVFoundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers
import Vision

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlayWindow: OverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Wazak is running. Look near the center of your screen, or click the menu bar item labeled '와'.")
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

    private enum CodingKeys: String, CodingKey {
        case remoteId
        case name
        case imagePath
        case imageFileName
        case soundPaths
        case soundFileNames
    }

    init(remoteId: String? = nil, name: String, imagePath: String, imageFileName: String? = nil, soundPaths: [String], soundFileNames: [String]? = nil) {
        self.remoteId = remoteId
        self.name = name
        self.imagePath = imagePath
        self.imageFileName = imageFileName
        self.soundPaths = soundPaths
        self.soundFileNames = soundFileNames ?? soundPaths.map { ResourceLocator.displayName(for: $0) }
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

struct SupabaseUser: Codable {
    let id: String
    let email: String?
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
    let name: String
    let imageURL: String
    let imageFileName: String?
    let soundURLs: [String]
    let soundFileNames: [String]
    let isPublic: Bool

    private enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case ownerEmail = "owner_email"
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

    private var isConfigured: Bool {
        baseURL != nil && publishableKey?.isEmpty == false
    }

    var canSync: Bool {
        isConfigured
    }

    var authSession: SupabaseAuthSession? {
        guard let data = UserDefaults.standard.data(forKey: authSessionKey) else { return nil }
        return try? decoder.decode(SupabaseAuthSession.self, from: data)
    }

    private init(session: URLSession = .shared) {
        let environment = ProcessInfo.processInfo.environment
        let urlString = environment["SUPABASE_URL"] ?? ""
        let key = environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? environment["SUPABASE_ANON_KEY"]
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

    func signIn(email: String, password: String) throws -> SupabaseAuthSession {
        let payload = ["email": email, "password": password]
        var request = try makeRequest(path: "/auth/v1/token", queryItems: [
            URLQueryItem(name: "grant_type", value: "password")
        ])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let session: SupabaseAuthSession = try perform(request)
        saveAuthSession(session)
        return session
    }

    func signUp(email: String, password: String) throws -> SupabaseAuthSession {
        let payload = ["email": email, "password": password]
        var request = try makeRequest(path: "/auth/v1/signup")
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let session: SupabaseAuthSession = try perform(request)
        saveAuthSession(session)
        return session
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: authSessionKey)
    }

    func fetchMarketplace() throws -> [MarketplaceMalangi] {
        guard isConfigured else { return [] }
        var request = try makeRequest(path: "/rest/v1/marketplace_malangis", queryItems: [
            URLQueryItem(name: "select", value: "id,owner_id,owner_email,name,image_url,image_file_name,sound_urls,sound_file_names,downloads_count"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ])
        request.httpMethod = "GET"
        return try perform(request)
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
            name: malangi.name,
            imageURL: imageURL,
            imageFileName: malangi.imageFileName,
            soundURLs: soundURLs,
            soundFileNames: malangi.soundFileNames,
            isPublic: true
        )

        var request = try makeRequest(path: "/rest/v1/marketplace_malangis", queryItems: [
            URLQueryItem(name: "select", value: "id,owner_id,owner_email,name,image_url,image_file_name,sound_urls,sound_file_names,downloads_count")
        ], accessToken: session.accessToken)
        request.httpMethod = "POST"
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
    private let settingsButton = SettingsButton(frame: .zero)
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

        leftButton.target = self
        leftButton.action = #selector(previousMalangi)
        rightButton.target = self
        rightButton.action = #selector(nextMalangi)
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)

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
        settingsButton.frame = NSRect(x: bounds.width - 48, y: bounds.height - 44, width: 32, height: 32)
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
    enum Direction {
        case left
        case right
    }

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
        toolTip = direction == .left ? "Previous Malangi" : "Next Malangi"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 1, dy: 1)
        let circle = NSBezierPath(ovalIn: circleRect)
        let fillAlpha: CGFloat = isHighlighted ? 0.98 : 0.88

        NSColor(calibratedWhite: 1, alpha: fillAlpha).setFill()
        circle.fill()

        NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let chevron = NSBezierPath()
        let midX = bounds.midX
        let midY = bounds.midY
        let spread: CGFloat = 5.2
        let reach: CGFloat = 3.8

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
}

final class SettingsButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        bezelStyle = .shadowlessSquare
        isBordered = false
        focusRingType = .none
        alphaValue = 0
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        toolTip = "Settings"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawGear(in: bounds.insetBy(dx: 7, dy: 7))
    }

    private func drawGear(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        let teeth = 8
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.72

        for index in 0..<(teeth * 2) {
            let angle = (Double(index) / Double(teeth * 2)) * Double.pi * 2 - Double.pi / 2
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = NSPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        path.close()
        NSColor(calibratedWhite: isHighlighted ? 0.32 : 0.48, alpha: 0.95).setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum MalangiSettings {
    private static let imagePathKey = "malangi.imagePath"
    private static let soundPathsKey = "malangi.soundPaths"
    private static let registeredMalangisKey = "malangi.registeredMalangis"
    private static let remoteMalangisKey = "malangi.remoteMalangis"
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

        let storageClient = SupabaseMalangiClient.shared
        let imagePath: String
        let imageFileName: String?
        if let sourceURL {
            let outputURL = registrationDirectory.appendingPathComponent("malangi.png")
            try BackgroundRemover.writeTransparentPNG(from: sourceURL, to: outputURL)
            imageFileName = sourceURL.lastPathComponent
            if storageClient.canSync {
                imagePath = try storageClient.uploadAsset(
                    fileURL: outputURL,
                    objectPath: "malangis/\(assetFolder)/\(storageSafeImageFileName())",
                    contentType: "image/png"
                )
            } else {
                imagePath = outputURL.path
            }
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
        var storedMalangi = StoredMalangi(
            remoteId: existing?.remoteId,
            name: trimmedName.isEmpty ? "말랑이 \(stored.count + 1)" : trimmedName,
            imagePath: imagePath,
            imageFileName: imageFileName,
            soundPaths: soundPaths,
            soundFileNames: soundFileNames
        )

        if let remoteMalangi = try? SupabaseMalangiClient.shared.upsert(storedMalangi) {
            storedMalangi = remoteMalangi
        }

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
        var stored = storedMalangis
        let allRegistrations = registrations
        guard allRegistrations.indices.contains(index) else { return }

        let removed = allRegistrations[index]
        if let remoteId = removed.remoteId {
            try? SupabaseMalangiClient.shared.delete(id: remoteId)
        }

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

        let storageClient = SupabaseMalangiClient.shared
        let savedPaths = try stagedDrafts.map { draft in
            let stagedURL = draft.url
            let fileName = stagedURL.lastPathComponent
            let destinationURL = soundDirectory.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
            if storageClient.canSync {
                return try storageClient.uploadAsset(
                    fileURL: destinationURL,
                    objectPath: "malangis/\(assetFolder)/sounds/\(fileName)",
                    contentType: contentType(for: destinationURL)
                )
            }
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

        return (try? JSONDecoder().decode([StoredMalangi].self, from: data)) ?? []
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
        let remoteOnly = remoteMalangis.filter { remote in
            if let remoteId = remote.remoteId {
                return !localRemoteIds.contains(remoteId)
            }
            return !localImagePaths.contains(remote.imagePath)
        }

        return local + remoteOnly
    }

    private static func localIndex(for malangi: StoredMalangi?, in stored: [StoredMalangi]) -> Int? {
        guard let malangi else { return nil }
        if let remoteId = malangi.remoteId,
           let index = stored.firstIndex(where: { $0.remoteId == remoteId }) {
            return index
        }

        return stored.firstIndex { $0.imagePath == malangi.imagePath }
    }

    private static func saveStoredMalangis(_ malangis: [StoredMalangi]) {
        let data = try? JSONEncoder().encode(malangis)
        UserDefaults.standard.set(data, forKey: registeredMalangisKey)
    }

    private static func saveRemoteMalangis(_ malangis: [StoredMalangi]) {
        let data = try? JSONEncoder().encode(malangis)
        UserDefaults.standard.set(data, forKey: remoteMalangisKey)
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

        (settingsWindow?.contentView as? SettingsView)?.resetForPresentation()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsWindow: NSWindow {
    init() {
        let view = SettingsView(frame: NSRect(x: 0, y: 0, width: 640, height: 430))
        super.init(
            contentRect: view.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Wazak Settings"
        center()
        contentView = view
    }
}

final class SettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let titleLabel = NSTextField(labelWithString: "말랑이 등록하기")
    private let modeControl = NSSegmentedControl(labels: ["내 말랑이", "마켓플레이스"], trackingMode: .selectOne, target: nil, action: nil)
    private let tableView = NSTableView(frame: .zero)
    private let soundTableView = NSTableView(frame: .zero)
    private let marketplaceTableView = NSTableView(frame: .zero)
    private let marketplacePanel = NSView(frame: .zero)
    private let authEmailField = NSTextField(string: "")
    private let authPasswordField = NSSecureTextField(string: "")
    private let authStatusLabel = NSTextField(labelWithString: "")
    private let marketplaceStatusLabel = NSTextField(labelWithString: "")
    private let uploadMarketplaceButton = NSButton(title: "마켓플레이스에 올리기", target: nil, action: nil)
    private let downloadMarketplaceButton = NSButton(title: "다운로드", target: nil, action: nil)
    private let refreshMarketplaceButton = NSButton(title: "새로고침", target: nil, action: nil)
    private let signInButton = NSButton(title: "로그인", target: nil, action: nil)
    private let signUpButton = NSButton(title: "가입", target: nil, action: nil)
    private let signOutButton = NSButton(title: "로그아웃", target: nil, action: nil)
    private let nameField = NSTextField(string: "")
    private let imageStatusLabel = NSTextField(labelWithString: "")
    private let imagePreview = NSImageView(frame: .zero)
    private let soundStatusLabel = NSTextField(labelWithString: "")
    private let confirmButton = NSButton(title: "확인", target: nil, action: nil)
    private let deleteMalangiButton = NSButton(title: "삭제", target: nil, action: nil)
    private let deleteSoundButton = NSButton(title: "사운드 삭제", target: nil, action: nil)
    private let spinner = NSProgressIndicator(frame: .zero)
    private var registrations: [StoredMalangi] = []
    private var marketplaceMalangis: [MarketplaceMalangi] = []
    private var localContentViews: [NSView] = []
    private var selectedIndex: Int?
    private var selectedMarketplaceIndex: Int?
    private var pendingImageURL: URL?
    private var soundDrafts: [SoundDraft] = []
    private var isSaving = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildUI()
        refreshStatus()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildUI() {
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.frame = NSRect(x: 24, y: 382, width: 260, height: 24)
        addSubview(titleLabel)

        let listLabel = NSTextField(labelWithString: "등록된 말랑이")
        listLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        listLabel.textColor = .secondaryLabelColor
        listLabel.frame = NSRect(x: 24, y: 350, width: 160, height: 18)
        addSubview(listLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 180
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 30
        tableView.allowsEmptySelection = true
        tableView.target = self
        tableView.action = #selector(selectRegistration)

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 76, width: 190, height: 268))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        addSubview(scrollView)

        let newButton = NSButton(title: "새 말랑이", target: self, action: #selector(newRegistration))
        newButton.bezelStyle = .rounded
        newButton.frame = NSRect(x: 24, y: 28, width: 92, height: 30)
        addSubview(newButton)

        deleteMalangiButton.target = self
        deleteMalangiButton.action = #selector(deleteRegistration)
        deleteMalangiButton.bezelStyle = .rounded
        deleteMalangiButton.frame = NSRect(x: 124, y: 28, width: 72, height: 30)
        addSubview(deleteMalangiButton)

        let nameLabel = NSTextField(labelWithString: "이름")
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.frame = NSRect(x: 250, y: 350, width: 180, height: 18)
        addSubview(nameLabel)

        nameField.placeholderString = "말랑이 이름"
        nameField.frame = NSRect(x: 250, y: 320, width: 340, height: 28)
        addSubview(nameField)

        let imageButton = NSButton(title: "말랑이 사진 등록", target: self, action: #selector(selectImage))
        imageButton.bezelStyle = .rounded
        imageButton.frame = NSRect(x: 250, y: 270, width: 150, height: 32)
        addSubview(imageButton)

        imageStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        imageStatusLabel.textColor = .secondaryLabelColor
        imageStatusLabel.lineBreakMode = .byTruncatingMiddle
        imageStatusLabel.frame = NSRect(x: 412, y: 282, width: 92, height: 20)
        addSubview(imageStatusLabel)

        imagePreview.imageScaling = .scaleProportionallyUpOrDown
        imagePreview.imageAlignment = .alignCenter
        imagePreview.imageFrameStyle = .grayBezel
        imagePreview.frame = NSRect(x: 512, y: 258, width: 78, height: 54)
        addSubview(imagePreview)

        let soundButton = NSButton(title: "사운드 여러 개 등록", target: self, action: #selector(selectSounds))
        soundButton.bezelStyle = .rounded
        soundButton.frame = NSRect(x: 250, y: 220, width: 150, height: 32)
        addSubview(soundButton)

        soundStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        soundStatusLabel.textColor = .secondaryLabelColor
        soundStatusLabel.lineBreakMode = .byTruncatingTail
        soundStatusLabel.frame = NSRect(x: 412, y: 225, width: 178, height: 20)
        addSubview(soundStatusLabel)

        let soundListLabel = NSTextField(labelWithString: "등록된 사운드")
        soundListLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        soundListLabel.textColor = .secondaryLabelColor
        soundListLabel.frame = NSRect(x: 250, y: 188, width: 180, height: 18)
        addSubview(soundListLabel)

        let soundColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sound"))
        soundColumn.width = 330
        soundTableView.addTableColumn(soundColumn)
        soundTableView.headerView = nil
        soundTableView.delegate = self
        soundTableView.dataSource = self
        soundTableView.rowHeight = 26
        soundTableView.allowsEmptySelection = true
        soundTableView.target = self
        soundTableView.action = #selector(selectSound)

        let soundScrollView = NSScrollView(frame: NSRect(x: 250, y: 76, width: 340, height: 108))
        soundScrollView.borderType = .bezelBorder
        soundScrollView.hasVerticalScroller = true
        soundScrollView.documentView = soundTableView
        addSubview(soundScrollView)

        deleteSoundButton.target = self
        deleteSoundButton.action = #selector(deleteSelectedSound)
        deleteSoundButton.bezelStyle = .rounded
        deleteSoundButton.frame = NSRect(x: 250, y: 28, width: 100, height: 30)
        addSubview(deleteSoundButton)

        confirmButton.target = self
        confirmButton.action = #selector(confirmSettings)
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.frame = NSRect(x: 518, y: 28, width: 72, height: 30)
        addSubview(confirmButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: 488, y: 33, width: 18, height: 18)
        addSubview(spinner)

        localContentViews = subviews
        buildModeControl()
        buildMarketplaceUI()
        updateMode()
    }

    private func buildModeControl() {
        modeControl.target = self
        modeControl.action = #selector(changeSettingsMode)
        modeControl.selectedSegment = 0
        modeControl.frame = NSRect(x: 400, y: 382, width: 190, height: 26)
        addSubview(modeControl)
    }

    private func buildMarketplaceUI() {
        marketplacePanel.frame = NSRect(x: 24, y: 24, width: 592, height: 346)
        marketplacePanel.isHidden = true
        addSubview(marketplacePanel)

        let authLabel = NSTextField(labelWithString: "로그인")
        authLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        authLabel.textColor = .secondaryLabelColor
        authLabel.frame = NSRect(x: 0, y: 316, width: 80, height: 18)
        marketplacePanel.addSubview(authLabel)

        authEmailField.placeholderString = "email"
        authEmailField.frame = NSRect(x: 0, y: 286, width: 170, height: 26)
        marketplacePanel.addSubview(authEmailField)

        authPasswordField.placeholderString = "password"
        authPasswordField.frame = NSRect(x: 178, y: 286, width: 130, height: 26)
        marketplacePanel.addSubview(authPasswordField)

        signInButton.target = self
        signInButton.action = #selector(signIn)
        signInButton.bezelStyle = .rounded
        signInButton.frame = NSRect(x: 318, y: 284, width: 64, height: 30)
        marketplacePanel.addSubview(signInButton)

        signUpButton.target = self
        signUpButton.action = #selector(signUp)
        signUpButton.bezelStyle = .rounded
        signUpButton.frame = NSRect(x: 388, y: 284, width: 54, height: 30)
        marketplacePanel.addSubview(signUpButton)

        signOutButton.target = self
        signOutButton.action = #selector(signOut)
        signOutButton.bezelStyle = .rounded
        signOutButton.frame = NSRect(x: 448, y: 284, width: 74, height: 30)
        marketplacePanel.addSubview(signOutButton)

        authStatusLabel.font = NSFont.systemFont(ofSize: 12)
        authStatusLabel.textColor = .secondaryLabelColor
        authStatusLabel.lineBreakMode = .byTruncatingMiddle
        authStatusLabel.frame = NSRect(x: 0, y: 260, width: 520, height: 18)
        marketplacePanel.addSubview(authStatusLabel)

        uploadMarketplaceButton.target = self
        uploadMarketplaceButton.action = #selector(uploadSelectedToMarketplace)
        uploadMarketplaceButton.bezelStyle = .rounded
        uploadMarketplaceButton.frame = NSRect(x: 0, y: 220, width: 172, height: 30)
        marketplacePanel.addSubview(uploadMarketplaceButton)

        refreshMarketplaceButton.target = self
        refreshMarketplaceButton.action = #selector(refreshMarketplace)
        refreshMarketplaceButton.bezelStyle = .rounded
        refreshMarketplaceButton.frame = NSRect(x: 182, y: 220, width: 86, height: 30)
        marketplacePanel.addSubview(refreshMarketplaceButton)

        downloadMarketplaceButton.target = self
        downloadMarketplaceButton.action = #selector(downloadSelectedMarketplaceMalangi)
        downloadMarketplaceButton.bezelStyle = .rounded
        downloadMarketplaceButton.frame = NSRect(x: 278, y: 220, width: 86, height: 30)
        marketplacePanel.addSubview(downloadMarketplaceButton)

        marketplaceStatusLabel.font = NSFont.systemFont(ofSize: 12)
        marketplaceStatusLabel.textColor = .secondaryLabelColor
        marketplaceStatusLabel.frame = NSRect(x: 374, y: 226, width: 210, height: 18)
        marketplacePanel.addSubview(marketplaceStatusLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("marketplace"))
        column.width = 560
        marketplaceTableView.addTableColumn(column)
        marketplaceTableView.headerView = nil
        marketplaceTableView.delegate = self
        marketplaceTableView.dataSource = self
        marketplaceTableView.rowHeight = 36
        marketplaceTableView.allowsEmptySelection = true
        marketplaceTableView.target = self
        marketplaceTableView.action = #selector(selectMarketplace)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 592, height: 210))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = marketplaceTableView
        marketplacePanel.addSubview(scrollView)
    }

    @objc private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        pendingImageURL = url
        refreshStatus()
    }

    @objc private func changeSettingsMode() {
        updateMode()
    }

    @objc private func signIn() {
        authenticate(isSignUp: false)
    }

    @objc private func signUp() {
        authenticate(isSignUp: true)
    }

    @objc private func signOut() {
        SupabaseMalangiClient.shared.signOut()
        refreshStatus()
    }

    @objc private func refreshMarketplace() {
        marketplaceStatusLabel.stringValue = "불러오는 중"
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try SupabaseMalangiClient.shared.fetchMarketplace() }
            DispatchQueue.main.async {
                switch result {
                case .success(let rows):
                    self.marketplaceMalangis = rows
                    self.marketplaceTableView.reloadData()
                    self.marketplaceStatusLabel.stringValue = "\(rows.count)개"
                case .failure(let error):
                    self.marketplaceStatusLabel.stringValue = "조회 실패"
                    self.showError("마켓 조회 실패", detail: error.localizedDescription)
                }
                self.updateActionStates()
            }
        }
    }

    @objc private func selectMarketplace() {
        let row = marketplaceTableView.selectedRow
        selectedMarketplaceIndex = marketplaceMalangis.indices.contains(row) ? row : nil
        updateActionStates()
    }

    @objc private func uploadSelectedToMarketplace() {
        guard let selectedIndex, registrations.indices.contains(selectedIndex) else {
            showError("말랑이를 선택해 주세요.", detail: "내 말랑이 탭에서 업로드할 말랑이를 먼저 선택해 주세요.")
            return
        }
        guard let session = SupabaseMalangiClient.shared.authSession else {
            showError("로그인이 필요해요.", detail: "마켓플레이스에 올리려면 먼저 로그인해 주세요.")
            return
        }

        marketplaceStatusLabel.stringValue = "업로드 중"
        let malangi = registrations[selectedIndex]
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try SupabaseMalangiClient.shared.publishToMarketplace(malangi, session: session) }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.marketplaceStatusLabel.stringValue = "업로드 완료"
                    self.refreshMarketplace()
                case .failure(let error):
                    self.marketplaceStatusLabel.stringValue = "업로드 실패"
                    self.showError("업로드 실패", detail: error.localizedDescription)
                }
            }
        }
    }

    @objc private func downloadSelectedMarketplaceMalangi() {
        guard let selectedMarketplaceIndex,
              marketplaceMalangis.indices.contains(selectedMarketplaceIndex) else { return }

        let item = marketplaceMalangis[selectedMarketplaceIndex]
        MalangiSettings.addMarketplaceMalangi(item)
        refreshStatus()
        marketplaceStatusLabel.stringValue = "다운로드 완료"
    }

    @objc private func selectSounds() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }

        soundDrafts.append(contentsOf: panel.urls.map { SoundDraft(url: $0, displayName: $0.lastPathComponent) })
        refreshStatus()
    }

    @objc private func confirmSettings() {
        guard !isSaving else { return }
        let name = nameField.stringValue
        let editingIndex = selectedIndex
        let imageURL = pendingImageURL
        let sounds = soundDrafts

        if editingIndex == nil, imageURL == nil {
            showError("사진을 먼저 선택해 주세요.", detail: "새 말랑이를 등록하려면 말랑이 사진이 필요해요.")
            return
        }

        setSaving(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try MalangiSettings.saveMalangi(name: name, editingIndex: editingIndex, image: imageURL, sounds: sounds)
            }

            DispatchQueue.main.async {
                self.setSaving(false)
                switch result {
                case .success:
                    self.clearDraft()
                    self.refreshStatus()
                    self.window?.close()
                case .failure(let error):
                    self.showError("등록에 실패했어요.", detail: error.localizedDescription)
                }
            }
        }
    }

    private func refreshStatus() {
        registrations = MalangiSettings.registrations
        tableView.reloadData()
        soundTableView.reloadData()
        if let selectedIndex, registrations.indices.contains(selectedIndex) {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }

        if let pendingImageURL {
            imageStatusLabel.stringValue = "\(pendingImageURL.lastPathComponent) 선택됨"
            imagePreview.image = NSImage(contentsOf: pendingImageURL)
        } else if let selectedIndex, registrations.indices.contains(selectedIndex) {
            let registration = registrations[selectedIndex]
            imageStatusLabel.stringValue = registration.imageFileName ?? ResourceLocator.displayName(for: registration.imagePath)
            imagePreview.image = ResourceLocator.image(for: registration.imagePath)
        } else {
            imageStatusLabel.stringValue = "새 사진 선택"
            imagePreview.image = nil
        }

        if !soundDrafts.isEmpty {
            soundStatusLabel.stringValue = "\(soundDrafts.count)개"
        } else {
            soundStatusLabel.stringValue = "선택 안 함"
        }

        updateActionStates()
        updateAuthStatus()
    }

    @objc private func selectRegistration() {
        let row = tableView.selectedRow
        guard registrations.indices.contains(row) else {
            clearDraft()
            refreshStatus()
            return
        }

        selectedIndex = row
        pendingImageURL = nil
        soundDrafts = registrations[row].soundPaths.enumerated().compactMap { index, path in
            guard let url = ResourceLocator.url(for: path) else { return nil }
            let displayName = registrations[row].soundFileNames.indices.contains(index)
                ? registrations[row].soundFileNames[index]
                : ResourceLocator.displayName(for: path)
            return SoundDraft(url: url, displayName: displayName)
        }
        nameField.stringValue = registrations[row].name
        refreshStatus()
    }

    @objc private func newRegistration() {
        tableView.deselectAll(nil)
        clearDraft()
        refreshStatus()
    }

    @objc private func selectSound() {
        updateActionStates()
    }

    @objc private func deleteRegistration() {
        guard let selectedIndex else { return }

        do {
            try MalangiSettings.deleteMalangi(at: selectedIndex)
            clearDraft()
            refreshStatus()
        } catch {
            showError("삭제에 실패했어요.", detail: error.localizedDescription)
        }
    }

    @objc private func deleteSelectedSound() {
        let row = soundTableView.selectedRow
        guard soundDrafts.indices.contains(row) else { return }
        soundDrafts.remove(at: row)
        let nextRow = min(row, soundDrafts.count - 1)
        refreshStatus()
        if nextRow >= 0 {
            soundTableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        }
        updateActionStates()
    }

    private func updateActionStates() {
        deleteMalangiButton.isEnabled = selectedIndex != nil
        deleteSoundButton.isEnabled = soundTableView.selectedRow >= 0
        uploadMarketplaceButton.isEnabled = selectedIndex != nil && SupabaseMalangiClient.shared.authSession != nil
        downloadMarketplaceButton.isEnabled = selectedMarketplaceIndex != nil
    }

    private func updateMode() {
        let isMarketplace = modeControl.selectedSegment == 1
        localContentViews.forEach { $0.isHidden = isMarketplace }
        marketplacePanel.isHidden = !isMarketplace
        titleLabel.stringValue = isMarketplace ? "마켓플레이스" : "말랑이 등록하기"
        if isMarketplace, marketplaceMalangis.isEmpty {
            refreshMarketplace()
        }
        refreshStatus()
    }

    private func updateAuthStatus() {
        if let session = SupabaseMalangiClient.shared.authSession {
            authStatusLabel.stringValue = "로그인됨: \(session.user.email ?? session.user.id)"
            signInButton.isEnabled = false
            signUpButton.isEnabled = false
            signOutButton.isEnabled = true
        } else {
            authStatusLabel.stringValue = "업로드하려면 로그인해 주세요."
            signInButton.isEnabled = true
            signUpButton.isEnabled = true
            signOutButton.isEnabled = false
        }
        if modeControl.selectedSegment == 1, selectedIndex == nil {
            marketplaceStatusLabel.stringValue = marketplaceStatusLabel.stringValue.isEmpty
                ? "내 말랑이를 선택하면 업로드 가능"
                : marketplaceStatusLabel.stringValue
        }
    }

    private func authenticate(isSignUp: Bool) {
        let email = authEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = authPasswordField.stringValue
        guard !email.isEmpty, !password.isEmpty else {
            showError("이메일과 비밀번호를 입력해 주세요.", detail: "마켓플레이스 업로드에 사용할 계정 정보가 필요해요.")
            return
        }

        authStatusLabel.stringValue = isSignUp ? "가입 중" : "로그인 중"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                if isSignUp {
                    return try SupabaseMalangiClient.shared.signUp(email: email, password: password)
                }
                return try SupabaseMalangiClient.shared.signIn(email: email, password: password)
            }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.authPasswordField.stringValue = ""
                    self.refreshStatus()
                case .failure(let error):
                    self.authStatusLabel.stringValue = "인증 실패"
                    self.showError("인증 실패", detail: error.localizedDescription)
                }
            }
        }
    }

    func resetForPresentation() {
        tableView.deselectAll(nil)
        clearDraft()
        refreshStatus()
    }

    private func clearDraft() {
        selectedIndex = nil
        pendingImageURL = nil
        soundDrafts = []
        nameField.stringValue = ""
        imagePreview.image = nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === soundTableView {
            return soundDrafts.count
        }
        if tableView === marketplaceTableView {
            return marketplaceMalangis.count
        }

        return registrations.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === soundTableView {
            guard soundDrafts.indices.contains(row) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("SoundCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
                ?? NSTextField(labelWithString: "")

            cell.identifier = identifier
            cell.stringValue = soundDrafts[row].displayName
            cell.lineBreakMode = .byTruncatingMiddle
            cell.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            return cell
        }

        if tableView === marketplaceTableView {
            guard marketplaceMalangis.indices.contains(row) else { return nil }
            let item = marketplaceMalangis[row]
            let identifier = NSUserInterfaceItemIdentifier("MarketplaceCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
                ?? NSTextField(labelWithString: "")
            cell.identifier = identifier
            let author = item.ownerEmail ?? "unknown"
            cell.stringValue = "\(item.name) · \(item.soundURLs.count) sounds · \(author)"
            cell.lineBreakMode = .byTruncatingTail
            cell.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            return cell
        }

        guard registrations.indices.contains(row) else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("MalangiCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")

        cell.identifier = identifier
        cell.stringValue = registrations[row].name
        cell.lineBreakMode = .byTruncatingTail
        cell.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        return cell
    }

    private func setSaving(_ saving: Bool) {
        isSaving = saving
        confirmButton.isEnabled = !saving
        confirmButton.title = saving ? "저장 중" : "확인"

        if saving {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
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
