import Foundation

/// A 1:1 or group chat as shown in the channel list. Backend-agnostic (Stream today, Firestore later).
public struct Conversation: Sendable, Hashable, Identifiable {
    /// Backend channel id (Stream `cid`, e.g. `messaging:!members-…`).
    public var id: String
    public var name: String
    public var imageURL: URL?
    public var memberIds: [String]
    public var lastMessageText: String?
    public var lastMessageAt: Date?
    public var unreadCount: Int

    public init(
        id: String,
        name: String,
        imageURL: URL? = nil,
        memberIds: [String] = [],
        lastMessageText: String? = nil,
        lastMessageAt: Date? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.memberIds = memberIds
        self.lastMessageText = lastMessageText
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
    }
}

public struct ConversationMessage: Sendable, Hashable, Identifiable {
    public enum Status: Sendable, Hashable {
        case sent
        case sending
        case failed
    }

    public var id: String
    public var text: String
    public var authorId: String
    public var authorName: String
    public var authorImageURL: URL?
    public var createdAt: Date
    public var isFromCurrentUser: Bool
    public var imageURLs: [URL]
    public var status: Status

    public init(
        id: String,
        text: String,
        authorId: String,
        authorName: String,
        authorImageURL: URL? = nil,
        createdAt: Date,
        isFromCurrentUser: Bool,
        imageURLs: [URL] = [],
        status: Status = .sent
    ) {
        self.id = id
        self.text = text
        self.authorId = authorId
        self.authorName = authorName
        self.authorImageURL = authorImageURL
        self.createdAt = createdAt
        self.isFromCurrentUser = isFromCurrentUser
        self.imageURLs = imageURLs
        self.status = status
    }
}

public extension Samples {
    static func directConversationId(_ a: String, _ b: String) -> String {
        "messaging:!members-" + [a, b].sorted().joined(separator: "-")
    }

    /// Chat timestamps are relative ("15 min ago"), so they must never be in the future.
    static let chatReferenceDate = min(referenceDate, Date())

    /// Sample DMs between `performer` and a couple of venues.
    static let conversations: [Conversation] = [
        Conversation(
            id: directConversationId(performer.id, venues[0].id),
            name: venues[0].displayName,
            memberIds: [performer.id, venues[0].id],
            lastMessageText: "sounds good — load in is at 7",
            lastMessageAt: chatReferenceDate.addingTimeInterval(-15 * 60),
            unreadCount: 2
        ),
        Conversation(
            id: directConversationId(performer.id, venues[3].id),
            name: venues[3].displayName,
            memberIds: [performer.id, venues[3].id],
            lastMessageText: "thanks for applying! we'll be in touch",
            lastMessageAt: chatReferenceDate.addingTimeInterval(-26 * 60 * 60),
            unreadCount: 1
        ),
        Conversation(
            id: directConversationId(performer.id, performers[2].id),
            name: performers[2].displayName,
            memberIds: [performer.id, performers[2].id],
            lastMessageText: "down to split the bill at balliceaux?",
            lastMessageAt: chatReferenceDate.addingTimeInterval(-4 * 24 * 60 * 60)
        ),
    ]

    static let conversationMessages: [String: [ConversationMessage]] = {
        func message(_ id: String, _ text: String, from user: UserModel, minutesAgo: Double) -> ConversationMessage {
            ConversationMessage(
                id: id,
                text: text,
                authorId: user.id,
                authorName: user.displayName,
                createdAt: chatReferenceDate.addingTimeInterval(-minutesAgo * 60),
                isFromCurrentUser: user.id == performer.id
            )
        }
        let camel = venues[0]
        let canal = venues[3]
        let mara = performers[2]
        return [
            conversations[0].id: [
                message("m1", "hey! saw your application for friday night openers", from: camel, minutesAgo: 120),
                message("m2", "hi! yes — we'd love to play. we can do a 40 minute set", from: performer, minutesAgo: 110),
                message("m3", "perfect. can you send a rider?", from: camel, minutesAgo: 30),
                message("m4", "sounds good — load in is at 7", from: camel, minutesAgo: 15),
            ],
            conversations[1].id: [
                message("m5", "applied for the late night house residency 🙏", from: performer, minutesAgo: 27 * 60),
                message("m6", "thanks for applying! we'll be in touch", from: canal, minutesAgo: 26 * 60),
            ],
            conversations[2].id: [
                message("m7", "down to split the bill at balliceaux?", from: mara, minutesAgo: 4 * 24 * 60),
            ],
        ]
    }()
}
