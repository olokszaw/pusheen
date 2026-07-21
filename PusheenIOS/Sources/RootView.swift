import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View {
        Group { if session.profile == nil { AuthView() } else { HomeView() } }
            .preferredColorScheme(.dark)
    }
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

    var body: some View {
        ZStack { AcrylicBackground()
            VStack(spacing: 18) {
                Image(systemName: "play.fill").font(.system(size: 34, weight: .bold)).frame(width: 74, height: 74).foregroundStyle(.white).liquidCard(RoundedRectangle(cornerRadius: 24))
                Text(isRegister ? "Создай профиль" : "Смотри. Чувствуй.\nБудь рядом.").font(.system(size: 31, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    if isRegister { TextField("Nickname", text: $nickname).textContentType(.nickname) }
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
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
        catch { error = error.localizedDescription }
    }
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var rooms: [Room] = []
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { ZStack { AcrylicBackground()
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                HStack { VStack(alignment: .leading) { Text("Pusheen").font(.largeTitle.bold()); Text("Привет, \(session.profile?.nickname ?? "")").foregroundStyle(.secondary) }; Spacer(); Button { session.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }.buttonStyle(.glass) }
                Text("Мои комнаты").font(.title2.bold())
                ForEach(rooms) { room in NavigationLink(value: room) { RoomCard(room: room) }.buttonStyle(.plain) }
                if rooms.isEmpty { ContentUnavailableView("Комнат пока нет", systemImage: "play.rectangle.on.rectangle", description: Text("Создай комнату в текущей Flutter-версии — SwiftUI-клиент сразу её увидит.")) }
            }.padding(18) }.task { await load() }
        }.navigationDestination(for: Room.self) { RoomView(room: $0) } }
    }
    private func load() async { rooms = (try? await session.api.rooms()) ?? [] }
}

struct RoomCard: View {
    let room: Room
    var body: some View { HStack(spacing: 14) { Image(systemName: "play.fill").font(.title2).frame(width: 58, height: 58).liquidCard(Circle()); VStack(alignment: .leading, spacing: 4) { Text(room.title).font(.headline).lineLimit(1); Text("\(room.membersCount) участников · \(room.inviteCode)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(14).liquidCard() }
}

struct RoomView: View {
    @EnvironmentObject private var session: SessionStore
    let room: Room
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var showTime = false
    var body: some View { ZStack { AcrylicBackground(); ScrollView { VStack(spacing: 14) {
        VideoPlayerPlaceholder(room: room, showTime: $showTime)
        VStack(alignment: .leading, spacing: 10) { Text("Чат").font(.headline); ForEach(messages) { message in HStack { Text(message.nickname).font(.caption.bold()).foregroundStyle(.purple); Text(message.text); Spacer() }.padding(10).liquidCard(RoundedRectangle(cornerRadius: 15)) }; HStack { TextField("Сообщение…", text: $draft); Button { draft = "" } label: { Image(systemName: "arrow.up.circle.fill") }.disabled(draft.isEmpty) }.padding(8).liquidCard(Capsule()) }.padding(14).liquidCard()
    } .padding(14) }.task { messages = (try? await session.api.messages(roomID: room.id)) ?? [] } }.navigationTitle(room.title).navigationBarTitleDisplayMode(.inline) }
}

struct VideoPlayerPlaceholder: View {
    let room: Room; @Binding var showTime: Bool
    var body: some View { VStack(spacing: 12) { ZStack { AsyncImage(url: URL(string: room.thumbnailURL)) { image in image.resizable().scaledToFill() } placeholder: { Color.black } }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 24)); Image(systemName: "play.fill").font(.system(size: 32)).frame(width: 66, height: 66).liquidCard(Circle()) }
        Slider(value: .constant(room.playback?.positionSeconds ?? 0), in: 0...max(1, (room.playback?.positionSeconds ?? 0) + 1)).disabled(true)
        HStack { Button { } label: { Image(systemName: "gobackward.10") }; Button { } label: { Image(systemName: "play.fill") }; Button { } label: { Image(systemName: "goforward.10") }; Spacer(); Button { showTime = true } label: { Text("00:00") } }.buttonStyle(.glass)
    }.padding(12).liquidCard() .sheet(isPresented: $showTime) { TimePickerSheet() }
}

struct TimePickerSheet: View { @Environment(\.dismiss) private var dismiss; @State private var minute = 0; @State private var second = 0
    var body: some View { VStack(spacing: 22) { Text("Перейти к таймкоду").font(.headline); HStack { Picker("Мин", selection: $minute) { ForEach(0..<180, id: \.self) { Text("\($0) мин") } }; Picker("Сек", selection: $second) { ForEach(0..<60, id: \.self) { Text("\($0) сек") } } }.pickerStyle(.wheel); Button("Перейти") { dismiss() }.buttonStyle(.borderedProminent) }.padding().presentationDetents([.height(330)]).presentationBackground(.ultraThinMaterial) }
}
