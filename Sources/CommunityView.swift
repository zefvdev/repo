//
//  CommunityView.swift
//  mSign Community
//
//  Community is exposed from Settings as individual destinations rather than
//  a segmented/table-style community hub.
//

import SwiftUI

// MARK: - Members

struct CommunityMembersScreen: View {
    @ObservedObject private var client = CommunityClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMember: CommunityMember?
    @State private var memberSearch = ""

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            List {
                ForEach(filteredMembers) { member in
                    Button {
                        selectedMember = member
                    } label: {
                        HStack(spacing: 12) {
                            avatar(member.username)

                            VStack(alignment: .leading, spacing: 3) {
                                StyledUsername(name: member.username, style: member.style, base: 17)
                                Text(member.role.uppercased())
                                    .foregroundStyle(Theme.accent)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                if !member.bio.isEmpty {
                                    Text(member.bio)
                                        .foregroundStyle(Theme.subtle)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.subtle)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $memberSearch, prompt: "Find members")
            .refreshable { await client.refresh() }
            .safeAreaInset(edge: .top, spacing: 0) {
                communityHeader(title: "Members", dismiss: dismiss)
            }
        }
        .task { await client.refresh() }
        .sheet(item: $selectedMember) { member in
            MemberProfileView(member: member) { body in
                Task { _ = await client.sendMessage(to: member.username, body: body) }
            }
        }
        .alert("Community", isPresented: Binding(
            get: { client.error != nil },
            set: { if !$0 { client.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(client.error ?? "")
        }
    }

    private var filteredMembers: [CommunityMember] {
        client.members.filter {
            memberSearch.isEmpty || $0.username.localizedCaseInsensitiveContains(memberSearch)
        }
    }

    private func avatar(_ name: String) -> some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 42, height: 42)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.black)
            )
    }
}

// MARK: - Messages

struct CommunityMessagesScreen: View {
    @ObservedObject private var client = CommunityClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedConversation: CommunityConversation?
    @State private var showNewMessage = false
    @State private var showAnnouncements = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            List(client.conversations) { conversation in
                Button {
                    selectedConversation = conversation
                } label: {
                    HStack(spacing: 12) {
                        avatar(conversation.participantUsername)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conversation.participantUsername)
                                    .foregroundStyle(Theme.text)
                                    .font(.headline)

                                if conversation.unreadCount > 0 {
                                    Text("\(conversation.unreadCount)")
                                        .font(.caption2.bold())
                                        .padding(5)
                                        .background(Theme.accent)
                                        .foregroundStyle(.black)
                                        .clipShape(Circle())
                                }
                            }

                            Text(conversation.lastMessage)
                                .foregroundStyle(Theme.subtle)
                                .font(.caption)
                                .lineLimit(2)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.subtle)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await client.refresh() }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    communityHeader(title: "Messages", dismiss: dismiss)
                    HStack(spacing: 8) {
                        Button { showNewMessage = true } label: {
                            Label("New Message", systemImage: "square.and.pencil")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(.black)
                        Button { showAnnouncements = true } label: {
                            Label("Announcements", systemImage: "megaphone.fill")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .background(Theme.bg)
            }
        }
        .task { await client.refresh() }
        .sheet(item: $selectedConversation) { conversation in
            ConversationView(conversation: conversation, client: client)
        }
        .sheet(isPresented: $showNewMessage) {
            NewCommunityMessageView(client: client)
        }
        .sheet(isPresented: $showAnnouncements) {
            CommunityAnnouncementsView(client: client)
        }
        .alert("Community", isPresented: Binding(
            get: { client.error != nil },
            set: { if !$0 { client.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(client.error ?? "")
        }
    }

    private func avatar(_ name: String) -> some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 42, height: 42)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.black)
            )
    }
}

// MARK: - Shared community shell

@ViewBuilder
private func communityHeader(title: String, dismiss: DismissAction) -> some View {
    ZStack {
        HStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(Theme.accent)
            Text("MSIGN COMMUNITY")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .kerning(1)
                .foregroundStyle(Theme.text)
            Spacer()
        }

        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.subtle)

        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.14))
                    .clipShape(Circle())
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .floatingGlassBar(edge: .top)
}

@ViewBuilder
private func communityCard<Content: View>(
    @ViewBuilder _ content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        content()
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card)
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Theme.stroke)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
}

// MARK: - Member profile

struct MemberProfileView: View {
    let member: CommunityMember
    let onMessage: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var friendAdded = false

    private var joinedText: String {
        guard let date = member.joinedAt else { return "Member" }
        return "Joined \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(Theme.accent.opacity(0.18))
                            .frame(width: 94, height: 94)
                            .overlay(Circle().stroke(Theme.accent.opacity(0.55), lineWidth: 2))
                            .overlay(
                                Text(String(member.username.prefix(1)).uppercased())
                                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.accent)
                            )

                        StyledUsername(name: member.username, style: member.style, base: 25)

                        Text(member.role.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(Capsule())

                        if !member.badges.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(member.badges, id: \.self) { badge in
                                    Text(badge.uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.subtle)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Theme.card)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(ProfileBackdrop(style: member.style))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 0) {
                        profileStat("\(member.profileViews)", "Profile views", "eye.fill")
                        Rectangle().fill(Theme.stroke).frame(width: 1, height: 38)
                        profileStat("\(member.friendsCount)", "Friends", "person.2.fill")
                        Rectangle().fill(Theme.stroke).frame(width: 1, height: 38)
                        profileStat("\(member.signsTotal)", "Signs", "checkmark.seal.fill")
                    }
                    .padding(.vertical, 14)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack(spacing: 10) {
                        Button {
                            withAnimation { friendAdded = true }
                            Task {
                                _ = await CommunityClient.shared.addFriend(memberID: member.id)
                            }
                        } label: {
                            Label(
                                friendAdded || member.isFriend ? "Friends" : "Add Friend",
                                systemImage: friendAdded || member.isFriend
                                    ? "person.fill.checkmark"
                                    : "person.badge.plus"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent.opacity(0.14))
                            .foregroundStyle(Theme.accent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Theme.accent.opacity(0.45))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .disabled(friendAdded || member.isFriend)

                        Button {
                            sendMessage()
                        } label: {
                            Label("Message", systemImage: "message.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.accent)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }

                    communityCard {
                        Text("About")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Text(member.bio.isEmpty ? "No bio yet." : member.bio)
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtle)
                        Text(joinedText)
                            .font(.caption)
                            .foregroundStyle(Theme.subtle)
                    }

                    communityCard {
                        Text("Send a message")
                            .font(.headline)
                            .foregroundStyle(Theme.text)

                        TextField("Write a message…", text: $messageText, axis: .vertical)
                            .padding(10)
                            .background(Theme.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button("Send message") {
                            sendMessage()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                .padding(14)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await CommunityClient.shared.recordProfileView(memberID: member.id)
            }
        }
    }

    private func sendMessage() {
        let body = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        messageText = ""
        onMessage(body)
        dismiss()
    }

    private func profileStat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Conversation

struct ConversationView: View {
    let conversation: CommunityConversation
    @ObservedObject var client: CommunityClient
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(client.messages) { message in
                            Text("\(message.senderUsername): \(message.body)")
                                .foregroundStyle(Theme.text)
                                .padding(10)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                }

                HStack {
                    TextField("Message", text: $text)
                        .textFieldStyle(.roundedBorder)

                    Button("Send") {
                        let value = text
                        text = ""
                        Task {
                            _ = await client.sendMessage(
                                to: conversation.participantUsername,
                                body: value
                            )
                            await client.loadMessages(conversationID: conversation.id)
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(conversation.participantUsername)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await client.loadMessages(conversationID: conversation.id)
            }
        }
    }
}

// MARK: - Certificate request

struct CertificateRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var client: CommunityClient

    @State private var type: CertificateRequestType = .development
    @State private var reason = ""
    @State private var udid = ""
    @State private var benefit = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Certificate") {
                    Picker("Type", selection: $type) {
                        ForEach(CertificateRequestType.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }

                    TextField("UDID", text: $udid, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Why do you need a certificate?") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 100)
                }

                Section("How will this benefit mSign?") {
                    TextEditor(text: $benefit)
                        .frame(minHeight: 100)
                }

                Section {
                    Button("Submit request") {
                        Task {
                            if await client.submitCertificateRequest(
                                type: type,
                                reason: reason,
                                udid: udid,
                                benefit: benefit
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        udid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        benefit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                Section {
                    Text("Certificates approved for your MDID are mSign-managed. The private key/P12 and password are not exportable or downloadable; signing consumes them through the service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Request Certificate")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
