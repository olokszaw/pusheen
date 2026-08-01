import Foundation
import UniformTypeIdentifiers

enum APIError: LocalizedError { case invalidURL, server(String); var errorDescription: String? { switch self { case .invalidURL: return "Неверный адрес сервера"; case .server(let text): return text } } }

@MainActor
final class SessionStore: ObservableObject {
    enum AuthenticationState: Equatable { case restoring, signedOut, signedIn }
    @Published var profile: Profile?
    @Published var token: String?
    @Published private(set) var authenticationState: AuthenticationState = .restoring
    @Published var friendRequests = FriendRequestsResponse(incoming: [], outgoing: [])
    @Published var friendRequestNotice: FriendRequestProfile?
    @Published var viewingStats: ViewingStats?
    let api = APIClient()
    private var friendRequestPollingTask: Task<Void, Never>?
    private var appActivityTask: Task<Void, Never>?
    private var knownIncomingRequestIDs = Set<Int>()
    private var hasPrimedFriendRequests = false

    init() {
        token = UserDefaults.standard.string(forKey: "pusheen.token")
        if let token {
            api.token = token
            Task { await restore() }
        } else {
            authenticationState = .signedOut
        }
    }

    func restore() async {
        defer { if profile == nil { authenticationState = .signedOut } }
        do {
            profile = try await api.profile()
            authenticationState = .signedIn
            viewingStats = try? await api.viewingStats()
            startFriendRequestPolling()
            startActivityHeartbeat()
        } catch {
            token = nil
            api.token = nil
            UserDefaults.standard.removeObject(forKey: "pusheen.token")
        }
    }
    func login(username: String, password: String) async throws { let auth = try await api.login(username: username, password: password); apply(auth) }
    func register(nickname: String, username: String, password: String) async throws { let auth = try await api.register(nickname: nickname, username: username, password: password); apply(auth) }
    func apply(_ auth: AuthPayload) { token = auth.token; profile = auth.profile; api.token = auth.token; authenticationState = .signedIn; UserDefaults.standard.set(auth.token, forKey: "pusheen.token"); startFriendRequestPolling(); startActivityHeartbeat(); Task { self.viewingStats = try? await self.api.viewingStats() } }
    func logout() { friendRequestPollingTask?.cancel(); friendRequestPollingTask = nil; appActivityTask?.cancel(); appActivityTask = nil; friendRequests = FriendRequestsResponse(incoming: [], outgoing: []); friendRequestNotice = nil; knownIncomingRequestIDs = []; hasPrimedFriendRequests = false; token = nil; profile = nil; api.token = nil; authenticationState = .signedOut; UserDefaults.standard.removeObject(forKey: "pusheen.token") }

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

    func refreshViewingStats() async { viewingStats = try? await api.viewingStats() }

    private func startFriendRequestPolling() {
        friendRequestPollingTask?.cancel()
        friendRequestPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshFriendRequests()
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
}

final class APIClient {
    static let fallbackBaseURLString = "https://located-prime-ranks-neural.trycloudflare.com"
    // The workflow writes this setting into Info.plist, so it remains available
    // after installation (unlike an environment variable available only at build time).
    let baseURL = URL(string: (Bundle.main.object(forInfoDictionaryKey: "PusheenAPIBaseURL") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackBaseURLString)!
    var serverHost: String { baseURL.host ?? baseURL.absoluteString }
    var token: String?
    private let decoder = JSONDecoder()

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token { request.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Ошибка сервера"
            throw APIError.server(detail)
        }
        return data
    }
    func login(username: String, password: String) async throws -> AuthPayload { let data = try await request("/api/auth/login/", method: "POST", body: ["username": username, "password": password], authenticated: false); return try decoder.decode(AuthPayload.self, from: data) }
    func register(nickname: String, username: String, password: String) async throws -> AuthPayload { let data = try await request("/api/auth/register/", method: "POST", body: ["nickname": nickname, "username": username, "password": password], authenticated: false); return try decoder.decode(AuthPayload.self, from: data) }
    func profile() async throws -> Profile { let data = try await request("/api/profile/"); return try decoder.decode(Profile.self, from: data) }
    func rooms() async throws -> [Room] { let data = try await request("/api/rooms/"); return try decoder.decode([Room].self, from: data) }
    func messages(roomID: Int) async throws -> [ChatMessage] { let data = try await request("/api/rooms/\(roomID)/messages/"); return try decoder.decode([ChatMessage].self, from: data) }
    func members(roomID: Int) async throws -> [RoomMember] { let data = try await request("/api/rooms/\(roomID)/members/"); return try decoder.decode([RoomMember].self, from: data) }
    func moderateMember(roomID: Int, userID: Int, action: String) async throws { _ = try await request("/api/rooms/\(roomID)/members/\(userID)/moderate/", method: "POST", body: ["action": action]) }
    func stream(roomID: Int) async throws -> VideoStream { let data = try await request("/api/rooms/\(roomID)/stream/"); return try decoder.decode(VideoStream.self, from: data) }
    func createRoom(videoURL: String, isPrivate: Bool) async throws -> Room { let data = try await request("/api/rooms/", method: "POST", body: ["title": "", "vk_video_url": videoURL, "media_url": videoURL, "is_private": isPrivate]); return try decoder.decode(Room.self, from: data) }
    func uploadRoomVideo(roomID: Int, fileURL: URL) async throws -> Room {
        guard let url = URL(string: "/api/rooms/\(roomID)/upload/", relativeTo: baseURL) else { throw APIError.invalidURL }
        let boundary = "PusheenUpload-\(UUID().uuidString)"
        let bodyURL = try makeMultipartUpload(fileURL: fileURL, boundary: boundary)
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
    private func makeMultipartUpload(fileURL: URL, boundary: String) throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("pusheen-upload-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let name = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "video/mp4"
        let title = fileURL.deletingPathExtension().lastPathComponent
        output.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n\(title)\r\n".utf8))
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
    func viewingStats() async throws -> ViewingStats { let data = try await request("/api/activity/"); return try decoder.decode(ViewingStats.self, from: data) }
    func reportActivity(appSeconds: Int = 0, watchedSeconds: Int = 0, durationSeconds: Int = 0, genres: [String] = [], roomID: Int? = nil) async throws -> ViewingStats {
        var body: [String: Any] = ["app_seconds": appSeconds, "watched_seconds": watchedSeconds, "duration_seconds": durationSeconds, "genres": genres]
        if let roomID { body["room_id"] = roomID }
        let data = try await request("/api/activity/", method: "POST", body: body)
        return try decoder.decode(ViewingStats.self, from: data)
    }
    func respondToFriendRequest(id: Int, accept: Bool) async throws { _ = try await request("/api/friends/requests/", method: "POST", body: ["request_id": id, "action": accept ? "accept" : "decline"]) }
    func updateProfile(nickname: String? = nil, username: String? = nil, avatar: String? = nil) async throws -> Profile { var body: [String: Any] = [:]; if let nickname { body["nickname"] = nickname }; if let username { body["username"] = username }; if let avatar { body["avatar_data_url"] = avatar }; let data = try await request("/api/profile/", method: "PATCH", body: body); return try decoder.decode(Profile.self, from: data) }
}
