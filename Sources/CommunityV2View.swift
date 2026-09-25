import SwiftUI

struct NewCommunityMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var client: CommunityClient
    @State private var username = ""
    @State private var messageBody = ""
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Message") {
                    TextEditor(text: $messageBody).frame(minHeight: 150)
                }
                Section {
                    Button {
                        Task {
                            sending = true
                            sent = await client.sendNewMessage(to: username, body: messageBody)
                            sending = false
                            if sent { dismiss() }
                        }
                    } label: {
                        HStack {
                            if sending { ProgressView().tint(.black) }
                            Text("Send Message")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(sending || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct CommunityAnnouncementsView: View {
    @ObservedObject var client: CommunityClient
    @Environment(\.dismiss) private var dismiss
    @State private var compose = false

    var body: some View {
        NavigationStack {
            List(client.announcements) { item in
                Button {
                    Task { await client.markAnnouncementRead(id: item.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(item.title).font(.headline).foregroundStyle(Theme.text)
                            Spacer()
                            if !item.read {
                                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            }
                        }
                        Text(item.body).font(.subheadline).foregroundStyle(Theme.subtle).lineLimit(5)
                        HStack {
                            Text(item.senderUsername).foregroundStyle(Theme.accent)
                            Text("•")
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(item.audience.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.subtle)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Announcements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if StaffGate.shared.role >= .developer {
                    ToolbarItem(placement: .primaryAction) { Button { compose = true } label: { Image(systemName: "plus") } }
                }
            }
            .task { await client.refresh() }
            .sheet(isPresented: $compose) { StaffAnnouncementComposer(client: client) }
        }
    }
}

struct StaffAnnouncementComposer: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var client: CommunityClient
    @State private var title = ""
    @State private var announcementBody = ""
    @State private var audience: AnnouncementAudience = .everyone
    @State private var target = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Announcement") {
                    TextField("Title", text: $title)
                    TextEditor(text: $announcementBody).frame(minHeight: 150)
                }
                Section("Audience") {
                    Picker("Send to", selection: $audience) {
                        ForEach(AnnouncementAudience.allCases) { Text($0.title).tag($0) }
                    }
                    if audience == .individual {
                        TextField("Username", text: $target)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Button {
                        Task {
                            sending = true
                            if await client.sendAnnouncement(title: title, body: announcementBody, audience: audience, target: audience == .individual ? target : nil) {
                                dismiss()
                            }
                            sending = false
                        }
                    } label: {
                        HStack {
                            if sending { ProgressView().tint(.black) }
                            Text("Publish Announcement")
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(sending || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || announcementBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (audience == .individual && target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .navigationTitle("New Announcement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct StaffCommunityView: View {
    @ObservedObject private var client = CommunityClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAnnouncements = false

    var body: some View {
        NavigationStack {
            List {
                Section("Staff") {
                    NavigationLink("Staff Messages", destination: StaffMessagesView(client: client))
                    Button("Announcements") { showAnnouncements = true }
                    NavigationLink("Audit Log", destination: CommunityAuditView(client: client))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Staff Community")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAnnouncements) { CommunityAnnouncementsView(client: client) }
        }
        .roleGated(.developer)
    }
}

struct StaffMessagesView: View {
    @ObservedObject var client: CommunityClient
    @State private var compose = false

    var body: some View {
        List(client.conversations) { conversation in
            NavigationLink(destination: ConversationView(conversation: conversation, client: client)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.participantUsername).font(.headline)
                        Spacer()
                        if conversation.unreadCount > 0 { Text("\(conversation.unreadCount)").font(.caption2.bold()) }
                    }
                    Text(conversation.lastMessage).font(.caption).foregroundStyle(Theme.subtle).lineLimit(2)
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Staff Messages")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { compose = true } label: { Image(systemName: "square.and.pencil") } } }
        .sheet(isPresented: $compose) { NewCommunityMessageView(client: client) }
        .task { await client.refresh() }
    }
}

struct CommunityAuditView: View {
    @ObservedObject var client: CommunityClient
    var body: some View {
        List(client.auditEvents) { event in
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(event.action).font(.headline); Spacer(); Text(event.actorRole.uppercased()).font(.caption2.bold()) }
                Text("\(event.actorUsername) → \(event.target)").font(.caption).foregroundStyle(Theme.accent)
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.subtle)
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Audit Log")
        .task { await client.loadAudit() }
    }
}
