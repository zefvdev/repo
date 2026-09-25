import Foundation

@MainActor
final class CommunityClient: ObservableObject {
    static let shared = CommunityClient()
    @Published private(set) var members: [CommunityMember] = []
    @Published private(set) var conversations: [CommunityConversation] = []
    @Published private(set) var messages: [CommunityMessage] = []
    @Published private(set) var requests: [CertificateRequest] = []
    @Published private(set) var managedCertificate: ManagedCertificateSummary?
    @Published private(set) var announcements: [CommunityAnnouncement] = []
    @Published private(set) var auditEvents: [CommunityAuditEvent] = []
    @Published var busy = false
    @Published var error: String?

    private init() {}

    private var base: URL? {
        let configured = UserDefaults.standard.string(forKey: "uzd_community_base") ?? ""
        return URL(string: configured.isEmpty ? ZefvAccount.accountAPIBase : configured)
    }

    private func request(_ path: String, method: String = "GET", query: [String:String] = [:], body: [String:Any]? = nil) async throws -> [String:Any] {
        guard let base else { throw ZefvAccount.Err.badURL }
        var finalQuery = query
        var finalBody = body ?? [:]
        if let token = ZefvAccount.shared.sessionToken {
            if method == "GET" { finalQuery["token"] = token }
            else { finalBody["token"] = token }
        }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if method == "GET" { components?.queryItems = finalQuery.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components?.url else { throw ZefvAccount.Err.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(ServerConfig.certSourceToken, forHTTPHeaderField: "X-OTA-Token")
        if let token = ZefvAccount.shared.sessionToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method != "GET" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: finalBody)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any] ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 { throw ZefvAccount.Err.server((object["error"] as? String) ?? "Server error (\(code))") }
        return object
    }

    func refresh() async {
        guard ZefvAccount.shared.isLoggedIn else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let m = try await request("members.php", query: ["mdid": MDID.current])
            members = Self.members(from: m["members"])
            let c = try await request("conversations.php")
            conversations = Self.conversations(from: c["conversations"])
            let a = try await request("community.php", query: ["action":"announcements"])
            announcements = Self.announcements(from: a["announcements"])
            let r = try await request("certificate_requests.php", query: ["action":"list"])
            requests = Self.requests(from: r["requests"])
            if let cert = r["managed_certificate"] as? [String:Any] { managedCertificate = Self.certificate(from: cert) }
        } catch let caughtError { self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription }
    }

    func sendMessage(to username: String, body: String) async -> Bool {
        do {
            _ = try await request("messages.php", method: "POST", body: ["action":"send", "to":username, "body":body])
            await refreshConversations()
            return true
        } catch let caughtError { self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription; return false }
    }


    func sendNewMessage(to username: String, body: String) async -> Bool {
        await sendMessage(to: username.trimmingCharacters(in: .whitespacesAndNewlines), body: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func markAnnouncementRead(id: String) async {
        do { _ = try await request("community.php", method: "POST", body: ["action":"announcement_read", "announcement_id":id]) } catch { }
        announcements = announcements.map { a in
            guard a.id == id else { return a }
            return CommunityAnnouncement(id:a.id, title:a.title, body:a.body, audience:a.audience, senderUsername:a.senderUsername, senderRole:a.senderRole, createdAt:a.createdAt, expiresAt:a.expiresAt, read:true)
        }
    }

    func sendAnnouncement(title: String, body: String, audience: AnnouncementAudience, target: String? = nil, expiresAt: Date? = nil) async -> Bool {
        do {
            var payload: [String:Any] = ["action":"announcement_create", "title":title, "body":body, "audience":audience.rawValue]
            if let target, !target.isEmpty { payload["target"] = target }
            if let expiresAt { payload["expires_at"] = ISO8601DateFormatter().string(from: expiresAt) }
            _ = try await request("community.php", method:"POST", body:payload)
            await refresh()
            return true
        } catch let caughtError {
            self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription
            return false
        }
    }

    func loadAudit() async {
        do {
            let o = try await request("community.php", query:["action":"audit"])
            auditEvents = Self.audit(from:o["events"])
        } catch let caughtError { self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription }
    }

    func recordProfileView(memberID: String) async {
        do { _ = try await request("profile.php", method: "POST", body: ["action":"view", "member_id":memberID]) } catch { }
    }

    func addFriend(memberID: String) async -> Bool {
        do { _ = try await request("friends.php", method: "POST", body: ["action":"add", "member_id":memberID]); return true }
        catch let caughtError { self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription; return false }
    }

    func loadMessages(conversationID: String) async {
        do {
            let o = try await request("messages.php", query: ["conversation_id":conversationID])
            messages = Self.messages(from: o["messages"])
        } catch let caughtError { self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription }
    }

    func submitCertificateRequest(type: CertificateRequestType, reason: String, udid: String, benefit: String) async -> Bool {
        do {
            _ = try await request("certificate_requests.php", method: "POST", body: [
                "action":"create", "certificate_type":type.rawValue,
                "reason":reason, "udid":udid, "benefit":benefit, "mdid":MDID.current
            ])
            await refresh()
            return true
        } catch let caughtError { self.error = (caughtError as? ZefvAccount.Err)?.message ?? caughtError.localizedDescription; return false }
    }

    private func refreshConversations() async {
        if let o = try? await request("conversations.php") { conversations = Self.conversations(from: o["conversations"]) }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: s) ?? DateFormatter.communityDate.date(from: s)
    }
    private static func members(from value: Any?) -> [CommunityMember] {
        guard let a = value as? [[String:Any]] else { return [] }
        return a.compactMap {
            guard let id = $0["id"] as? String, let username = $0["username"] as? String else { return nil }
            return CommunityMember(id:id, username:username, role:$0["role"] as? String ?? "member", joinedAt:date($0["joined_at"]), badges:$0["badges"] as? [String] ?? [], style:UserStyle(json:$0["style"] as? [String:Any]), signsTotal:$0["signs_total"] as? Int ?? 0, bio:$0["bio"] as? String ?? "", profileViews:$0["profile_views"] as? Int ?? 0, friendsCount:$0["friends_count"] as? Int ?? 0, isFriend:$0["is_friend"] as? Bool ?? false)
        }
    }
    private static func conversations(from value: Any?) -> [CommunityConversation] {
        guard let a = value as? [[String:Any]] else { return [] }
        return a.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return CommunityConversation(id:id, participantUsername:$0["participant_username"] as? String ?? "", participantRole:$0["participant_role"] as? String ?? "member", lastMessage:$0["last_message"] as? String ?? "", updatedAt:date($0["updated_at"]) ?? Date(), unreadCount:$0["unread_count"] as? Int ?? 0)
        }
    }
    private static func messages(from value: Any?) -> [CommunityMessage] {
        guard let a = value as? [[String:Any]] else { return [] }
        return a.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return CommunityMessage(id:id, conversationID:$0["conversation_id"] as? String ?? "", senderUsername:$0["sender_username"] as? String ?? "", senderRole:$0["sender_role"] as? String ?? "member", body:$0["body"] as? String ?? "", createdAt:date($0["created_at"]) ?? Date(), unread:$0["unread"] as? Bool ?? false)
        }
    }
    private static func requests(from value: Any?) -> [CertificateRequest] {
        guard let a = value as? [[String:Any]] else { return [] }
        return a.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return CertificateRequest(id:id, status:CertificateRequestStatus(rawValue:$0["status"] as? String ?? "Pending") ?? .pending, certificateType:$0["certificate_type"] as? String ?? "", reason:$0["reason"] as? String ?? "", udid:$0["udid"] as? String ?? "", benefit:$0["benefit"] as? String ?? "", staffResponse:$0["staff_response"] as? String, createdAt:date($0["created_at"]) ?? Date(), updatedAt:date($0["updated_at"]) ?? Date())
        }
    }
    private static func announcements(from value: Any?) -> [CommunityAnnouncement] {
        guard let a = value as? [[String:Any]] else { return [] }
        return a.compactMap { x in
            guard let id = x["id"] as? String else { return nil }
            return CommunityAnnouncement(id:id, title:x["title"] as? String ?? "", body:x["body"] as? String ?? "", audience:x["audience"] as? String ?? "everyone", senderUsername:x["sender_username"] as? String ?? "", senderRole:x["sender_role"] as? String ?? "member", createdAt:date(x["created_at"]) ?? Date(), expiresAt:date(x["expires_at"]), read:x["read"] as? Bool ?? false)
        }
    }

    private static func audit(from value: Any?) -> [CommunityAuditEvent] {
        guard let a = value as? [[String:Any]] else { return [] }
        return a.compactMap { x in
            guard let id = x["id"] as? String else { return nil }
            return CommunityAuditEvent(id:id, actorUsername:x["actor_username"] as? String ?? "", actorRole:x["actor_role"] as? String ?? "", action:x["action"] as? String ?? "", target:x["target"] as? String ?? "", createdAt:date(x["created_at"]) ?? Date())
        }
    }

    private static func certificate(from value: [String:Any]) -> ManagedCertificateSummary {
        ManagedCertificateSummary(name:value["name"] as? String ?? "Managed certificate", type:value["type"] as? String ?? "", expiresAt:date(value["expires_at"]), status:value["status"] as? String ?? "Active", mdid:value["mdid"] as? String ?? MDID.current)
    }
}

private extension DateFormatter {
    static let communityDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
}
