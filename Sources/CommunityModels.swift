import Foundation

struct CommunityMember: Identifiable, Hashable {
    let id: String
    let username: String
    let role: String
    let joinedAt: Date?
    let badges: [String]
    let style: UserStyle
    let signsTotal: Int
    let bio: String
    let profileViews: Int
    let friendsCount: Int
    let isFriend: Bool
}

struct CommunityMessage: Identifiable, Hashable {
    let id: String
    let conversationID: String
    let senderUsername: String
    let senderRole: String
    let body: String
    let createdAt: Date
    let unread: Bool
}

struct CommunityConversation: Identifiable, Hashable {
    let id: String
    let participantUsername: String
    let participantRole: String
    let lastMessage: String
    let updatedAt: Date
    let unreadCount: Int
}

enum CertificateRequestType: String, CaseIterable, Identifiable {
    case development = "Development"
    case testing = "Testing"
    case personal = "Personal use"
    case other = "Other"
    var id: String { rawValue }
}

enum CertificateRequestStatus: String {
    case pending = "Pending"
    case reviewing = "Reviewing"
    case approved = "Approved"
    case denied = "Denied"
    case completed = "Completed"
}

struct CertificateRequest: Identifiable, Hashable {
    let id: String
    let status: CertificateRequestStatus
    let certificateType: String
    let reason: String
    let udid: String
    let benefit: String
    let staffResponse: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ManagedCertificateSummary: Hashable {
    let name: String
    let type: String
    let expiresAt: Date?
    let status: String
    let mdid: String
}

struct CommunityAnnouncement: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let audience: String
    let senderUsername: String
    let senderRole: String
    let createdAt: Date
    let expiresAt: Date?
    let read: Bool
}

enum AnnouncementAudience: String, CaseIterable, Identifiable {
    case everyone = "everyone"
    case staff = "staff"
    case developer = "developer"
    case admin = "admin"
    case individual = "individual"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: return "Everyone"
        case .staff: return "Staff"
        case .developer: return "Developers"
        case .admin: return "Admins"
        case .individual: return "Individual user"
        }
    }
}

struct CommunityAuditEvent: Identifiable, Hashable {
    let id: String
    let actorUsername: String
    let actorRole: String
    let action: String
    let target: String
    let createdAt: Date
}
