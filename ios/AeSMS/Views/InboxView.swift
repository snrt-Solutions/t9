import SwiftUI

struct InboxView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var pendingDeleteChat: ChatSummary?
    @State private var confirmDeleteChat = false

    private var chats: [ChatSummary] { app.chatSummaries() }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if chats.isEmpty {
                    Text("No chats yet")
                        .font(T9Theme.font(15))
                        .foregroundStyle(T9Theme.muted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                } else {
                    List {
                        ForEach(chats) { chat in
                            NavigationLink {
                                ChatThreadView(username: chat.username)
                            } label: {
                                chatRow(chat)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparatorTint(T9Theme.hair.opacity(0.25))
                            .listRowBackground(T9Theme.bg)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeleteChat = chat
                                    confirmDeleteChat = true
                                } label: {
                                    Label("Delete chat", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeleteChat = chat
                                    confirmDeleteChat = true
                                } label: {
                                    Label("Delete chat", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                if !app.statusLine.isEmpty {
                    Text(app.statusLine)
                        .font(T9Theme.font(12))
                        .foregroundStyle(T9Theme.muted)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .background(T9Theme.bg.ignoresSafeArea())
            .confirmationDialog(
                "Delete chat with \(pendingDeleteChat?.username ?? "")?",
                isPresented: $confirmDeleteChat,
                titleVisibility: .visible
            ) {
                Button("Delete chat", role: .destructive) {
                    if let u = pendingDeleteChat?.username {
                        app.deleteChat(fromUsername: u)
                    }
                    pendingDeleteChat = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteChat = nil
                }
            } message: {
                Text("Removes local messages from this sender. Server copies are already gone after fetch.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Chats")
                    .font(T9Theme.font(28, .bold))
                    .foregroundStyle(T9Theme.ink)
                Text("Local copies only. Swipe a chat to clear it.")
                    .font(T9Theme.font(14))
                    .foregroundStyle(T9Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(T9Theme.hair).frame(height: T9Theme.stroke)
            }

            HStack {
                if app.pushOnline {
                    Text("LIVE")
                        .font(T9Theme.font(10, .semibold))
                        .tracking(1.4)
                        .foregroundStyle(T9Theme.teal)
                }
                Spacer()
                PrimaryButton(title: "Fetch", tint: T9Theme.accent, busy: busy) {
                    Task { await fetch() }
                }
                .frame(maxWidth: 160)
            }
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }

    private func chatRow(_ chat: ChatSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(chat.username)
                    .font(T9Theme.font(15, .semibold))
                    .foregroundStyle(T9Theme.teal)
                Spacer(minLength: 8)
                Text("\(chat.count)")
                    .font(T9Theme.font(11, .semibold))
                    .foregroundStyle(T9Theme.muted)
            }
            Text(chat.latest.outbound ? "You: \(chat.latest.plaintext)" : chat.latest.plaintext)
                .font(T9Theme.font(14))
                .foregroundStyle(T9Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fetch() async {
        busy = true
        defer { busy = false }
        await app.fetchInboxQuiet()
        app.statusLine = "fetched"
    }
}
