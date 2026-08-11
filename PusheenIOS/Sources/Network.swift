import Foundation
import UniformTypeIdentifiers
import AVFoundation

enum APIError: LocalizedError {
    case invalidURL, unauthorized, server(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Неверный адрес сервера"
        case .unauthorized: return "Сессия закончилась"
        case .server(let text): return text
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    enum AuthenticationState: Equatable { case restoring, signedOut, signedIn }
    @Published var profile: Profile?
    @Published var token: String?
    @Published private(set) var authenticationState: AuthenticationState = .restoring
    @Published var friendRequests = FriendRequestsResponse(incoming: [], outgoing: [])
    @Published var friendRequestNotice: FriendRequestProfile?
    @Published var roomInvitations: [RoomInvitation] = []
    @Published var roomInvitationNotice: RoomInvitation?
    @Published var roomInvitationStatusNotice: String?
    @Published var acceptedInvitedRoom: Room?
    @Published var viewingStats: ViewingStats?
    @Published private(set) var isOffline = false
    let api = APIClient()
    private var friendRequestPollingTask: Task<Void, Never>?
    private var appActivityTask: Task<Void, Never>?
    private var presenceHeartbeatTask: Task<Void, Never>?
    private var restoreRetryTask: Task<Void, Never>?
    private var appIsActive = true
    private var knownIncomingRequestIDs = Set<Int>()
    private var hasPrimedFriendRequests = false
    private let cachedProfileKey = "pusheen.cached-profile"
    private let cachedViewingStatsKey = "pusheen.cached-viewing-stats"

    init() {
        token = UserDefaults.standard.string(forKey: "pusheen.token")
        if let token {
            api.token = token
            profile = Self.loadCachedProfile()
            viewingStats = Self.loadCachedViewingStats()
            authenticationState = .signedIn
            Task { await restore() }
        } else {
            authenticationState = .signedOut
        }
    }

    func restore() async {
        do {
            profile = try await api.profile()
            saveCachedProfile()
            authenticationState = .signedIn
            isOffline = false
            restoreRetryTask = nil
            if let stats = try? await api.viewingStats() { viewingStats = stats; saveCachedViewingStats() }
            startForegroundTasks()
        } catch APIError.unauthorized {
            logout()
        } catch {
            // A tunnel outage, timeout, or no network must not erase a saved login.
            authenticationState = .signedIn
            isOffline = true
            startOfflineRetry()
        }
    }
    func login(username: String, password: String) async throws { let auth = try await api.login(username: username, password: password); apply(auth) }
    func register(nickname: String, username: String, password: String) async throws { let auth = try await api.register(nickname: nickname, username: username, password: password); apply(auth) }
    func apply(_ auth: AuthPayload) { token = auth.token; profile = auth.profile; saveCachedProfile(); api.token = auth.token; authenticationState = .signedIn; UserDefaults.standard.set(auth.token, forKey: "pusheen.token"); startForegroundTasks(); Task { if let stats = try? await self.api.viewingStats() { self.viewingStats = stats; self.saveCachedViewingStats() } } }
    func logout() {
        let authorizationToken = token
        if let authorizationToken {
            Task { [api] in try? await api.setPresence(active: false, authorizationToken: authorizationToken) }
        }
        friendRequestPollingTask?.cancel(); friendRequestPollingTask = nil; appActivityTask?.cancel(); appActivityTask = nil; presenceHeartbeatTask?.cancel(); presenceHeartbeatTask = nil; restoreRetryTask?.cancel(); restoreRetryTask = nil; friendRequests = FriendRequestsResponse(incoming: [], outgoing: []); friendRequestNotice = nil; roomInvitations = []; roomInvitationNotice = nil; roomInvitationStatusNotice = nil; acceptedInvitedRoom = nil; knownIncomingRequestIDs = []; hasPrimedFriendRequests = false; isOffline = false; token = nil; profile = nil; viewingStats = nil; api.token = nil; authenticationState = .signedOut; UserDefaults.standard.removeObject(forKey: "pusheen.token"); UserDefaults.standard.removeObject(forKey: cachedProfileKey); UserDefaults.standard.removeObject(forKey: cachedViewingStatsKey)
    }

    func setAppActive(_ active: Bool) {
        guard appIsActive != active else {
            if active { startForegroundTasks() }
            return
        }
        appIsActive = active
        if active {
            startForegroundTasks()
        } else {
            friendRequestPollingTask?.cancel(); friendRequestPollingTask = nil
            appActivityTask?.cancel(); appActivityTask = nil
            presenceHeartbeatTask?.cancel(); presenceHeartbeatTask = nil
            guard token != nil else { return }
            Task { [api] in try? await api.setPresence(active: false) }
        }
    }

    private func startForegroundTasks() {
        guard appIsActive, authenticationState == .signedIn, token != nil else { return }
        startFriendRequestPolling()
        startActivityHeartbeat()
        startPresenceHeartbeat()
    }

    private static func loadCachedProfile() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: "pusheen.cached-profile") else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    private static func loadCachedViewingStats() -> ViewingStats? {
        guard let data = UserDefaults.standard.data(forKey: "pusheen.cached-viewing-stats") else { return nil }
        return try? JSONDecoder().decode(ViewingStats.self, from: data)
    }

    private func saveCachedProfile() {
        guard let profile, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: cachedProfileKey)
    }

    private func saveCachedViewingStats() {
        guard let viewingStats, let data = try? JSONEncoder().encode(viewingStats) else { return }
        UserDefaults.standard.set(data, forKey: cachedViewingStatsKey)
    }

    private func startOfflineRetry() {
        guard restoreRetryTask == nil else { return }
        restoreRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.token != nil else { return }
                await self.restore()
                if !self.isOffline { return }
            }
        }
    }

    func refreshFriendRequests() async {
        guard authenticationState == .signedIn, let response = try? await api.friendRequests() else { return }
        let newItems = response.incoming.filter { !knownIncomingRequestIDs.contains($0.id) }
        friendRequests = response
        knownIncomingRequestIDs = Set(response.incoming.map(\.id))
        if hasPrimedFriendRequests, let first = newItems.first { friendRequestNotice = first }
        hasPrimedFriendRequests = true
    }

    func respond(to request: FriendRequestProfile, accept: Bool) async {
        guard (try? await api.respondToFriendRequest(id: request.id, accept: accept)) != nil else { return }
        if friendRequestNotice?.id == request.id { friendRequestNotice = nil }
        await refreshFriendRequests()
    }

    func cancel(_ request: FriendRequestProfile) async {
        guard (try? await api.cancelFriendRequest(id: request.id)) != nil else { return }
        await refreshFriendRequests()
    }

    func refreshRoomInvitations() async {
        guard authenticationState == .signedIn, let invitations = try? await api.roomInvitations() else { return }
        roomInvitations = invitations
        if let shown = roomInvitationNotice, !invitations.contains(where: { $0.id == shown.id }) {
            roomInvitationNotice = nil
        }
        if roomInvitationNotice == nil { roomInvitationNotice = invitations.first }
    }

    func respond(to invitation: RoomInvitation, accept: Bool) async {
        do {
            roomInvitationStatusNotice = nil
            let response = try await api.respondToRoomInvitation(id: invitation.id, accept: accept)
            roomInvitations.removeAll { $0.id == invitation.id }
            if roomInvitationNotice?.id == invitation.id { roomInvitationNotice = nil }
            if accept, let room = response.room { acceptedInvitedRoom = room }
            await refreshRoomInvitations()
        } catch {
            roomInvitations.removeAll { $0.id == invitation.id }
            roomInvitationNotice = nil
            roomInvitationStatusNotice = error.localizedDescription.isEmpty ? "Приглашение больше недействительно" : error.localizedDescription
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                self?.roomInvitationStatusNotice = nil
            }
        }
    }

    func refreshViewingStats() async { if let stats = try? await api.viewingStats() { viewingStats = stats; saveCachedViewingStats() } }

    private func startFriendRequestPolling() {
        friendRequestPollingTask?.cancel()
        friendRequestPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshFriendRequests()
                await self?.refreshRoomInvitations()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startActivityHeartbeat() {
        appActivityTask?.cancel()
        appActivityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                let stats = try? await self.api.reportActivity(appSeconds: 30)
                guard !Task.isCancelled else { return }
                if let stats { self.viewingStats = stats }
            }
        }
    }

    private func startPresenceHeartbeat() {
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.appIsActive, self.token != nil else { return }
                try? await self.api.setPresence(active: true)
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }
}

final class APIClient {
    static let fallbackBaseURLString = "https://try-believe-portable-prostate.trycloudflare.com"
    // The workflow writes this setting into Info.plist, so it remains available
    // after installation (unlike an environment variable available only at build time).
    let baseURL = URL(string: (Bundle.main.object(forInfoDictionaryKey: "PusheenAPIBaseURL") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackBaseURLString)!
    var serverHost: String { baseURL.host ?? baseURL.absoluteString }
    var token: String?
    private let decoder = JSONDecoder()

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true, timeout: TimeInterval = 8, authorizationToken: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let credential = authorizationToken ?? token { request.setValue("Token \(credential)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("Unexpected server response")
        }
        guard 200..<300 ~= http.statusCode else {
            if authenticated, http.statusCode == 401 || http.statusCode == 403 {
                throw APIError.unauthorized
            }
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Ошибка сервера"
            throw APIError.server(detail)
        }
        return data
    }
    func login(username: String, password: String) async throws -> AuthPayload { let data = try await request("/api/auth/login/", method: "POST", body: ["username": username, "password": password], authenticated: false); return try decoder.decode(AuthPayload.self, from: data) }
    func register(nickname: String, username: String, password: String) async throws -> AuthPayload { let data = try await request("/api/auth/register/", method: "POST", body: ["nickname": nickname, "username": username, "password": password], authenticated: false); return try decoder.decode(AuthPayload.self, from: data) }
    func profile() async throws -> Profile { let data = try await request("/api/profile/"); return try decoder.decode(Profile.self, from: data) }
    func setPresence(active: Bool, authorizationToken: String? = nil) async throws { _ = try await request("/api/presence/", method: "POST", body: ["active": active], timeout: 5, authorizationToken: authorizationToken) }
    func publicProfile(userID: Int) async throws -> PublicUserProfile { let data = try await request("/api/users/\(userID)/profile/"); return try decoder.decode(PublicUserProfile.self, from: data) }
    func rooms() async throws -> [Room] { let data = try await request("/api/rooms/"); return try decoder.decode([Room].self, from: data) }
    func searchMovies(_ query: String) async throws -> [MovieCatalogItem] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: query), URLQueryItem(name: "media", value: "all"), URLQueryItem(name: "limit", value: "25")]
        guard let url = components.url else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw APIError.server("Не удалось выполнить поиск фильмов") }
        return try decoder.decode(MovieCatalogResponse.self, from: data).results.filter { $0.kind == "feature-movie" }
    }
    func messages(roomID: Int) async throws -> [ChatMessage] { let data = try await request("/api/rooms/\(roomID)/messages/"); return try decoder.decode([ChatMessage].self, from: data) }
    func sendMessage(roomID: Int, text: String, image: String = "", clientMessageID: String, replyToID: Int? = nil) async throws -> ChatMessage {
        var body: [String: Any] = ["text": text, "image_data_url": image, "client_message_id": clientMessageID]
        if let replyToID { body["reply_to_id"] = replyToID }
        let data = try await request("/api/rooms/\(roomID)/messages/", method: "POST", body: body)
        return try decoder.decode(ChatMessage.self, from: data)
    }
    func sendMessagesBatch(roomID: Int, messages: [[String: Any]]) async throws -> [ChatMessage] {
        let data = try await request("/api/rooms/\(roomID)/messages/batch/", method: "POST", body: ["messages": messages])
        return try decoder.decode([ChatMessage].self, from: data)
    }
    func members(roomID: Int) async throws -> [RoomMember] { let data = try await request("/api/rooms/\(roomID)/members/"); return try decoder.decode([RoomMember].self, from: data) }
    func moderateMember(roomID: Int, userID: Int, action: String) async throws { _ = try await request("/api/rooms/\(roomID)/members/\(userID)/moderate/", method: "POST", body: ["action": action]) }
    func stream(roomID: Int) async throws -> VideoStream { let data = try await request("/api/rooms/\(roomID)/stream/"); return try decoder.decode(VideoStream.self, from: data) }
    func createRoom(videoURL: String, isPrivate: Bool) async throws -> Room { let data = try await request("/api/rooms/", method: "POST", body: ["title": "", "vk_video_url": videoURL, "media_url": videoURL, "is_private": isPrivate]); return try decoder.decode(Room.self, from: data) }
    func uploadRoomVideo(roomID: Int, fileURL: URL) async throws -> Room {
        guard let url = URL(string: "/api/rooms/\(roomID)/upload/", relativeTo: baseURL) else { throw APIError.invalidURL }
        let boundary = "PusheenUpload-\(UUID().uuidString)"
        let asset = AVURLAsset(url: fileURL)
        let loadedDuration = try? await asset.load(.duration)
        let duration = loadedDuration?.seconds ?? 0
        let sourceTitle = fileURL.deletingPathExtension().lastPathComponent
        let generatedTemporaryName = sourceTitle.hasPrefix("pusheen-movie-") || sourceTitle.hasPrefix("pusheen-file-")
        let displayTitle = generatedTemporaryName ? "Видео из галереи" : sourceTitle
        let bodyURL = try makeMultipartUpload(
            fileURL: fileURL,
            boundary: boundary,
            title: displayTitle,
            duration: duration.isFinite ? max(0, duration) : 0
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Не удалось загрузить видео"
            throw APIError.server(detail)
        }
        return try decoder.decode(Room.self, from: data)
    }
    private func makeMultipartUpload(fileURL: URL, boundary: String, title: String, duration: Double) throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("pusheen-upload-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let name = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "video/mp4"
        output.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n\(title)\r\n".utf8))
        output.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"duration_seconds\"\r\n\r\n\(duration)\r\n".utf8))
        output.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty { output.write(chunk) }
        output.write(Data("\r\n--\(boundary)--\r\n".utf8))
        return destination
    }
    func joinRoom(code: String) async throws -> Room { let data = try await request("/api/rooms/join/", method: "POST", body: ["invite_code": code.uppercased()]); return try decoder.decode(Room.self, from: data) }
    func deleteRoom(id: Int) async throws { _ = try await request("/api/rooms/\(id)/", method: "DELETE") }
    func usernameAvailable(_ username: String) async throws -> Bool { let data = try await request("/api/auth/username-available/?username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)"); return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["available"] as? Bool ?? false }
    func friends(query: String = "") async throws -> [FriendProfile] { let suffix = query.isEmpty ? "" : "?username=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"; let data = try await request("/api/friends/\(suffix)"); return try decoder.decode([FriendProfile].self, from: data) }
    func addFriend(username: String) async throws { _ = try await request("/api/friends/", method: "POST", body: ["username": username]) }
    func removeFriend(username: String) async throws {
        // New servers accept the query parameter because some tunnels discard a
        // DELETE body. Fall back to the legacy JSON-body contract so the current
        // IPA can also remove friends before the backend archive is deployed.
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        do {
            _ = try await request("/api/friends/?username=\(encoded)", method: "DELETE")
        } catch {
            _ = try await request("/api/friends/", method: "DELETE", body: ["username": username])
        }
    }
    func friendRequests() async throws -> FriendRequestsResponse { let data = try await request("/api/friends/requests/"); return try decoder.decode(FriendRequestsResponse.self, from: data) }
    func roomInvitations() async throws -> [RoomInvitation] { let data = try await request("/api/room-invitations/"); return try decoder.decode([RoomInvitation].self, from: data) }
    func inviteFriends(roomID: Int, userIDs: [Int]) async throws { _ = try await request("/api/rooms/\(roomID)/invites/", method: "POST", body: ["user_ids": userIDs]) }
    func respondToRoomInvitation(id: Int, accept: Bool) async throws -> RoomInvitationResponse { let data = try await request("/api/room-invitations/\(id)/", method: "POST", body: ["action": accept ? "accept" : "decline"]); return try decoder.decode(RoomInvitationResponse.self, from: data) }
    func viewingStats() async throws -> ViewingStats { let data = try await request("/api/activity/"); return try decoder.decode(ViewingStats.self, from: data) }
    func reportActivity(appSeconds: Int = 0, watchedSeconds: Int = 0, durationSeconds: Int = 0, genres: [String] = [], roomID: Int? = nil) async throws -> ViewingStats {
        var body: [String: Any] = ["app_seconds": appSeconds, "watched_seconds": watchedSeconds, "duration_seconds": durationSeconds, "genres": genres]
        if let roomID { body["room_id"] = roomID }
        let data = try await request("/api/activity/", method: "POST", body: body)
        return try decoder.decode(ViewingStats.self, from: data)
    }
    func respondToFriendRequest(id: Int, accept: Bool) async throws { _ = try await request("/api/friends/requests/", method: "POST", body: ["request_id": id, "action": accept ? "accept" : "decline"]) }
    func cancelFriendRequest(id: Int) async throws { _ = try await request("/api/friends/requests/", method: "POST", body: ["request_id": id, "action": "cancel"]) }
    func stickerPacks() async throws -> [TelegramStickerPack] { let data = try await request("/api/sticker-packs/"); return try decoder.decode([TelegramStickerPack].self, from: data) }
    func importStickerPack(url: String) async throws -> TelegramStickerPack { let data = try await request("/api/sticker-packs/", method: "POST", body: ["url": url], timeout: 180); return try decoder.decode(TelegramStickerPack.self, from: data) }
    func stickerData(id: Int, preview: Bool = true) async throws -> Data { try await request("/api/stickers/\(id)/\(preview ? "preview" : "file")/") }
    func updateProfile(nickname: String? = nil, username: String? = nil, avatar: String? = nil) async throws -> Profile { var body: [String: Any] = [:]; if let nickname { body["nickname"] = nickname }; if let username { body["username"] = username }; if let avatar { body["avatar_data_url"] = avatar }; let data = try await request("/api/profile/", method: "PATCH", body: body); return try decoder.decode(Profile.self, from: data) }
}
