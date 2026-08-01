import SwiftUI
import AVKit
import UIKit
import PhotosUI
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers
import WebKit

private struct ImportedRoomMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let source = received.file
            let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
            let copy = URL.temporaryDirectory.appendingPathComponent("pusheen-movie-\(UUID().uuidString)").appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: copy)
            return Self(url: copy)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View {
        Group {
            switch session.authenticationState {
            case .restoring: PusheenLaunchView()
            case .signedOut: LiquidAuthView()
            case .signedIn: PusheenTabs()
            }
        }
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) {
                if let request = session.friendRequestNotice {
                    FriendRequestToast(request: request)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: session.friendRequestNotice?.id)
    }
}

private struct FriendRequestToast: View {
    @EnvironmentObject private var session: SessionStore
    let request: FriendRequestProfile

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(dataURL: request.avatarDataURL, name: request.nickname, size: 45)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.nickname).font(.subheadline.bold()).lineLimit(1)
                Text("хочет добавить тебя в друзья").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Принять") { Task { await session.respond(to: request, accept: true) } }
                .font(.caption.weight(.bold)).buttonStyle(.plain).padding(.horizontal, 11).padding(.vertical, 8)
                .liquidCard(Capsule())
            Button { Task { await session.respond(to: request, accept: false) } } label: {
                Image(systemName: "xmark").font(.caption.bold()).frame(width: 28, height: 28)
            }.buttonStyle(.plain).liquidCard(Circle())
        }
        .padding(10)
        .liquidCard(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

private struct PusheenLaunchView: View {
    var body: some View {
        ZStack {
            AcrylicBackground()
            VStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.system(size: 56)).foregroundStyle(.teal)
                ProgressView().tint(.white)
            }
        }
    }
}

struct LegacyPusheenTabs: View {
    var body: some View { TabView {
        HomeView().tabItem { Label("Комнаты", systemImage: "play.rectangle.fill") }
        FriendsView().tabItem { Label("Друзья", systemImage: "person.2.fill") }
        ProfileView().tabItem { Label("Профиль", systemImage: "person.crop.circle") }
    }.tint(.purple) }
}

struct FriendsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var query = ""; @State private var people: [FriendProfile] = []
    var body: some View { ZStack { AcrylicBackground(); VStack(spacing: 14) { HStack { Image(systemName: "person.badge.plus"); TextField("Найти по @username", text: $query).textInputAutocapitalization(.never).onSubmit { Task { await search() } } }.padding(12).liquidCard(Capsule()); ScrollView { LazyVStack(spacing: 8) { ForEach(people) { person in HStack { Circle().fill(.purple.opacity(0.7)).frame(width: 42, height: 42).overlay(Text(person.nickname.prefix(1))); VStack(alignment: .leading) { Text(person.nickname).bold(); Text("@\(person.username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(person.isFriend ? "Добавлен" : "Добавить") { Task { try? await session.api.addFriend(username: person.username); await search() } }.buttonStyle(.bordered) }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 18)) } } } }.padding(16) }.task { await search() } }
    private func search() async { people = (try? await session.api.friends(query: query)) ?? [] }
}

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var nickname = ""; @State private var username = ""; @State private var available: Bool?; @State private var error = ""
    var body: some View { ZStack { AcrylicBackground(); VStack(spacing: 16) { Circle().fill(.purple.opacity(0.7)).frame(width: 94, height: 94).overlay(Text((session.profile?.nickname ?? "?").prefix(1)).font(.largeTitle.bold())); Text(session.profile?.nickname ?? "").font(.title2.bold()); Text("@\(session.profile?.username ?? "")").foregroundStyle(.secondary); VStack(spacing: 10) { TextField("Nickname", text: $nickname); TextField("Username", text: $username).textInputAutocapitalization(.never).onChange(of: username) { _, value in Task { available = try? await session.api.usernameAvailable(value) } }; if !username.isEmpty { Text(available == true ? "@\(username) свободен" : "Проверяем или занято").font(.caption).foregroundStyle(available == true ? .green : .orange) }; Button("Сохранить") { Task { await save() } }.buttonStyle(.borderedProminent); if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) } }.textFieldStyle(.roundedBorder).padding(16).liquidCard(RoundedRectangle(cornerRadius: 24)); Spacer() }.padding(20) }.onAppear { nickname = session.profile?.nickname ?? ""; username = session.profile?.username ?? "" } }
    private func save() async { do { let profile = try await session.api.updateProfile(nickname: nickname, username: username); session.profile = profile } catch { self.error = error.localizedDescription } }
}

struct AcrylicBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.024, blue: 0.075).ignoresSafeArea()
            Circle().fill(Color(red: 0.12, green: 0.48, blue: 0.52).opacity(0.28)).frame(width: 340).blur(radius: 90).offset(x: -175, y: -330)
            Circle().fill(Color(red: 0.10, green: 0.27, blue: 0.40).opacity(0.32)).frame(width: 300).blur(radius: 100).offset(x: 185, y: 385)
            Circle().fill(Color(red: 0.26, green: 0.38, blue: 0.62).opacity(0.20)).frame(width: 250).blur(radius: 95).offset(x: 185, y: 70)
        }
    }
}

extension View {
    @ViewBuilder func liquidCard<S: Shape>(_ shape: S = RoundedRectangle(cornerRadius: 26)) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular.interactive(), in: shape) }
        else { self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.16))) }
    }
    @ViewBuilder func genreLiquidGlass<S: Shape>(_ color: Color, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(color.opacity(0.42)).interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 0.75))
        }
    }

    /// Liquid Glass without the system press deformation. Use this for views
    /// that already have their own drag interaction, otherwise iOS 26 pushes
    /// the whole surface inward while the finger is held down.
    @ViewBuilder func passiveLiquidCard<S: Shape>(_ shape: S = RoundedRectangle(cornerRadius: 26)) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: shape) }
        else { self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.16))) }
    }
}

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isRegister = false
    @State private var nickname = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error = ""
    @State private var loading = false
    @State private var usernameState: UsernameState = .idle

    enum UsernameState { case idle, invalid, checking, available, taken }
    private var usernameValid: Bool {
        username.range(of: "^[A-Za-z][A-Za-z0-9_]{2,29}$", options: .regularExpression) != nil
    }

    var body: some View {
        ZStack { AcrylicBackground()
            VStack(spacing: 18) {
                Image(systemName: "play.fill").font(.system(size: 34, weight: .bold)).frame(width: 74, height: 74).foregroundStyle(.white).liquidCard(RoundedRectangle(cornerRadius: 24))
                Text(isRegister ? "Создать аккаунт" : "Войти").font(.system(size: 31, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    if isRegister { TextField("Nickname", text: $nickname).textContentType(.nickname) }
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: username) { _, value in Task { await checkUsername(value) } }
                    if isRegister && !username.isEmpty { UsernamePreview(nickname: nickname, username: username, state: usernameState) }
                    SecureField("Password", text: $password)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                    Button { Task { await submit() } } label: { Label(isRegister ? "Создать" : "Войти", systemImage: "arrow.right").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).disabled(loading)
                }.textFieldStyle(.roundedBorder).padding(18).liquidCard(RoundedRectangle(cornerRadius: 24))
                Button(isRegister ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Создать") { withAnimation(.spring(response: 0.38)) { isRegister.toggle(); error = "" } }
            }.padding(24).frame(maxWidth: 430)
        }
    }
    private func submit() async {
        error = ""; loading = true; defer { loading = false }
        do { if isRegister { try await session.register(nickname: nickname, username: username, password: password) } else { try await session.login(username: username, password: password) } }
        catch let caughtError { error = caughtError.localizedDescription }
    }

    private func checkUsername(_ value: String) async {
        guard isRegister else { usernameState = .idle; return }
        guard usernameValid else { usernameState = .invalid; return }
        usernameState = .checking
        try? await Task.sleep(for: .milliseconds(260))
        guard value == username else { return }
        usernameState = (try? await session.api.usernameAvailable(value)) == true ? .available : .taken
    }
}

private struct UsernamePreview: View {
    let nickname: String; let username: String; let state: AuthView.UsernameState
    private var title: String { switch state { case .available: return "Available"; case .taken: return "Taken"; case .invalid: return "Use A–Z, 0–9 or _"; case .checking: return "Checking…"; case .idle: return "" } }
    private var tint: Color { switch state { case .available: return .green; case .taken: return .red; case .invalid: return .orange; default: return .secondary } }
    var body: some View { HStack(spacing: 10) { Circle().fill(.indigo.opacity(0.62)).frame(width: 38, height: 38).overlay(Text((nickname.isEmpty ? username : nickname).prefix(1)).bold()); VStack(alignment: .leading, spacing: 2) { Text(nickname.isEmpty ? "Your nickname" : nickname).font(.subheadline.bold()); Text("@\(username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tint) }.padding(9).liquidCard(RoundedRectangle(cornerRadius: 16)).transition(.opacity.combined(with: .move(edge: .top))).animation(.spring(response: 0.32), value: username) }
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var rooms: [Room] = []
    @State private var path = NavigationPath()
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showMovieSearch = false
    @State private var previewedRoom: Room?
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ZStack { AcrylicBackground()
                    ScrollView { VStack(alignment: .leading, spacing: 18) {
                HStack { VStack(alignment: .leading) { Text("Pusheen").font(.largeTitle.bold()); Text("Привет, \(session.profile?.nickname ?? "")").foregroundStyle(.secondary) }; Spacer(); Button { session.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right").padding(10).liquidCard(Circle()) }.buttonStyle(.plain) }
                HStack { Text("Мои комнаты").font(.title2.bold()); Spacer(); Menu { Button("Найти фильм", systemImage: "magnifyingglass") { showMovieSearch = true }; Button("Создать комнату", systemImage: "plus") { showCreate = true }; Button("Войти по коду", systemImage: "number") { showJoin = true } } label: { Image(systemName: "plus").font(.headline).frame(width: 38, height: 38).liquidCard(Circle()) }.buttonStyle(.plain) }
                ForEach(rooms) { room in
                    RoomCard(room: room)
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                        .gesture(
                            LongPressGesture(minimumDuration: 0.42)
                                .onEnded { _ in previewedRoom = room }
                                .exclusively(before: TapGesture().onEnded { path.append(room) })
                        )
                }
                if rooms.isEmpty { ContentUnavailableView("Комнат пока нет", systemImage: "play.rectangle.on.rectangle", description: Text("Создай комнату в текущей Flutter-версии — SwiftUI-клиент сразу её увидит.")) }
                    }.padding(18) }.task { await load() }
                }
                .blur(radius: previewedRoom == nil ? 0 : 17)
                .allowsHitTesting(previewedRoom == nil)

                if let room = previewedRoom {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { previewedRoom = nil } }
                    RoomPreviewOverlay(room: room, canDelete: room.owner == session.profile?.userId, close: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { previewedRoom = nil }
                    }) {
                        try? await session.api.deleteRoom(id: room.id)
                        rooms.removeAll { $0.id == room.id }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { previewedRoom = nil }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: previewedRoom?.id)
            .navigationDestination(for: Room.self) { RoomView(room: $0, api: session.api, token: session.token ?? "") }
            .sheet(isPresented: $showCreate) { CreateRoomSheet { room in rooms.insert(room, at: 0); path.append(room) } }
            .sheet(isPresented: $showJoin) { JoinRoomSheet { room in rooms.insert(room, at: 0); path.append(room) } }
            .sheet(isPresented: $showMovieSearch) { MovieSearchSheet { room in rooms.insert(room, at: 0); path.append(room) } }
        }
    }
    private func load() async { rooms = (try? await session.api.rooms()) ?? [] }
}

struct MovieSearchSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let created: (Room) -> Void
    @State private var query = ""
    @State private var currentURL = URL(string: "https://www.google.com")!
    @State private var selectedURL = ""
    @State private var isCreating = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AcrylicBackground().ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("Что ищем?", text: $query)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit { search() }
                            .padding(12)
                            .liquidCard(RoundedRectangle(cornerRadius: 16))
                        Button { search() } label: {
                            Image(systemName: "magnifyingglass").frame(width: 42, height: 42)
                        }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .liquidCard(Circle())
                    }
                    .padding(.horizontal, 18)

                    BrowserPageView(url: currentURL, visitedURL: $selectedURL)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 12)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 18) }
                    Button { Task { await createRoom() } } label: { Label(isCreating ? "Создаю…" : "Создать комнату с этой страницей", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).padding(.horizontal, 18)
                        .disabled(isCreating || !isBrowsablePage)
                }
            }
            .navigationTitle("Поиск в Google")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationBackground(.clear)
    }

    private var isBrowsablePage: Bool {
        guard let url = URL(string: selectedURL), let host = url.host?.lowercased() else { return false }
        return !host.contains("google.")
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentURL = URL(string: "https://www.google.com/search?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)")!
    }

    private func createRoom() async {
        guard isBrowsablePage else { return }
        isCreating = true; error = ""; defer { isCreating = false }
        do { let room = try await session.api.createRoom(videoURL: selectedURL, isPrivate: false); created(room); dismiss() }
        catch { error = error.localizedDescription }
    }
}

struct BrowserPageView: UIViewRepresentable {
    let url: URL
    @Binding var visitedURL: String
    var reloadOnURLChange = true
    func makeCoordinator() -> Coordinator { Coordinator(visitedURL: $visitedURL) }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard reloadOnURLChange else { return }
        guard view.url?.absoluteString != url.absoluteString else { return }
        view.load(URLRequest(url: url))
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var visitedURL: String
        init(visitedURL: Binding<String>) { _visitedURL = visitedURL }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { visitedURL = webView.url?.absoluteString ?? "" }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

struct CreateRoomSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let created: (Room) -> Void
    @State private var url = ""
    @State private var selectedMovie: PhotosPickerItem?
    @State private var movieURL: URL?
    @State private var movieError = ""
    @State private var isPrivate = false
    @State private var loading = false
    @State private var error = ""
    var body: some View { ZStack { AcrylicBackground(); VStack(alignment: .leading, spacing: 16) {
        Text("Новая комната").font(.title2.bold())
        Text("Вставь ссылку VK Видео, сайта или выбери файл из галереи.").font(.subheadline).foregroundStyle(.secondary)
        TextField("Ссылка на видео", text: $url, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
        PhotosPicker(selection: $selectedMovie, matching: .videos) {
            HStack { Image(systemName: "video.badge.plus"); Text(movieURL == nil ? "Выбрать видео из галереи" : movieURL!.lastPathComponent); Spacer(); if movieURL != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) } }
                .lineLimit(1).padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
        }
        .onChange(of: selectedMovie) { _, item in Task { await loadMovie(item) } }
        Toggle("Публичная комната", isOn: Binding(get: { !isPrivate }, set: { isPrivate = !$0 })).padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
        if !movieError.isEmpty { Text(movieError).font(.caption).foregroundStyle(.red) }
        if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        Button { Task { await create() } } label: { Label(loading ? "Загрузка…" : "Создать", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled((url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && movieURL == nil) || loading)
    }.padding(22) }.presentationDetents([.medium, .large]).presentationBackground(.clear) }
    private func loadMovie(_ item: PhotosPickerItem?) async {
        movieError = ""; movieURL = nil
        guard let item else { return }
        do { movieURL = try await item.loadTransferable(type: ImportedRoomMovie.self)?.url }
        catch { movieError = "Не удалось получить видео из галереи" }
    }
    private func create() async {
        loading = true; error = ""; defer { loading = false }
        var pendingRoom: Room?
        do {
            pendingRoom = try await session.api.createRoom(videoURL: movieURL == nil ? url.trimmingCharacters(in: .whitespacesAndNewlines) : "", isPrivate: isPrivate)
            let room: Room
            if let movieURL { room = try await session.api.uploadRoomVideo(roomID: pendingRoom!.id, fileURL: movieURL) }
            else { room = pendingRoom! }
            created(room); dismiss()
        } catch {
            if let pendingRoom { try? await session.api.deleteRoom(id: pendingRoom.id) }
            self.error = error.localizedDescription
        }
    }
}

struct LegacyRoomCard: View {
    let room: Room
    var body: some View { HStack(spacing: 14) { Image(systemName: "play.fill").font(.title2).frame(width: 58, height: 58).liquidCard(Circle()); VStack(alignment: .leading, spacing: 4) { Text(room.title).font(.headline).lineLimit(1); Text("\(room.membersCount) участников · \(room.inviteCode)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(14).liquidCard() }
}

struct RoomView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let room: Room
    let api: APIClient
    let token: String
    @State private var draft = ""
    @State private var showTime = false
    @State private var showMembers = false
    @State private var chatFocused = false
    @State private var copiedCode = false
    @State private var copyFeedbackTick = 0
    @State private var roomSwipeOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var controlsVisible = false
    @State private var isScrubbingPlayer = false
    @State private var controlsHideTask: Task<Void, Never>?
    private let roomPlayerHeight: CGFloat = 214
    @StateObject private var model: RoomViewModel
    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token; _model = StateObject(wrappedValue: RoomViewModel(room: room, api: api, token: token)) }
    private var usesEmbeddedBrowser: Bool { room.sourceType == "web" && URL(string: room.mediaURL) != nil }
    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let geometryTop = geometry.frame(in: .global).minY
            // Depending on the parent container, GeometryReader may already
            // start below the status bar. Add only the still-uncovered part of
            // the top safe area so the inset is never applied twice.
            let uncoveredSafeTop = max(0, safeTop - geometryTop)
            let contentTop = uncoveredSafeTop + (chatFocused ? 2 : 6)
            let playerHeight = chatFocused ? 176.0 : roomPlayerHeight
            let roomHeight = max(playerHeight + 180, geometry.size.height - (chatFocused ? keyboardHeight : 0))
            let roomShape = RoundedRectangle(cornerRadius: 25, style: .continuous)
            ZStack(alignment: .top) { AcrylicBackground().contentShape(Rectangle()).onTapGesture { chatFocused = false }
                VStack(spacing: 0) {
                    Group {
                        if usesEmbeddedBrowser, let pageURL = URL(string: room.mediaURL) {
                            BrowserPageView(url: pageURL, visitedURL: .constant(pageURL.absoluteString), reloadOnURLChange: false)
                        } else if let player = model.player {
                            BarePlayerSurface(player: player)
                        } else {
                            ZStack {
                                Color.black
                                ProgressView().tint(.white)
                            }
                        }
                    }
                        .frame(height: playerHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleControls() }
                    if controlsVisible && !usesEmbeddedBrowser {
                        playerControls
                            .padding(.horizontal, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(20)
                    }
                    NativeChatPane(messages: model.messages, currentUserID: session.profile?.userId, draft: $draft, focused: $chatFocused, isMuted: model.isMuted, send: { text, image in model.send(text: text, image: image, as: session.profile) }, react: { id, emoji in model.react(messageID: id, emoji: emoji) })
                        .frame(maxHeight: .infinity)
                        .layoutPriority(2)
                }
                .clipShape(roomShape)
                .liquidCard(roomShape)
                .padding(.horizontal, 7)
                .padding(.top, contentTop)
                .padding(.bottom, 2)
                .frame(width: geometry.size.width, height: roomHeight, alignment: .top)
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: controlsVisible)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: chatFocused)
                .animation(.easeOut(duration: 0.22), value: keyboardHeight)
            }
            .offset(x: max(0, roomSwipeOffset))
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        let playerInteractionBottom: CGFloat = contentTop + (controlsVisible ? playerHeight + 188 : playerHeight + 80)
                        guard !isScrubbingPlayer,
                              value.startLocation.y > playerInteractionBottom,
                              value.startLocation.x <= 44,
                              value.translation.width > 0,
                              horizontal > vertical * 1.25 else { return }
                        roomSwipeOffset = min(value.translation.width, 420)
                    }
                    .onEnded { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        let playerInteractionBottom: CGFloat = contentTop + (controlsVisible ? playerHeight + 188 : playerHeight + 80)
                        let beganOutsidePlayer = value.startLocation.y > playerInteractionBottom
                        let exitsFromLeftEdge = !isScrubbingPlayer && beganOutsidePlayer && value.startLocation.x <= 44 && value.translation.width > 0
                        let opensMembersFromRightEdge = beganOutsidePlayer && value.startLocation.x >= geometry.size.width - 44 && value.translation.width < 0
                        guard horizontal > vertical * 1.25, exitsFromLeftEdge || opensMembersFromRightEdge else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { roomSwipeOffset = 0 }
                            return
                        }
                        if value.translation.width < -70 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) { roomSwipeOffset = 0 }
                            presentMembers()
                        } else if value.translation.width > 0 {
                            let shouldLeave = value.translation.width > 145 || value.predictedEndTranslation.width > 270
                            if shouldLeave {
                                withAnimation(.easeOut(duration: 0.2)) { roomSwipeOffset = 520 }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(190))
                                    guard !Task.isCancelled else { return }
                                    await MainActor.run { dismiss() }
                                }
                            } else {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { roomSwipeOffset = 0 }
                            }
                        }
                    }
            )
        }
        // The container owns keyboard avoidance. Its top is clamped by the
        // real safe-area inset, so it can never slide under system chrome.
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = max(0, min(360, UIScreen.main.bounds.maxY - frame.minY))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                keyboardHeight = 0
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                chatFocused = false
            }
        }
        .onChange(of: chatFocused) { _, focused in
            if focused && controlsVisible {
                withAnimation(.easeOut(duration: 0.18)) { controlsVisible = false }
            }
        }
        .onChange(of: model.wasRemovedFromRoom) { _, removed in
            if removed { dismiss() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { model.setCurrentUserID(session.profile?.userId); await model.start(loadVideo: !usesEmbeddedBrowser) }.onDisappear { model.stop() }
            .sheet(isPresented: $showTime) { SeekTimePickerSheet(initial: model.position) { model.seek($0) } }
            .sheet(isPresented: $showMembers) { MembersSheet(members: model.members, currentID: session.profile?.userId, canModerate: model.isOwner) { member, action in await model.moderate(member: member, action: action) } }
    }
    private func time(_ value: Double) -> String { let total = Int(value); if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }; return String(format: "%02d:%02d", total / 60, total % 60) }
    private var playerControls: some View {
        VStack(spacing: 7) {
            PlaybackScrubber(
                position: model.position,
                duration: model.duration,
                enabled: model.isOwner,
                commit: { model.seek($0) },
                interactionChanged: { isScrubbingPlayer = $0 }
            )
            HStack(spacing: 10) {
                playerControl("gobackward.10") { model.seek(max(0, model.position - 10)) }
                playerControl(model.isPlaying ? "pause.fill" : "play.fill", primary: true) { model.toggle() }
                playerControl("goforward.10") { model.seek(min(model.duration, model.position + 10)) }
                Spacer(minLength: 6)
                ZStack {
                    Image(systemName: copiedCode ? "checkmark" : "link")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: copyFeedbackTick)
                        .liquidCard(Circle())
                }
                .frame(width: 52, height: 48)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { copyInviteCode() })
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Скопировать код комнаты")
                .accessibilityAction { copyInviteCode() }
                Button { showTime = true } label: {
                    Text(time(model.position))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .liquidCard(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(7)
            .liquidCard(Capsule())
            .opacity(model.isOwner ? 1 : 0.62)
        }
        .padding(9)
        // Keep the controls part of the same dark glass surface as the chat.
        // The previous blue wash made this read as a separate, unrelated card.
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .liquidCard(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    private func copyInviteCode() {
        controlsHideTask?.cancel()
        let code = room.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        UIPasteboard.general.setItems([["public.utf8-plain-text": code]], options: [:])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copyFeedbackTick += 1
        let feedbackTick = copyFeedbackTick
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { copiedCode = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, feedbackTick == copyFeedbackTick else { return }
            await MainActor.run { withAnimation(.easeOut(duration: 0.22)) { copiedCode = false } }
        }
    }
    @ViewBuilder private func playerControl(_ symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(primary ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: primary ? 48 : 42, height: 42)
                .contentShape(Circle())
                .liquidCard(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isOwner)
        .accessibilityLabel(symbol.contains("pause") ? "Пауза" : symbol.contains("play") ? "Воспроизвести" : "Перемотка")
    }
    private func toggleControls() {
        controlsHideTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { controlsVisible.toggle() }
        guard controlsVisible else { return }
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(.easeOut(duration: 0.22)) { controlsVisible = false } }
        }
    }
    private func presentMembers() {
        // A sheet and an active UIKit text view must never compete for the
        // keyboard. Resign first, then present; the chat stays in place.
        chatFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.async { showMembers = true }
    }
}

private struct RoomPreviewOverlay: View {
    let room: Room
    let canDelete: Bool
    let close: () -> Void
    let delete: () async -> Void
    @State private var deleting = false
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if let url = URL(string: room.thumbnailURL), !room.thumbnailURL.isEmpty {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
                } else {
                    LinearGradient(colors: [.indigo.opacity(0.58), .mint.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Image(systemName: "play.fill").font(.title2.weight(.semibold)).padding(16).liquidCard(Circle())
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Text(room.title).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(2)
            Text("Код \(room.inviteCode)").font(.caption.monospaced()).foregroundStyle(.secondary)
            if canDelete {
                Button(role: .destructive) {
                    Task { deleting = true; await delete(); deleting = false }
                } label: {
                    Label(deleting ? "Удаление…" : "Удалить комнату", systemImage: "trash")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .disabled(deleting)
                .buttonStyle(.bordered)
                .tint(.red)
                .liquidCard(Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: 330)
        .liquidCard(RoundedRectangle(cornerRadius: 30))
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 32, height: 32).liquidCard(Circle()) }
                .buttonStyle(.plain).padding(10)
        }
        .padding(.horizontal, 30)
    }
}

struct ChatPane: View {
    let messages: [ChatMessage]; @Binding var draft: String; let send: (String) -> Void
    @FocusState private var focused: Bool
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text("Чат").font(.headline); ScrollViewReader { proxy in ScrollView { LazyVStack(spacing: 7) { ForEach(messages) { message in HStack(alignment: .top, spacing: 8) { Circle().fill(.purple.opacity(0.7)).frame(width: 28, height: 28).overlay(Text(message.nickname.prefix(1)).font(.caption.bold())); VStack(alignment: .leading, spacing: 2) { Text(message.nickname).font(.caption.bold()).foregroundStyle(.secondary); Text(message.text).font(.subheadline) }.padding(9).liquidCard(RoundedRectangle(cornerRadius: 15)); Spacer(minLength: 20) }.id(message.id) } } }.onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } } } }.frame(maxHeight: 250); HStack { TextField("Сообщение…", text: $draft, axis: .vertical).lineLimit(1...3).onSubmit { send(draft) }; Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(8).liquidCard(Capsule()) }.padding(12).liquidCard() }
}

struct VideoPlayerPlaceholder: View {
    let room: Room
    @Binding var showTime: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                AsyncImage(url: URL(string: room.thumbnailURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                Image(systemName: "play.fill")
                    .font(.system(size: 32))
                    .frame(width: 66, height: 66)
                    .liquidCard(Circle())
            }
            Slider(value: .constant(room.playback?.positionSeconds ?? 0),
                   in: 0...max(1, (room.playback?.positionSeconds ?? 0) + 1))
                .disabled(true)
            HStack {
                Button { } label: { Image(systemName: "gobackward.10") }
                Button { } label: { Image(systemName: "play.fill") }
                Button { } label: { Image(systemName: "goforward.10") }
                Spacer()
                Button { showTime = true } label: { Text("00:00") }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .liquidCard()
        .sheet(isPresented: $showTime) { TimePickerSheet() }
    }
}

struct TimePickerSheet: View { @Environment(\.dismiss) private var dismiss; @State private var minute = 0; @State private var second = 0
    var body: some View { VStack(spacing: 22) { Text("Перейти к таймкоду").font(.headline); HStack { Picker("Мин", selection: $minute) { ForEach(0..<180, id: \.self) { Text("\($0) мин") } }; Picker("Сек", selection: $second) { ForEach(0..<60, id: \.self) { Text("\($0) сек") } } }.pickerStyle(.wheel); Button("Перейти") { dismiss() }.buttonStyle(.borderedProminent) }.padding().presentationDetents([.height(330)]).presentationBackground(.ultraThinMaterial) }
}

struct SeekTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minute: Int
    @State private var second: Int
    let select: (Double) -> Void
    init(initial: Double, select: @escaping (Double) -> Void) {
        _minute = State(initialValue: Int(initial) / 60)
        _second = State(initialValue: Int(initial) % 60)
        self.select = select
    }
    var body: some View {
        VStack(spacing: 22) {
            Text("Перейти к таймкоду").font(.headline)
            HStack {
                Picker("Мин", selection: $minute) { ForEach(0..<600, id: \.self) { Text("\($0) мин") } }
                Picker("Сек", selection: $second) { ForEach(0..<60, id: \.self) { Text("\($0) сек") } }
            }.pickerStyle(.wheel)
            Button("Перейти") { select(Double(minute * 60 + second)); dismiss() }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 18).padding(.vertical, 14).presentationDetents([.height(286)]).presentationBackground(.ultraThinMaterial).presentationCornerRadius(30)
    }
}

struct MembersSheet: View {
    let members: [RoomMember]
    let currentID: Int?
    let canModerate: Bool
    let moderate: (RoomMember, String) async -> Void
    @State private var selected: RoomMember?
    var body: some View {
        ZStack {
            AcrylicBackground()
            VStack(alignment: .leading, spacing: 12) {
                Text("Участники").font(.title2.bold())
                ForEach(members) { member in
                    HStack(spacing: 11) {
                        AvatarView(dataURL: member.avatarDataURL, name: member.nickname, size: 46)
                        VStack(alignment: .leading) {
                            HStack { Text(member.nickname).bold(); if member.isOwner { Image(systemName: "crown.fill").font(.caption).foregroundStyle(.yellow) }; if member.userId == currentID { Text("Вы").font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).liquidCard(Capsule()) } }
                            Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); if member.isMuted { Image(systemName: "speaker.slash.fill").font(.caption).foregroundStyle(.orange) }; Circle().fill(member.isOnline ? .green : .gray).frame(width: 8, height: 8)
                    }.padding(9).liquidCard(RoundedRectangle(cornerRadius: 17))
                        .contentShape(RoundedRectangle(cornerRadius: 17))
                        .onLongPressGesture { guard canModerate && !member.isOwner else { return }; withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selected = member } }
                }; Spacer()
            }
            .padding(20)
            .blur(radius: selected == nil ? 0 : 13)
            .scaleEffect(selected == nil ? 1 : 0.985)
            .allowsHitTesting(selected == nil)

            if let member = selected {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeModerationMenu() }
                    .transition(.opacity)
                MemberModerationOverlay(member: member) { action in
                    closeModerationMenu()
                    Task { await moderate(member, action) }
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: selected?.id)
        .presentationDetents([.medium, .large]).presentationBackground(.clear)
    }

    private func closeModerationMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { selected = nil }
    }
}

private struct MemberModerationOverlay: View {
    let member: RoomMember
    let action: (String) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AvatarView(dataURL: member.avatarDataURL, name: member.nickname, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.nickname).font(.headline)
                    Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(15)

            Divider().overlay(.white.opacity(0.08))

            VStack(spacing: 0) {
                moderationButton("speaker.slash.fill", member.isMuted ? "Снять заглушение" : "Заглушить", "mute", color: .orange)
                menuDivider
                moderationButton("rectangle.portrait.and.arrow.right", "Выгнать", "kick", color: .primary)
                menuDivider
                moderationButton("crown.fill", "Передать управление", "transfer", color: .yellow)
                menuDivider
                moderationButton("person.crop.circle.badge.xmark", "Заблокировать", "ban", color: .red)
            }
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.38), radius: 28, y: 16)
    }
    private func moderationButton(_ icon: String, _ title: String, _ key: String, color: Color) -> some View {
        Button { action(key) } label: {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: 23)
                Text(title).font(.body.weight(.medium))
                Spacer()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var menuDivider: some View { Divider().padding(.leading, 52).overlay(.white.opacity(0.07)) }
}

struct BarePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView { PlayerLayerView(player: player) }
    func updateUIView(_ view: PlayerLayerView, context: Context) { view.playerLayer.player = player }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    init(player: AVPlayer) { super.init(frame: .zero); playerLayer.player = player; playerLayer.videoGravity = .resizeAspect; backgroundColor = .black }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct PlaybackScrubber: View {
    let position: Double; let duration: Double; let enabled: Bool; let commit: (Double) -> Void
    var interactionChanged: (Bool) -> Void = { _ in }
    @State private var dragging: Double?
    private var display: Double { dragging ?? position }
    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let ratio = min(1, max(0, display / max(1, duration)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.07))
                    .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 0.7))
                    .frame(height: 5)
                Capsule()
                    .fill(.white.opacity(0.34))
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.6))
                    .frame(width: max(10, width * ratio), height: 5)
                Circle()
                    .fill(.white.opacity(0.10))
                    .overlay(Circle().stroke(.white.opacity(0.48), lineWidth: 0.8))
                    .frame(width: 20, height: 20)
                    .liquidCard(Circle())
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                    .offset(x: max(0, min(width - 20, width * ratio - 10)))
                if let dragging { Text(scrubTime(dragging)).font(.caption2.monospacedDigit().weight(.bold)).padding(.horizontal, 8).padding(.vertical, 5).liquidCard(Capsule()).offset(x: max(0, min(width - 70, width * ratio - 35)), y: -31).transition(.opacity.combined(with: .scale)) }
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard enabled else { return }
                        interactionChanged(true)
                        dragging = min(duration, max(0, duration * value.location.x / width))
                    }
                    .onEnded { _ in
                        defer {
                            dragging = nil
                            interactionChanged(false)
                        }
                        if let value = dragging { commit(value) }
                    }
            )
        }.frame(height: 26).padding(.horizontal, 10).padding(.vertical, 5).liquidCard(Capsule()).opacity(enabled ? 1 : 0.58)
    }
    private func scrubTime(_ seconds: Double) -> String { let total = Int(seconds); return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60) }
}

struct NativeChatPane: View {
    let messages: [ChatMessage]
    let currentUserID: Int?
    @Binding var draft: String
    @Binding var focused: Bool
    let isMuted: Bool
    let send: (String, String) -> Void
    let react: (Int, String) -> Void
    // UIKit owns first-responder state for PersistentChatTextField. Using
    // FocusState without a SwiftUI `.focused` attachment makes SwiftUI reset
    // it to false, which immediately dismisses the keyboard after any tap.
    @State private var inputFocused = false
    @State private var inputHeight: CGFloat = 38
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingPhoto: PendingChatPhoto?
    @State private var sticksToBottom = true
    @State private var didInitialScroll = false
    @State private var forceScrollOnNextMessage = false
    @State private var latestDistanceToBottom: CGFloat = 0
    private let quickReactions = ["👍", "❤️", "😂", "🔥", "😮", "👏", "😭", "🎬", "🍿", "✨"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            NativeMessageBubble(message: message, isMine: message.authorId == currentUserID, react: react, quickReactions: quickReactions)
                                .padding(.bottom, message.id == messages.last?.id ? 14 : 0)
                                .id(message.id)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                    .scrollTargetLayout()
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = false; inputFocused = false }
                .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                    max(0, geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y)
                }, action: { _, distanceToBottom in
                    // A keyboard/control resize also changes this distance, but it
                    // is not a user scroll. Keep it only as a measurement and
                    // commit the reading position when scrolling actually ends.
                    latestDistanceToBottom = distanceToBottom
                })
                .onScrollPhaseChange { _, phase in
                    guard !phase.isScrolling else { return }
                    sticksToBottom = latestDistanceToBottom < 44
                }
                .onChange(of: messages.last?.id) { oldID, newID in
                    guard newID != nil, newID != oldID else { return }
                    if forceScrollOnNextMessage || !didInitialScroll || sticksToBottom {
                        scrollToLatestMessage(proxy, animated: didInitialScroll)
                        didInitialScroll = true
                        forceScrollOnNextMessage = false
                    }
                }
                .onAppear {
                    guard !didInitialScroll, messages.last != nil else { return }
                    DispatchQueue.main.async {
                        scrollToLatestMessage(proxy, animated: false)
                        didInitialScroll = true
                    }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .liquidCard(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isMuted)
                .opacity(isMuted ? 0.42 : 1)
                .onChange(of: selectedPhoto) { _, item in Task { await preparePhoto(item) } }

                HStack(alignment: .bottom, spacing: 7) {
                    PersistentChatTextField(
                        text: $draft,
                        isFocused: Binding(get: { inputFocused }, set: { inputFocused = $0 }),
                        height: $inputHeight,
                        isEnabled: !isMuted,
                        placeholder: isMuted ? "Вас заглушили" : "Сообщение…",
                        onSubmit: submit
                    )
                        .frame(height: inputHeight)
                        .animation(.easeOut(duration: 0.14), value: inputHeight)
                        .onChange(of: inputFocused) { _, value in focused = value }
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                        .onTapGesture { submit() }
                        .allowsHitTesting(!isMuted)
                        .opacity(isMuted ? 0.42 : 1)
                        .accessibilityAddTraits(.isButton)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .liquidCard(RoundedRectangle(cornerRadius: 25, style: .continuous))
            }
            // Keep the composer in the unified chat surface.  The old negative
            // offset could make it protrude beyond the lower rounded edge.
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        // RoomView owns the single continuous glass surface around video and
        // chat. A second card here created the visible seam and double corners.
        // RoomView shortens the unified surface to the keyboard edge. No
        // keyboard-sized padding belongs inside the chat: it created the large
        // empty rectangle below the composer.
        .animation(.easeOut(duration: 0.18), value: inputFocused)
        .onChange(of: focused) { _, roomFocused in
            // RoomView can explicitly close the keyboard before presenting
            // participants; keep UIKit and SwiftUI focus in sync.
            if !roomFocused { inputFocused = false }
        }
        .onChange(of: isMuted) { _, muted in
            guard muted else { return }
            draft = ""
            focused = false
            inputFocused = false
        }
        .task {
            FluentEmojiCache.shared.warmCommonEmoji()
            messages.forEach { FluentEmojiCache.shared.prefetch(in: $0.text) }
        }
        .onChange(of: draft) { _, value in FluentEmojiCache.shared.prefetch(in: value) }
        .onChange(of: messages.count) { _, _ in
            if let text = messages.last?.text { FluentEmojiCache.shared.prefetch(in: text) }
        }
        .sheet(item: $pendingPhoto) { photo in
            ChatPhotoConfirmation(photo: photo) {
                pendingPhoto = nil
            } send: {
                sticksToBottom = true
                forceScrollOnNextMessage = true
                send("", photo.dataURL)
                pendingPhoto = nil
            }
        }
    }
    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sticksToBottom = true
        forceScrollOnNextMessage = true
        send(text, "")
        draft = ""
    }
    private func preparePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let dataURL = await Task.detached(priority: .userInitiated, operation: {
            Self.chatPhotoDataURL(from: data)
        }).value else { return }
        let photo = PendingChatPhoto(dataURL: dataURL)
        await MainActor.run { pendingPhoto = photo; selectedPhoto = nil }
    }
    nonisolated private static func chatPhotoDataURL(from source: Data) -> String? {
        guard let image = UIImage(data: source) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 1_440 / max(longestSide, 1))
        let target = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard var jpeg = normalized.jpegData(compressionQuality: 0.8) else { return nil }
        // The backend accepts a 2.8 MB data URL. Keep enough room for Base64
        // expansion and the websocket envelope even for very detailed photos.
        if jpeg.count > 1_850_000, let smaller = normalized.jpegData(compressionQuality: 0.56) { jpeg = smaller }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
    private func scrollToLatestMessage(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(lastID, anchor: .bottom) }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(lastID, anchor: .bottom) }
        }
    }
}

private struct PendingChatPhoto: Identifiable {
    let id = UUID()
    let dataURL: String
}

private struct ChatPhotoConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let photo: PendingChatPhoto
    let cancel: () -> Void
    let send: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("Отправить фотографию?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            DataURLImage(dataURL: photo.dataURL, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            HStack(spacing: 10) {
                Button {
                    cancel()
                    dismiss()
                } label: {
                    Text("Отмена").frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
                }
                .liquidCard(Capsule())
                Button {
                    send()
                    dismiss()
                } label: {
                    Label("Отправить", systemImage: "arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                }
                .liquidCard(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .presentationDetents([.fraction(0.62)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(30)
    }
}

/// A one-line `UITextView` intercepts Return before UIKit can end editing.
/// Both the software-keyboard Send key and the in-app button therefore call
/// the same submit closure without ever dropping first-responder status.
private struct PersistentChatTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var height: CGFloat
    let isEnabled: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> ChatTextView {
        let view = ChatTextView()
        view.delegate = context.coordinator
        view.textColor = .label
        view.tintColor = .systemTeal
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = true
        view.autocorrectionType = .yes
        view.backgroundColor = .clear
        view.isEditable = isEnabled
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.maximumNumberOfLines = 5
        view.textContainer.lineBreakMode = .byWordWrapping
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }
    func updateUIView(_ field: ChatTextView, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.isEditable = isEnabled
        field.placeholderText = placeholder
        field.updatePlaceholder()
        DispatchQueue.main.async {
            let measured = field.refreshLayout()
            if abs(context.coordinator.parent.height - measured) > 0.5 {
                context.coordinator.parent.height = measured
            }
        }
        if isFocused && isEnabled && !field.isFirstResponder { field.becomeFirstResponder() }
        if !isFocused && field.isFirstResponder { field.resignFirstResponder() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChatTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? max(1, uiView.bounds.width), height: height)
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PersistentChatTextField
        init(parent: PersistentChatTextField) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView as? ChatTextView)?.updatePlaceholder()
            if let field = textView as? ChatTextView {
                let measured = field.refreshLayout()
                if abs(parent.height - measured) > 0.5 { parent.height = measured }
            }
        }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFocused = false }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            parent.isFocused = true
            parent.onSubmit()
            return false
        }
    }
    final class ChatTextView: UITextView {
        private let placeholderLabel = UILabel()
        var placeholderText = "Сообщение…"
        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            placeholderLabel.text = placeholderText
            placeholderLabel.textColor = .placeholderText
            placeholderLabel.font = .preferredFont(forTextStyle: .body)
            placeholderLabel.adjustsFontForContentSizeCategory = true
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func updatePlaceholder() {
            placeholderLabel.text = placeholderText
            placeholderLabel.isHidden = !text.isEmpty
        }
        @discardableResult
        func refreshLayout() -> CGFloat {
            guard bounds.width > 1 else { return 38 }
            let availableWidth = bounds.width
            let requiredHeight = sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude)).height
            let fittedHeight = min(112, max(38, ceil(requiredHeight)))
            let shouldScroll = requiredHeight > 112
            if isScrollEnabled != shouldScroll { isScrollEnabled = shouldScroll }
            if shouldScroll {
                let bottom = max(-adjustedContentInset.top, contentSize.height - bounds.height + adjustedContentInset.bottom)
                setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
            invalidateIntrinsicContentSize()
            return fittedHeight
        }
    }
}

struct NativeMessageBubble: View {
    let message: ChatMessage; let isMine: Bool; let react: (Int, String) -> Void; let quickReactions: [String]
    private var containsEmoji: Bool {
        message.text.unicodeScalars.contains { scalar in
            (0x1F000...0x1FAFF).contains(Int(scalar.value)) || (0x2600...0x27FF).contains(Int(scalar.value))
        }
    }
    // Bubbles use their content length, not the whole chat width. This keeps a
    // one-word reply compact while giving a real sentence enough readable space.
    private var bubbleWidth: CGFloat {
        if !message.imageDataURL.isEmpty { return 230 }
        if emojiOnly.count == 1 { return 72 }
        if emojiOnly.count == 2 { return 112 }
        let count = message.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        switch count {
        case 0...5: return 88
        case 6...12: return 128
        case 13...24: return 184
        case 25...42: return 218
        default: return 238
        }
    }
    private var emojiOnly: [String] {
        let characters = message.text.filter { !$0.isWhitespace }
        guard !characters.isEmpty, characters.count <= 2 else { return [] }
        guard characters.allSatisfy({ character in
            String(character).unicodeScalars.contains {
                (0x1F000...0x1FAFF).contains(Int($0.value)) || (0x2600...0x27FF).contains(Int($0.value))
            }
        }) else { return [] }
        return characters.map { String($0) }
    }
    @ViewBuilder private var messageContent: some View {
        if !message.text.isEmpty {
            if !emojiOnly.isEmpty {
                HStack(spacing: 4) {
                    ForEach(emojiOnly, id: \.self) { emoji in
                        FluentEmojiGlyph(emoji, size: emojiOnly.count == 1 ? 46 : 37)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 1)
            } else if containsEmoji {
                FluentInlineText(message.text).multilineTextAlignment(.leading).layoutPriority(1)
            } else {
                Text(message.text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            messageContent
            if !message.imageDataURL.isEmpty { DataURLImage(dataURL: message.imageDataURL).frame(maxWidth: 210, minHeight: 80, maxHeight: 150).clipShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { } }
            if !message.reactions.isEmpty { HStack(spacing: 5) { ForEach(message.reactions) { item in Button { react(message.id, item.emoji) } label: { HStack(spacing: 3) { FluentEmojiGlyph(item.emoji, size: 16); Text("\(item.count)") }.font(.caption2).padding(.horizontal, 7).padding(.vertical, 3).background(item.reacted ? Color.teal.opacity(0.38) : Color.white.opacity(0.08), in: Capsule()) }.buttonStyle(.plain) } } }
        }
        .padding(10)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(isMine ? Color.indigo.opacity(0.28) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .contextMenu { ForEach(quickReactions, id: \.self) { emoji in Button(emoji) { react(message.id, emoji) } } }
    }
    var body: some View {
        if message.isSystem {
            Text(message.text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 6).liquidCard(Capsule()).frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 9) {
                if !isMine { AvatarView(dataURL: message.avatarDataURL, name: message.nickname, size: 42) }
                if isMine { Spacer(minLength: 0) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    Text(message.nickname).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
                    bubble.frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
                }
                .frame(width: 238, alignment: isMine ? .trailing : .leading)
                if isMine { AvatarView(dataURL: message.avatarDataURL, name: message.nickname, size: 42) } else { Spacer(minLength: 0) }
            }
        }
    }
}

struct LiquidAuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var register = false
    @State private var nickname = ""
    @State private var username = ""
    @State private var password = ""
    @State private var availability: Availability = .idle
    @State private var error = ""
    @State private var loading = false
    enum Availability { case idle, invalid, checking, available, taken }
    private var usernameValid: Bool { username.range(of: "^[A-Za-z][A-Za-z0-9_]{2,29}$", options: .regularExpression) != nil }
    var body: some View {
        ZStack { AcrylicBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 48)
                    Image(systemName: "play.fill").font(.system(size: 30, weight: .bold)).frame(width: 76, height: 76).liquidCard(RoundedRectangle(cornerRadius: 25))
                    Text(register ? "Создать аккаунт" : "Войти").font(.system(size: 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center).contentTransition(.opacity)
                    AuthModeSwitcher(register: $register) {
                        error = ""
                        availability = .idle
                    }
                    Text(register ? "Укажи данные для нового аккаунта" : "Введи username и пароль").font(.subheadline).foregroundStyle(.secondary).contentTransition(.opacity)
                    VStack(spacing: 11) {
                        if register {
                            GlassField(icon: "person.text.rectangle", title: "Nickname", text: $nickname)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        GlassField(icon: "at", title: "Username", text: $username).onChange(of: username) { _, value in Task { await validate(value) } }
                        if register && !username.isEmpty { AuthProfilePreview(nickname: nickname, username: username, availability: availability) }
                        GlassSecureField(title: "Password", text: $password)
                        if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { Task { await submit() } } label: {
                            HStack(spacing: 9) {
                                if loading { ProgressView().tint(.white).controlSize(.small) }
                                Text(register ? "Создать" : "Войти")
                                Image(systemName: "arrow.right").font(.subheadline.weight(.bold))
                            }
                            .font(.body.weight(.semibold))
                            .frame(width: 188, height: 42)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.055), in: Capsule())
                        .liquidCard(Capsule())
                        .frame(maxWidth: .infinity)
                        .disabled(loading)
                    }
                    .padding(15)
                    .liquidCard(RoundedRectangle(cornerRadius: 30))
                    .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: register)
                    Spacer(minLength: 20)
                }.frame(maxWidth: 440).padding(22)
            }
        }
    }
    private func validate(_ value: String) async { guard register else { withAnimation { availability = .idle }; return }; guard usernameValid else { withAnimation(.easeOut(duration: 0.2)) { availability = .invalid }; return }; withAnimation(.easeOut(duration: 0.2)) { availability = .checking }; try? await Task.sleep(for: .milliseconds(250)); guard username == value else { return }; let isAvailable = (try? await session.api.usernameAvailable(value)) == true; withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { availability = isAvailable ? .available : .taken } }
    private func submit() async { error = ""; guard !username.isEmpty, !password.isEmpty else { error = "Заполни username и пароль"; return }; if register && (!usernameValid || nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2) { error = "Проверь nickname и username"; return }; loading = true; defer { loading = false }; do { if register { try await session.register(nickname: nickname, username: username, password: password) } else { try await session.login(username: username, password: password) } } catch { self.error = error.localizedDescription } }
}

/// Compact login/register control. The highlight follows the finger and snaps
/// to the closest mode on release, so switching does not feel like a hard tap.
private struct AuthModeSwitcher: View {
    @Binding var register: Bool
    var didChangeMode: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    // Keep the drag anchored to the mode from which the finger started. The
    // binding itself can then change while the finger is still down without
    // making the thumb jump under it.
    @State private var dragStartMode: Bool?

    private let height: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let side = width / 2
            let startMode = dragStartMode ?? register
            let restingCenter = startMode ? side * 1.5 : side * 0.5
            let draggedCenter = min(width - side / 2, max(side / 2, restingCenter + dragOffset))
            let selectionShape = Capsule()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.13))
                selectionShape
                    .fill(.white.opacity(0.14))
                    .frame(width: side - 4, height: height - 4)
                    .overlay(selectionShape.stroke(.white.opacity(0.15), lineWidth: 0.65))
                    .offset(x: draggedCenter - (side - 4) / 2)
                HStack(spacing: 0) {
                    modeButton("Login", selected: !register) { setMode(false) }
                    modeButton("Register", selected: register) { setMode(true) }
                }
            }
            .contentShape(Capsule())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if !isDragging {
                            dragStartMode = register
                            isDragging = true
                        }
                        dragOffset = value.translation.width
                        let startCenter = (dragStartMode ?? register) ? side * 1.5 : side * 0.5
                        let candidate = startCenter + value.translation.width >= width / 2
                        // Change immediately at the midpoint. Keeping the
                        // finger down and moving back reverses this live.
                        if candidate != register {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { register = candidate }
                            didChangeMode()
                        }
                    }
                    .onEnded { value in
                        let startCenter = (dragStartMode ?? register) ? side * 1.5 : side * 0.5
                        let finalCenter = startCenter + value.predictedEndTranslation.width * 0.22 + value.translation.width
                        let finalMode = finalCenter >= width / 2
                        if finalMode != register {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.58)
                            register = finalMode
                            didChangeMode()
                        }
                        // Resetting the offset and anchor in one spring is what
                        // makes the thumb visibly settle into its final slot.
                        withAnimation(.interpolatingSpring(stiffness: 360, damping: 29)) {
                            dragOffset = 0
                            dragStartMode = nil
                        }
                        isDragging = false
                    }
            )
        }
        .frame(width: 160, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Режим входа")
    }

    @ViewBuilder private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setMode(_ next: Bool) {
        guard next != register else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.72)
        withAnimation(.interpolatingSpring(stiffness: 360, damping: 29)) { register = next }
        didChangeMode()
    }
}

struct GlassField: View {
    let icon: String; let title: String; @Binding var text: String
    var body: some View { HStack(spacing: 11) { Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18); TextField(title, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled() }.padding(14).liquidCard(RoundedRectangle(cornerRadius: 17)) }
}
struct GlassSecureField: View {
    let title: String; @Binding var text: String
    var body: some View { HStack(spacing: 11) { Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 18); SecureField(title, text: $text) }.padding(14).liquidCard(RoundedRectangle(cornerRadius: 17)) }
}
struct AuthProfilePreview: View {
    let nickname: String; let username: String; let availability: LiquidAuthView.Availability
    private var label: String { switch availability { case .available: return "Available"; case .taken: return "Taken"; case .invalid: return "Use A–Z, 0–9, _"; case .checking: return "Checking…"; case .idle: return "" } }
    private var color: Color { switch availability { case .available: return .green; case .taken: return .red; case .invalid: return .orange; default: return .secondary } }
    var body: some View { HStack(spacing: 10) { Circle().fill(LinearGradient(colors: [.indigo.opacity(0.85), .mint.opacity(0.58)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 43, height: 43).overlay(Text((nickname.isEmpty ? username : nickname).prefix(1)).font(.headline.bold())); VStack(alignment: .leading, spacing: 2) { Text(nickname.isEmpty ? "Your nickname" : nickname).font(.subheadline.bold()); Text("@\(username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color) }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 18)).transition(.opacity.combined(with: .move(edge: .top))).animation(.spring(response: 0.35), value: username) }
}

struct DataURLImage: View {
    let dataURL: String
    let contentMode: ContentMode
    init(dataURL: String, contentMode: ContentMode = .fill) {
        self.dataURL = dataURL
        self.contentMode = contentMode
    }
    var body: some View {
        if let comma = dataURL.firstIndex(of: ","), let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])), let image = UIImage(data: data) { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
        else { Color.white.opacity(0.08) }
    }
}

struct AvatarView: View {
    let dataURL: String; let name: String; let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.52, blue: 0.56), Color(red: 0.16, green: 0.28, blue: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if !dataURL.isEmpty {
                DataURLImage(dataURL: dataURL).clipShape(Circle()).padding(2)
            } else {
                Text(name.prefix(1)).font(.system(size: max(12, size * 0.38), weight: .bold, design: .rounded))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.26), radius: 7, y: 3)
    }
}

struct RoomCard: View {
    let room: Room
    var body: some View {
        HStack(spacing: 13) {
            ZStack { if !room.thumbnailURL.isEmpty { AsyncImage(url: URL(string: room.thumbnailURL)) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) } } else { LinearGradient(colors: [.indigo.opacity(0.58), .mint.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing) }; Image(systemName: "play.fill").font(.headline).padding(11).liquidCard(Circle()) }.frame(width: 92, height: 64).clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 5) { Text(room.title).font(.headline).lineLimit(2); Text("\(room.membersCount) участников · \(room.inviteCode)").font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 22))
    }
}

struct PusheenTabs: View {
    var body: some View { TabView { HomeView().tabItem { Label("Комнаты", systemImage: "play.rectangle.fill") }; FriendsGlassView().tabItem { Label("Друзья", systemImage: "person.2.fill") }; ProfileGlassView().tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") } }.tint(.indigo) }
}

struct LegacyFriendsGlassView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var expanded = false; @State private var query = ""; @State private var people: [FriendProfile] = []
    var body: some View { ZStack { AcrylicBackground(); VStack(spacing: 16) { HStack { Text("Друзья").font(.largeTitle.bold()); Spacer(); Button { withAnimation(.spring(response: 0.35)) { expanded.toggle() }; if expanded { Task { await search() } } } label: { Image(systemName: expanded ? "xmark" : "magnifyingglass").frame(width: 42, height: 42).liquidCard(Circle()) }.buttonStyle(.plain) }; if expanded { HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Найти по @username", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: query) { _, _ in Task { await search() } } }.padding(12).liquidCard(Capsule()).transition(.opacity.combined(with: .move(edge: .top))) }; ScrollView { LazyVStack(spacing: 9) { ForEach(people) { person in HStack(spacing: 11) { Circle().fill(.purple.opacity(0.7)).frame(width: 48, height: 48).overlay(Text(person.nickname.prefix(1)).bold()); VStack(alignment: .leading, spacing: 3) { Text(person.nickname).bold(); Text("@\(person.username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(person.isFriend ? "Добавлен" : "Добавить") { Task { try? await session.api.addFriend(username: person.username); await search() } }.buttonStyle(.bordered) }.padding(11).liquidCard(RoundedRectangle(cornerRadius: 20)) } } }; Spacer() }.padding(20) } }
    private func search() async { people = (try? await session.api.friends(query: query)) ?? [] }
}

struct ProfileGlassView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var edit = false
    @State private var avatarPicker: PhotosPickerItem?
    @State private var friends: [FriendProfile] = []
    var body: some View {
        ZStack {
            AcrylicBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Spacer(minLength: 22)
                    PhotosPicker(selection: $avatarPicker, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(dataURL: session.profile?.avatarDataUrl ?? "", name: session.profile?.nickname ?? "?", size: 112)
                            Image(systemName: "camera.fill").font(.caption.weight(.bold)).padding(8).liquidCard(Circle())
                        }
                    }.onChange(of: avatarPicker) { _, item in Task { await updateAvatar(item) } }
                    if !edit {
                        VStack(spacing: 3) {
                            Text(session.profile?.nickname ?? "").font(.title2.bold())
                            Text("@\(session.profile?.username ?? "")").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { edit = true } }
                    }
                    if edit { ProfileInlineEditor(close: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { edit = false } }).transition(.opacity.combined(with: .move(edge: .top))) }
                    ViewingInsightsPager(stats: session.viewingStats, friends: friends)
                    Button("Выйти") { session.logout() }.buttonStyle(.bordered).tint(.red).padding(.top, 8)
                }.padding(20)
            }
        }.onAppear {
            Task {
                await session.refreshViewingStats()
                friends = (try? await session.api.friends()) ?? []
            }
        }
    }
    private func updateAvatar(_ item: PhotosPickerItem?) async { guard let item, let data = try? await item.loadTransferable(type: Data.self), let profile = session.profile else { return }; let value = "data:image/jpeg;base64," + data.base64EncodedString(); session.profile = try? await session.api.updateProfile(nickname: profile.nickname, username: profile.username, avatar: value) }
}

private struct ViewingInsightsPager: View {
    let stats: ViewingStats?
    let friends: [FriendProfile]
    @State private var page = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private var pages: [AnyView] {
        [
            AnyView(GenreOnlyCard(stats: stats)),
            AnyView(ViewingHeatmapCard(daily: stats?.dailySeconds ?? [:])),
            AnyView(SharedWatchingCard(companion: stats?.topCompanion, fallbackFriends: friends)),
        ]
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let isHorizontalDrag = abs(dragTranslation) > 0
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        pages[index]
                            .frame(width: width, height: proxy.size.height)
                    }
                }
                // A real interactive offset fixes the old UIPageViewController
                // bounce: returning the finger right now follows it continuously
                // instead of waiting for the system pager to settle first.
                .offset(x: -CGFloat(page) * width + dragTranslation)
                .animation(isHorizontalDrag ? nil : .interactiveSpring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.06), value: page)
                .frame(width: width, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .updating($dragTranslation) { value, state, _ in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let proposed = value.translation.width
                            let atLeadingEdge = page == 0 && proposed > 0
                            let atTrailingEdge = page == pages.count - 1 && proposed < 0
                            // Keep a small elastic edge only; it cannot make a
                            // reverse swipe appear stuck at either end.
                            state = (atLeadingEdge || atTrailingEdge) ? proposed * 0.16 : proposed
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let predicted = value.predictedEndTranslation.width
                            let threshold = width * 0.18
                            var next = page
                            if predicted < -threshold { next += 1 }
                            if predicted > threshold { next -= 1 }
                            next = min(max(next, 0), pages.count - 1)
                            guard next != page else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.82)
                            withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.06)) {
                                page = next
                            }
                        }
                )
            }
            .frame(height: 278)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.primary.opacity(0.72) : Color.white.opacity(0.16))
                        .frame(width: index == page ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: page)
                }
            }
        }
        .padding(15)
        .liquidCard(RoundedRectangle(cornerRadius: 26))
        .accessibilityLabel("Страницы статистики")
    }
}

private struct GenreOnlyCard: View {
    let stats: ViewingStats?
    @State private var selectedGenreID: String?

    var body: some View {
        let genres = stats?.genres ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Жанры").font(.headline)
            if genres.isEmpty {
                ContentUnavailableView("Жанров пока нет", systemImage: "film", description: Text("После первого фильма здесь появятся твои предпочтения."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GenrePreferenceOrb(genres: genres, selectedGenreID: $selectedGenreID)
                    .frame(width: 176, height: 176)
                    .frame(maxWidth: .infinity)
                GenreLegend(genres: genres, selectedGenreID: $selectedGenreID)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selectedGenreID = nil } }
        .onAppear { selectedGenreID = nil }
    }
}

private struct ViewingHeatmapCard: View {
    let daily: [String: Int]
    private let calendar = Calendar.current
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLL"
        return formatter
    }()
    private static let detailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()
    @State private var selectedDay: Date?
    @State private var visibleMonths = 3
    @State private var pinchScale: CGFloat = 1

    private var today: Date { calendar.startOfDay(for: Date()) }
    private var currentMonthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: today)
        return calendar.date(from: components) ?? today
    }

    private var visibleStart: Date {
        calendar.date(byAdding: .month, value: -(visibleMonths - 1), to: currentMonthStart) ?? currentMonthStart
    }

    // One uninterrupted chronological data set removes the artificial holes
    // that appeared at the boundary of two separately rendered months.
    // Its first day is always the first day of the first labelled month and
    // its last day is today, so neither April under "May" nor future cells can
    // enter the grid.
    private var visibleDays: [Date] {
        let dayCount = max(1, (calendar.dateComponents([.day], from: visibleStart, to: today).day ?? 0) + 1)
        return (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: visibleStart)
        }
    }

    private var columns: [[Date]] {
        // Capture this computed range once. Accessing visibleDays from inside
        // every nested loop used to rebuild the whole range for every tile.
        let days = visibleDays
        if visibleMonths == 1 {
            let columnCount = min(7, max(1, days.count))
            let rowCount = max(1, Int(ceil(Double(days.count) / Double(columnCount))))
            return (0..<columnCount).map { column in
                (0..<rowCount).compactMap { row in
                    let index = row * columnCount + column
                    return index < days.count ? days[index] : nil
                }
            }
        }

        let rowCount = 7
        let columnCount = max(1, Int(ceil(Double(days.count) / Double(rowCount))))
        return (0..<columnCount).map { column in
            (0..<rowCount).compactMap { row in
                let index = column * rowCount + row
                return index < days.count ? days[index] : nil
            }
        }
    }

    private var monthLabels: [String] {
        return (0..<visibleMonths).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: visibleStart) else { return nil }
            return Self.monthFormatter.string(from: month).replacingOccurrences(of: ".", with: "")
        }
    }

    var body: some View {
        // Keep a single immutable layout snapshot for this SwiftUI render.
        let renderedColumns = columns
        let renderedMonthLabels = monthLabels
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Активность").font(.headline)
                    Text(visibleMonths == 1 ? "Последний месяц" : "Последние 3 месяца")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(selectedDay.map(activityDetail(for:)) ?? "Нажми на день, чтобы увидеть дату и время.")
                .font(.caption.weight(.medium))
                .foregroundStyle(selectedDay == nil ? Color.secondary : Color.cyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            GeometryReader { proxy in
                let spacing: CGFloat = visibleMonths == 1 ? 6 : 3
                let totalGaps = CGFloat(max(0, renderedColumns.count - 1)) * spacing
                let fitted = (proxy.size.width - totalGaps) / CGFloat(max(1, renderedColumns.count))
                let labelAllowance: CGFloat = 23
                let actualRows = renderedColumns.map(\.count).max() ?? 1
                let rowCount = CGFloat(actualRows)
                let verticalFit = max(8, (proxy.size.height - labelAllowance - (rowCount - 1) * spacing) / rowCount)
                let tile = min(visibleMonths == 1 ? 30 : 20, fitted, verticalFit)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(renderedColumns.indices, id: \.self) { columnIndex in
                            VStack(spacing: spacing) {
                                ForEach(renderedColumns[columnIndex], id: \.self) { day in
                                    RoundedRectangle(cornerRadius: max(3, tile * 0.25), style: .continuous)
                                        .fill(color(for: day))
                                        .frame(width: tile, height: tile)
                                        .overlay {
                                            if let selectedDay, calendar.isDate(day, inSameDayAs: selectedDay) {
                                                RoundedRectangle(cornerRadius: max(3, tile * 0.25), style: .continuous)
                                                    .stroke(.white.opacity(0.94), lineWidth: 1.8)
                                                    .shadow(color: .cyan.opacity(0.8), radius: 6)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            guard selectedDay.map({ !calendar.isDate($0, inSameDayAs: day) }) ?? true else { return }
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { selectedDay = day }
                                        }
                                }
                            }
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(renderedMonthLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(width: CGFloat(renderedColumns.count) * tile + totalGaps, height: 14)
                }
                .scaleEffect(pinchScale, anchor: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            // The parent statistics page is 278pt tall. Keeping the heatmap
            // inside this budget prevents the current-month label from being
            // clipped below the page in the zoomed state.
            .frame(height: 166)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .simultaneousGesture(heatmapMagnification)
    }

    private func color(for day: Date) -> Color {
        let value = daily[dayKey(for: day)] ?? 0
        guard value > 0 else { return .white.opacity(0.10) }
        // Use an absolute time scale instead of comparing a day with the
        // current maximum. A short session stays subtle and translucent;
        // three hours and above reaches the clear light-cyan level.
        let threeHours = 3.0 * 60.0 * 60.0
        let progress = min(1, Double(value) / threeHours)
        return Color.cyan.opacity(0.12 + 0.68 * progress)
    }

    private func dayKey(for day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private var heatmapMagnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                pinchScale = min(1.16, max(0.86, value))
            }
            .onEnded { value in
                let next: Int
                if value > 1.04 {
                    next = 1
                } else if value < 0.96 {
                    next = 3
                } else {
                    next = visibleMonths
                }
                if next != visibleMonths {
                    // A firm, single confirmation makes zoom-in and return to
                    // the overview feel deliberate without buzzing per frame.
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1)
                }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    visibleMonths = next
                    selectedDay = nil
                    pinchScale = 1
                }
            }
    }

    private func activityDetail(for day: Date) -> String {
        let totalMinutes = (daily[dayKey(for: day)] ?? 0) / 60
        guard totalMinutes > 0 else { return "\(Self.detailFormatter.string(from: day)): активности нет" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours == 0
            ? "\(Self.detailFormatter.string(from: day)): \(minutes) мин"
            : "\(Self.detailFormatter.string(from: day)): \(hours) ч \(minutes) мин"
    }
}

private struct SharedWatchingCard: View {
    let companion: ViewingCompanion?
    let fallbackFriends: [FriendProfile]
    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let companion {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.86)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { showsDetail.toggle() }
                } label: {
                    VStack(spacing: 9) {
                        AvatarView(dataURL: companion.avatarDataURL, name: companion.nickname, size: 104)
                            .padding(7)
                            .liquidCard(Circle())
                        Text(showsDetail ? companion.nickname : "Нажми на аватар")
                            .font(.subheadline.weight(.semibold))
                        if showsDetail {
                            Text("@\(companion.username) · \(formattedHours(companion.seconds)) вместе")
                                .font(.caption).foregroundStyle(.secondary)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            } else if let friend = fallbackFriends.first(where: \.isFriend) {
                VStack(spacing: 8) {
                    AvatarView(dataURL: friend.avatarDataURL, name: friend.nickname, size: 96)
                        .padding(5)
                        .liquidCard(Circle())
                    Text(friend.nickname).font(.subheadline.weight(.semibold))
                    Text("Совместные часы появятся после общего просмотра").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Добавь друга", systemImage: "person.badge.plus", description: Text("Здесь появится человек, с которым вы чаще всего смотрите вместе."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func formattedHours(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours) ч \(minutes) мин" : "\(minutes) мин"
    }
}

private struct ViewingActivityCard: View {
    let stats: ViewingStats?
    @State private var selectedGenreID: String?
    var body: some View {
        let genres = stats?.genres ?? []
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Твой просмотр").font(.headline)
                Spacer()
                Image(systemName: "sparkles").foregroundStyle(.teal)
            }
            if genres.isEmpty {
                HStack(spacing: 12) {
                    ActivityOrb(daily: stats?.dailySeconds ?? [:])
                    Text("После первого фильма здесь появятся твои жанры и ритм просмотра.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    VStack(spacing: 7) {
                        ActivityOrb(daily: stats?.dailySeconds ?? [:])
                        Text("Активность").font(.caption2).foregroundStyle(.secondary)
                    }
                    GenrePreferenceOrb(genres: genres, selectedGenreID: $selectedGenreID)
                        .frame(width: 164, height: 164)
                }
                GenreLegend(genres: genres, selectedGenreID: $selectedGenreID)
            }
        }
        .padding(15)
        .liquidCard(RoundedRectangle(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                selectedGenreID = nil
            }
        }
        .onAppear { selectedGenreID = nil }
    }
}

private struct ActivityOrb: View {
    let daily: [String: Int]
    private var values: [Int] { Array(daily.sorted(by: { $0.key < $1.key }).suffix(14).map(\.value)) }
    var body: some View {
        let maximum = max(1, values.max() ?? 1)
        ZStack {
            Circle().fill(.white.opacity(0.055))
            Circle().stroke(.white.opacity(0.14), lineWidth: 1)
            ForEach(Array(0..<14), id: \.self) { index in
                let value = index < values.count ? values[index] : 0
                let strength = Double(value) / Double(maximum)
                Circle()
                    .fill(Color.teal.opacity(value == 0 ? 0.10 : 0.30 + strength * 0.65))
                    .frame(width: 8, height: 8)
                    .offset(y: -35)
                    .rotationEffect(.degrees(Double(index) * 360 / 14))
            }
            Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(.teal)
        }
        .frame(width: 90, height: 90)
    }
}

private struct GenrePreferenceOrb: View {
    let genres: [ViewingGenre]
    @Binding var selectedGenreID: String?
    var body: some View {
        let total = max(1, genres.reduce(0) { $0 + $1.seconds })
        let selected = genres.first(where: { $0.id == selectedGenreID })
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                    let before = genres.prefix(index).reduce(0) { $0 + $1.seconds }
                    let slice = DonutSlice(start: Double(before) / Double(total), end: Double(before + genre.seconds) / Double(total))
                    let color = GenrePalette.color(for: genre.name)
                    slice
                        .fill(color.opacity(selected == nil || genre.id == selected?.id ? 0.48 : 0.20))
                        .overlay(slice.stroke(.white.opacity(genre.id == selected?.id ? 0.36 : 0.16), lineWidth: genre.id == selected?.id ? 1.15 : 0.7))
                        .genreLiquidGlass(color, in: slice)
                        .shadow(color: color.opacity(genre.id == selected?.id ? 0.42 : 0.16), radius: genre.id == selected?.id ? 10 : 4)
                        .scaleEffect(genre.id == selected?.id ? 1.045 : 1)
                }
                Circle().fill(.white.opacity(0.045)).frame(width: 86, height: 86).liquidCard(Circle())
                VStack(spacing: 2) {
                    Text(selected?.name ?? "Жанры").font(.caption.weight(.bold)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.70)
                    if let selected {
                        Text("\(selected.percent)%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("Зажми и проведи").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                }.frame(width: 74)
            }
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in updateSelection(at: value.location, size: proxy.size) }
            )
            .animation(.spring(response: 0.27, dampingFraction: 0.82), value: selectedGenreID)
            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.8).allowsHitTesting(false))
            .shadow(color: GenrePalette.color(for: selected?.name ?? genres.first?.name ?? "").opacity(selected == nil ? 0.16 : 0.30), radius: selected == nil ? 8 : 13)
        }
    }
    private func updateSelection(at location: CGPoint, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let outerRadius = min(size.width, size.height) / 2
        guard distance >= outerRadius - 42, distance <= outerRadius + 10 else { return }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        let total = max(1, genres.reduce(0) { $0 + $1.seconds })
        var upperBound = 0.0
        for genre in genres {
            upperBound += Double(genre.seconds) / Double(total)
            if fraction <= upperBound {
                guard selectedGenreID != genre.id else { return }
                selectedGenreID = genre.id
                UISelectionFeedbackGenerator().selectionChanged()
                return
            }
        }
        if let last = genres.last, selectedGenreID != last.id {
            selectedGenreID = last.id
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

private struct DonutSlice: Shape {
    let start: Double
    let end: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 3
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        path.addArc(center: center, radius: radius - 28, startAngle: .degrees(end * 360 - 90), endAngle: .degrees(start * 360 - 90), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct GenreLegend: View {
    let genres: [ViewingGenre]
    @Binding var selectedGenreID: String?
    var body: some View {
        let smallText = genres.count > 6
        EmojiFlowLayout(spacing: 6) {
            ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        selectedGenreID = genre.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(GenrePalette.color(for: genre.name)).frame(width: 6, height: 6)
                        Text("\(genre.name) \(genre.percent)%")
                    }
                    .font(.system(size: smallText ? 9 : 11, weight: .medium))
                    .foregroundStyle(selectedGenreID == genre.id ? .primary : .secondary)
                    .padding(.horizontal, smallText ? 6 : 8)
                    .padding(.vertical, 4)
                    .background(selectedGenreID == genre.id ? GenrePalette.color(for: genre.name).opacity(0.22) : .white.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private enum GenrePalette {
    private static let fallback: [Color] = [.teal, .orange, .purple, .blue, .green, .pink, .yellow, .indigo, .brown, .mint]
    static func color(for name: String) -> Color {
        let value = name.lowercased()
        if value.contains("анима") || value.contains("animation") { return .cyan }
        if value.contains("ужас") || value.contains("horror") { return .red }
        if value.contains("комед") || value.contains("comedy") { return .yellow }
        if value.contains("драм") || value.contains("drama") { return .blue }
        if value.contains("роман") || value.contains("мелодрам") || value.contains("romance") { return .pink }
        if value.contains("триллер") || value.contains("thriller") { return .orange }
        if value.contains("кримин") || value.contains("crime") { return .purple }
        if value.contains("семейн") || value.contains("family") { return .green }
        if value.contains("фантаст") || value.contains("sci-fi") || value.contains("science fiction") { return .mint }
        if value.contains("фэнтез") || value.contains("fantasy") { return .indigo }
        if value.contains("приключ") || value.contains("adventure") { return .teal }
        if value.contains("документ") || value.contains("documentary") { return .brown }
        if value.contains("другое") || value.contains("other") { return .gray }
        let stableIndex = value.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % fallback.count }
        return fallback[stableIndex]
    }
}

/// Uses Unicode filenames, so every emoji typed from the system keyboard maps to
/// the corresponding Microsoft Fluent asset instead of a small hard-coded set.
struct FluentEmojiGlyph: UIViewRepresentable {
    let emoji: String
    let size: CGFloat
    init(_ emoji: String, size: CGFloat = 21) { self.emoji = emoji; self.size = size }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> EmojiImageView {
        let imageView = EmojiImageView(emojiSize: size)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)
        return imageView
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EmojiImageView, context: Context) -> CGSize { CGSize(width: size, height: size) }
    func updateUIView(_ imageView: EmojiImageView, context: Context) {
        guard context.coordinator.lastEmoji != emoji else { return }
        context.coordinator.lastEmoji = emoji
        // Never flash the native iOS glyph before Fluent arrives.
        imageView.prepareForFluentImage()
        context.coordinator.task?.cancel()
        if let image = FluentEmojiCache.shared.image(for: emoji) {
            imageView.image = image
            imageView.startAnimating()
            return
        }
        context.coordinator.task = FluentEmojiCache.shared.load(emoji: emoji) { image in
            guard let image else { return }
            DispatchQueue.main.async {
                guard context.coordinator.lastEmoji == emoji else { return }
                imageView.image = image
                imageView.startAnimating()
            }
        }
    }
    static func dismantleUIView(_ imageView: EmojiImageView, coordinator: Coordinator) { coordinator.task?.cancel() }
    final class Coordinator { var task: URLSessionDataTask?; var lastEmoji = "" }
}

/// Keeps already-used Fluent APNGs in memory for the whole app session. It
/// removes the visible network delay when the same emoji appears in the chat,
/// reactions or profile again.
final class FluentEmojiCache {
    static let shared = FluentEmojiCache()
    private let images = NSCache<NSString, UIImage>()
    private let cacheDirectory: URL
    private let stateQueue = DispatchQueue(label: "app.pusheen.fluent-emoji-cache")
    private var warmingCommonEmoji = false
    private init() {
        images.countLimit = 420
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = base.appendingPathComponent("FluentEmoji", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    func image(for emoji: String) -> UIImage? { images.object(forKey: emoji as NSString) }
    func store(_ image: UIImage, for emoji: String) { images.setObject(image, forKey: emoji as NSString) }
    private func slug(for emoji: String, preservingVariationSelector: Bool = true) -> String {
        emoji.unicodeScalars
            .filter { preservingVariationSelector || $0.value != 0xFE0F }
            .map { String($0.value, radix: 16) }
            .joined(separator: "-")
    }
    private func assetURLs(for emoji: String) -> [URL] {
        let exact = slug(for: emoji)
        let withoutVariation = slug(for: emoji, preservingVariationSelector: false)
        var slugs = [exact]
        // Some keyboards omit the emoji variation selector for symbols even
        // though Fluent stores the asset with FE0F in its canonical filename.
        if !emoji.unicodeScalars.contains(where: { $0.value == 0xFE0F }),
           emoji.unicodeScalars.count == 1,
           let scalar = emoji.unicodeScalars.first,
           scalar.value <= 0xFFFF {
            slugs.append(exact + "-fe0f")
        }
        if withoutVariation != exact { slugs.append(withoutVariation) }
        var seen = Set<String>()
        return slugs.flatMap { slug -> [URL] in
            guard seen.insert(slug).inserted else { return [] }
            // animated-static is the complete Fluent catalogue: it keeps APNG
            // animation where Microsoft provides it and a Fluent PNG otherwise.
            return ["animated-static", "static"].compactMap {
                URL(string: "https://raw.githubusercontent.com/bignutty/fluent-emoji/main/\($0)/\(slug).png")
            }
        }
    }
    @discardableResult
    func load(emoji: String, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        if let cached = image(for: emoji) { completion(cached); return nil }
        let diskURL = cacheDirectory.appendingPathComponent(slug(for: emoji) + ".png")
        if let data = try? Data(contentsOf: diskURL), let decoded = EmojiImageView.decodeAPNG(data) {
            store(decoded, for: emoji)
            completion(decoded)
            return nil
        }
        let urls = assetURLs(for: emoji)
        guard !urls.isEmpty else { completion(nil); return nil }
        func request(_ index: Int) -> URLSessionDataTask? {
            guard index < urls.count else { completion(nil); return nil }
            let task = URLSession.shared.dataTask(with: urls[index]) { [weak self] data, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let self, (200..<300).contains(status), let data,
                      let decoded = EmojiImageView.decodeAPNG(data) else {
                    _ = request(index + 1)
                    return
                }
                self.store(decoded, for: emoji)
                try? data.write(to: diskURL, options: .atomic)
                completion(decoded)
            }
            task.resume()
            return task
        }
        return request(0)
    }
    func prefetch(in text: String) {
        for character in text {
            let emoji = String(character)
            guard emoji.unicodeScalars.contains(where: { (0x1F000...0x1FAFF).contains(Int($0.value)) || (0x2600...0x27FF).contains(Int($0.value)) }) else { continue }
            guard image(for: emoji) == nil else { continue }
            _ = load(emoji: emoji) { _ in }
        }
    }
    func warmCommonEmoji() {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !warmingCommonEmoji else { return false }
            warmingCommonEmoji = true
            return true
        }
        guard shouldStart else { return }
        // Starts while the room is opening, so the most common chat/reaction
        // glyphs are already in memory (and on disk for future launches).
        let common = "😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😍🥰😘😋😜🤪🤗🤭🫢🤫🤔🫡🤐😐😑😶🙄😏😣😥😮🤐😯😪😫🥱😴😌🤓😎🥳😤😡🤬😱😨😰😢😭😓🤩🥺❤️🧡💛💚💙💜🖤🤍🤎💔💕💞💓💗💖💘💝💟👍👎👏🙌🫶🤝🙏💪🔥✨🎉🎊💯🎬🍿"
        prefetch(in: common)
    }
}

final class EmojiImageView: UIImageView {
    private let emojiSize: CGFloat
    init(emojiSize: CGFloat) {
        self.emojiSize = emojiSize
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: emojiSize, height: emojiSize) }
    func prepareForFluentImage() { image = nil; stopAnimating() }
    static func decodeAPNG(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let delay = (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double)
                ?? 0.09
            duration += max(0.02, delay)
            frames.append(UIImage(cgImage: frame))
        }
        return frames.isEmpty ? UIImage(data: data) : UIImage.animatedImage(with: frames, duration: duration)
    }
}

struct FluentInlineText: View {
    let text: String
    init(_ text: String) { self.text = text }
    private func isEmoji(_ value: String) -> Bool { value.unicodeScalars.contains { scalar in (0x1F000...0x1FAFF).contains(Int(scalar.value)) || (0x2600...0x27FF).contains(Int(scalar.value)) } }
    private struct Token: Identifiable {
        let id: Int
        let value: String
        let emoji: Bool
    }
    private var tokens: [Token] {
        var result: [Token] = []
        var word = ""
        func flushWord() {
            guard !word.isEmpty else { return }
            result.append(Token(id: result.count, value: word, emoji: false))
            word = ""
        }
        for character in text {
            let value = String(character)
            if isEmoji(value) {
                flushWord()
                result.append(Token(id: result.count, value: value, emoji: true))
            } else if character.isWhitespace {
                flushWord()
                result.append(Token(id: result.count, value: value, emoji: false))
            } else {
                word.append(character)
            }
        }
        flushWord()
        return result
    }
    var body: some View {
        EmojiFlowLayout(spacing: 1) {
            ForEach(tokens) { token in
                if token.emoji { FluentEmojiGlyph(token.value, size: 20) }
                else { Text(token.value).font(.subheadline) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A wrapping layout keeps long mixed text/emoji messages readable. HStack
/// cannot line-wrap a UIViewRepresentable emoji, which caused the clipping.
struct EmojiFlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let intrinsic = subview.sizeThatFits(.unspecified)
            let size = intrinsic.width > maxWidth
                ? subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                : intrinsic
            if x > 0 && x + size.width > maxWidth { y += lineHeight + spacing; x = 0; lineHeight = 0 }
            x += size.width
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x)
            x += spacing
        }
        return CGSize(width: min(maxWidth, usedWidth), height: y + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let intrinsic = subview.sizeThatFits(.unspecified)
            let size = intrinsic.width > bounds.width
                ? subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                : intrinsic
            if x > bounds.minX && x + size.width > bounds.maxX { y += lineHeight + spacing; x = bounds.minX; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct JoinRoomSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let joined: (Room) -> Void
    @State private var code = ""
    @State private var error = ""
    var body: some View { ZStack { AcrylicBackground(); VStack(spacing: 16) { Text("Войти в комнату").font(.title3.bold()); GlassField(icon: "number", title: "Код комнаты", text: $code); if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }; Button("Присоединиться") { Task { await join() } }.buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 12).liquidCard(Capsule()) }.padding(22).liquidCard(RoundedRectangle(cornerRadius: 28)).padding(18) }.presentationDetents([.height(250)]).presentationBackground(.clear) }
    private func join() async { do { let room = try await session.api.joinRoom(code: code.trimmingCharacters(in: .whitespacesAndNewlines)); joined(room); dismiss() } catch { self.error = error.localizedDescription } }
}

struct LegacyProfileEditSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""; @State private var username = ""; @State private var available: Bool?; @State private var error = ""
    var body: some View { ZStack { AcrylicBackground(); VStack(spacing: 13) { Text("Редактировать профиль").font(.title3.bold()); GlassField(icon: "person", title: "Nickname", text: $nickname); GlassField(icon: "at", title: "Username", text: $username).onChange(of: username) { _, value in Task { available = try? await session.api.usernameAvailable(value) } }; if !username.isEmpty { Text(available == true ? "@\(username) available" : "Username unavailable").font(.caption).foregroundStyle(available == true ? .green : .orange) }; if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }; Button("Сохранить") { Task { await save() } }.buttonStyle(.borderedProminent) }.padding(22) }.onAppear { nickname = session.profile?.nickname ?? ""; username = session.profile?.username ?? "" }.presentationDetents([.height(360)]).presentationBackground(.clear) }
    private func save() async { do { session.profile = try await session.api.updateProfile(nickname: nickname, username: username); dismiss() } catch { self.error = error.localizedDescription } }
}

struct ProfileEditSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var username = ""
    @State private var avatar = ""
    @State private var available: Bool?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var error = ""
    var body: some View {
        ZStack { AcrylicBackground()
            VStack(spacing: 14) {
                Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5)
                Text("Профиль").font(.title3.bold())
                PhotosPicker(selection: $selectedPhoto, matching: .images) { ZStack(alignment: .bottomTrailing) { AvatarView(dataURL: avatar, name: nickname, size: 78); Image(systemName: "camera.fill").font(.caption).padding(7).liquidCard(Circle()) } }
                    .onChange(of: selectedPhoto) { _, item in Task { await loadAvatar(item) } }
                VStack(spacing: 9) {
                    GlassField(icon: "person", title: "Nickname", text: $nickname)
                    VStack(spacing: 5) { GlassField(icon: "at", title: "Username", text: $username).onChange(of: username) { _, value in Task { available = try? await session.api.usernameAvailable(value) } }; HStack { Text("@\(username)").font(.caption).foregroundStyle(.secondary); Spacer(); if !username.isEmpty { Text(available == true ? "Available" : "Unavailable").font(.caption2.weight(.semibold)).foregroundStyle(available == true ? .green : .orange) } } }
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Готово") { Task { await save() } }.buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(20).liquidCard(RoundedRectangle(cornerRadius: 30)).padding(18)
        }.presentationDetents([.height(470)]).presentationBackground(.clear).onAppear { nickname = session.profile?.nickname ?? ""; username = session.profile?.username ?? ""; avatar = session.profile?.avatarDataUrl ?? "" }
    }
    private func loadAvatar(_ item: PhotosPickerItem?) async { guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }; avatar = "data:image/jpeg;base64," + data.base64EncodedString() }
    private func save() async { do { session.profile = try await session.api.updateProfile(nickname: nickname, username: username, avatar: avatar); dismiss() } catch { self.error = error.localizedDescription } }
}

struct ProfileInlineEditor: View {
    @EnvironmentObject private var session: SessionStore
    let close: () -> Void
    @State private var nickname = ""
    @State private var username = ""
    @State private var error = ""
    var body: some View { VStack(spacing: 10) { GlassField(icon: "person", title: "Nickname", text: $nickname); GlassField(icon: "at", title: "Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled(); if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }; HStack { Button("Отмена", action: close).buttonStyle(.bordered); Button("Готово") { Task { await save() } }.buttonStyle(.plain).padding(.horizontal, 22).padding(.vertical, 11).liquidCard(Capsule()) } }.padding(14).liquidCard(RoundedRectangle(cornerRadius: 22)).onAppear { nickname = session.profile?.nickname ?? ""; username = session.profile?.username ?? "" } }
    private func save() async { do { session.profile = try await session.api.updateProfile(nickname: nickname, username: username); close() } catch { self.error = error.localizedDescription } }
}

private enum FriendRequestFilter { case incoming, outgoing }

struct FriendsGlassView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var expanded = false
    @State private var query = ""
    @State private var friends: [FriendProfile] = []
    @State private var results: [FriendProfile] = []
    @State private var requestFilter: FriendRequestFilter?
    @FocusState private var searchFocused: Bool
    var body: some View {
        ZStack { AcrylicBackground()
            VStack(spacing: 15) {
                HStack {
                    Text("Друзья").font(.title3.bold())
                    Spacer()
                    if !session.friendRequests.incoming.isEmpty {
                        RequestHeaderButton(symbol: "tray.and.arrow.down.fill", count: session.friendRequests.incoming.count, active: requestFilter == .incoming) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) { requestFilter = requestFilter == .incoming ? nil : .incoming }
                        }
                    }
                    if !session.friendRequests.outgoing.isEmpty {
                        RequestHeaderButton(symbol: "paperplane.fill", count: nil, active: requestFilter == .outgoing) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) { requestFilter = requestFilter == .outgoing ? nil : .outgoing }
                        }
                    }
                    Button { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { expanded.toggle() }; if expanded { DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { searchFocused = true } } else { query = ""; searchFocused = false } } label: { Image(systemName: expanded ? "xmark" : "magnifyingglass").frame(width: 42, height: 42).liquidCard(Circle()) }.buttonStyle(.plain)
                }
                if expanded {
                    HStack(spacing: 9) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Username", text: $query).focused($searchFocused).textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: query) { _, _ in Task { await search() } } }
                        .padding(13).liquidCard(Capsule()).transition(.opacity.combined(with: .move(edge: .top)))
                }
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if !session.friendRequests.incoming.isEmpty && requestFilter == .incoming {
                            FriendRequestSection(title: "Входящие", requests: session.friendRequests.incoming, incoming: true) { request, accept in
                                await session.respond(to: request, accept: accept)
                                await loadFriends()
                            }
                        }
                        if !session.friendRequests.outgoing.isEmpty && requestFilter == .outgoing {
                            FriendRequestSection(title: "Отправленные", requests: session.friendRequests.outgoing, incoming: false) { _, _ in }
                        }
                        if requestFilter == nil {
                            ForEach(expanded && !query.isEmpty ? results : friends) { person in
                                FriendSwipeRow(
                                person: person,
                                showAdd: expanded && !person.isFriend,
                                pending: session.friendRequests.outgoing.contains { $0.userId == person.userId },
                                add: {
                                    try? await session.api.addFriend(username: person.username)
                                    await session.refreshFriendRequests()
                                    await search()
                                },
                                remove: {
                                    do {
                                        try await session.api.removeFriend(username: person.username)
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                            friends.removeAll { $0.id == person.id }
                                        }
                                    } catch {
                                        // Keep the person visible if the server rejected the request.
                                    }
                                }
                                )
                            }
                        }
                        if friends.isEmpty && !expanded && requestFilter == nil { ContentUnavailableView("Друзей пока нет", systemImage: "person.2") }
                    }
                }
            }.padding(20)
        }
        .task { await loadFriends(); await session.refreshFriendRequests() }
        .onChange(of: session.friendRequests) { _, _ in Task { await loadFriends() } }
    }
    private func loadFriends() async { friends = (try? await session.api.friends()) ?? [] }
    private func search() async { results = (try? await session.api.friends(query: query)) ?? [] }
}

private struct RequestHeaderButton: View {
    let symbol: String
    let count: Int?
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .background(active ? Color.teal.opacity(0.20) : .clear, in: Circle())
                    .liquidCard(Circle())
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(.red.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.7))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FriendSwipeRow: View {
    private enum SwipeGestureState: Equatable {
        case inactive
        case horizontal(CGFloat)
        case vertical

        var horizontalTranslation: CGFloat {
            if case let .horizontal(value) = self { return value }
            return 0
        }

        var isHorizontal: Bool {
            if case .horizontal = self { return true }
            return false
        }
    }

    let person: FriendProfile
    let showAdd: Bool
    let pending: Bool
    let add: () async -> Void
    let remove: () async -> Void
    @State private var revealed = false
    // Lock the gesture axis once, at the beginning of the drag. Re-evaluating
    // X versus Y on every frame makes a reversing horizontal swipe stall when
    // its X translation crosses zero and tiny vertical finger noise wins.
    @GestureState private var swipeGesture: SwipeGestureState = .inactive
    @State private var removing = false
    @State private var showDeleteConfirmation = false
    @State private var deletePromptTriggeredByDrag = false
    @State private var deletePromptHoldOffset: CGFloat?

    private let settledOffset: CGFloat = -104
    private var offset: CGFloat {
        if let deletePromptHoldOffset { return deletePromptHoldOffset }
        let settled = revealed ? settledOffset : 0
        return min(0, max(-148, settled + swipeGesture.horizontalTranslation))
    }
    private var deleteReveal: CGFloat {
        min(1, max(0, (-offset) / (-settledOffset)))
    }
    /// The action grows exactly with the revealed part of the row. There is no
    /// fixed oversized pill that can cover the friend card.
    private var deleteWidth: CGFloat { max(60, min(148, -offset)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Keep the glass action in the hierarchy while the row closes so
            // its width and opacity can animate back with the card instead of
            // disappearing one frame before the return animation.
            if person.isFriend {
                Button {
                    requestDeleteConfirmation()
                } label: {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            // Material remains visible through the destructive tint:
                            // this keeps the action a glass control rather than a
                            // solid red banner.
                            .overlay { Capsule().fill(Color.red.opacity(0.38)) }
                            .overlay {
                                Capsule().stroke(
                                    LinearGradient(colors: [.white.opacity(0.48), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.8
                                )
                            }
                        Group {
                            if removing { ProgressView().tint(.white) }
                            else {
                                Image(systemName: "trash.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 19, weight: .semibold))
                                    .frame(width: 42, height: 42)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.leading, min(27, max(18, deleteWidth * 0.18)))
                        .scaleEffect(0.84 + 0.16 * deleteReveal)
                        .opacity(min(1, deleteReveal * 2.6))
                    }
                    .frame(width: deleteWidth, height: 56)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .frame(width: deleteWidth, height: 64)
                .padding(.trailing, 3)
                .opacity(min(1, deleteReveal * 2.2))
                // The action stays behind the row. It is revealed by movement,
                // never drawn on top of the friend's card.
                .zIndex(0)
            }
            HStack(spacing: 11) {
                AvatarView(dataURL: person.avatarDataURL, name: person.nickname, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.nickname).bold().lineLimit(1)
                    Text("@\(person.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if showAdd {
                    Button(pending ? "Отправлено" : "Добавить") {
                        guard !pending else { return }
                        Task { await add() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(pending)
                }
            }
            .padding(11)
            .background(.clear)
            .passiveLiquidCard(RoundedRectangle(cornerRadius: 20))
            .offset(x: offset)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .zIndex(1)
            // A simultaneous gesture preserves the delete button's own tap
            // handling once it is exposed, while still tracking the swipe.
            .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .updating($swipeGesture) { value, state, _ in
                    guard person.isFriend else { return }
                    switch state {
                    case .inactive:
                        state = abs(value.translation.width) >= abs(value.translation.height)
                            ? .horizontal(value.translation.width)
                            : .vertical
                    case .horizontal:
                        // Once horizontal, stay horizontal even while the finger
                        // reverses and total X translation passes through zero.
                        state = .horizontal(value.translation.width)
                    case .vertical:
                        break
                    }
                }
                .onChanged { value in
                    guard person.isFriend, !revealed, !removing else { return }
                    guard !showDeleteConfirmation, !deletePromptTriggeredByDrag else { return }
                    guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                    guard value.translation.width <= -64 else { return }

                    // Crossing the destructive threshold with the finger is the
                    // action that presents confirmation. Do not first settle the
                    // row to its resting offset: that produced a second, automatic
                    // left swipe before the dialog appeared.
                    deletePromptTriggeredByDrag = true
                    // Freeze the card exactly where the user's finger crossed
                    // the threshold. Presentation cancels the drag gesture, but
                    // this retained offset prevents a close/reopen flicker.
                    deletePromptHoldOffset = min(0, max(-148, value.translation.width))
                    showDeleteConfirmation = true
                }
                .onEnded { value in
                    guard person.isFriend else { return }
                    if deletePromptTriggeredByDrag {
                        // The confirmation owns the retained offset now. Do not
                        // run another settle animation after the gesture ends.
                        deletePromptTriggeredByDrag = false
                        return
                    }
                    guard swipeGesture.isHorizontal || abs(value.translation.width) >= abs(value.translation.height) else { return }
                    let wasRevealed = revealed
                    let projected = value.predictedEndTranslation.width + (wasRevealed ? settledOffset : 0)
                    withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.08)) {
                        if wasRevealed {
                            // Once the row visibly follows a deliberate reverse
                            // gesture, let it close instead of snapping back left.
                            revealed = !(value.translation.width > 8 || value.predictedEndTranslation.width > 18)
                        } else {
                            revealed = projected < -54
                        }
                    }
                })
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .confirmationDialog("Удалить \(person.nickname) из друзей?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { performRemove() }
            Button("Отмена", role: .cancel) {
                withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88)) {
                    deletePromptHoldOffset = nil
                    revealed = false
                }
            }
        } message: {
            Text("Пользователь исчезнет из списка друзей.")
        }
        .onChange(of: showDeleteConfirmation) { _, isPresented in
            guard !isPresented, !removing else { return }
            deletePromptTriggeredByDrag = false
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88)) {
                deletePromptHoldOffset = nil
                revealed = false
            }
        }
    }

    private func requestDeleteConfirmation() {
        guard !removing else { return }
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88)) { revealed = true }
        showDeleteConfirmation = true
    }

    private func performRemove() {
        guard !removing else { return }
        removing = true
        Task {
            await remove()
            await MainActor.run {
                removing = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    deletePromptHoldOffset = nil
                    revealed = false
                }
            }
        }
    }
}

private struct FriendRequestSection: View {
    let title: String
    let requests: [FriendRequestProfile]
    let incoming: Bool
    let action: (FriendRequestProfile, Bool) async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            ForEach(requests) { request in
                HStack(spacing: 11) {
                    AvatarView(dataURL: request.avatarDataURL, name: request.nickname, size: 44)
                    VStack(alignment: .leading, spacing: 2) { Text(request.nickname).font(.subheadline.bold()); Text("@\(request.username)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if incoming {
                        Button { Task { await action(request, true) } } label: { Image(systemName: "checkmark").frame(width: 32, height: 32) }.buttonStyle(.plain).liquidCard(Circle())
                        Button { Task { await action(request, false) } } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }.buttonStyle(.plain).liquidCard(Circle())
                    } else { Text("Отправлено").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 19))
            }
        }
    }
}
