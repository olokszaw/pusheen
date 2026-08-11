import SwiftUI
import AVKit
import UIKit
import PencilKit
import PhotosUI
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers
import WebKit
import Lottie

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
                if let status = session.roomInvitationStatusNotice {
                    RoomInvitationStatusToast(text: status)
                        .padding(.horizontal, 18).padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity)).zIndex(24)
                } else if let invitation = session.roomInvitationNotice {
                    RoomInvitationToast(invitation: invitation)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(22)
                } else if let request = session.friendRequestNotice {
                    FriendRequestToast(request: request)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                }
            }
            .fullScreenCover(item: $session.acceptedInvitedRoom) { room in
                RoomView(room: room, api: session.api, token: session.token ?? "")
                    .environmentObject(session)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: session.roomInvitationNotice?.id)
            .animation(.spring(response: 0.35, dampingFraction: 0.84), value: session.roomInvitationStatusNotice)
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

    func contextPreviewBackdrop(active: Bool) -> some View {
        self
            .blur(radius: active ? 14 : 0)
            .scaleEffect(active ? 0.986 : 1)
            .allowsHitTesting(!active)
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: active)
    }
}

private struct RoomInvitationStatusToast: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
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
    private static let roomsCacheKey = "pusheen.cached-rooms"
    @EnvironmentObject private var session: SessionStore
    @State private var rooms: [Room] = []
    @State private var path = NavigationPath()
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var pendingRoomToOpen: Room?
    @State private var previewedRoom: Room?
    @State private var selectedRoomIDs = Set<Int>()
    @State private var isSelectingRooms = false
    @State private var showBulkDeleteConfirmation = false
    @State private var isDeletingSelectedRooms = false
    @State private var roomNavigationBlockedUntil = Date.distantPast
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ZStack { AcrylicBackground()
                    ScrollView { VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 34, height: 34)
                        .background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.cyan.opacity(0.24), lineWidth: 0.8))
                    Text("Мои комнаты")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Menu {
                        Button("Создать комнату", systemImage: "plus") { showCreate = true }
                        Button("Войти по коду", systemImage: "number") { showJoin = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 38, height: 38)
                            .liquidCard(Circle())
                    }
                    .buttonStyle(AlivePressButtonStyle())
                }
                ForEach(rooms) { room in
                    let canSelect = room.owner == session.profile?.userId
                    let selected = selectedRoomIDs.contains(room.id)
                    HStack(spacing: 11) {
                        if isSelectingRooms && canSelect {
                            RoomSelectionIndicator(selected: selected)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        RoomCard(room: room)
                            .scaleEffect(selected ? 0.985 : 1)
                            .opacity(isSelectingRooms && !canSelect ? 0.56 : 1)
                    }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelectingRooms)
                        .animation(.spring(response: 0.24, dampingFraction: 0.74), value: selected)
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                        .gesture(
                            LongPressGesture(minimumDuration: 0.42)
                                .onEnded { _ in if !isSelectingRooms { previewedRoom = room } }
                                .exclusively(before: TapGesture().onEnded {
                                    if isSelectingRooms, canSelect {
                                        toggleRoomSelection(room.id)
                                    } else if !isSelectingRooms, Date() >= roomNavigationBlockedUntil {
                                        path.append(room)
                                    }
                                })
                        )
                }
                if rooms.isEmpty {
                    ContentUnavailableView("Комнат пока нет", systemImage: "play.rectangle.on.rectangle")
                }
                    }.padding(18) }.task { await monitorRooms() }.onChange(of: session.isOffline) { _, offline in if !offline { Task { await load() } } }
                }
                .blur(radius: previewedRoom == nil ? 0 : 17)
                .allowsHitTesting(previewedRoom == nil)
                if isSelectingRooms {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        selectionToolbar
                            .padding(.horizontal, 18)
                            .padding(.bottom, 12)
                    }
                    .zIndex(40)
                    .allowsHitTesting(true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let room = previewedRoom {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { previewedRoom = nil } }
                    RoomPreviewOverlay(room: room, canDelete: room.owner == session.profile?.userId, canSelectAll: rooms.contains { $0.owner == session.profile?.userId && $0.id != room.id }, close: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { previewedRoom = nil }
                    }, selectAll: {
                        blockRoomNavigation()
                        selectedRoomIDs = Set(rooms.filter { $0.owner == session.profile?.userId }.map(\.id))
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { isSelectingRooms = true; previewedRoom = nil }
                    }) {
                        blockRoomNavigation()
                        try? await session.api.deleteRoom(id: room.id)
                        rooms.removeAll { $0.id == room.id }
                        saveRoomsCache()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { previewedRoom = nil }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: previewedRoom?.id)
            .navigationDestination(for: Room.self) { RoomView(room: $0, api: session.api, token: session.token ?? "") }
            .sheet(isPresented: $showCreate, onDismiss: openPendingRoom) {
                CreateRoomSheet { room in
                    stageRoomForOpening(room)
                    showCreate = false
                }
            }
            .sheet(isPresented: $showJoin, onDismiss: openPendingRoom) {
                JoinRoomSheet { room in
                    stageRoomForOpening(room)
                    showJoin = false
                }
            }
            .confirmationDialog("Удалить выбранные комнаты?", isPresented: $showBulkDeleteConfirmation, titleVisibility: .visible) {
                Button("Удалить \(selectedRoomIDs.count)", role: .destructive) { Task { await deleteSelectedRooms() } }
            } message: { Text("Видео, загруженные в эти комнаты, тоже удалятся с сервера.") }
        }
        // NavigationStack is the only source of truth for tab-bar visibility.
        // A destination can no longer leave the native Liquid Glass bar hidden
        // after an interactive pop, overlay, reconnect or programmatic exit.
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }
    private func load() async {
        // Render the last known room list immediately, then refresh it without
        // flashing an empty screen when a tunnel or mobile connection is slow.
        if rooms.isEmpty,
           let data = UserDefaults.standard.data(forKey: Self.roomsCacheKey),
           let cached = try? JSONDecoder().decode([Room].self, from: data) {
            rooms = cached
        }
        guard let refreshed = try? await session.api.rooms() else { return }
        if rooms.map(\.id) == refreshed.map(\.id) {
            rooms = refreshed
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { rooms = refreshed }
        }
        saveRoomsCache()
    }
    private func monitorRooms() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !session.isOffline else { continue }
            await load()
        }
    }
    private func saveRoomsCache() {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        UserDefaults.standard.set(data, forKey: Self.roomsCacheKey)
    }
    private func stageRoomForOpening(_ room: Room) {
        // A list refresh can finish at the same moment as creation/joining.
        // Upsert instead of inserting a duplicate card, then wait until the
        // modal is fully gone before mutating NavigationStack's path.
        rooms.removeAll { $0.id == room.id }
        rooms.insert(room, at: 0)
        saveRoomsCache()
        pendingRoomToOpen = room
    }
    private func openPendingRoom() {
        guard let room = pendingRoomToOpen else { return }
        pendingRoomToOpen = nil
        DispatchQueue.main.async {
            path.append(room)
        }
    }
    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 36, height: 36)
                    .liquidCard(Circle())
            }
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { cancelRoomSelection() })
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Отменить выбор")
            .accessibilityAction { cancelRoomSelection() }
            Text("Выбрано: \(selectedRoomIDs.count)").font(.subheadline.weight(.semibold))
            Spacer()
            Label("Удалить", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 42)
                .liquidCard(Capsule())
                .foregroundStyle(.red)
                .opacity(selectedRoomIDs.isEmpty || isDeletingSelectedRooms ? 0.42 : 1)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    guard !selectedRoomIDs.isEmpty, !isDeletingSelectedRooms else { return }
                    blockRoomNavigation()
                    showBulkDeleteConfirmation = true
                })
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    guard !selectedRoomIDs.isEmpty, !isDeletingSelectedRooms else { return }
                    blockRoomNavigation()
                    showBulkDeleteConfirmation = true
                }
        }
        .padding(9)
        .liquidCard(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
    private func toggleRoomSelection(_ roomID: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
            if selectedRoomIDs.contains(roomID) { selectedRoomIDs.remove(roomID) }
            else { selectedRoomIDs.insert(roomID) }
        }
    }
    private func cancelRoomSelection() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        blockRoomNavigation()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            showBulkDeleteConfirmation = false
            selectedRoomIDs.removeAll()
            isSelectingRooms = false
            previewedRoom = nil
        }
    }
    private func deleteSelectedRooms() async {
        blockRoomNavigation()
        isDeletingSelectedRooms = true
        let ids = selectedRoomIDs
        for id in ids { try? await session.api.deleteRoom(id: id) }
        rooms.removeAll { ids.contains($0.id) }
        saveRoomsCache()
        selectedRoomIDs = []
        isSelectingRooms = false
        isDeletingSelectedRooms = false
    }
    private func blockRoomNavigation() {
        roomNavigationBlockedUntil = Date().addingTimeInterval(0.8)
    }

}

private struct ContextPreviewGlass<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close)
            content()
                .padding(16)
                .frame(maxWidth: 340)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.4), radius: 28, y: 16)
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .zIndex(100)
    }
}

private struct RoomInvitationToast: View {
    @EnvironmentObject private var session: SessionStore
    let invitation: RoomInvitation
    @State private var responding: String?

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                if !invitation.room.thumbnailURL.isEmpty {
                    AsyncImage(url: URL(string: invitation.room.thumbnailURL)) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
                } else {
                    AvatarView(dataURL: invitation.sender.avatarDataURL, name: invitation.sender.nickname, size: 52, showsBorder: false)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(invitation.sender.nickname) приглашает вас в комнату")
                    .font(.caption.weight(.semibold)).lineLimit(2)
                Text(invitation.room.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            inviteResponseButton("checkmark", tint: Color(red: 0.31, green: 0.72, blue: 0.55), action: "accept")
            inviteResponseButton("xmark", tint: Color(red: 0.78, green: 0.35, blue: 0.40), action: "decline")
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private func inviteResponseButton(_ symbol: String, tint: Color, action: String) -> some View {
        Button {
            guard responding == nil else { return }
            responding = action
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.82)
            Task { await session.respond(to: invitation, accept: action == "accept") }
        } label: {
            Group {
                if responding == action { ProgressView().controlSize(.mini) }
                else { Image(systemName: symbol).font(.caption.bold()) }
            }
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.18), in: Circle())
            .overlay(Circle().stroke(tint.opacity(0.38), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(responding != nil)
    }
}

private struct RoomSelectionIndicator: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.cyan.opacity(0.24) : Color.white.opacity(0.055))
            Circle()
                .stroke(selected ? Color.cyan.opacity(0.95) : Color.white.opacity(0.2), lineWidth: selected ? 1.6 : 1)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
        }
        .frame(width: 32, height: 32)
        .shadow(color: selected ? Color.cyan.opacity(0.3) : Color.clear, radius: 9, y: 3)
        .accessibilityHidden(true)
    }
}

struct MovieSearchSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MovieCatalogItem] = []
    @State private var isSearching = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AcrylicBackground().ignoresSafeArea()
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        TextField("Название фильма", text: $query)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                            .padding(12)
                            .liquidCard(RoundedRectangle(cornerRadius: 16))
                        Button { Task { await search() } } label: {
                            Image(systemName: "magnifyingglass").frame(width: 42, height: 42)
                        }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                        .liquidCard(Circle())
                    }
                    .padding(.horizontal, 18)

                    if isSearching {
                        ProgressView("Ищу фильмы…").tint(.white).padding(.top, 20)
                    } else if !error.isEmpty {
                        ContentUnavailableView("Поиск недоступен", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if results.isEmpty {
                        ContentUnavailableView("Найди фильм", systemImage: "film", description: Text("Введи название — покажу официальные карточки фильма."))
                    } else {
                        List(results) { film in
                            HStack(alignment: .top, spacing: 12) {
                                AsyncImage(url: URL(string: film.artworkUrl100 ?? "")) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1).overlay(Image(systemName: "film")) }
                                    .frame(width: 66, height: 94).clipShape(RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(film.title).font(.headline)
                                    Text([film.year, film.primaryGenreName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    Text(film.description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    if let link = film.trackViewUrl, let url = URL(string: link) { Link("Открыть официальную страницу", destination: url).font(.caption.weight(.semibold)) }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Поиск фильмов")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationBackground(.clear)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true; error = ""; defer { isSearching = false }
        do { results = try await session.api.searchMovies(text) }
        catch let caughtError { self.error = caughtError.localizedDescription }
    }
}

struct CreateRoomSheet: View {
    @EnvironmentObject private var session: SessionStore
    let created: (Room) -> Void
    @State private var url = ""
    @State private var selectedMovie: PhotosPickerItem?
    @State private var showsMoviePicker = false
    @State private var showsFilePicker = false
    @State private var movieURL: URL?
    @State private var movieError = ""
    @State private var isPrivate = false
    @State private var loading = false
    @State private var error = ""
    var body: some View { ZStack { AcrylicBackground(); VStack(alignment: .leading, spacing: 16) {
        Text("Новая комната").font(.title2.bold())
        Text("Вставь ссылку VK Видео, сайта или выбери файл из галереи.").font(.subheadline).foregroundStyle(.secondary)
        TextField("Ссылка на видео", text: $url, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
            .onChange(of: url) { _, value in
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, movieURL != nil {
                    selectedMovie = nil
                    cleanupSelectedMovie()
                }
            }
        Button {
            showsMoviePicker = true
        } label: {
            HStack { Image(systemName: "video.badge.plus"); Text(movieURL == nil ? "Выбрать видео из галереи" : movieURL!.lastPathComponent); Spacer(); if movieURL != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) } }
                .lineLimit(1).padding(12).passiveLiquidCard(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(ImmediateGalleryButtonStyle())
        .photosPicker(isPresented: $showsMoviePicker, selection: $selectedMovie, matching: .videos)
        .onChange(of: selectedMovie) { _, item in Task { await loadMovie(item) } }
        Button { showsFilePicker = true } label: {
            HStack { Image(systemName: "folder"); Text("Выбрать видео из файлов"); Spacer() }
                .padding(12).passiveLiquidCard(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(ImmediateGalleryButtonStyle())
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            do {
                guard let source = try result.get().first else { return }
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                let copy = URL.temporaryDirectory.appendingPathComponent("pusheen-file-\(UUID().uuidString)").appendingPathExtension(source.pathExtension.isEmpty ? "mp4" : source.pathExtension)
                try FileManager.default.copyItem(at: source, to: copy)
                cleanupSelectedMovie()
                movieURL = copy; movieError = ""; url = ""
            } catch { movieError = "Не удалось получить видео из файлов" }
        }
        Toggle("Публичная комната", isOn: Binding(get: { !isPrivate }, set: { isPrivate = !$0 })).padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
        if !movieError.isEmpty { Text(movieError).font(.caption).foregroundStyle(.red) }
        if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        Button { Task { await create() } } label: { Label(loading ? "Загрузка…" : "Создать", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled((url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && movieURL == nil) || loading)
    }.padding(22) }
        .presentationDetents([.medium, .large])
        .presentationBackground(.clear)
        .interactiveDismissDisabled(loading)
        .onDisappear { cleanupSelectedMovie() }
    }
    private func loadMovie(_ item: PhotosPickerItem?) async {
        movieError = ""
        guard let item else { return }
        do {
            if let imported = try await item.loadTransferable(type: ImportedRoomMovie.self)?.url {
                cleanupSelectedMovie()
                movieURL = imported
                url = ""
            } else {
                movieError = "Не удалось получить видео из галереи"
            }
        }
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
            created(room)
        } catch {
            if let pendingRoom { try? await session.api.deleteRoom(id: pendingRoom.id) }
            self.error = error.localizedDescription
        }
    }
    private func cleanupSelectedMovie() {
        guard let movieURL, movieURL.path.contains("pusheen-") else { return }
        try? FileManager.default.removeItem(at: movieURL)
        self.movieURL = nil
    }
}

struct LegacyRoomCard: View {
    let room: Room
    var body: some View { HStack(spacing: 14) { Image(systemName: "play.fill").font(.title2).frame(width: 58, height: 58).liquidCard(Circle()); VStack(alignment: .leading, spacing: 4) { Text(room.title).font(.headline).lineLimit(1); Text("\(room.membersCount) участников · \(room.inviteCode)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(14).liquidCard() }
}

struct RoomView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let room: Room
    let api: APIClient
    let token: String
    @State private var draft = ""
    @State private var showTime = false
    @State private var showMembers = false
    @State private var chatFocused = false
    @State private var copiedCode = false
    @State private var copyFeedbackTick = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var controlsVisible = false
    @State private var isScrubbingPlayer = false
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var profilePreview: UserProfileReference?
    @State private var fullProfile: UserProfileReference?
    private let roomPlayerHeight: CGFloat = 214
    @StateObject private var model: RoomViewModel
    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token; _model = StateObject(wrappedValue: RoomViewModel(room: room, api: api, token: token)) }
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
            // Leave a tiny visual margin so the lower glass corners do not
            // touch or clip against the physical edge of the display.
            // The keyboard overlap is the single source of truth. Tying the
            // subtraction to focus made the room jump to its full height one
            // frame before the keyboard had actually finished closing.
            let roomHeight = max(playerHeight + 180, geometry.size.height - keyboardHeight - 14)
            let roomShape = RoundedRectangle(cornerRadius: 25, style: .continuous)
            ZStack(alignment: .top) { AcrylicBackground().contentShape(Rectangle()).onTapGesture { chatFocused = false }
                VStack(spacing: 0) {
                    Group {
                        if let player = model.player {
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
                    if controlsVisible {
                        playerControls
                            .padding(.horizontal, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(20)
                    }
                    NativeChatPane(messages: model.messages, typingMembers: model.typingMembers, currentUserID: session.profile?.userId, draft: $draft, focused: $chatFocused, keyboardHeight: keyboardHeight, isMuted: model.isMuted, typingChanged: model.draftDidChange, send: { text, image, reply in model.send(text: text, image: image, replyTo: reply, as: session.profile) }, react: { id, emoji in model.react(messageID: id, emoji: emoji) }, previewProfile: { message in
                        guard message.authorId != session.profile?.userId else { return }
                        profilePreview = UserProfileReference(message)
                    }, openProfile: { message in
                        guard message.authorId != session.profile?.userId else { return }
                        fullProfile = UserProfileReference(message)
                    })
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
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        let playerInteractionBottom: CGFloat = contentTop + (controlsVisible ? playerHeight + 188 : playerHeight + 80)
                        let beganOutsidePlayer = value.startLocation.y > playerInteractionBottom
                        let exitsFromLeftEdge = value.startLocation.x <= 44 && value.translation.width > 0
                        let opensMembersFromRightEdge = beganOutsidePlayer && value.startLocation.x >= geometry.size.width - 44 && value.translation.width < 0
                        guard !isScrubbingPlayer,
                              horizontal > vertical * 1.25 else { return }
                        if exitsFromLeftEdge,
                           (value.translation.width > 85 || value.predictedEndTranslation.width > 180) {
                            leaveRoom()
                        } else if opensMembersFromRightEdge, value.translation.width < -70 {
                            presentMembers()
                        }
                    }
            )
        }
        // The container owns keyboard avoidance. Its top is clamped by the
        // real safe-area inset, so it can never slide under system chrome.
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { updateKeyboardFrame($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { updateKeyboardFrame($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { resetKeyboardLayout(animatedWith: $0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in resetKeyboardLayout() }
        .onChange(of: chatFocused) { _, focused in
            if focused && controlsVisible {
                withAnimation(.easeOut(duration: 0.18)) { controlsVisible = false }
            }
            if !focused && keyboardHeight > 0 {
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS can dismiss the software keyboard while the app is inactive
            // without delivering the complete will-hide notification sequence.
            if phase != .active { resetKeyboardLayout() }
        }
        .onChange(of: model.wasRemovedFromRoom) { _, removed in
            if removed { leaveRoom() }
        }
        .onChange(of: session.liveRefreshRevision) { _, _ in
            Task { await model.refreshAfterConnectivityRecovery() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .userProfilePresentation(preview: $profilePreview, fullProfile: $fullProfile)
        .task { model.setCurrentUserID(session.profile?.userId); await model.start() }.onDisappear { model.stop() }
            .sheet(isPresented: $showTime) { SeekTimePickerSheet(initial: model.position) { model.seek($0) } }
            .sheet(isPresented: $showMembers) { MembersSheet(room: room, members: model.activeMembers, currentID: session.profile?.userId, canModerate: model.isOwner) { member, action in await model.moderate(member: member, action: action) } }
    }
    private func leaveRoom() {
        dismiss()
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
    private func updateKeyboardFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let bounds = UIScreen.main.bounds
        let overlap = bounds.intersection(frame)
        let nextHeight: CGFloat = frame.minY >= bounds.maxY - 1 || overlap.isNull || overlap.height <= 1
            ? 0
            : min(420, overlap.height)
        guard nextHeight > 0 else {
            resetKeyboardLayout(animatedWith: notification)
            return
        }
        // Ignore keyboards presented by a profile/settings sheet above the
        // room. Only the chat's own first responder may resize this surface.
        guard chatFocused else { return }
        withAnimation(keyboardAnimation(from: notification)) {
            keyboardHeight = nextHeight
        }
    }
    private func resetKeyboardLayout(animatedWith notification: Notification? = nil) {
        if let notification {
            withAnimation(keyboardAnimation(from: notification)) {
                keyboardHeight = 0
                chatFocused = false
            }
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { keyboardHeight = 0 }
        chatFocused = false
    }
    private func keyboardAnimation(from notification: Notification) -> Animation {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let rawCurve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue
        switch rawCurve.flatMap(UIView.AnimationCurve.init(rawValue:)) {
        case .easeIn: return .easeIn(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        case .linear: return .linear(duration: duration)
        default: return .easeInOut(duration: duration)
        }
    }
}

private struct RoomPreviewOverlay: View {
    let room: Room
    let canDelete: Bool
    let canSelectAll: Bool
    let close: () -> Void
    let selectAll: () -> Void
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
                if canSelectAll {
                    Button(action: selectAll) {
                        Label("Выбрать все", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .liquidCard(Capsule())
                }
                Label(deleting ? "Удаление…" : "Удалить комнату", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.red)
                .liquidCard(Capsule())
                .opacity(deleting ? 0.42 : 1)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    guard !deleting else { return }
                    deleting = true
                    Task { await delete(); deleting = false }
                })
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    guard !deleting else { return }
                    deleting = true
                    Task { await delete(); deleting = false }
                }
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
    @EnvironmentObject private var session: SessionStore
    let room: Room
    let members: [RoomMember]
    let currentID: Int?
    let canModerate: Bool
    let moderate: (RoomMember, String) async -> Void
    @State private var selected: RoomMember?
    @State private var profilePreview: UserProfileReference?
    @State private var fullProfile: UserProfileReference?
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showInviteFriends = false
    var body: some View {
        ZStack {
            AcrylicBackground()
            if !showInviteFriends {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Участники").font(.title2.bold())
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { showInviteFriends = true }
                    } label: {
                        Label("Пригласить", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11).frame(height: 36)
                    }
                    .buttonStyle(AlivePressButtonStyle()).liquidCard(Capsule())
                }
                ForEach(members) { member in
                    HStack(spacing: 11) {
                        HStack(spacing: 11) {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(dataURL: member.avatarDataURL, name: member.nickname, size: 46)
                                Circle().fill(member.isOnline ? Color(red: 0.32, green: 0.70, blue: 0.54) : Color.gray.opacity(0.55)).frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 2))
                            }
                            VStack(alignment: .leading) {
                                HStack { Text(member.nickname).bold(); if member.isOwner { Image(systemName: "crown.fill").font(.caption).foregroundStyle(.yellow) }; if member.userId == currentID { Text("Вы").font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).liquidCard(Capsule()) } }
                                Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard member.userId != currentID else { return }
                            profilePreview = UserProfileReference(member)
                        }
                        Spacer(); if member.isMuted { Image(systemName: "speaker.slash.fill").font(.caption).foregroundStyle(.orange) }
                    }.padding(9).liquidCard(RoundedRectangle(cornerRadius: 17))
                        .contentShape(RoundedRectangle(cornerRadius: 17))
                        .onLongPressGesture(minimumDuration: 0.38) {
                            guard member.userId != currentID else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.82)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selected = member }
                        }
                }; Spacer()
            }
            .padding(20)
            .blur(radius: selected == nil ? 0 : 13)
            .scaleEffect(selected == nil ? 1 : 0.985)
            .allowsHitTesting(selected == nil)
            .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if !showInviteFriends, let member = selected {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeModerationMenu() }
                    .transition(.opacity)
                MemberModerationOverlay(member: member, canModerate: canModerate && !member.isOwner, close: closeModerationMenu, profile: {
                    closeModerationMenu()
                    fullProfile = UserProfileReference(member)
                }) { action in
                    closeModerationMenu()
                    Task { await moderate(member, action) }
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(2)
            }

            if showInviteFriends {
                InviteFriendsPanel(room: room, currentMembers: members, close: closeInviteFriends)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .userProfilePresentation(preview: $profilePreview, fullProfile: $fullProfile)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: selected?.id)
        .onChange(of: fullProfile?.id) { _, value in if value != nil { selectedDetent = .large } }
        .presentationDetents([.medium, .large], selection: $selectedDetent).presentationBackground(.clear)
    }

    private func closeModerationMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { selected = nil }
    }

    private func closeInviteFriends() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { showInviteFriends = false }
    }
}

private struct MemberModerationOverlay: View {
    let member: RoomMember
    let canModerate: Bool
    let close: () -> Void
    let profile: () -> Void
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
                Button(action: profile) {
                    HStack(spacing: 13) {
                        Image(systemName: "person.crop.circle").font(.system(size: 17, weight: .semibold)).frame(width: 23)
                        Text("Профиль").font(.body.weight(.medium)); Spacer()
                    }.padding(.horizontal, 16).frame(height: 49).contentShape(Rectangle())
                }.buttonStyle(.plain)
                menuDivider
                Button {
                    UIPasteboard.general.string = member.username
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    close()
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "doc.on.doc").font(.system(size: 17, weight: .semibold)).frame(width: 23)
                        Text("Скопировать username").font(.body.weight(.medium)); Spacer()
                    }.padding(.horizontal, 16).frame(height: 49).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if canModerate {
                    menuDivider
                    moderationButton("speaker.slash.fill", member.isMuted ? "Снять заглушение" : "Заглушить", "mute", color: .orange)
                    menuDivider
                    moderationButton("rectangle.portrait.and.arrow.right", "Выгнать", "kick", color: .primary)
                    menuDivider
                    moderationButton("crown.fill", "Передать управление", "transfer", color: .yellow)
                    menuDivider
                    moderationButton("person.crop.circle.badge.xmark", "Заблокировать", "ban", color: .red)
                }
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

private struct InviteFriendsPanel: View {
    @EnvironmentObject private var deviceEnvironment: DeviceEnvironmentStore
    @EnvironmentObject private var session: SessionStore
    let room: Room
    let currentMembers: [RoomMember]
    let close: () -> Void
    @State private var friends: [FriendProfile] = []
    @State private var selectedIDs = Set<Int>()
    @State private var sentIDs = Set<Int>()
    @State private var sending = false
    @State private var error = ""

    private var availableFriends: [FriendProfile] {
        let memberIDs = Set(currentMembers.map(\.userId))
        return friends.filter { !memberIDs.contains($0.userId) }
    }

    var body: some View {
        VStack(spacing: 13) {
                HStack {
                    Label("Пригласить друзей", systemImage: "person.2.badge.plus")
                        .font(.title3.bold())
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .liquidCard(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(availableFriends) { friend in
                            let selected = selectedIDs.contains(friend.id)
                            let sent = sentIDs.contains(friend.id)
                            HStack(spacing: 11) {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(dataURL: friend.avatarDataURL, name: friend.nickname, size: 46, showsBorder: false)
                                    if presenceIsOnline(isOnline: friend.isOnline, lastSeen: friend.lastSeen, visible: friend.activityVisible) {
                                        Circle().fill(Color(red: 0.32, green: 0.70, blue: 0.54)).frame(width: 10, height: 10)
                                            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 2))
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.nickname).font(.subheadline.bold()).lineLimit(1)
                                    Text("@\(friend.username) · \(presenceText(isOnline: friend.isOnline, lastSeen: friend.lastSeen, lastSeenAgeSeconds: friend.lastSeenAgeSeconds, ageAnchor: friend.presenceSnapshotReceivedAt, visible: friend.activityVisible, now: deviceEnvironment.currentTime))")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if sent {
                                    Label("Отправлено", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(.cyan)
                                } else {
                                    RoomSelectionIndicator(selected: selected).scaleEffect(0.82)
                                }
                            }
                            .padding(9)
                            .passiveLiquidCard(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .onTapGesture {
                                guard !sent else { return }
                                UISelectionFeedbackGenerator().selectionChanged()
                                if selected { selectedIDs.remove(friend.id) } else { selectedIDs.insert(friend.id) }
                            }
                        }
                    }
                }
                if availableFriends.isEmpty {
                    ContentUnavailableView("Некого приглашать", systemImage: "person.2", description: Text("Все друзья уже находятся в комнате."))
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                Button {
                    Task { await sendInvitations() }
                } label: {
                    Label(sending ? "Отправляем…" : "Пригласить (\(selectedIDs.count))", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 46)
                }
                .buttonStyle(AlivePressButtonStyle()).liquidCard(Capsule()).disabled(selectedIDs.isEmpty || sending)
                .opacity(selectedIDs.isEmpty ? 0.48 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { friends = (try? await session.api.friends()) ?? [] }
    }

    private func sendInvitations() async {
        guard !selectedIDs.isEmpty, !sending else { return }
        sending = true; error = ""; defer { sending = false }
        let ids = Array(selectedIDs)
        do {
            try await session.api.inviteFriends(roomID: room.id, userIDs: ids)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                sentIDs.formUnion(ids)
                selectedIDs.removeAll()
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = error.localizedDescription
        }
    }
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
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var deviceEnvironment: DeviceEnvironmentStore
    let messages: [ChatMessage]
    let typingMembers: [RoomMember]
    let currentUserID: Int?
    @Binding var draft: String
    @Binding var focused: Bool
    let keyboardHeight: CGFloat
    let isMuted: Bool
    let typingChanged: (String) -> Void
    let send: (String, String, ChatReplyPreview?) -> Void
    let react: (Int, String) -> Void
    let previewProfile: (ChatMessage) -> Void
    let openProfile: (ChatMessage) -> Void
    // UIKit owns first-responder state for PersistentChatTextField. Using
    // FocusState without a SwiftUI `.focused` attachment makes SwiftUI reset
    // it to false, which immediately dismisses the keyboard after any tap.
    @State private var inputFocused = false
    @State private var inputHeight: CGFloat = 34
    @State private var showPhotoLibrary = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingPhoto: PendingChatPhoto?
    @State private var sticksToBottom = true
    @State private var didInitialScroll = false
    @State private var forceScrollOnNextMessage = false
    @State private var unreadMessageCount = 0
    @State private var unreadSenderNickname = ""
    @State private var unreadSenderAvatar = ""
    @State private var showsUnreadSender = false
    @State private var unreadPreviewToken = UUID()
    @State private var contextMessage: ChatMessage?
    @State private var replyingTo: ChatReplyPreview?
    @State private var requestedMessageID: Int?
    @State private var highlightedMessageID: Int?
    @State private var showStickerPicker = false
    private let quickReactions = [
        "👍", "❤️", "😂", "🔥", "😮", "👏", "😭", "🎬", "🍿", "✨",
        "🥰", "🤣", "😍", "🤔", "😎", "🥳", "😡", "💀", "💯", "👎",
        "🙏", "🙌", "🤝", "💔", "🎉", "🤩", "🥺", "😴", "🤯", "🫡",
    ]
    var body: some View {
        ZStack {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { message in
                                NativeMessageBubble(message: message, isMine: message.authorId == currentUserID, react: react, quickReactions: quickReactions, previewProfile: previewProfile, openProfile: openProfile, reply: beginReply, jumpToMessage: { requestedMessageID = $0 }, showContext: { selected in
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.84)
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { contextMessage = selected }
                                }, isHighlighted: highlightedMessageID == message.id, timePresentationRevision: deviceEnvironment.formattingRevision)
                                    .equatable()
                                    .padding(.bottom, message.id == messages.last?.id ? 14 : 0)
                                    .id(message.id)
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                        .scrollTargetLayout()
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture { focused = false; inputFocused = false }
                    .onScrollGeometryChange(for: Bool.self, of: { geometry in
                        let distanceToBottom = max(0, geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y)
                        // A small manual scroll should still follow the live chat.
                        // Only a deliberate, deeper history scroll pauses it.
                        return distanceToBottom < 260
                    }, action: { wasNearBottom, isNearBottom in
                        // Avoid changing @State on every scroll frame.
                        guard wasNearBottom != isNearBottom else { return }
                        sticksToBottom = isNearBottom
                        if isNearBottom { clearUnreadMessages() }
                    })
                    .onChange(of: messages.count) { oldCount, newCount in
                        let addedCount = max(0, newCount - oldCount)
                        guard addedCount > 0 else { return }
                        if forceScrollOnNextMessage || !didInitialScroll || sticksToBottom {
                            scrollToLatestMessage(proxy, animated: didInitialScroll)
                            clearUnreadMessages()
                            didInitialScroll = true
                            forceScrollOnNextMessage = false
                        } else {
                            let unread = messages.suffix(addedCount).filter {
                                !$0.isSystem && $0.authorId != currentUserID
                            }
                            if let newest = unread.last {
                                showUnreadMessage(from: newest, addedCount: unread.count)
                            }
                        }
                    }
                    .onChange(of: keyboardHeight) { oldHeight, newHeight in
                        // The chat becomes taller as the keyboard closes. Keep
                        // the newest bubbles attached to the composer instead of
                        // leaving them at the top of the expanded scroll view.
                        if oldHeight > 0, newHeight == 0 {
                            inputFocused = false
                            focused = false
                        }
                        guard oldHeight > 0, newHeight == 0, sticksToBottom else { return }
                        // Follow the keyboard animation immediately instead of
                        // showing a wrong intermediate frame and correcting it
                        // after a delay.
                        DispatchQueue.main.async {
                            guard keyboardHeight == 0, sticksToBottom else { return }
                            scrollToLatestMessage(proxy, animated: true)
                        }
                    }
                    .onChange(of: requestedMessageID) { _, messageID in
                        guard let messageID else { return }
                        withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo(messageID, anchor: .center) }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.68)
                        withAnimation(.easeOut(duration: 0.18)) { highlightedMessageID = messageID }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            guard highlightedMessageID == messageID else { return }
                            withAnimation(.easeOut(duration: 0.35)) { highlightedMessageID = nil }
                        }
                        requestedMessageID = nil
                    }
                    .onAppear {
                        guard !didInitialScroll, messages.last != nil else { return }
                        DispatchQueue.main.async {
                            scrollToLatestMessage(proxy, animated: false)
                            didInitialScroll = true
                        }
                    }

                    if unreadMessageCount > 0 {
                        Button {
                            sticksToBottom = true
                            clearUnreadMessages()
                            scrollToLatestMessage(proxy, animated: true)
                        } label: {
                            unreadMessagesIndicator
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .zIndex(5)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: unreadMessageCount > 0)
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 7) {
            if let reply = replyingTo {
                HStack(spacing: 9) {
                    Capsule().fill(.cyan.opacity(0.76)).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reply.nickname).font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                        Text(reply.text.isEmpty ? "Изображение" : reply.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    ChatAccessoryControl(action: cancelReply) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Отменить ответ")
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .passiveLiquidCard(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 7) {
                ChatAccessoryControl(action: presentPhotoLibrary) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .passiveLiquidCard(Circle())
                }
                .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhoto, matching: .images)
                .disabled(isMuted)
                .opacity(isMuted ? 0.42 : 1)
                .onChange(of: selectedPhoto) { _, item in Task { await preparePhoto(item) } }

                ChatAccessoryControl(action: presentStickerPicker) {
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .passiveLiquidCard(Circle())
                }
                .disabled(isMuted).opacity(isMuted ? 0.42 : 1)

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
                        .onChange(of: inputFocused) { _, value in
                            focused = value
                            if value, showStickerPicker {
                                withAnimation(.easeOut(duration: 0.18)) { showStickerPicker = false }
                            }
                        }
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                        .onTapGesture { submit() }
                        .allowsHitTesting(!isMuted)
                        .opacity(isMuted ? 0.42 : 1)
                        .accessibilityAddTraits(.isButton)
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 3)
                .liquidCard(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if showStickerPicker {
                TelegramStickerKeyboard { sticker in
                    sendSticker(sticker)
                } close: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        showStickerPicker = false
                    }
                }
                .frame(height: 286)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            }
            .overlay(alignment: .topLeading) {
                if !typingMembers.isEmpty {
                    TypingParticipantsIndicator(members: typingMembers)
                        .offset(y: -42)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Keep the composer in the unified chat surface.  The old negative
            // offset could make it protrude beyond the lower rounded edge.
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 7)
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
        .onChange(of: draft) { _, value in
            FluentEmojiCache.shared.prefetch(in: value)
            typingChanged(value)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: typingMembers.map(\.userId))
        .onChange(of: messages.count) { _, _ in
            if let text = messages.last?.text { FluentEmojiCache.shared.prefetch(in: text) }
        }
        .contextPreviewBackdrop(active: contextMessage != nil)
        .sheet(item: $pendingPhoto) { photo in
            ChatPhotoEditor(photo: photo) {
                pendingPhoto = nil
            } send: { editedDataURL in
                sticksToBottom = true
                forceScrollOnNextMessage = true
                send("", editedDataURL, replyingTo)
                replyingTo = nil
                pendingPhoto = nil
            }
        }
        }
        .overlayPreferenceValue(MessageBubbleAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let selected = contextMessage {
                    // LazyVStack may recycle the selected row between the long-press
                    // and the preference pass. Previously that left the backdrop
                    // blurred forever because the overlay was conditional on an
                    // anchor that no longer existed. Keep the context UI dismissible
                    // and use a safe in-chat fallback frame for that rare pass.
                    let frame = anchors[selected.id].map { proxy[$0] } ?? CGRect(
                        x: 12,
                        y: max(72, min(proxy.size.height - 170, proxy.size.height * 0.48)),
                        width: max(1, proxy.size.width - 24),
                        height: 76
                    )
                    MessageAnchoredContextOverlay(
                        message: selected,
                        isMine: selected.authorId == currentUserID,
                        frame: frame,
                        containerSize: proxy.size,
                        emojis: quickReactions,
                        react: { emoji in
                            react(selected.id, emoji)
                            withAnimation { contextMessage = nil }
                        },
                        copy: {
                            UIPasteboard.general.string = selected.text
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation { contextMessage = nil }
                        },
                        reply: {
                            beginReply(selected)
                            withAnimation { contextMessage = nil }
                        },
                        close: { withAnimation { contextMessage = nil } }
                    )
                }
            }
        }
    }
    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sticksToBottom = true
        forceScrollOnNextMessage = true
        send(text, "", replyingTo)
        replyingTo = nil
        draft = ""
    }

    private func cancelReply() {
        guard replyingTo != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
        withAnimation(.easeOut(duration: 0.16)) { replyingTo = nil }
    }

    private func presentPhotoLibrary() {
        guard !isMuted, !showPhotoLibrary, pendingPhoto == nil else { return }
        withAnimation(.easeOut(duration: 0.16)) { showStickerPicker = false }
        prepareForAccessoryPresentation()
        DispatchQueue.main.async { showPhotoLibrary = true }
    }

    private func presentStickerPicker() {
        guard !isMuted else { return }
        if showStickerPicker {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showStickerPicker = false }
            return
        }
        prepareForAccessoryPresentation()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showStickerPicker = true }
        }
    }

    private func prepareForAccessoryPresentation() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.72)
        focused = false
        inputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func sendSticker(_ sticker: TelegramSticker) {
        // A full Lottie/WebM payload can exceed the chat JSON limit. Store a
        // tiny stable reference; every room participant fetches the same file.
        sticksToBottom = true
        forceScrollOnNextMessage = true
        send("", "sticker://\(sticker.id)/\(sticker.format)", replyingTo)
        replyingTo = nil
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
    private func beginReply(_ message: ChatMessage) {
        guard !message.isSystem, message.id > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.82)
        replyingTo = ChatReplyPreview(id: message.id, authorId: message.authorId, nickname: message.nickname, text: message.text, hasImage: !message.imageDataURL.isEmpty)
        inputFocused = true
        focused = true
    }
    private var unreadMessagesIndicator: some View {
        HStack(spacing: 8) {
            ZStack {
                if showsUnreadSender {
                    AvatarView(dataURL: unreadSenderAvatar, name: unreadSenderNickname, size: 32, showsBorder: false)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(unreadMessageCount)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.cyan)
                        .contentTransition(.numericText())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 32, height: 32)

            if showsUnreadSender {
                Text(unreadSenderNickname)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 132, alignment: .leading)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                Text("+\(unreadMessageCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, showsUnreadSender ? 9 : 5)
        .frame(height: 42)
        .liquidCard(Capsule())
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: showsUnreadSender)
        .accessibilityLabel("Новых сообщений: \(unreadMessageCount)")
    }
    private func showUnreadMessage(from message: ChatMessage, addedCount: Int) {
        unreadMessageCount += addedCount
        unreadSenderNickname = message.nickname
        unreadSenderAvatar = message.avatarDataURL
        let token = UUID()
        unreadPreviewToken = token
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            showsUnreadSender = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard unreadPreviewToken == token, unreadMessageCount > 0 else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showsUnreadSender = false
            }
        }
    }
    private func clearUnreadMessages() {
        unreadPreviewToken = UUID()
        unreadMessageCount = 0
        showsUnreadSender = false
    }
}

private struct TypingParticipantsIndicator: View {
    let members: [RoomMember]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(members.prefix(4)) { member in
                    HStack(spacing: 7) {
                        AvatarView(
                            dataURL: member.avatarDataURL,
                            name: member.nickname,
                            size: 27,
                            showsBorder: false
                        )
                        BouncingTypingDots()
                    }
                    .padding(.horizontal, 3)
                    .frame(height: 35)
                    .shadow(color: .black.opacity(0.30), radius: 6, y: 3)
                    .accessibilityLabel("\(member.nickname) is typing")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(height: 39)
    }
}

private struct BouncingTypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.cyan.opacity(0.9))
                        .frame(width: 4.5, height: 4.5)
                        .offset(y: CGFloat(sin(time * 6.2 - Double(index) * 0.9)) * 2.4)
                }
            }
            .frame(width: 20, height: 16)
        }
        .accessibilityHidden(true)
    }
}

private struct TelegramStickerKeyboard: View {
    @EnvironmentObject private var session: SessionStore
    let select: (TelegramSticker) -> Void
    let close: () -> Void
    @State private var packs: [TelegramStickerPack] = []
    @State private var selectedPackID: Int?
    @State private var showsRecents = false
    @State private var recentStickers: [TelegramSticker] = []

    private var visibleStickers: [TelegramSticker] {
        if showsRecents { return recentStickers }
        return packs.first(where: { $0.id == selectedPackID })?.stickers ?? []
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            showsRecents = true
                        } label: {
                            Image(systemName: "clock")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(showsRecents ? .cyan : Color.white.opacity(0.66))
                                .frame(width: 40, height: 40)
                                .background(showsRecents ? Color.cyan.opacity(0.12) : Color.white.opacity(0.055), in: Circle())
                                .overlay(Circle().stroke(showsRecents ? Color.cyan.opacity(0.34) : Color.white.opacity(0.11), lineWidth: 0.8))
                                .symbolEffect(.bounce, value: showsRecents)
                        }
                        .buttonStyle(AlivePressButtonStyle())
                        .accessibilityLabel("Недавние стикеры")

                        ForEach(packs) { pack in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                showsRecents = false
                                selectedPackID = pack.id
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(!showsRecents && selectedPackID == pack.id ? Color.white.opacity(0.1) : .clear)
                                    if let cover = pack.stickers.first {
                                        TelegramStickerThumbnail(sticker: cover, size: 34)
                                    } else {
                                        Image(systemName: "face.smiling")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 42, height: 42)
                                .overlay(Circle().stroke(!showsRecents && selectedPackID == pack.id ? Color.cyan.opacity(0.42) : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(pack.title)
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                Button(action: close) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .passiveLiquidCard(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
            if packs.isEmpty && !showsRecents {
                ContentUnavailableView("Нет наборов", systemImage: "face.smiling", description: Text("Импортируй набор в настройках профиля"))
                    .frame(maxHeight: .infinity)
            } else if showsRecents && recentStickers.isEmpty {
                ContentUnavailableView("Недавних пока нет", systemImage: "clock", description: Text("Отправленные стикеры появятся здесь"))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                        ForEach(visibleStickers) { sticker in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                choose(sticker)
                            } label: {
                                TelegramStickerThumbnail(sticker: sticker)
                                    .frame(width: 54, height: 54)
                                    .clipped()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .contentShape(Rectangle())
                            .clipped()
                            .buttonStyle(ImmediateGalleryButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 0.8))
        .task {
            recentStickers = StickerRecentsStore.load(userID: session.profile?.userId)
            packs = (try? await session.api.stickerPacks()) ?? []
            if selectedPackID == nil { selectedPackID = packs.first?.id }
            if packs.isEmpty && !recentStickers.isEmpty { showsRecents = true }
        }
    }

    private func choose(_ sticker: TelegramSticker) {
        recentStickers = StickerRecentsStore.record(sticker, userID: session.profile?.userId)
        select(sticker)
    }
}

private struct TelegramStickerThumbnail: View {
    @EnvironmentObject private var session: SessionStore
    let sticker: TelegramSticker
    var size: CGFloat = 54
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Color.white.opacity(0.035)
                    if failed {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: sticker.id) {
            if let cached = StickerThumbnailCache.shared.image(for: sticker.id) {
                image = cached
                return
            }
            // Telegram provides a lightweight, correctly framed WebP preview.
            // Playing every full Lottie JSON in a scrolling grid saturates the
            // main thread/GPU and is the source of the picker stutter.
            guard let data = try? await session.api.stickerData(id: sticker.id, preview: true) else {
                failed = true
                return
            }
            // New imports have WebP previews. Older imported animated packs may
            // return their original Lottie JSON here; UIImage cannot decode it,
            // which used to expose the Telegram emoji as an ugly placeholder.
            // Render one real, non-playing frame and cache it instead.
            let decoded = UIImage(data: data) ?? Self.renderLottiePreview(from: data)
            image = decoded
            failed = decoded == nil
            if let decoded { StickerThumbnailCache.shared.insert(decoded, for: sticker.id) }
        }
    }

    @MainActor
    private static func renderLottiePreview(from data: Data) -> UIImage? {
        guard let animation = try? LottieAnimation.from(data: data) else { return nil }
        let size = CGSize(width: 162, height: 162)
        let animationView = LottieAnimationView(animation: animation)
        animationView.frame = CGRect(origin: .zero, size: size)
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundColor = .clear
        animationView.currentProgress = 0.12
        animationView.layoutIfNeeded()
        animationView.forceDisplayUpdate()
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            animationView.layer.render(in: context.cgContext)
        }
    }
}

private final class StickerThumbnailCache {
    static let shared = StickerThumbnailCache()
    private let cache = NSCache<NSNumber, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 20 * 1_024 * 1_024
    }

    func image(for id: Int) -> UIImage? { cache.object(forKey: NSNumber(value: id)) }
    func insert(_ image: UIImage, for id: Int) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: NSNumber(value: id), cost: cost)
    }
}

private struct TelegramStickerMedia: View {
    @EnvironmentObject private var session: SessionStore
    let dataURL: String
    @State private var isVisible = false
    @State private var remoteDataURL = ""

    private var reference: TelegramStickerReference? {
        TelegramStickerReference(dataURL: dataURL)
    }

    private var resolvedDataURL: String {
        reference == nil ? dataURL : remoteDataURL
    }

    var body: some View {
        Group {
            if resolvedDataURL.isEmpty {
                ProgressView().controlSize(.small)
            } else if resolvedDataURL.lowercased().hasPrefix("data:application/json;") {
                LottieStickerView(dataURL: resolvedDataURL, isPlaying: isVisible)
            } else if resolvedDataURL.lowercased().hasPrefix("data:video/") {
                WebVideoStickerView(dataURL: resolvedDataURL, isPlaying: isVisible)
            } else {
                DataURLImage(dataURL: resolvedDataURL, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: dataURL) {
            guard let reference else {
                remoteDataURL = ""
                return
            }
            guard let data = try? await session.api.stickerData(id: reference.id, preview: false) else { return }
            let mime: String
            switch reference.format {
            case "animated": mime = "application/json"
            case "video": mime = "video/webm"
            default: mime = "image/webp"
            }
            remoteDataURL = "data:\(mime);base64," + data.base64EncodedString()
        }
    }
}

private struct TelegramStickerReference {
    let id: Int
    let format: String

    init?(dataURL: String) {
        guard dataURL.lowercased().hasPrefix("sticker://") else { return nil }
        let parts = dataURL.dropFirst("sticker://".count).split(separator: "/", maxSplits: 1)
        guard let rawID = parts.first, let id = Int(rawID) else { return nil }
        self.id = id
        self.format = parts.count > 1 ? String(parts[1]).lowercased() : "static"
    }
}

private struct LottieStickerView: UIViewRepresentable {
    let dataURL: String
    let isPlaying: Bool

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: ContainerView, context: Context) {
        guard context.coordinator.loadedDataURL != dataURL else {
            updatePlayback(of: view.animationView)
            return
        }
        load(into: view, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func load(into view: ContainerView, coordinator: Coordinator) {
        guard let data = Self.data(from: dataURL),
              let animation = try? LottieAnimation.from(data: data) else { return }
        coordinator.loadedDataURL = dataURL
        view.animationView.animation = animation
        view.animationView.currentProgress = 0
        updatePlayback(of: view.animationView)
    }

    private func updatePlayback(of view: LottieAnimationView) {
        if isPlaying {
            if !view.isAnimationPlaying { view.play() }
        } else if view.isAnimationPlaying {
            view.pause()
        }
    }

    private static func data(from dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }

    final class Coordinator {
        var loadedDataURL = ""
    }

    final class ContainerView: UIView {
        let animationView = LottieAnimationView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.masksToBounds = true
            animationView.translatesAutoresizingMaskIntoConstraints = false
            animationView.contentMode = .scaleAspectFit
            animationView.clipsToBounds = true
            animationView.layer.masksToBounds = true
            animationView.loopMode = .loop
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.isUserInteractionEnabled = false
            addSubview(animationView)
            NSLayoutConstraint.activate([
                animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
                animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
                animationView.topAnchor.constraint(equalTo: topAnchor),
                animationView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: CGSize { .zero }
    }
}

private struct WebVideoStickerView: UIViewRepresentable {
    let dataURL: String
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.loadedDataURL != dataURL {
            load(into: view, coordinator: context.coordinator)
        } else {
            updatePlayback(of: view)
        }
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        coordinator.loadedDataURL = dataURL
        let autoplay = isPlaying ? "autoplay" : ""
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}video{width:100%;height:100%;object-fit:contain}</style></head><body><video src="\(dataURL)" \(autoplay) loop muted playsinline></video></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    private func updatePlayback(of view: WKWebView) {
        let command = isPlaying
            ? "document.querySelector('video')?.play().catch(()=>{});"
            : "document.querySelector('video')?.pause();"
        view.evaluateJavaScript(command)
    }

    final class Coordinator {
        var loadedDataURL = ""
    }
}

private struct ImmediateGalleryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

private struct AlivePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// Chat accessory buttons sit next to a UIKit text view and underneath the
/// room's drag gestures. A regular SwiftUI Button can lose its first tap while
/// the text view resigns first responder or interactive glass claims the press.
/// Owning the zero-distance gesture gives immediate visual feedback and a
/// deterministic single action, while passive glass preserves the same look.
private struct ChatAccessoryControl<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @GestureState private var isPressed = false
    @State private var activationTick = 0

    var body: some View {
        label()
            .scaleEffect(isPressed ? 0.91 : 1)
            .opacity(isPressed ? 0.84 : 1)
            .symbolEffect(.bounce, value: activationTick)
            .contentShape(Rectangle())
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.62), value: isPressed)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($isPressed) { value, state, _ in
                        state = abs(value.translation.width) < 18 && abs(value.translation.height) < 18
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) < 18,
                              abs(value.translation.height) < 18 else { return }
                        activationTick += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.64)
                        action()
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

private struct PendingChatPhoto: Identifiable {
    let id = UUID()
    let dataURL: String
}

private struct ChatPhotoEditor: View {
    @Environment(\.dismiss) private var dismiss
    let photo: PendingChatPhoto
    let cancel: () -> Void
    let send: (String) -> Void
    @State private var drawing = PKDrawing()
    @State private var drawingMode = false
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    @State private var cropAspect: CGFloat = 1
    @State private var previewSize = CGSize(width: 300, height: 300)

    private var sourceImage: UIImage? {
        guard let comma = photo.dataURL.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(photo.dataURL[photo.dataURL.index(after: comma)...])).flatMap(UIImage.init(data:))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(drawingMode ? "Рисование" : "Обрезка")
                .font(.headline)
                Spacer()
                Text(drawingMode ? "Проведи пальцем" : "Потяни или приблизь")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let size = cropSize(in: proxy.size)
                ZStack {
                    Color.black
                    if let sourceImage {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(zoom)
                            .offset(offset)
                    }
                    DrawingCanvas(drawing: $drawing, isDrawing: drawingMode)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { previewSize = size }
                .onChange(of: proxy.size) { _, _ in previewSize = cropSize(in: proxy.size) }
                .onChange(of: cropAspect) { _, _ in
                    previewSize = cropSize(in: proxy.size)
                    drawing = PKDrawing()
                    zoom = 1
                    offset = .zero
                    settledOffset = .zero
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard !drawingMode else { return }
                            offset = CGSize(
                                width: settledOffset.width + value.translation.width,
                                height: settledOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            guard !drawingMode else { return }
                            settledOffset = offset
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            guard !drawingMode else { return }
                            zoom = min(4, max(1, value))
                        }
                )
            }
            .frame(height: 340)

            HStack(spacing: 9) {
                Button {
                    cropAspect = cropAspect == 1 ? 4.0 / 5.0 : cropAspect == 4.0 / 5.0 ? 16.0 / 9.0 : 1
                } label: {
                    Label("Кадр", systemImage: "crop")
                }
                .buttonStyle(PhotoEditToolButton(active: !drawingMode))

                Button {
                    drawingMode.toggle()
                } label: {
                    Label("Рисовать", systemImage: "pencil.tip")
                }
                .buttonStyle(PhotoEditToolButton(active: drawingMode))

                Button {
                    drawing = PKDrawing()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(PhotoEditToolButton(active: false))
                .disabled(drawing.strokes.isEmpty)
            }

            HStack(spacing: 10) {
                Button {
                    cancel()
                    dismiss()
                } label: {
                    Text("Отмена").frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
                }
                .liquidCard(Capsule())
                Button {
                    guard let dataURL = editedDataURL() else { return }
                    send(dataURL)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(30)
    }

    private func cropSize(in available: CGSize) -> CGSize {
        let width = max(1, available.width)
        let height = min(available.height, width / cropAspect)
        if height < available.height { return CGSize(width: width, height: height) }
        return CGSize(width: available.height * cropAspect, height: available.height)
    }

    private func editedDataURL() -> String? {
        guard let sourceImage, previewSize.width > 0, previewSize.height > 0 else { return nil }
        let outputWidth = min(1_440, max(720, previewSize.width * 3))
        let outputSize = CGSize(width: outputWidth, height: outputWidth / cropAspect)
        let baseScale = max(previewSize.width / sourceImage.size.width, previewSize.height / sourceImage.size.height)
        let previewImageSize = CGSize(
            width: sourceImage.size.width * baseScale * zoom,
            height: sourceImage.size.height * baseScale * zoom
        )
        let previewOrigin = CGPoint(
            x: (previewSize.width - previewImageSize.width) / 2 + offset.width,
            y: (previewSize.height - previewImageSize.height) / 2 + offset.height
        )
        let outputScale = outputSize.width / previewSize.width
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let edited = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: outputSize))
            sourceImage.draw(in: CGRect(
                x: previewOrigin.x * outputScale,
                y: previewOrigin.y * outputScale,
                width: previewImageSize.width * outputScale,
                height: previewImageSize.height * outputScale
            ))
            let marks = drawing.image(from: CGRect(origin: .zero, size: previewSize), scale: outputScale)
            marks.draw(in: CGRect(origin: .zero, size: outputSize))
        }
        guard var jpeg = edited.jpegData(compressionQuality: 0.82) else { return nil }
        if jpeg.count > 1_850_000, let smaller = edited.jpegData(compressionQuality: 0.56) { jpeg = smaller }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

private struct PhotoEditToolButton: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? .cyan : .primary)
            .frame(height: 36)
            .padding(.horizontal, 12)
            .background(active ? .cyan.opacity(0.13) : .white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(active ? 0.18 : 0.08), lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let isDrawing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput
        view.tool = PKInkingTool(.pen, color: .systemCyan, width: 5)
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if view.drawing.dataRepresentation() != drawing.dataRepresentation() {
            view.drawing = drawing
        }
        view.isUserInteractionEnabled = isDrawing
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas

        init(parent: DrawingCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
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
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
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
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func updatePlaceholder() {
            placeholderLabel.text = placeholderText
            placeholderLabel.isHidden = !text.isEmpty
        }
        @discardableResult
        func refreshLayout() -> CGFloat {
            guard bounds.width > 1 else { return 34 }
            let availableWidth = bounds.width
            let requiredHeight = sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude)).height
            let fittedHeight = min(96, max(34, ceil(requiredHeight)))
            let shouldScroll = requiredHeight > 96
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

struct NativeMessageBubble: View, Equatable {
    let message: ChatMessage; let isMine: Bool; let react: (Int, String) -> Void; let quickReactions: [String]
    let previewProfile: (ChatMessage) -> Void
    let openProfile: (ChatMessage) -> Void
    let reply: (ChatMessage) -> Void
    let jumpToMessage: (Int) -> Void
    let showContext: (ChatMessage) -> Void
    var reportsAnchor = true
    var isHighlighted = false
    var timePresentationRevision = 0
    @GestureState private var replyDragOffset: CGFloat = 0

    static func == (lhs: NativeMessageBubble, rhs: NativeMessageBubble) -> Bool {
        // `react` is an action, not display data. Redraw only when this row's content changes.
        lhs.message == rhs.message && lhs.isMine == rhs.isMine && lhs.quickReactions == rhs.quickReactions && lhs.reportsAnchor == rhs.reportsAnchor && lhs.isHighlighted == rhs.isHighlighted && lhs.timePresentationRevision == rhs.timePresentationRevision
    }
    private var containsEmoji: Bool {
        message.text.unicodeScalars.contains { scalar in
            (0x1F000...0x1FAFF).contains(Int(scalar.value)) || (0x2600...0x27FF).contains(Int(scalar.value))
        }
    }
    private var sentTime: String {
        ChatTimestampFormatter.string(
            from: message.createdAt,
            ageSeconds: message.createdAtAgeSeconds,
            ageAnchor: message.timestampSnapshotReceivedAt
        )
    }
    private var isStickerMessage: Bool {
        guard message.text.isEmpty else { return false }
        let value = message.imageDataURL.lowercased()
        return value.hasPrefix("sticker://")
            || value.hasPrefix("data:image/webp;")
            || value.hasPrefix("data:application/json;")
            || value.hasPrefix("data:video/webm;")
    }
    private var interactiveAvatar: some View {
        AvatarView(dataURL: message.avatarDataURL, name: message.nickname, size: 38, showsBorder: false)
            .contentShape(Circle())
            .onTapGesture { previewProfile(message) }
            .contextMenu {
                Button("Профиль", systemImage: "person.crop.circle") { openProfile(message) }
            }
    }

    // Measure the actual rendered text instead of assigning broad character
    // buckets. A one-letter reply stays Telegram-compact while sentences grow
    // naturally until they reach the readable maximum width.
    private var bubbleWidth: CGFloat {
        let reactionWidth: CGFloat = message.reactions.count >= 2 ? 116 : message.reactions.isEmpty ? 0 : 58
        if isStickerMessage { return max(142, reactionWidth) }
        if !message.imageDataURL.isEmpty { return max(230, reactionWidth) }
        if emojiOnly.count == 1 { return max(72, reactionWidth) }
        if emojiOnly.count == 2 { return max(112, reactionWidth) }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        let font = UIFont.systemFont(ofSize: 15, weight: .regular)
        let measuredText = ceil(text.size(withAttributes: [.font: font]).width)
        let timeFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        let measuredTime = ceil((sentTime as NSString).size(withAttributes: [.font: timeFont]).width)
        let naturalWidth = min(238, max(54, max(measuredText, measuredTime) + 18))
        return max(naturalWidth, reactionWidth, message.replyTo == nil ? 0 : 154)
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
                    .font(.system(size: 15, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var bubbleFill: Color {
        if isHighlighted { return Color.cyan.opacity(0.17) }
        if isStickerMessage { return Color.clear }
        return isMine ? Color.indigo.opacity(0.18) : Color.white.opacity(0.055)
    }

    private var bubbleStroke: Color {
        isHighlighted ? Color.cyan.opacity(0.72) : Color.white.opacity(isStickerMessage ? 0 : 0.08)
    }

    private var replyIndicatorOpacity: Double {
        Double(min(1, replyDragOffset / 42))
    }

    private var replyIndicatorScale: CGFloat {
        0.72 + min(1, replyDragOffset / 52) * 0.28
    }

    private var replyIndicator: some View {
        Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.cyan)
            .opacity(replyIndicatorOpacity)
            .scaleEffect(replyIndicatorScale)
            .offset(x: -28)
    }

    private var replySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($replyDragOffset) { value, state, _ in
                guard value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height) * 1.15 else { return }
                state = min(58, value.translation.width * 0.72)
            }
            .onEnded { value in
                guard value.translation.width > 52,
                      abs(value.translation.width) > abs(value.translation.height) * 1.35 else { return }
                reply(message)
            }
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let original = message.replyTo {
                Button { jumpToMessage(original.id) } label: {
                    HStack(spacing: 7) {
                        Capsule().fill(.cyan.opacity(0.78)).frame(width: 3, height: 29)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(original.nickname).font(.caption2.weight(.semibold)).foregroundStyle(.cyan)
                            Text(original.text.isEmpty ? "Изображение" : original.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            messageContent
            if isStickerMessage {
                TelegramStickerMedia(dataURL: message.imageDataURL)
                    .frame(width: 132, height: 132)
            } else if !message.imageDataURL.isEmpty {
                DataURLImage(dataURL: message.imageDataURL)
                    .frame(maxWidth: 210, minHeight: 80, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { }
            }
            if !sentTime.isEmpty {
                Text(sentTime)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            reactionChips
        }
        .padding(.horizontal, isStickerMessage ? 5 : 9)
        .padding(.vertical, isStickerMessage ? 3 : 7)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(bubbleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(bubbleStroke, lineWidth: isHighlighted ? 1.2 : 1))
        .overlay(alignment: .leading) { replyIndicator }
        .shadow(color: isHighlighted ? Color.cyan.opacity(0.24) : Color.clear, radius: 10)
        .offset(x: replyDragOffset)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.82), value: replyDragOffset)
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        .onLongPressGesture(minimumDuration: 0.44, maximumDistance: 8) { showContext(message) }
        .simultaneousGesture(replySwipeGesture)
    }

    @ViewBuilder private var reactionChips: some View {
        if !message.reactions.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(message.reactions.prefix(2))) { item in
                    Button { react(message.id, item.emoji) } label: {
                        HStack(spacing: 4) {
                            FluentEmojiGlyph(item.emoji, size: 19)
                            Text("\(item.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            item.reacted ? Color.cyan.opacity(0.18) : Color.white.opacity(0.055),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(item.reacted ? 0.18 : 0.08), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        }
    }

    @ViewBuilder private var messageRow: some View {
        if message.isSystem {
            Text(message.text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 6).liquidCard(Capsule()).frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 8) {
                if !isMine { interactiveAvatar }
                if isMine { Spacer(minLength: 0) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    Text(message.nickname)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 5)
                        .frame(width: 238, alignment: isMine ? .trailing : .leading)
                    bubble
                }
                .frame(width: 238, alignment: isMine ? .trailing : .leading)
                if isMine { AvatarView(dataURL: message.avatarDataURL, name: message.nickname, size: 38, showsBorder: false) } else { Spacer(minLength: 0) }
            }
        }
    }

    @ViewBuilder var body: some View {
        if reportsAnchor {
            messageRow.anchorPreference(key: MessageBubbleAnchorKey.self, value: .bounds) { [message.id: $0] }
        } else {
            messageRow
        }
    }
}

private struct MessageBubbleAnchorKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct ReactionPickerBar: View {
    let emojis: [String]
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 4) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        select(emoji)
                    } label: {
                        FluentEmojiGlyph(emoji, size: 24)
                            .frame(width: 24, height: 24)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.055), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
        }
        .scrollIndicators(.hidden)
        .frame(width: 282, height: 48)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { emojis.forEach { FluentEmojiCache.shared.prefetch(in: $0) } }
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
    let dataURL: String
    let name: String
    let size: CGFloat
    let showsBorder: Bool

    init(dataURL: String, name: String, size: CGFloat, showsBorder: Bool = true) {
        self.dataURL = dataURL
        self.name = name
        self.size = size
        self.showsBorder = showsBorder
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.52, blue: 0.56), Color(red: 0.16, green: 0.28, blue: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if !dataURL.isEmpty {
                DataURLImage(dataURL: dataURL)
                    .clipShape(Circle())
                    .padding(showsBorder ? 2 : 0)
            } else {
                Text(name.prefix(1)).font(.system(size: max(12, size * 0.38), weight: .bold, design: .rounded))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.26), radius: 7, y: 3)
    }
}

private struct MessageAnchoredContextOverlay: View {
    @EnvironmentObject private var deviceEnvironment: DeviceEnvironmentStore
    let message: ChatMessage
    let isMine: Bool
    let frame: CGRect
    let containerSize: CGSize
    let emojis: [String]
    let react: (String) -> Void
    let copy: () -> Void
    let reply: () -> Void
    let close: () -> Void

    private var reactionsY: CGFloat {
        frame.minY > 68 ? frame.minY - 32 : min(containerSize.height - 32, frame.maxY + 32)
    }

    private var copyY: CGFloat {
        let below = frame.maxY + 30
        if below < containerSize.height - 28 { return below }
        return max(28, frame.minY - 30)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close)

            ReactionPickerBar(emojis: emojis, select: react)
                .position(x: containerSize.width / 2, y: reactionsY)

            NativeMessageBubble(
                message: message,
                isMine: isMine,
                react: { _, emoji in react(emoji) },
                quickReactions: emojis,
                previewProfile: { _ in },
                openProfile: { _ in },
                reply: { _ in reply() },
                jumpToMessage: { _ in },
                showContext: { _ in },
                reportsAnchor: false,
                timePresentationRevision: deviceEnvironment.formattingRevision
            )
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(1.035)
            .shadow(color: .black.opacity(0.42), radius: 18, y: 10)
            .position(x: frame.midX, y: frame.midY)

            HStack(spacing: 8) {
                Button(action: reply) {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.8))
                }
                if !message.text.isEmpty {
                    Button(action: copy) {
                        Label("Скопировать", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.8))
                    }
                }
            }
            .frame(width: min(306, containerSize.width - 28))
            .buttonStyle(.plain)
            .position(x: containerSize.width / 2, y: copyY)
        }
        .transition(.opacity)
    }
}

struct UserProfileReference: Identifiable, Hashable {
    let id: Int
    let username: String
    let nickname: String
    let avatarDataURL: String
    let isFriend: Bool

    init(id: Int, username: String, nickname: String, avatarDataURL: String, isFriend: Bool = false) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.avatarDataURL = avatarDataURL
        self.isFriend = isFriend
    }
    init(_ person: FriendProfile) {
        self.init(id: person.userId, username: person.username, nickname: person.nickname, avatarDataURL: person.avatarDataURL, isFriend: person.isFriend)
    }
    init(_ member: RoomMember) {
        self.init(id: member.userId, username: member.username, nickname: member.nickname, avatarDataURL: member.avatarDataURL)
    }
    init(_ message: ChatMessage) {
        self.init(id: message.authorId, username: "", nickname: message.nickname, avatarDataURL: message.avatarDataURL)
    }
}

private struct UserProfilePresentationModifier: ViewModifier {
    @Binding var preview: UserProfileReference?
    @Binding var fullProfile: UserProfileReference?

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(preview == nil && fullProfile == nil)
            if let user = preview, fullProfile == nil {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closePreview() }
                    .transition(.opacity)
                    .zIndex(80)
                VStack {
                    Spacer(minLength: 42)
                    UserProfilePreviewCard(user: user, close: closePreview) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            preview = nil
                            fullProfile = user
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(81)
            }
            if let user = fullProfile {
                PublicProfileScreen(user: user) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { fullProfile = nil }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(90)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: preview?.id)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: fullProfile?.id)
    }

    private func closePreview() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { preview = nil }
    }
}

private extension View {
    func userProfilePresentation(preview: Binding<UserProfileReference?>, fullProfile: Binding<UserProfileReference?>) -> some View {
        modifier(UserProfilePresentationModifier(preview: preview, fullProfile: fullProfile))
    }
}

private struct UserProfilePreviewCard: View {
    @EnvironmentObject private var session: SessionStore
    let user: UserProfileReference
    let close: () -> Void
    let openFull: () -> Void
    @State private var profile: PublicUserProfile?
    @GestureState private var dragY: CGFloat = 0

    private var shownName: String { profile?.nickname ?? user.nickname }
    private var shownUsername: String { profile?.username ?? user.username }
    private var shownAvatar: String { profile?.avatarDataURL ?? user.avatarDataURL }

    var body: some View {
        VStack(spacing: 13) {
            Capsule().fill(.white.opacity(0.28)).frame(width: 38, height: 5).padding(.top, 2)
            AvatarView(dataURL: shownAvatar, name: shownName, size: 84, showsBorder: false)
            VStack(spacing: 2) {
                Text(shownName).font(.title3.bold()).lineLimit(1)
                if !shownUsername.isEmpty { Text("@\(shownUsername)").font(.subheadline).foregroundStyle(.secondary) }
            }
            if let watching = profile?.nowWatching {
                CurrentWatchingPreview(watching: watching)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if let stats = profile?.stats {
                HStack(spacing: 8) {
                    previewMetric("play.fill", compactDuration(stats.watchedSeconds), "просмотрено")
                    previewMetric("flame.fill", "\(stats.currentStreakDays ?? 0)", "дней подряд")
                    previewMetric("film.fill", "\(stats.genres.count)", "жанров")
                }
                if !stats.genres.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(stats.genres.prefix(3)) { genre in
                            Text(genre.name).font(.caption2.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 6).liquidCard(Capsule())
                        }
                    }
                }
            } else if profile?.analyticsVisible == false {
                Label("Аналитика доступна друзьям", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Button(action: openFull) {
                Label("Открыть профиль", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .liquidCard(Capsule())
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.36), radius: 26, y: 14)
        .offset(y: max(0, dragY))
        .gesture(DragGesture(minimumDistance: 8)
            .updating($dragY) { value, state, _ in if value.translation.height > 0 { state = value.translation.height } }
            .onEnded { value in if value.translation.height > 78 || value.predictedEndTranslation.height > 150 { close() } })
        .task(id: user.id) {
            while !Task.isCancelled {
                if let refreshed = try? await session.api.publicProfile(userID: user.id) {
                    withAnimation(.easeInOut(duration: 0.22)) { profile = refreshed }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func previewMetric(_ icon: String, _ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(.cyan)
            Text(value).font(.caption.weight(.bold)).lineLimit(1)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).liquidCard(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CurrentWatchingPreview: View {
    let watching: CurrentWatching
    @State private var player: AVPlayer?
    @State private var resolvedDuration: Double = 0
    @State private var itemStatusObservation: NSKeyValueObservation?

    private var effectiveDuration: Double {
        if resolvedDuration.isFinite, resolvedDuration > 0 { return resolvedDuration }
        return watching.durationSeconds.isFinite ? max(0, watching.durationSeconds) : 0
    }

    var body: some View {
        VStack(spacing: 9) {
            ZStack(alignment: .bottom) {
                // Never flash a thumbnail/gradient pretending to be the live
                // preview. The surface is black only until AVPlayer produces
                // its first real frame, then it continuously renders the same
                // media clock as the watched user.
                Color.black
                if let player {
                    BarePlayerSurface(player: player)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.74)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                HStack(spacing: 7) {
                    Circle().fill(.cyan).frame(width: 7, height: 7)
                        .shadow(color: .cyan.opacity(0.65), radius: 5)
                    Text("Смотрит сейчас")
                        .font(.caption2.weight(.bold))
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 11)
                .padding(.bottom, 9)
            }
            .frame(height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.8))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7) {
                Text(watching.title.isEmpty ? "Видео" : watching.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let position = projectedPosition(at: context.date)
                    VStack(spacing: 5) {
                        GeometryReader { proxy in
                            let ratio = effectiveDuration > 0
                                ? min(1, max(0, position / effectiveDuration)) : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.11))
                                Capsule().fill(.cyan.opacity(0.82))
                                    .frame(width: max(5, proxy.size.width * ratio))
                            }
                        }
                        .frame(height: 4)
                        HStack {
                            Text(clock(position))
                            Spacer()
                            Text(clock(effectiveDuration))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .liquidCard(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task(id: watching.previewURL) { await configurePlayer() }
        .onChange(of: watching.positionSeconds) { _, _ in synchronizePlayer() }
        .onChange(of: watching.isPlaying) { _, _ in synchronizePlayer() }
        .onChange(of: watching.serverUpdatedAt) { _, _ in synchronizePlayer() }
        .onChange(of: watching.durationSeconds) { _, value in
            if resolvedDuration <= 0, value.isFinite, value > 0 { resolvedDuration = value }
        }
        .onDisappear { tearDownPlayer() }
    }

    @MainActor
    private func configurePlayer() async {
        tearDownPlayer()
        guard let url = URL(string: watching.previewURL), !watching.previewURL.isEmpty else {
            return
        }
        let options: [String: Any] = watching.headers.isEmpty
            ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": watching.headers]
        let asset = AVURLAsset(url: url, options: options)
        resolvedDuration = watching.durationSeconds.isFinite ? max(0, watching.durationSeconds) : 0
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        let previewPlayer = AVPlayer(playerItem: item)
        previewPlayer.isMuted = true
        previewPlayer.volume = 0
        previewPlayer.automaticallyWaitsToMinimizeStalling = true
        previewPlayer.actionAtItemEnd = .pause
        player = previewPlayer
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { observedItem, _ in
            Task { @MainActor in
                guard self.player === previewPlayer else { return }
                if observedItem.status == .readyToPlay {
                    self.synchronizePlayer()
                }
            }
        }
        Task {
            let loaded = try? await asset.load(.duration)
            guard !Task.isCancelled,
                  self.player === previewPlayer,
                  let seconds = loaded?.seconds,
                  seconds.isFinite,
                  seconds > 0 else { return }
            self.resolvedDuration = seconds
            self.synchronizePlayer()
        }
        previewPlayer.seek(
            to: CMTime(seconds: projectedPosition(at: Date()), preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.2, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.2, preferredTimescale: 600)
        ) { _ in
            DispatchQueue.main.async {
                previewPlayer.isMuted = true
                previewPlayer.volume = 0
                if watching.isPlaying { previewPlayer.play() }
            }
        }
    }

    @MainActor
    private func synchronizePlayer() {
        guard let player else { return }
        let expected = projectedPosition(at: Date())
        let actual = player.currentTime().seconds
        if !actual.isFinite || abs(actual - expected) > 2.5 {
            player.seek(to: CMTime(seconds: expected, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.isMuted = true
        player.volume = 0
        watching.isPlaying ? player.play() : player.pause()
    }

    @MainActor
    private func tearDownPlayer() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        player?.pause()
        player = nil
    }

    private func projectedPosition(at date: Date) -> Double {
        projectedCurrentWatchingPosition(
            positionSeconds: watching.positionSeconds,
            isPlaying: watching.isPlaying,
            receivedAt: watching.playbackSnapshotReceivedAt,
            now: date,
            durationSeconds: effectiveDuration
        )
    }

    private func clock(_ value: Double) -> String {
        let total = max(0, Int(value.isFinite ? value : 0))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct PublicProfileScreen: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var deviceEnvironment: DeviceEnvironmentStore
    let user: UserProfileReference
    let close: () -> Void
    @State private var profile: PublicUserProfile?
    @State private var loading = true
    @State private var loadError: String?
    @State private var friendshipBusy = false
    @State private var context: ProfileContext?

    private enum ProfileContext: String, Identifiable, Equatable {
        case username, views, appTime, longestMovie, removeFriend
        var id: String { rawValue }
    }

    private var shownName: String { profile?.nickname ?? user.nickname }
    private var shownUsername: String { profile?.username ?? user.username }
    private var shownAvatar: String { profile?.avatarDataURL ?? user.avatarDataURL }

    var body: some View {
        ZStack {
            AcrylicBackground()
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Button(action: close) { Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 40, height: 40).liquidCard(Circle()) }.buttonStyle(.plain)
                        Spacer()
                        Text("Профиль").font(.headline)
                        Spacer()
                        if profile?.isFriend == true, profile?.userId != session.profile?.userId {
                            Button { showContext(.removeFriend) } label: {
                                Image(systemName: "person.badge.minus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.43))
                                    .frame(width: 40, height: 40).liquidCard(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Удалить из друзей")
                        } else { Color.clear.frame(width: 40, height: 40) }
                    }
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(dataURL: shownAvatar, name: shownName, size: 112, showsBorder: false)
                        if presenceIsOnline(isOnline: profile?.isOnline, lastSeen: profile?.lastSeen, visible: profile?.activityVisible) {
                            Circle().fill(Color(red: 0.32, green: 0.70, blue: 0.54)).frame(width: 17, height: 17)
                                .overlay(Circle().stroke(Color.black.opacity(0.64), lineWidth: 3))
                        }
                    }
                    VStack(spacing: 3) {
                        Text(shownName).font(.title2.bold())
                        if !shownUsername.isEmpty {
                            Text("@\(shownUsername)").foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                                .anchorPreference(key: ProfileUsernameAnchorKey.self, value: .bounds) { $0 }
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.42, maximumDistance: 8)
                                        .exclusively(before: TapGesture())
                                        .onEnded { result in
                                            switch result {
                                            case .first(true): showContext(.username)
                                            case .second(_): copyUsername()
                                            default: break
                                            }
                                        }
                                )
                                .accessibilityHint("Нажмите, чтобы скопировать username")
                        }
                        Text(presenceText(isOnline: profile?.isOnline, lastSeen: profile?.lastSeen, lastSeenAgeSeconds: profile?.lastSeenAgeSeconds, ageAnchor: profile?.presenceSnapshotReceivedAt, visible: profile?.activityVisible, now: deviceEnvironment.currentTime))
                            .font(.caption).foregroundStyle(presenceIsOnline(isOnline: profile?.isOnline, lastSeen: profile?.lastSeen, visible: profile?.activityVisible) ? Color.cyan.opacity(0.86) : Color.secondary).padding(.top, 2)
                    }
                    if let loaded = profile, loaded.userId != session.profile?.userId, !loaded.isFriend {
                        Button { Task { await toggleFriend(loaded) } } label: {
                            Label("Добавить в друзья", systemImage: "person.badge.plus")
                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain).liquidCard(Capsule()).disabled(friendshipBusy)
                    }
                    if let stats = profile?.stats {
                        HStack(spacing: 9) {
                            fullMetric("play.rectangle.fill", compactDuration(stats.watchedSeconds), "просмотры", context: .views)
                            fullMetric("clock.fill", compactDuration(stats.appSeconds), "в приложении", context: .appTime)
                            fullMetric("film.fill", compactDuration(stats.longestMovieSeconds), "макс. фильм", context: .longestMovie)
                        }
                        ViewingInsightsPager(stats: stats, friends: [])
                    } else if profile?.analyticsVisible == false {
                        ContentUnavailableView("Статистика скрыта", systemImage: "lock.shield", description: Text("Агрегированная аналитика доступна только подтверждённым друзьям."))
                            .padding(.vertical, 32).liquidCard(RoundedRectangle(cornerRadius: 25))
                    } else if loading {
                        ProgressView().padding(.vertical, 42)
                    } else if let loadError {
                        VStack(spacing: 12) {
                            ContentUnavailableView("Не удалось загрузить профиль", systemImage: "wifi.exclamationmark", description: Text(loadError))
                            Button("Повторить") { Task { await load() } }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .liquidCard(Capsule())
                        }
                        .padding(.vertical, 32).liquidCard(RoundedRectangle(cornerRadius: 25))
                    }
                }
                .padding(20)
            }
            .contextPreviewBackdrop(active: context != nil)

            if let context, context != .username {
                profileContextOverlay(context)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(10)
            }
        }
        .overlayPreferenceValue(ProfileUsernameAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if context == .username, let anchor {
                    UsernameAnchoredHighlight(
                        username: shownUsername,
                        frame: proxy[anchor],
                        close: { withAnimation { context = nil } }
                    )
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: context)
        .task(id: user.id) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    private func fullMetric(_ icon: String, _ value: String, _ title: String, context: ProfileContext) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.caption.weight(.bold)).lineLimit(1)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity).padding(.vertical, 11).liquidCard(RoundedRectangle(cornerRadius: 17))
            .contentShape(RoundedRectangle(cornerRadius: 17))
            .onLongPressGesture(minimumDuration: 0.42, maximumDistance: 8) { showContext(context) }
    }

    @ViewBuilder private func profileContextOverlay(_ item: ProfileContext) -> some View {
        ContextPreviewGlass(close: { withAnimation { context = nil } }) {
            VStack(spacing: 13) {
                switch item {
                case .removeFriend:
                    Image(systemName: "person.badge.minus").font(.title2).foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.43))
                    Text("Удалить из друзей?").font(.headline)
                    Text("@\(shownUsername) останется доступен через поиск.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button("Отмена") { withAnimation { context = nil } }.frame(maxWidth: .infinity).padding(.vertical, 10).liquidCard(Capsule())
                        Button("Удалить") { Task { await removeFriend() } }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(Color(red: 0.95, green: 0.48, blue: 0.50)).liquidCard(Capsule()).disabled(friendshipBusy)
                    }.buttonStyle(.plain)
                case .username:
                    EmptyView()
                case .views, .appTime, .longestMovie:
                    let stats = profile?.stats
                    let icon = item == .views ? "play.rectangle.fill" : item == .appTime ? "clock.fill" : "film.fill"
                    let title = item == .views ? "Просмотры" : item == .appTime ? "В приложении" : "Макс. фильм"
                    let seconds = item == .views ? stats?.watchedSeconds : item == .appTime ? stats?.appSeconds : stats?.longestMovieSeconds
                    Image(systemName: icon).font(.title2).foregroundStyle(.cyan)
                    Text(title).font(.headline)
                    Text(compactDuration(seconds ?? 0)).font(.title3.bold()).foregroundStyle(.cyan)
                    Text(item == .views ? "Общее время совместных просмотров." : item == .appTime ? "Суммарная активность пользователя в приложении." : "Самый продолжительный просмотр фильма.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }.frame(maxWidth: 300)
        }
    }

    private func showContext(_ value: ProfileContext) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.82)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { context = value }
    }
    private func copyUsername() {
        UIPasteboard.general.string = shownUsername
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.66)
    }
    private func load() async {
        let initialLoad = profile == nil
        if initialLoad { loading = true }
        loadError = nil
        do {
            profile = try await session.api.publicProfile(userID: user.id)
        } catch {
            if initialLoad {
                profile = nil
                loadError = error.localizedDescription
            }
        }
        if initialLoad { loading = false }
    }
    private func toggleFriend(_ loaded: PublicUserProfile) async {
        guard !friendshipBusy else { return }
        friendshipBusy = true; defer { friendshipBusy = false }
        try? await session.api.addFriend(username: loaded.username)
        await load()
        await session.refreshFriendRequests()
    }
    private func removeFriend() async {
        guard !friendshipBusy, let loaded = profile else { return }
        friendshipBusy = true
        do {
            try await session.api.removeFriend(username: loaded.username)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load(); await session.refreshFriendRequests()
            withAnimation { context = nil }
        } catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        friendshipBusy = false
    }
}

private struct ProfileUsernameAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct UsernameAnchoredHighlight: View {
    let username: String
    let frame: CGRect
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.30).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close)
            Text("@\(username)")
                .foregroundStyle(.primary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.17), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.36), radius: 14, y: 8)
                .scaleEffect(1.08)
                .position(x: frame.midX, y: frame.midY)
        }
        .transition(.opacity)
    }
}

private func presenceIsOnline(isOnline: Bool?, lastSeen: String?, visible: Bool?) -> Bool {
    PresenceTimestampFormatter.isOnline(isOnline: isOnline, visible: visible)
}

private func presenceText(isOnline: Bool?, lastSeen: String?, lastSeenAgeSeconds: Int? = nil, ageAnchor: Date? = nil, visible: Bool?, now: Date = Date()) -> String {
    PresenceTimestampFormatter.string(
        isOnline: isOnline,
        lastSeen: lastSeen,
        lastSeenAgeSeconds: lastSeenAgeSeconds,
        ageAnchor: ageAnchor,
        visible: visible,
        now: now
    )
}

private func compactDuration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? "\(hours) ч" : "\(minutes) мин"
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

private enum PusheenTab: Hashable { case rooms, friends, profile }

struct PusheenTabs: View {
    @State private var selection: PusheenTab = .rooms
    @State private var showProfileQuickAction = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selection) {
                HomeView().tag(PusheenTab.rooms).tabItem {
                    Label {
                        Text("Комнаты")
                    } icon: {
                        Image(systemName: "play.rectangle.fill")
                            .symbolEffect(.bounce, value: selection == .rooms)
                    }
                }
                FriendsGlassView().tag(PusheenTab.friends).tabItem {
                    Label {
                        Text("Друзья")
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .symbolEffect(.bounce, value: selection == .friends)
                    }
                }
                ProfileGlassView().tag(PusheenTab.profile).tabItem {
                    Label {
                        Text("Профиль")
                    } icon: {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolEffect(.bounce, value: selection == .profile)
                    }
                }
            }
            .tint(.indigo)
            .overlay(alignment: .bottomTrailing) {
                // Keep the native Liquid Glass tab bar untouched. This clear
                // interaction layer only adds tap/hold behavior to Profile.
                Color.clear
                    .frame(width: proxy.size.width / 3, height: 76)
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.42, maximumDistance: 10)
                            .exclusively(before: TapGesture())
                            .onEnded { result in
                                switch result {
                                case .first(true):
                                    selection = .profile
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.88)
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                                        showProfileQuickAction = true
                                    }
                                case .second:
                                    selection = .profile
                                    if showProfileQuickAction {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                                            showProfileQuickAction = false
                                        }
                                    }
                                default:
                                    break
                                }
                            }
                    )
                    // When a room is pushed from the Rooms tab this invisible
                    // profile long-press target must not sit over the chat send
                    // button. Native TabView handles the first Profile tap;
                    // the extra hit area is needed only while Profile is active.
                    .allowsHitTesting(selection == .profile || showProfileQuickAction)
            }
            .overlay(alignment: .bottomTrailing) {
                if showProfileQuickAction {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { showProfileQuickAction = false }
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                            .liquidCard(Circle())
                    }
                    .buttonStyle(.plain)
                    // Centre the action over the Profile third of the native
                    // tab bar and keep it visually attached to that tab.
                    .padding(.trailing, max(12, proxy.size.width / 6 - 19))
                    .padding(.bottom, 46)
                    .transition(
                        .scale(scale: 0.62, anchor: .bottom)
                            .combined(with: .offset(y: 14))
                            .combined(with: .opacity)
                    )
                    .zIndex(50)
                }
            }
            .onChange(of: selection) { _, value in
                guard value != .profile, showProfileQuickAction else { return }
                withAnimation(.easeOut(duration: 0.16)) { showProfileQuickAction = false }
            }
        }
        .sheet(isPresented: $showSettings) { TelegramStickerSettingsSheet() }
    }
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
                    }
                    .onChange(of: avatarPicker) { _, item in Task { await updateAvatar(item) } }
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
        }
        .task {
            while !Task.isCancelled {
                await session.refreshViewingStats()
                if let refreshedFriends = try? await session.api.friends() {
                    friends = refreshedFriends
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    private func updateAvatar(_ item: PhotosPickerItem?) async { guard let item, let data = try? await item.loadTransferable(type: Data.self), let profile = session.profile else { return }; let value = "data:image/jpeg;base64," + data.base64EncodedString(); session.profile = try? await session.api.updateProfile(nickname: profile.nickname, username: profile.username, avatar: value) }
}

private struct ViewingInsightsPager: View {
    let stats: ViewingStats?
    let friends: [FriendProfile]
    @State private var page = 0
    @State private var indicatorPressed = false
    @GestureState private var dragTranslation: CGFloat = 0

    private var pages: [AnyView] {
        [
            AnyView(GenreOnlyCard(stats: stats)),
            AnyView(ViewingHeatmapCard(
                daily: stats?.dailySeconds ?? [:],
                backendMonthIncreasePercentage: stats?.monthIncreasePercentage,
                backendStreakDays: stats?.currentStreakDays
            )),
            AnyView(SharedWatchingCard(companion: stats?.topCompanion, fallbackFriends: friends)),
        ]
    }

    private var pageHeight: CGFloat {
        page == 1 ? 360 : 278
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let isHorizontalDrag = abs(dragTranslation) > 0
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        pages[index]
                            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
                            .clipped()
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
            .frame(height: pageHeight)
            .animation(.interactiveSpring(response: 0.36, dampingFraction: 0.88), value: pageHeight)

            GeometryReader { proxy in
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.primary.opacity(0.72) : Color.white.opacity(0.16))
                            .frame(width: index == page ? 20 : 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(indicatorPressed ? 1.11 : 1)
                .shadow(color: indicatorPressed ? Color.white.opacity(0.14) : .clear, radius: 6)
                .contentShape(Rectangle())
                .highPriorityGesture(indicatorScrubGesture(width: proxy.size.width))
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        updateIndicatorPage(at: value.location.x, width: proxy.size.width)
                    }
                )
            }
            .frame(width: 58, height: 30)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.76), value: indicatorPressed)
            .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.80), value: page)
        }
        .padding(15)
        .liquidCard(RoundedRectangle(cornerRadius: 26))
        .accessibilityLabel("Страницы статистики")
    }

    private func indicatorScrubGesture(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.22, maximumDistance: 16)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                switch value {
                case .first(true):
                    guard !indicatorPressed else { return }
                    indicatorPressed = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.80)
                case .second(true, let drag):
                    if !indicatorPressed { indicatorPressed = true }
                    guard let drag else { return }
                    updateIndicatorPage(at: drag.location.x, width: width)
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, let drag) = value, let drag {
                    updateIndicatorPage(at: drag.location.x, width: width)
                }
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.8)) {
                    indicatorPressed = false
                }
            }
    }

    private func updateIndicatorPage(at x: CGFloat, width: CGFloat) {
        guard width > 0, !pages.isEmpty else { return }
        let normalized = min(0.999, max(0, x / width))
        let target = min(pages.count - 1, Int(normalized * CGFloat(pages.count)))
        guard target != page else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.88)
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.82, blendDuration: 0.04)) {
            page = target
        }
    }
}

private struct TelegramStickerSettingsSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var loading = false
    @State private var statusText = ""
    var body: some View {
        ZStack {
            AcrylicBackground()
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text("Настройки").font(.title2.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 38, height: 38).liquidCard(Circle()) }.buttonStyle(.plain) }
                Label("Импортировать стикеры из Telegram", systemImage: "paperplane.fill").font(.headline)
                ZStack(alignment: .leading) {
                    if link.isEmpty {
                        Text("https://t.me/addstickers/...")
                            .foregroundStyle(Color(uiColor: .placeholderText))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $link)
                        .foregroundStyle(.primary)
                        .tint(Color(white: 0.62))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .liquidCard(RoundedRectangle(cornerRadius: 16))
                Button { Task { await importPack() } } label: {
                    HStack { if loading { ProgressView().controlSize(.small) }; Text("Импортировать"); Spacer(); Image(systemName: "square.and.arrow.down") }
                        .frame(height: 44).padding(.horizontal, 13).liquidCard(RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).disabled(loading || link.isEmpty)
                if !statusText.isEmpty { Text(statusText).font(.caption).foregroundStyle(statusText.hasPrefix("Готово") ? .mint : .red) }
                Spacer()
            }.padding(20)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationBackground(.clear)
    }
    private func importPack() async {
        loading = true; defer { loading = false }
        do { let pack = try await session.api.importStickerPack(url: link.trimmingCharacters(in: .whitespacesAndNewlines)); statusText = "Готово: \(pack.title)" }
        catch { statusText = error.localizedDescription }
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
                    .frame(width: 158, height: 158)
                    .frame(maxWidth: .infinity)
                GenreLegend(genres: genres, selectedGenreID: $selectedGenreID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selectedGenreID = nil } }
        .onAppear { selectedGenreID = nil }
    }
}

private struct ViewingHeatmapCard: View {
    let daily: [String: Int]
    let backendMonthIncreasePercentage: Int?
    let backendStreakDays: Int?
    private let calendar = Calendar.current
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
    private var calendarLayout: ActivityCalendarLayout {
        ActivityCalendarLayout(today: today, visibleMonths: visibleMonths, calendar: calendar)
    }
    private var allVisibleDays: [Date] { calendarLayout.displayedDays }
    private var highlightedDay: Date { selectedDay ?? latestActiveDay ?? today }
    private var latestActiveDay: Date? {
        allVisibleDays.last(where: { (daily[dayKey(for: $0)] ?? 0) > 0 })
    }
    private var streakDays: Int {
        if let backendStreakDays { return backendStreakDays }
        var count = 0
        var cursor = today
        while daily[dayKey(for: cursor)] ?? 0 > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
    private var monthIncreasePercentage: Int {
        if let backendMonthIncreasePercentage { return backendMonthIncreasePercentage }
        return ActivityCalendarLayout.monthIncreasePercentage(
            daily: daily,
            today: today,
            calendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 34, height: 34)
                    .background(.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.cyan.opacity(0.30), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Активность").font(.headline.bold())
                    Text(visibleMonths == 1 ? "Последний месяц" : "Последние 3 месяца").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.subheadline).foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(streakDays) дней подряд").font(.caption2.weight(.bold)).foregroundStyle(.cyan)
                        Text("Текущая серия").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.cyan.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.8))
            }

            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 26, height: 26)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(Self.detailFormatter.string(from: highlightedDay)).font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Text("•").foregroundStyle(.blue.opacity(0.7))
                Text(durationText(for: highlightedDay)).font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(LinearGradient(colors: [.cyan.opacity(0.17), .blue.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.cyan.opacity(0.25), lineWidth: 0.9))

            GeometryReader { proxy in
                let layout = calendarLayout
                let columns = layout.columns
                let weekdayWidth: CGFloat = 25
                let weekdayGap: CGFloat = 9
                let columnGap: CGFloat = 4
                let totalColumns = max(1, columns.count)
                let widthLimitedCell = (proxy.size.width - weekdayWidth - weekdayGap - CGFloat(totalColumns - 1) * columnGap) / CGFloat(totalColumns)
                let rowGap: CGFloat = 4
                let captionHeight: CGFloat = 15
                let heightLimitedCell = (proxy.size.height - captionHeight - 7 - (6 * rowGap)) / 7
                let cell = max(9, min(22, widthLimitedCell, heightLimitedCell))

                HStack(alignment: .top, spacing: weekdayGap) {
                    VStack(alignment: .leading, spacing: rowGap) {
                        ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "вс"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: weekdayWidth, height: cell, alignment: .leading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: columnGap) {
                            ForEach(columns.indices, id: \.self) { column in
                                VStack(spacing: rowGap) {
                                    ForEach(columns[column]) { item in
                                        RoundedRectangle(cornerRadius: max(3, cell * 0.24), style: .continuous)
                                            .fill(item.isSelectable ? tileGradient(for: item.date) : inactiveTileGradient)
                                            .frame(width: cell, height: cell)
                                            .overlay {
                                                if item.isSelectable && calendar.isDate(item.date, inSameDayAs: highlightedDay) {
                                                    RoundedRectangle(cornerRadius: max(3, cell * 0.24), style: .continuous)
                                                        .stroke(.white, lineWidth: 1.7)
                                                        .shadow(color: .cyan.opacity(0.75), radius: 4)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                if item.isSelectable { select(item.date) }
                                            }
                                    }
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: columnGap) {
                            ForEach(columns.indices, id: \.self) { column in
                                let label = layout.monthMarkers.first(where: { $0.column == column })?.label
                                Text(label ?? "")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: cell, height: captionHeight, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .scaleEffect(pinchScale, anchor: .center)
            }
            .frame(height: 172)

            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.cyan).font(.caption.weight(.bold))
                (
                    Text("В этом месяце активность выше на ")
                        .foregroundColor(.secondary)
                    + Text("\(monthIncreasePercentage)%")
                        .foregroundColor(.cyan)
                        .fontWeight(.semibold)
                    + Text(", чем в прошлом")
                        .foregroundColor(.secondary)
                )
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .simultaneousGesture(heatmapMagnification)
    }

    private func select(_ day: Date) {
        guard selectedDay.map({ !calendar.isDate($0, inSameDayAs: day) }) ?? true else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { selectedDay = day }
    }
    private func color(for day: Date) -> Color {
        let seconds = daily[dayKey(for: day)] ?? 0
        guard seconds > 0 else { return .white.opacity(0.10) }
        return .cyan.opacity(0.22 + 0.72 * min(1, Double(seconds) / 10_800))
    }
    private func tileGradient(for day: Date) -> LinearGradient {
        let base = color(for: day)
        return LinearGradient(colors: [base.opacity(0.72), base], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var inactiveTileGradient: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.035), .white.opacity(0.055)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private func dayKey(for day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private func durationText(for day: Date) -> String {
        let minutes = (daily[dayKey(for: day)] ?? 0) / 60
        return minutes == 0 ? "активности нет" : minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
    }
    private var heatmapMagnification: some Gesture {
        MagnificationGesture()
            .onChanged { pinchScale = min(1.16, max(0.86, $0)) }
            .onEnded { value in
                let next = value > 1.04 ? 1 : value < 0.96 ? 3 : visibleMonths
                if next != visibleMonths { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1) }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { visibleMonths = next; selectedDay = nil; pinchScale = 1 }
            }
    }
}

private struct LegacyViewingHeatmapCard: View {
    private struct MonthMarker {
        let label: String
        let column: Int
    }
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

    private func monthMarkers(for renderedColumns: [[Date]]) -> [MonthMarker] {
        renderedColumns.enumerated().compactMap { column, days in
            // A label belongs to the exact column that contains day 1. This
            // remains correct even when a column spans the end of one month
            // and the beginning of the next.
            guard let firstDayOfMonth = days.first(where: { calendar.component(.day, from: $0) == 1 }) else {
                return nil
            }
            return MonthMarker(
                label: Self.monthFormatter.string(from: firstDayOfMonth).replacingOccurrences(of: ".", with: ""),
                column: column
            )
        }
    }

    var body: some View {
        // Keep a single immutable layout snapshot for this SwiftUI render.
        let renderedColumns = columns
        let renderedMonthMarkers = monthMarkers(for: renderedColumns)
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
                let spacing: CGFloat = visibleMonths == 1 ? 6 : 4
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
                                    RoundedRectangle(cornerRadius: max(3, tile * 0.28), style: .continuous)
                                        .fill(tileGradient(for: day))
                                        .frame(width: tile, height: tile)
                                        .overlay(RoundedRectangle(cornerRadius: max(3, tile * 0.28), style: .continuous).stroke(.white.opacity(0.055), lineWidth: 0.6))
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
                    ZStack(alignment: .leading) {
                        ForEach(Array(renderedMonthMarkers.enumerated()), id: \.offset) { _, marker in
                            Text(marker.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .offset(x: CGFloat(marker.column) * (tile + spacing))
                        }
                    }
                    .frame(
                        width: CGFloat(renderedColumns.count) * tile + totalGaps,
                        height: 14,
                        alignment: .leading
                    )
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

    private func tileGradient(for day: Date) -> LinearGradient {
        let base = color(for: day)
        return LinearGradient(
            colors: [base.opacity(0.88), base],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

/// Reaction pickers use a static Fluent frame. Rendering dozens of animated
/// APNG views while a horizontal ScrollView is moving causes avoidable frame
/// drops on iPhone; the selected reaction remains fully Fluent everywhere.
private struct FluentReactionGlyph: UIViewRepresentable {
    let emoji: String
    let size: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize {
        CGSize(width: size, height: size)
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        guard context.coordinator.lastEmoji != emoji else { return }
        context.coordinator.lastEmoji = emoji
        context.coordinator.task?.cancel()
        view.image = nil
        if let image = FluentEmojiCache.shared.image(for: emoji) {
            view.image = image.images?.first ?? image
            return
        }
        context.coordinator.task = FluentEmojiCache.shared.load(emoji: emoji) { image in
            guard let image else { return }
            let staticFrame = image.images?.first ?? image
            DispatchQueue.main.async {
                guard context.coordinator.lastEmoji == emoji else { return }
                view.image = staticFrame
            }
        }
    }
    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) { coordinator.task?.cancel() }
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
    let joined: (Room) -> Void
    @State private var code = ""
    @State private var error = ""
    @State private var loading = false
    var body: some View { ZStack { AcrylicBackground(); VStack(spacing: 16) { Text("Войти в комнату").font(.title3.bold()); GlassField(icon: "number", title: "Код комнаты", text: $code); if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }; Button(loading ? "Подключение…" : "Присоединиться") { Task { await join() } }.buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 12).liquidCard(Capsule()).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading) }.padding(22).liquidCard(RoundedRectangle(cornerRadius: 28)).padding(18) }.presentationDetents([.height(250)]).presentationBackground(.clear).interactiveDismissDisabled(loading) }
    private func join() async {
        guard !loading else { return }
        loading = true; error = ""; defer { loading = false }
        do {
            let room = try await session.api.joinRoom(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            joined(room)
        } catch { self.error = error.localizedDescription }
    }
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
    @State private var profilePreview: UserProfileReference?
    @State private var fullProfile: UserProfileReference?
    @State private var friendsPresenceSnapshotFresh = false
    @State private var lastFriendsRefreshAt: Date?
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
                            FriendRequestSection(title: "Отправленные", requests: session.friendRequests.outgoing, incoming: false) { request, _ in
                                await session.cancel(request)
                            }
                        }
                        if requestFilter == nil {
                            ForEach(expanded && !query.isEmpty ? results : friends) { person in
                                FriendSwipeRow(
                                person: person,
                                showAdd: expanded && !person.isFriend,
                                pending: session.friendRequests.outgoing.contains { $0.userId == person.userId },
                                presenceSnapshotFresh: friendsPresenceSnapshotFresh,
                                preview: { profilePreview = UserProfileReference(person) },
                                openProfile: { fullProfile = UserProfileReference(person) },
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
        .userProfilePresentation(preview: $profilePreview, fullProfile: $fullProfile)
        .task {
            await session.refreshFriendRequests()
            while !Task.isCancelled {
                await loadFriends()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onChange(of: session.friendRequests) { _, _ in Task { await loadFriends() } }
    }
    private func loadFriends() async {
        // A transient tunnel error must not erase the list or freeze it on the
        // last offline label. Replace the list only after a valid response, but
        // expire a previously green presence snapshot if refreshing has failed
        // for longer than the backend TTL.
        do {
            let refreshed = try await session.api.friends()
            if friends.map(\.id) == refreshed.map(\.id) {
                friends = refreshed
            } else {
                withAnimation(.easeInOut(duration: 0.22)) { friends = refreshed }
            }
            lastFriendsRefreshAt = Date()
            friendsPresenceSnapshotFresh = true
        } catch {
            let age = lastFriendsRefreshAt.map { Date().timeIntervalSince($0) } ?? .infinity
            if age > 18 { friendsPresenceSnapshotFresh = false }
        }
    }
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
    @EnvironmentObject private var deviceEnvironment: DeviceEnvironmentStore
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
    let presenceSnapshotFresh: Bool
    let preview: () -> Void
    let openProfile: () -> Void
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
                HStack(spacing: 11) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(dataURL: person.avatarDataURL, name: person.nickname, size: 48)
                        if presenceIsOnline(isOnline: presenceSnapshotFresh ? person.isOnline : false, lastSeen: person.lastSeen, visible: person.activityVisible) {
                            Circle().fill(Color(red: 0.32, green: 0.70, blue: 0.54)).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 2))
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.nickname).bold().lineLimit(1)
                        Text("@\(person.username) · \(presenceText(isOnline: presenceSnapshotFresh ? person.isOnline : false, lastSeen: person.lastSeen, lastSeenAgeSeconds: person.lastSeenAgeSeconds, ageAnchor: person.presenceSnapshotReceivedAt, visible: person.activityVisible, now: deviceEnvironment.currentTime))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { preview() }
                .contextMenu {
                    Button("Профиль", systemImage: "person.crop.circle") { openProfile() }
                    if person.isFriend {
                        Button("Удалить из друзей", systemImage: "person.badge.minus", role: .destructive) { requestDeleteConfirmation() }
                    } else if !pending {
                        Button("Добавить в друзья", systemImage: "person.badge.plus") { Task { await add() } }
                    }
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
                    } else {
                        Button { Task { await action(request, false) } } label: {
                            Label("Отменить", systemImage: "xmark")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).frame(height: 32)
                        }
                        .buttonStyle(.plain)
                        .liquidCard(Capsule())
                    }
                }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 19))
            }
        }
    }
}
