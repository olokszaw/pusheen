import SwiftUI
import AVKit
import UIKit
import PhotosUI
import ImageIO

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
    @State private var previewedRoom: Room?
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ZStack { AcrylicBackground()
                    ScrollView { VStack(alignment: .leading, spacing: 18) {
                HStack { VStack(alignment: .leading) { Text("Pusheen").font(.largeTitle.bold()); Text("Привет, \(session.profile?.nickname ?? "")").foregroundStyle(.secondary) }; Spacer(); Button { session.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right").padding(10).liquidCard(Circle()) }.buttonStyle(.plain) }
                HStack { Text("Мои комнаты").font(.title2.bold()); Spacer(); Menu { Button("Создать комнату", systemImage: "plus") { showCreate = true }; Button("Войти по коду", systemImage: "number") { showJoin = true } } label: { Image(systemName: "plus").font(.headline).frame(width: 38, height: 38).liquidCard(Circle()) }.buttonStyle(.plain) }
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
        }
    }
    private func load() async { rooms = (try? await session.api.rooms()) ?? [] }
}

struct CreateRoomSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let created: (Room) -> Void
    @State private var url = ""
    @State private var isPrivate = false
    @State private var loading = false
    @State private var error = ""
    var body: some View { ZStack { AcrylicBackground(); VStack(alignment: .leading, spacing: 16) {
        Text("Новая комната").font(.title2.bold())
        Text("Вставь ссылку VK Видео или сайта. Сервер сам возьмёт название и обложку.").font(.subheadline).foregroundStyle(.secondary)
        TextField("Ссылка на видео", text: $url, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
        Toggle("Публичная комната", isOn: Binding(get: { !isPrivate }, set: { isPrivate = !$0 })).padding(12).liquidCard(RoundedRectangle(cornerRadius: 17))
        if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        Button { Task { await create() } } label: { Label("Создать", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
    }.padding(22) }.presentationDetents([.medium]).presentationBackground(.clear) }
    private func create() async { loading = true; error = ""; defer { loading = false }; do { let room = try await session.api.createRoom(videoURL: url.trimmingCharacters(in: .whitespacesAndNewlines), isPrivate: isPrivate); created(room); dismiss() } catch { self.error = error.localizedDescription } }
}

struct LegacyRoomCard: View {
    let room: Room
    var body: some View { HStack(spacing: 14) { Image(systemName: "play.fill").font(.title2).frame(width: 58, height: 58).liquidCard(Circle()); VStack(alignment: .leading, spacing: 4) { Text(room.title).font(.headline).lineLimit(1); Text("\(room.membersCount) участников · \(room.inviteCode)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(14).liquidCard() }
}

struct RoomView: View {
    @EnvironmentObject private var session: SessionStore
    let room: Room
    let api: APIClient
    let token: String
    @State private var draft = ""
    @State private var showTime = false
    @State private var showMembers = false
    @State private var chatFocused = false
    @State private var copiedCode = false
    @State private var controlsVisible = false
    @State private var controlsHideTask: Task<Void, Never>?
    @StateObject private var model: RoomViewModel
    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token; _model = StateObject(wrappedValue: RoomViewModel(room: room, api: api, token: token)) }
    var body: some View {
        ZStack { AcrylicBackground().contentShape(Rectangle()).onTapGesture { chatFocused = false }
            VStack(spacing: 12) {
                ZStack(alignment: .bottom) {
                    Group { if let player = model.player { BarePlayerSurface(player: player) } else { ProgressView() } }
                    if controlsVisible {
                        VStack(spacing: 7) {
                            PlaybackScrubber(position: model.position, duration: model.duration, enabled: model.isOwner) { model.seek($0) }
                            HStack(spacing: 10) {
                                playerControl("gobackward.10") { model.seek(max(0, model.position - 10)) }
                                playerControl(model.isPlaying ? "pause.fill" : "play.fill", primary: true) { model.toggle() }
                                playerControl("goforward.10") { model.seek(min(model.duration, model.position + 10)) }
                                Spacer(minLength: 6)
                                Button { copyInviteCode() } label: {
                                    Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                                        .font(.body.weight(.semibold))
                                        .frame(width: 38, height: 38)
                                        .contentTransition(.symbolEffect(.replace))
                                        .liquidCard(Circle())
                                }.buttonStyle(.plain).accessibilityLabel("Скопировать код комнаты")
                                Button { showTime = true } label: {
                                    Text(time(model.position)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 7).liquidCard(Capsule())
                                }.buttonStyle(.plain)
                            }
                            .padding(7).liquidCard(Capsule()).opacity(model.isOwner ? 1 : 0.62)
                        }
                        .padding(9)
                        .background(LinearGradient(colors: [.black.opacity(0.02), .black.opacity(0.58)], startPoint: .top, endPoint: .bottom))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(height: 238)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: controlsVisible)
                NativeChatPane(messages: model.messages, currentUserID: session.profile?.userId, draft: $draft, focused: $chatFocused, send: { text, image in model.send(text: text, image: image, as: session.profile) }, react: { id, emoji in model.react(messageID: id, emoji: emoji) }).frame(maxHeight: .infinity).layoutPriority(1)
            }.padding(.horizontal, 7).padding(.vertical, 12).frame(maxHeight: .infinity, alignment: .top)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 22).onEnded { value in
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            guard value.translation.width < -70, horizontal > vertical * 1.35 else { return }
            showMembers = true
        })
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                chatFocused = false
                showMembers = false
            }
        }
        .navigationTitle(room.title).navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true).toolbar(.hidden, for: .tabBar).task { await model.start() }.onDisappear { model.stop() }
            .sheet(isPresented: $showTime) { SeekTimePickerSheet(initial: model.position) { model.seek($0) } }
            .sheet(isPresented: $showMembers) { MembersSheet(members: model.members, currentID: session.profile?.userId) }
    }
    private func time(_ value: Double) -> String { let total = Int(value); if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }; return String(format: "%02d:%02d", total / 60, total % 60) }
    private func copyInviteCode() { UIPasteboard.general.string = room.inviteCode; withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { copiedCode = true }; Task { try? await Task.sleep(for: .seconds(1.6)); await MainActor.run { withAnimation(.easeOut(duration: 0.22)) { copiedCode = false } } } }
    @ViewBuilder private func playerControl(_ symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(primary ? .title3.weight(.semibold) : .body.weight(.semibold))
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
    var body: some View {
        ZStack { AcrylicBackground(); VStack(alignment: .leading, spacing: 12) {
            Text("Участники").font(.title2.bold())
            ForEach(members) { member in
                HStack(spacing: 11) {
                    AvatarView(dataURL: member.avatarDataURL, name: member.nickname, size: 46)
                    VStack(alignment: .leading) {
                        HStack { Text(member.nickname).bold(); if member.isOwner { Image(systemName: "crown.fill").font(.caption).foregroundStyle(.yellow) }; if member.userId == currentID { Text("Вы").font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).liquidCard(Capsule()) } }
                        Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Circle().fill(member.isOnline ? .green : .gray).frame(width: 8, height: 8)
                }.padding(9).liquidCard(RoundedRectangle(cornerRadius: 17))
            }; Spacer()
        }.padding(20) }.presentationDetents([.medium, .large]).presentationBackground(.clear)
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
    @State private var dragging: Double?
    private var display: Double { dragging ?? position }
    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let ratio = min(1, max(0, display / max(1, duration)))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13)).frame(height: 6)
                Capsule().fill(LinearGradient(colors: [.mint, .cyan.opacity(0.82), .indigo.opacity(0.86)], startPoint: .leading, endPoint: .trailing)).frame(width: max(10, width * ratio), height: 6)
                Circle().fill(.white).shadow(color: .cyan.opacity(0.45), radius: 7).frame(width: 18, height: 18).offset(x: max(0, min(width - 18, width * ratio - 9)))
                if let dragging { Text(scrubTime(dragging)).font(.caption2.monospacedDigit().weight(.bold)).padding(.horizontal, 8).padding(.vertical, 5).liquidCard(Capsule()).offset(x: max(0, min(width - 70, width * ratio - 35)), y: -31).transition(.opacity.combined(with: .scale)) }
            }.frame(height: proxy.size.height).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in guard enabled else { return }; dragging = min(duration, max(0, duration * value.location.x / width)) }.onEnded { _ in if let value = dragging { commit(value) }; dragging = nil })
        }.frame(height: 26).padding(.horizontal, 10).padding(.vertical, 5).liquidCard(Capsule()).opacity(enabled ? 1 : 0.58)
    }
    private func scrubTime(_ seconds: Double) -> String { let total = Int(seconds); return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60) }
}

struct NativeChatPane: View {
    let messages: [ChatMessage]
    let currentUserID: Int?
    @Binding var draft: String
    @Binding var focused: Bool
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
    private let quickReactions = ["👍", "❤️", "😂", "🔥", "😮", "👏", "😭", "🎬", "🍿", "✨"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Чат").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in NativeMessageBubble(message: message, isMine: message.authorId == currentUserID, react: react, quickReactions: quickReactions).id(message.id) }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }.padding(.vertical, 2)
                }.defaultScrollAnchor(.bottom).contentShape(Rectangle()).onTapGesture { focused = false; inputFocused = false }
                    .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in sticksToBottom = false })
                    .onAppear { scroll(proxy, force: true) }
                    .onChange(of: focused) { _, active in if active { sticksToBottom = true; scroll(proxy, force: true) } }
                    .onChange(of: messages.count) { _, _ in scroll(proxy) }
            }.frame(maxHeight: .infinity)
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .liquidCard(Circle())
                }
                .buttonStyle(.plain)
                .onChange(of: selectedPhoto) { _, item in Task { await preparePhoto(item) } }

                HStack(alignment: .bottom, spacing: 7) {
                    PersistentChatTextField(
                        text: $draft,
                        isFocused: Binding(get: { inputFocused }, set: { inputFocused = $0 }),
                        height: $inputHeight,
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
                        .accessibilityAddTraits(.isButton)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .liquidCard(RoundedRectangle(cornerRadius: 25, style: .continuous))
            }
            .padding(.horizontal, 26)
        }
        .padding(12)
        .liquidCard()
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
                send("", photo.dataURL)
                pendingPhoto = nil
            }
        }
    }
    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sticksToBottom = true
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
    private func scroll(_ proxy: ScrollViewProxy, force: Bool = false) {
        guard force || sticksToBottom else { return }
        func pin() { var transaction = Transaction(); transaction.disablesAnimations = true; withTransaction(transaction) { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
        DispatchQueue.main.async { pin() }
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
        field.updatePlaceholder()
        DispatchQueue.main.async {
            let measured = field.refreshLayout()
            if abs(context.coordinator.parent.height - measured) > 0.5 {
                context.coordinator.parent.height = measured
            }
        }
        if isFocused && !field.isFirstResponder { field.becomeFirstResponder() }
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
        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            placeholderLabel.text = "Сообщение…"
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
        func updatePlaceholder() { placeholderLabel.isHidden = !text.isEmpty }
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
        case 25...42: return 226
        default: return 266
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
                if !isMine { AvatarView(dataURL: message.avatarDataURL, name: message.nickname, size: 38) }
                if isMine { Spacer(minLength: 38) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    Text(message.nickname).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 240, alignment: isMine ? .trailing : .leading)
                    bubble
                }
                if isMine { AvatarView(dataURL: message.avatarDataURL, name: message.nickname, size: 38) } else { Spacer(minLength: 18) }
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
                    Text(register ? "Создать аккаунт" : "Войти").font(.system(size: 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                    Text(register ? "Укажи данные для нового аккаунта" : "Введи username и пароль").font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing: 11) {
                        if register { GlassField(icon: "person.text.rectangle", title: "Nickname", text: $nickname) }
                        GlassField(icon: "at", title: "Username", text: $username).onChange(of: username) { _, value in Task { await validate(value) } }
                        if register && !username.isEmpty { AuthProfilePreview(nickname: nickname, username: username, availability: availability) }
                        GlassSecureField(title: "Password", text: $password)
                        if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { Task { await submit() } } label: { HStack { if loading { ProgressView().tint(.white) }; Text(register ? "Создать аккаунт" : "Войти"); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity).padding(.vertical, 4) }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(loading)
                    }.padding(15).liquidCard(RoundedRectangle(cornerRadius: 30))
                    Button(register ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Создать") { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { register.toggle(); error = ""; availability = .idle } }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer(minLength: 20)
                }.frame(maxWidth: 440).padding(22)
            }
        }
    }
    private func validate(_ value: String) async { guard register else { withAnimation { availability = .idle }; return }; guard usernameValid else { withAnimation(.easeOut(duration: 0.2)) { availability = .invalid }; return }; withAnimation(.easeOut(duration: 0.2)) { availability = .checking }; try? await Task.sleep(for: .milliseconds(250)); guard username == value else { return }; let isAvailable = (try? await session.api.usernameAvailable(value)) == true; withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { availability = isAvailable ? .available : .taken } }
    private func submit() async { error = ""; guard !username.isEmpty, !password.isEmpty else { error = "Заполни username и пароль"; return }; if register && (!usernameValid || nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2) { error = "Проверь nickname и username"; return }; loading = true; defer { loading = false }; do { if register { try await session.register(nickname: nickname, username: username, password: password) } else { try await session.login(username: username, password: password) } } catch { self.error = error.localizedDescription } }
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
                    HStack(spacing: 8) {
                        VStack(spacing: 3) {
                            Text(session.profile?.nickname ?? "").font(.title2.bold())
                            Text("@\(session.profile?.username ?? "")").foregroundStyle(.secondary)
                        }
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { edit.toggle() } } label: {
                            Image(systemName: "pencil").font(.caption.weight(.bold)).frame(width: 30, height: 30).liquidCard(Circle())
                        }.buttonStyle(.plain)
                    }
                    if edit { ProfileInlineEditor(close: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { edit = false } }).transition(.opacity.combined(with: .move(edge: .top))) }
                    ViewingActivityCard(stats: session.viewingStats)
                    Button("Выйти") { session.logout() }.buttonStyle(.bordered).tint(.red).padding(.top, 8)
                }.padding(20)
            }
        }.onAppear { Task { await session.refreshViewingStats() } }
    }
    private func updateAvatar(_ item: PhotosPickerItem?) async { guard let item, let data = try? await item.loadTransferable(type: Data.self), let profile = session.profile else { return }; let value = "data:image/jpeg;base64," + data.base64EncodedString(); session.profile = try? await session.api.updateProfile(nickname: profile.nickname, username: profile.username, avatar: value) }
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
        let selected = genres.first(where: { $0.id == selectedGenreID }) ?? genres[0]
        ZStack {
            ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                let before = genres.prefix(index).reduce(0) { $0 + $1.seconds }
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        selectedGenreID = genre.id
                    }
                } label: {
                    DonutSlice(start: Double(before) / Double(total), end: Double(before + genre.seconds) / Double(total))
                        .fill(GenrePalette.color(for: genre.name).opacity(genre.id == selected.id ? 1 : 0.68))
                        .scaleEffect(genre.id == selected.id ? 1.045 : 0.96)
                        .contentShape(DonutSlice(start: Double(before) / Double(total), end: Double(before + genre.seconds) / Double(total)))
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.34, dampingFraction: 0.76), value: selected.id)
            }
            Circle().fill(.ultraThinMaterial).frame(width: 86, height: 86)
            VStack(spacing: 2) {
                Text(selected.name).font(.caption.weight(.bold)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.70)
                Text("\(selected.percent)%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }.frame(width: 74)
        }
        .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
        .shadow(color: GenrePalette.color(for: genres.first?.name ?? "").opacity(0.22), radius: 12)
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
    let person: FriendProfile
    let showAdd: Bool
    let pending: Bool
    let add: () async -> Void
    let remove: () async -> Void
    @State private var revealed = false
    @State private var dragOffset: CGFloat = 0
    @State private var removing = false

    private let settledOffset: CGFloat = -122
    private var offset: CGFloat { dragOffset == 0 ? (revealed ? settledOffset : 0) : dragOffset }
    private var deleteReveal: CGFloat {
        min(1, max(0, (-offset) / (-settledOffset)))
    }
    /// The action grows exactly with the revealed part of the row. There is no
    /// fixed oversized pill that can cover the friend card.
    private var deleteWidth: CGFloat { max(58, min(164, -offset)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if person.isFriend && (revealed || dragOffset < -4) {
                Button {
                    guard !removing else { return }
                    removing = true
                    Task {
                        await remove()
                        await MainActor.run {
                            removing = false
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) { revealed = false }
                        }
                    }
                } label: {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.25, blue: 0.29).opacity(0.96),
                                                 Color(red: 0.78, green: 0.04, blue: 0.12).opacity(0.92)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            }
                            .overlay {
                                Capsule().stroke(
                                    LinearGradient(colors: [.white.opacity(0.48), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.8
                                )
                            }
                            .shadow(color: .red.opacity(0.27), radius: 10, y: 4)
                        Group {
                            if removing { ProgressView().tint(.white) }
                            else {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(.white.opacity(0.13), in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 0.7))
                                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
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
            .liquidCard(RoundedRectangle(cornerRadius: 20))
            .offset(x: offset)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .zIndex(1)
            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { value in
                    guard person.isFriend else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = min(0, max(-164, value.translation.width + (revealed ? settledOffset : 0)))
                }
                .onEnded { value in
                    guard person.isFriend else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { dragOffset = 0; return }
                    let wasRevealed = revealed
                    let projected = value.predictedEndTranslation.width + (wasRevealed ? settledOffset : 0)
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.91, blendDuration: 0.06)) {
                        if wasRevealed {
                            // A deliberate reverse swipe closes the action even
                            // if the finger did not travel all the way back.
                            revealed = !(value.translation.width > 16 || value.predictedEndTranslation.width > 30)
                        } else {
                            revealed = projected < -54
                        }
                        dragOffset = 0
                    }
                })
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.91, blendDuration: 0.08), value: revealed)
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
