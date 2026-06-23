import AuthenticationServices
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme

enum MalangiTheme {
    static let background   = Color(red: 1.0, green: 0.97, blue: 0.93)  // 크림
    static let card         = Color.white
    static let accentPink   = Color(red: 1.0, green: 0.71, blue: 0.76)  // 연핑크
    static let accentBlue   = Color(red: 0.66, green: 0.78, blue: 0.92) // 앱 기존 파랑 (main.swift:109)
    static let accentGold   = Color(red: 0.94, green: 0.82, blue: 0.54) // 앱 기존 노랑 (main.swift:110)
}

// MARK: - Supporting Types

enum SettingsMode {
    case local
    case marketplace
}

struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    var confirmAction: (() -> Void)? = nil
}

/// 마켓플레이스 탭에서 기본 말랑이(malangis)와 사용자 공유(marketplace_malangis)를 통합 표시하는 타입.
enum MarketplaceItem: Identifiable {
    case builtIn(StoredMalangi)
    case shared(MarketplaceMalangi)

    var id: String {
        switch self {
        case .builtIn(let m): return "builtin-\(m.remoteId ?? m.name)"
        case .shared(let m):  return "shared-\(m.id)"
        }
    }

    var name: String {
        switch self {
        case .builtIn(let m): return m.name
        case .shared(let m):  return m.name
        }
    }

    var isBuiltIn: Bool {
        if case .builtIn = self { return true }
        return false
    }

    var imageURLString: String {
        switch self {
        case .builtIn(let m): return m.imagePath
        case .shared(let m):  return m.imageURL
        }
    }

    var subtitle: String {
        switch self {
        case .builtIn: return "기본 제공"
        case .shared(let m): return "\(m.soundURLs.count) sounds · \(m.ownerName ?? "익명")"
        }
    }

    var firstSoundURL: String? {
        switch self {
        case .builtIn(let m): return m.soundPaths.first
        case .shared(let m):  return m.soundURLs.first
        }
    }
}

// MARK: - ViewModel

final class SettingsViewModel: ObservableObject {

    // Local tab state
    @Published var registrations: [StoredMalangi] = []
    @Published var selectedIndex: Int? = nil
    @Published var draftName: String = ""
    @Published var pendingImageURL: URL? = nil
    @Published var soundDrafts: [SoundDraft] = []
    @Published var selectedSoundIndex: Int? = nil
    @Published var isSaving: Bool = false
    @Published var imageStatusText: String = "새 사진 선택"
    @Published var soundStatusText: String = "선택 안 함"

    // Marketplace tab state
    @Published var marketplaceMalangis: [MarketplaceMalangi] = []
    @Published var defaultCatalog: [StoredMalangi] = []
    @Published var selectedMarketplaceIndex: Int? = nil
    @Published var authStatusText: String = ""
    @Published var marketplaceStatusText: String = ""
    @Published var points: Int? = nil               // 로그인 사용자의 포인트 잔액

    // Login sheet state
    @Published var isAuthenticating: Bool = false   // 구글 인증 브라우저 대기 중
    @Published var nicknameStage: Bool = false       // 닉네임 입력 단계
    @Published var authNickname: String = ""         // 닉네임 입력값

    // Common
    @Published var mode: SettingsMode = .local
    @Published var alert: SettingsAlert? = nil
    @Published var showLoginSheet: Bool = false
    @Published var didLoadMarketplace: Bool = false

    // 로그인 완료 후 자동으로 업로드를 이어받기 위한 플래그
    private var pendingUpload: Bool = false

    // 마켓 미리듣기용 플레이어
    private let previewPlayer = SoundPlayer()

    var onRequestClose: (() -> Void)? = nil

    // MARK: Computed

    var isSignedIn: Bool {
        SupabaseMalangiClient.shared.authSession != nil
    }

    var previewImage: NSImage? {
        if let pendingImageURL {
            return NSImage(contentsOf: pendingImageURL)
        }
        if let idx = selectedIndex, registrations.indices.contains(idx) {
            return ResourceLocator.image(for: registrations[idx].imagePath)
        }
        return nil
    }

    var canDelete: Bool      { selectedIndex != nil }
    var canDeleteSound: Bool { selectedSoundIndex != nil }
    var canUpload: Bool      { selectedIndex != nil }
    var canDownload: Bool    { selectedMarketplaceIndex != nil }
    var selectedIsDefault: Bool {
        guard let idx = selectedIndex, registrations.indices.contains(idx) else { return false }
        return registrations[idx].isDefault
    }

    /// 마켓플레이스 탭: 기본 말랑이 + 사용자 공유 통합 목록
    var marketplaceItems: [MarketplaceItem] {
        defaultCatalog.map { .builtIn($0) } + marketplaceMalangis.map { .shared($0) }
    }

    // MARK: - Local Tab Actions

    func reload() {
        registrations = MalangiSettings.registrations
        defaultCatalog = MalangiSettings.defaultCatalog
        updateImageStatus()
        updateSoundStatus()
        updateAuthStatus()
    }

    func selectRegistration(at index: Int) {
        guard registrations.indices.contains(index) else { return }
        selectedIndex = index
        pendingImageURL = nil
        selectedSoundIndex = nil
        let reg = registrations[index]
        draftName = reg.name
        soundDrafts = reg.soundPaths.enumerated().compactMap { i, path in
            guard let url = ResourceLocator.url(for: path) else { return nil }
            let name = reg.soundFileNames.indices.contains(i)
                ? reg.soundFileNames[i]
                : ResourceLocator.displayName(for: path)
            return SoundDraft(url: url, displayName: name)
        }
        reload()
    }

    func newRegistration() {
        selectedIndex = nil
        clearDraft()
        reload()
    }

    func deleteRegistration() {
        guard let idx = selectedIndex, registrations.indices.contains(idx) else { return }
        let name = registrations[idx].name
        alert = SettingsAlert(
            title: "정말 삭제할까요?",
            detail: "\(name)을(를) 삭제하면 되돌릴 수 없어요.",
            confirmAction: { [weak self] in
                guard let self else { return }
                guard let idx = self.selectedIndex else { return }
                do {
                    try MalangiSettings.deleteMalangi(at: idx)
                    self.clearDraft()
                    self.reload()
                } catch {
                    self.alert = SettingsAlert(title: "삭제에 실패했어요.", detail: error.localizedDescription)
                }
            }
        )
    }

    func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingImageURL = url
        reload()
    }

    func selectSounds() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        soundDrafts.append(contentsOf: panel.urls.map {
            SoundDraft(url: $0, displayName: $0.lastPathComponent)
        })
        reload()
    }

    func deleteSound(at index: Int) {
        guard soundDrafts.indices.contains(index) else { return }
        soundDrafts.remove(at: index)
        selectedSoundIndex = soundDrafts.isEmpty ? nil : min(index, soundDrafts.count - 1)
        reload()
    }

    func confirm() {
        guard !isSaving else { return }
        let name        = draftName
        let editingIdx  = selectedIndex
        let imageURL    = pendingImageURL
        let sounds      = soundDrafts

        if let editingIdx, registrations.indices.contains(editingIdx), registrations[editingIdx].isDefault {
            alert = SettingsAlert(title: "기본 말랑이는 수정할 수 없어요.",
                                  detail: "기본으로 제공되는 말랑이는 편집이 되지 않아요.")
            return
        }

        if editingIdx == nil, imageURL == nil {
            alert = SettingsAlert(title: "사진을 먼저 선택해 주세요.",
                                  detail: "새 말랑이를 등록하려면 말랑이 사진이 필요해요.")
            return
        }

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try MalangiSettings.saveMalangi(name: name,
                                                editingIndex: editingIdx,
                                                image: imageURL,
                                                sounds: sounds)
            }
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success:
                    self.clearDraft()
                    self.reload()
                    self.onRequestClose?()
                case .failure(let error):
                    self.alert = SettingsAlert(title: "등록에 실패했어요.",
                                              detail: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Marketplace Tab Actions

    func setMode(_ newMode: SettingsMode) {
        mode = newMode
        if newMode == .marketplace && marketplaceMalangis.isEmpty {
            refreshMarketplace()
        }
        reload()
    }

    /// 포인트 잔액을 서버에서 새로고침합니다 (로그인 상태일 때만).
    func refreshPoints() {
        guard isSignedIn else { points = nil; return }
        DispatchQueue.global(qos: .utility).async {
            let p = try? SupabaseMalangiClient.shared.fetchMyPoints()
            DispatchQueue.main.async { self.points = p }
        }
    }

    func refreshMarketplace() {
        marketplaceStatusText = "불러오는 중"
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try SupabaseMalangiClient.shared.fetchMarketplace() }
            DispatchQueue.main.async {
                switch result {
                case .success(let rows):
                    self.marketplaceMalangis = rows
                    self.didLoadMarketplace = true
                    let total = self.marketplaceItems.count
                    self.marketplaceStatusText = total > 0 ? "\(total)개" : ""
                    self.refreshPoints()    // 마켓 새로고침 시 잔액도 갱신
                case .failure(let error):
                    self.marketplaceStatusText = "조회 실패"
                    self.alert = SettingsAlert(title: "마켓 조회 실패",
                                              detail: error.localizedDescription)
                }
            }
        }
    }

    func upload() {
        guard let idx = selectedIndex, registrations.indices.contains(idx) else {
            alert = SettingsAlert(title: "말랑이를 선택해 주세요.",
                                  detail: "업로드할 말랑이를 먼저 선택해 주세요.")
            return
        }
        guard let session = SupabaseMalangiClient.shared.authSession else {
            // 비로그인 → 로그인 시트를 띄우고, 완료 후 업로드를 자동으로 이어받음
            pendingUpload = true
            isAuthenticating = false
            nicknameStage = false
            authNickname = ""
            authStatusText = ""
            showLoginSheet = true
            return
        }
        let malangi = registrations[idx]
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try SupabaseMalangiClient.shared.publishToMarketplace(malangi, session: session)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let row):
                    MalangiSettings.setMarketplaceId(row.id, for: malangi)
                    self.reload()
                    self.refreshPoints()    // 업로드 트리거 +3 반영
                    let verb = malangi.marketplaceId != nil ? "갱신" : "업로드"
                    self.alert = SettingsAlert(title: "마켓 \(verb) 완료",
                                              detail: "'\(malangi.name)'이(가) 마켓플레이스에 \(verb)됐어요.")
                case .failure(let error):
                    self.alert = SettingsAlert(title: "업로드 실패",
                                              detail: error.localizedDescription)
                }
            }
        }
    }

    func isDownloaded(_ item: MarketplaceItem) -> Bool {
        switch item {
        case .builtIn(let m):
            return registrations.contains { $0.remoteId == m.remoteId }
        case .shared(let mk):
            return registrations.contains { $0.imagePath == mk.imageURL || $0.name == mk.name }
        }
    }

    func download(_ item: MarketplaceItem) {
        // 이미 "내 말랑이"에 있으면 과금/로그인 전에 먼저 조기 반환
        if isDownloaded(item) {
            marketplaceStatusText = "이미 추가됨"
            return
        }
        switch item {
        case .builtIn(let m):
            // 앱 기본 제공 말랑이는 무료·무로그인
            if let rid = m.remoteId { MalangiSettings.unhideDefault(remoteId: rid) }
            reload()
            marketplaceStatusText = "다운로드 완료"

        case .shared(let mk):
            // 공유 말랑이: 로그인 필수 + 서버 RPC로 1포인트 차감
            guard let session = SupabaseMalangiClient.shared.authSession else {
                marketplaceStatusText = "로그인이 필요해요"
                openLogin()
                return
            }
            marketplaceStatusText = "다운로드 중…"
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result {
                    try SupabaseMalangiClient.shared.downloadMarketplaceMalangi(
                        id: mk.id, session: session
                    )
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
                            self.marketplaceStatusText = "포인트 부족"
                            self.alert = SettingsAlert(
                                title: "포인트가 부족해요",
                                detail: "말랑이를 마켓에 올리면 +3포인트를 받아요. 올려서 포인트를 모아보세요!"
                            )
                        } else {
                            self.marketplaceStatusText = "다운로드 실패"
                            self.alert = SettingsAlert(title: "다운로드 실패",
                                                      detail: error.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    func download() {
        guard let idx = selectedMarketplaceIndex,
              marketplaceItems.indices.contains(idx) else { return }
        download(marketplaceItems[idx])
    }

    /// 마켓 탭에서 소리 미리듣기 — URL 문자열로 직접 재생
    func previewSound(urlString: String) {
        previewPlayer.preview(urlString)
    }

    /// 마켓 탭에서 소리 미리듣기 (첫 번째 사운드, 백그라운드 재생)
    func previewSound(_ item: MarketplaceMalangi) {
        guard let first = item.soundURLs.first else { return }
        previewPlayer.preview(first)
    }

    /// 로그인 시트를 열어줍니다 (업로드 없이 순수 로그인).
    func openLogin() {
        pendingUpload = false
        isAuthenticating = false
        nicknameStage = false
        authNickname = ""
        authStatusText = ""
        showLoginSheet = true
    }

    /// 닉네임 변경 시트를 엽니다 (이미 로그인된 상태).
    func editNickname() {
        authNickname = SupabaseMalangiClient.shared.authSession?.user.userMetadata?.displayName ?? ""
        isAuthenticating = false
        nicknameStage = true
        showLoginSheet = true
    }

    /// 구글 로그인 시작
    func signInWithGoogle() {
        isAuthenticating = true
        authStatusText = "브라우저에서 로그인을 완료해 주세요…"

        SupabaseMalangiClient.shared.signInWithGoogle { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let session):
                self.isAuthenticating = false
                let displayName = session.user.userMetadata?.displayName
                self.authNickname = displayName ?? ""
                // 이미 닉네임이 저장돼 있으면 바로 완료, 없으면 입력 단계
                if session.user.userMetadata?.nickname != nil {
                    self.finishLogin()
                } else {
                    self.nicknameStage = true
                    self.authStatusText = "마켓에 표시될 닉네임을 정해주세요."
                }
            case .failure(let error):
                self.isAuthenticating = false
                self.authStatusText = ""
                // 사용자가 직접 창을 닫아 취소한 경우 — alert 없이 조용히 종료
                let authErr = error as? ASWebAuthenticationSessionError
                if authErr?.code == .canceledLogin { return }
                self.alert = SettingsAlert(title: "로그인 실패", detail: error.localizedDescription)
            }
        }
    }

    /// 닉네임 저장 (첫 로그인 or 변경)
    func saveNickname() {
        let trimmed = authNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = SettingsAlert(title: "닉네임을 입력해 주세요.", detail: "마켓에 표시될 닉네임이 필요해요.")
            return
        }
        authStatusText = "저장 중…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try SupabaseMalangiClient.shared.updateNickname(trimmed) }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.finishLogin()
                case .failure(let error):
                    self.authStatusText = ""
                    self.alert = SettingsAlert(title: "닉네임 저장 실패", detail: error.localizedDescription)
                }
            }
        }
    }

    private func finishLogin() {
        showLoginSheet = false
        nicknameStage = false
        isAuthenticating = false
        authNickname = ""
        authStatusText = ""
        reload()
        refreshPoints()     // 로그인 직후 잔액 표시
        if pendingUpload {
            pendingUpload = false
            upload()
        }
    }

    func signOut() {
        SupabaseMalangiClient.shared.signOut()
        points = nil
        reload()
    }

    // MARK: - Reset

    func resetForPresentation() {
        selectedIndex = nil
        clearDraft()
        reload()
    }

    // MARK: - Private

    private func clearDraft() {
        selectedIndex      = nil
        pendingImageURL    = nil
        soundDrafts        = []
        selectedSoundIndex = nil
        draftName          = ""
    }

    private func updateImageStatus() {
        if let url = pendingImageURL {
            imageStatusText = "\(url.lastPathComponent) 선택됨"
        } else if let idx = selectedIndex, registrations.indices.contains(idx) {
            let reg = registrations[idx]
            imageStatusText = reg.imageFileName ?? ResourceLocator.displayName(for: reg.imagePath)
        } else {
            imageStatusText = "새 사진 선택"
        }
    }

    private func updateSoundStatus() {
        soundStatusText = soundDrafts.isEmpty ? "선택 안 함" : "\(soundDrafts.count)개"
    }

    private func updateAuthStatus() {
        if let session = SupabaseMalangiClient.shared.authSession {
            let name = session.user.userMetadata?.displayName ?? session.user.email ?? session.user.id
            authStatusText = name
        } else {
            authStatusText = ""
        }
    }
}

// MARK: - Root View

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            MalangiTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                Divider().opacity(0.25)

                if viewModel.mode == .local {
                    LocalTabView(viewModel: viewModel)
                } else {
                    MarketplaceTabView(viewModel: viewModel)
                }
            }
        }
        .frame(width: 680, height: 480)
        .alert(item: $viewModel.alert) { a in
            if let confirm = a.confirmAction {
                return Alert(
                    title: Text(a.title),
                    message: Text(a.detail),
                    primaryButton: .destructive(Text("삭제"), action: confirm),
                    secondaryButton: .cancel(Text("취소"))
                )
            } else {
                return Alert(
                    title: Text(a.title),
                    message: Text(a.detail),
                    dismissButton: .default(Text("확인"))
                )
            }
        }
        .sheet(isPresented: $viewModel.showLoginSheet) {
            LoginSheetView(viewModel: viewModel)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("🫧")
                .font(.title2)
            Text(viewModel.mode == .local ? "말랑이 등록하기" : "마켓플레이스")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Spacer()

            // Pill-style tab switcher
            HStack(spacing: 2) {
                tabButton(.local, label: "내 말랑이")
                tabButton(.marketplace, label: "마켓플레이스")
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.06)))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func tabButton(_ tab: SettingsMode, label: String) -> some View {
        Button {
            viewModel.setMode(tab)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(viewModel.mode == tab
                              ? MalangiTheme.accentPink
                              : Color.clear)
                )
                .foregroundColor(viewModel.mode == tab ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .pointingCursor()
    }
}

// MARK: - Login Sheet

struct LoginSheetView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Group {
            if viewModel.isAuthenticating {
                // 단계 1: 브라우저 인증 대기 중
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.2)
                    Text("브라우저에서 로그인을 완료해 주세요…")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                    MalangiButton(title: "취소", style: .secondary) {
                        SupabaseMalangiClient.shared.cancelGoogleSignIn()
                        viewModel.showLoginSheet = false
                        viewModel.isAuthenticating = false
                    }
                }
            } else if viewModel.nicknameStage {
                // 단계 2: 닉네임 입력
                VStack(spacing: 16) {
                    Text("🏷️ 닉네임 설정")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("닉네임", text: $viewModel.authNickname)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        Text("마켓플레이스에 표시될 이름이에요.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    if !viewModel.authStatusText.isEmpty {
                        Text(viewModel.authStatusText)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                    }

                    HStack(spacing: 10) {
                        MalangiButton(title: "취소", style: .secondary) {
                            viewModel.showLoginSheet = false
                            viewModel.nicknameStage = false
                        }
                        MalangiButton(title: "저장", style: .primary) {
                            viewModel.saveNickname()
                        }
                    }
                }
            } else {
                // 단계 0: 로그인 시작
                VStack(spacing: 16) {
                    Text("🔑 로그인")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Text("구글 계정으로 간편하게 로그인해요.\n마켓플레이스 업로드와 닉네임 설정에 사용됩니다.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)

                    HStack(spacing: 10) {
                        MalangiButton(title: "취소", style: .secondary) {
                            viewModel.showLoginSheet = false
                        }
                        MalangiButton(title: "Google로 로그인", style: .primary) {
                            viewModel.signInWithGoogle()
                        }
                    }
                }
            }
        }
        .padding(32)
        .frame(minWidth: 340)
        .background(MalangiTheme.background)
    }
}

// MARK: - Local Tab

struct LocalTabView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            malangiListCard
                .frame(width: 200)
            registrationFormCard
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Left — Registered list

    private var malangiListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("등록된 말랑이")

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.registrations.enumerated()), id: \.offset) { index, reg in
                        HStack {
                            Text(reg.name)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer()
                            if reg.isDefault {
                                Text("기본")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(MalangiTheme.accentBlue.opacity(0.25)))
                                    .foregroundColor(.secondary)
                            }
                            if reg.marketplaceId != nil {
                                Text("✓ 업로드됨")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(MalangiTheme.accentGold.opacity(0.4)))
                                    .foregroundColor(.primary.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.selectedIndex == index
                                      ? MalangiTheme.accentPink.opacity(0.25)
                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.selectRegistration(at: index) }
                        .pointingCursor()
                    }
                }
                .padding(4)
            }
            .background(listBackground)
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                MalangiButton(title: "새 말랑이", style: .secondary) {
                    viewModel.newRegistration()
                }
                MalangiButton(title: "삭제", style: .secondary, isDestructive: true) {
                    viewModel.deleteRegistration()
                }
                .disabled(!viewModel.canDelete)
            }
        }
        .malangiCard()
    }

    // MARK: Right — Registration form

    private var registrationFormCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name field
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("이름")
                TextField("말랑이 이름", text: $viewModel.draftName)
                    .textFieldStyle(.roundedBorder)
            }

            // Image picker
            HStack(spacing: 10) {
                MalangiButton(title: "말랑이 사진 등록", style: .secondary) {
                    viewModel.selectImage()
                }
                Text(viewModel.imageStatusText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                imagePreviewView
            }

            // Sound picker
            HStack(spacing: 10) {
                MalangiButton(title: "사운드 여러 개 등록", style: .secondary) {
                    viewModel.selectSounds()
                }
                Text(viewModel.soundStatusText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Sound list
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("등록된 사운드")
                ScrollView {
                    VStack(spacing: 2) {
                        if viewModel.soundDrafts.isEmpty {
                            Text("사운드를 등록해 주세요")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(Array(viewModel.soundDrafts.enumerated()), id: \.offset) { index, draft in
                                HStack {
                                    Text(draft.displayName)
                                        .font(.system(size: 12, design: .rounded))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewModel.selectedSoundIndex == index
                                              ? MalangiTheme.accentBlue.opacity(0.3)
                                              : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { viewModel.selectedSoundIndex = index }
                                .pointingCursor()
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 60, maxHeight: 90)
                .background(listBackground)
            }

            Spacer()

            // Bottom actions
            HStack {
                MalangiButton(title: "사운드 삭제", style: .secondary, isDestructive: true) {
                    if let idx = viewModel.selectedSoundIndex {
                        viewModel.deleteSound(at: idx)
                    }
                }
                .disabled(!viewModel.canDeleteSound)

                Spacer()

                // 마켓 업로드/갱신 버튼 (기본 말랑이는 숨김)
                if let idx = viewModel.selectedIndex,
                   viewModel.registrations.indices.contains(idx),
                   !viewModel.selectedIsDefault {
                    let isPublished = viewModel.registrations[idx].marketplaceId != nil
                    MalangiButton(
                        title: isPublished ? "마켓 갱신" : "마켓에 올리기",
                        style: .secondary
                    ) {
                        viewModel.upload()
                    }
                    .disabled(viewModel.isSaving)
                }

                if viewModel.isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }
                MalangiButton(title: viewModel.isSaving ? "저장 중…" : "확인",
                              style: .primary) {
                    viewModel.confirm()
                }
                .disabled(viewModel.isSaving || viewModel.selectedIsDefault)
            }
        }
        .malangiCard()
    }

    @ViewBuilder
    private var imagePreviewView: some View {
        if let img = viewModel.previewImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .foregroundColor(.secondary.opacity(0.35))
                .frame(width: 72, height: 54)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary.opacity(0.4))
                )
        }
    }
}

// MARK: - Marketplace Tab

struct MarketplaceTabView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 10) {
            // 상단: 슬림 액션 바 (새로고침 + 다운로드 + 로그아웃)
            actionsBar
            // 메인: 다른 사용자들이 올린 목록
            listCard
                .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionsBar: some View {
        HStack(spacing: 8) {
            MalangiButton(title: "새로고침", style: .secondary) { viewModel.refreshMarketplace() }
            Spacer()
            Text(viewModel.marketplaceStatusText)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
            if viewModel.isSignedIn {
                Text(viewModel.authStatusText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let p = viewModel.points {
                    Text("🍬 \(p)P")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(MalangiTheme.accentPink)
                }
                MalangiButton(title: "닉네임 변경", style: .secondary) { viewModel.editNickname() }
                MalangiButton(title: "로그아웃", style: .secondary) { viewModel.signOut() }
            } else {
                MalangiButton(title: "로그인", style: .primary) { viewModel.openLogin() }
            }
        }
        .malangiCard()
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 비로그인 안내 배너
            if !viewModel.isSignedIn {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(MalangiTheme.accentPink)
                    Text("기본 말랑이는 무료예요. 공유 말랑이 다운로드는 로그인 + 1포인트, 업로드하면 +3포인트!")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            ScrollView {
                VStack(spacing: 2) {
                    if viewModel.marketplaceItems.isEmpty {
                        Text(viewModel.didLoadMarketplace
                             ? "아직 등록된 말랑이들이 없어요."
                             : "새로고침을 눌러 말랑이를 불러오세요.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(Array(viewModel.marketplaceItems.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 10) {
                                // 좌측 — 말랑이 썸네일 (비동기 로드)
                                MarketplaceThumbnail(urlString: item.imageURLString)

                                // 중앙 — 이름 + 정보
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                        if item.isBuiltIn {
                                            Text("기본")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(MalangiTheme.accentBlue.opacity(0.25)))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Text(item.subtitle)
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                // 우측 — 미리듣기 버튼
                                Button {
                                    if let url = item.firstSoundURL {
                                        viewModel.previewSound(urlString: url)
                                    }
                                } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(MalangiTheme.accentPink)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(MalangiTheme.accentPink.opacity(0.35)))
                                }
                                .buttonStyle(.plain)
                                .disabled(item.firstSoundURL == nil)
                                .pointingCursor()

                                // 다운로드 버튼
                                Button {
                                    viewModel.download(item)
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 12))
                                        .foregroundColor(MalangiTheme.accentGold)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(MalangiTheme.accentGold.opacity(0.4)))
                                }
                                .buttonStyle(.plain)
                                .pointingCursor()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(viewModel.selectedMarketplaceIndex == index
                                          ? MalangiTheme.accentGold.opacity(0.3)
                                          : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.selectedMarketplaceIndex = index }
                            .pointingCursor()
                        }
                    }
                }
                .padding(4)
            }
            .background(listBackground)
            .frame(maxHeight: .infinity)
        }
        .malangiCard()
    }
}

// MARK: - Marketplace Thumbnail

/// 원격 이미지 URL을 비동기로 로드해 표시합니다. 로드 전/실패 시 플레이스홀더.
struct MarketplaceThumbnail: View {
    let urlString: String
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.4))
                    )
            }
        }
        .task(id: urlString) {
            guard image == nil else { return }
            // Data를 백그라운드에서 로드해 Sendable 경고 회피 (NSImage는 macOS 14+에서만 Sendable)
            let data = await Task.detached(priority: .utility) { () -> Data? in
                guard let url = ResourceLocator.url(for: urlString) else { return nil }
                return try? Data(contentsOf: url)
            }.value
            if let data, let loaded = NSImage(data: data) {
                await MainActor.run { self.image = loaded }
            }
        }
    }
}

// MARK: - Shared Helpers

private var listBackground: some View {
    RoundedRectangle(cornerRadius: 10)
        .fill(Color.black.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
}

private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundColor(.secondary)
        .padding(.horizontal, 2)
}

// MARK: - Button Component

enum MalangiButtonStyle { case primary, secondary }

struct MalangiButton: View {
    let title: String
    let style: MalangiButtonStyle
    var isDestructive: Bool = false
    let action: () -> Void

    private var fillColor: Color {
        if isDestructive { return Color.red.opacity(0.1) }
        switch style {
        case .primary:   return MalangiTheme.accentPink
        case .secondary: return MalangiTheme.accentBlue.opacity(0.25)
        }
    }

    private var foreColor: Color {
        if isDestructive { return .red }
        switch style {
        case .primary:   return .white
        case .secondary: return .primary
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(foreColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(fillColor))
        }
        .buttonStyle(.plain)
        .pointingCursor()
    }
}

// MARK: - Modifiers

private struct PointingCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside && isEnabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct MalangiCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(MalangiTheme.card)
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

extension View {
    func malangiCard() -> some View {
        modifier(MalangiCardModifier())
    }

    func pointingCursor() -> some View {
        modifier(PointingCursorModifier())
    }
}
