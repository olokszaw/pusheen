import SwiftUI
import AVKit
import UIKit

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View {
        Group { if session.profile == nil { AuthView() } else { PusheenTabs() } }
            .preferredColorScheme(.dark)
    }
}

struct PusheenTabs: View {
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
            Circle().fill(.purple.opacity(0.50)).frame(width: 340).blur(radius: 85).offset(x: -170, y: -330)
            Circle().fill(.pink.opacity(0.30)).frame(width: 290).blur(radius: 95).offset(x: 180, y: 390)
            Circle().fill(.blue.opacity(0.27)).frame(width: 240).blur(radius: 90).offset(x: 190, y: 70)
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
                Text(isRegister ? "Создай профиль" : "Смотри. Чувствуй.\nБудь рядом.").font(.system(size: 31, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
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
    var body: some View { HStack(spacing: 10) { Circle().fill(.purple.opacity(0.72)).frame(width: 38, height: 38).overlay(Text((nickname.isEmpty ? username : nickname).prefix(1)).bold()); VStack(alignment: .leading, spacing: 2) { Text(nickname.isEmpty ? "Your nickname" : nickname).font(.subheadline.bold()); Text("@\(username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tint) }.padding(9).liquidCard(RoundedRectangle(cornerRadius: 16)).transition(.opacity.combined(with: .move(edge: .top))).animation(.spring(response: 0.32), value: username) }
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var rooms: [Room] = []
    @State private var path = NavigationPath()
    @State private var showCreate = false
    var body: some View {
        NavigationStack(path: $path) { ZStack { AcrylicBackground()
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                HStack { VStack(alignment: .leading) { Text("Pusheen").font(.largeTitle.bold()); Text("Привет, \(session.profile?.nickname ?? "")").foregroundStyle(.secondary) }; Spacer(); Button { session.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right").padding(10).liquidCard(Circle()) }.buttonStyle(.plain) }
                HStack { Text("Мои комнаты").font(.title2.bold()); Spacer(); Button { showCreate = true } label: { Image(systemName: "plus").font(.headline).frame(width: 38, height: 38).liquidCard(Circle()) }.buttonStyle(.plain) }
                ForEach(rooms) { room in NavigationLink(value: room) { RoomCard(room: room) }.buttonStyle(.plain) }
                if rooms.isEmpty { ContentUnavailableView("Комнат пока нет", systemImage: "play.rectangle.on.rectangle", description: Text("Создай комнату в текущей Flutter-версии — SwiftUI-клиент сразу её увидит.")) }
            }.padding(18) }.task { await load() }
        }.navigationDestination(for: Room.self) { RoomView(room: $0, api: session.api, token: session.token ?? "") }.sheet(isPresented: $showCreate) { CreateRoomSheet { room in rooms.insert(room, at: 0); path.append(room) } } }
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

struct RoomCard: View {
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
    @StateObject private var model: RoomViewModel
    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token; _model = StateObject(wrappedValue: RoomViewModel(room: room, api: api, token: token)) }
    var body: some View {
        ZStack { AcrylicBackground()
            VStack(spacing: 12) {
                if let player = model.player { BarePlayerSurface(player: player).frame(height: chatFocused ? 148 : 235).clipShape(RoundedRectangle(cornerRadius: 25)).animation(.spring(response: 0.3, dampingFraction: 0.9), value: chatFocused) } else { ProgressView().frame(height: chatFocused ? 148 : 235) }
                HStack { Button { model.seek(max(0, model.position - 10)) } label: { Image(systemName: "gobackward.10") }; Button { model.toggle() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }.font(.title3); Button { model.seek(min(model.duration, model.position + 10)) } label: { Image(systemName: "goforward.10") }; Spacer(); Button { showTime = true } label: { Text(time(model.position)) } }.padding(10).liquidCard(Capsule())
                PlaybackScrubber(position: model.position, duration: model.duration, enabled: model.isOwner) { model.seek($0) }
                NativeChatPane(messages: model.messages, draft: $draft, focused: $chatFocused, send: { text in model.send(text) }, react: { id, emoji in model.react(messageID: id, emoji: emoji) })
            }.padding(14)
        }.contentShape(Rectangle()).onTapGesture { chatFocused = false }.navigationTitle(room.title).navigationBarTitleDisplayMode(.inline).task { await model.start() }
            .sheet(isPresented: $showTime) { SeekTimePickerSheet(initial: model.position) { model.seek($0) } }
            .sheet(isPresented: $showMembers) { MembersSheet(members: model.members, currentID: session.profile?.userId) }
    }
    private func time(_ value: Double) -> String { let total = Int(value); if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }; return String(format: "%02d:%02d", total / 60, total % 60) }
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
        }.padding().presentationDetents([.height(330)]).presentationBackground(.ultraThinMaterial)
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
                    Circle().fill(.purple.opacity(0.7)).frame(width: 46, height: 46).overlay(Text(member.nickname.prefix(1)).bold())
                    VStack(alignment: .leading) {
                        HStack { Text(member.nickname).bold(); if member.userId == currentID { Text("Вы").font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).liquidCard(Capsule()) } }
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
                Capsule().fill(LinearGradient(colors: [.pink, .purple, .blue], startPoint: .leading, endPoint: .trailing)).frame(width: max(10, width * ratio), height: 6)
                Circle().fill(.white).shadow(color: .purple.opacity(0.7), radius: 7).frame(width: 18, height: 18).offset(x: max(0, min(width - 18, width * ratio - 9)))
            }.frame(height: proxy.size.height).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in guard enabled else { return }; dragging = min(duration, max(0, duration * value.location.x / width)) }.onEnded { _ in if let value = dragging { commit(value) }; dragging = nil })
        }.frame(height: 26).opacity(enabled ? 1 : 0.58)
    }
}

struct NativeChatPane: View {
    let messages: [ChatMessage]
    @Binding var draft: String
    @Binding var focused: Bool
    let send: (String) -> Void
    let react: (Int, String) -> Void
    @FocusState private var inputFocused: Bool
    private let quickReactions = ["👍", "❤️", "😂", "🔥", "😮", "👏", "😭", "🎬", "🍿", "✨"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Чат").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in NativeMessageBubble(message: message, react: react, quickReactions: quickReactions).id(message.id) }
                    }.padding(.vertical, 2)
                }.contentShape(Rectangle()).onTapGesture { focused = false; inputFocused = false }
                    .onChange(of: messages.count) { _, _ in scroll(proxy) }
                    .onChange(of: focused) { _, value in if value { scroll(proxy) } }
            }.frame(maxHeight: focused ? 310 : 220)
            HStack(spacing: 8) {
                TextField("Сообщение…", text: $draft).focused($inputFocused).submitLabel(.send).onSubmit { submit() }
                    .onChange(of: inputFocused) { _, value in focused = value }
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 31, weight: .medium)) }
                    .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.horizontal, 12).padding(.vertical, 8).liquidCard(Capsule())
        }.padding(12).liquidCard()
    }
    private func submit() { let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; send(text); draft = ""; focused = true; inputFocused = true }
    private func scroll(_ proxy: ScrollViewProxy) { if let id = messages.last?.id { DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } } } }
}

struct NativeMessageBubble: View {
    let message: ChatMessage; let react: (Int, String) -> Void; let quickReactions: [String]
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(.purple.opacity(0.72)).frame(width: 36, height: 36).overlay(Text(message.nickname.prefix(1)).font(.caption.bold()))
            VStack(alignment: .leading, spacing: 4) {
                Text(message.nickname).font(.caption.bold()).foregroundStyle(.secondary)
                if !message.text.isEmpty { Text(message.text).font(.subheadline).lineLimit(5) }
                if !message.reactions.isEmpty { HStack(spacing: 5) { ForEach(message.reactions) { item in Button { react(message.id, item.emoji) } label: { Text("\(item.emoji) \(item.count)").font(.caption2).padding(.horizontal, 7).padding(.vertical, 3).background(item.reacted ? Color.purple.opacity(0.44) : Color.white.opacity(0.08), in: Capsule()) }.buttonStyle(.plain) } } }
            }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 16)).contextMenu { ForEach(quickReactions, id: \.self) { emoji in Button(emoji) { react(message.id, emoji) } }
            }
            Spacer(minLength: 20)
        }
    }
}
