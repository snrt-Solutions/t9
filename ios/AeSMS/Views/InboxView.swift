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

                if chats.isEmpty {
                    EmptyStateBlock(
                        title: "No chats yet",
                        detail: "Fetch sealed messages, or start a new chat with a QR contact."
                    )
                    .padding(.horizontal, T9Theme.pageInset)
                    Spacer(minLength: 0)
                } else {
                    List {
                        ForEach(chats) { chat in
                            NavigationLink {
                                ChatThreadView(username: chat.username)
                            } label: {
                                chatRow(chat)
                            }
                            .listRowInsets(EdgeInsets(
                                top: 14,
                                leading: T9Theme.pageInset,
                                bottom: 14,
                                trailing: T9Theme.pageInset
                            ))
                            .listRowSeparatorTint(T9Theme.hair.opacity(0.12))
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
                        .padding(.horizontal, T9Theme.pageInset)
                        .padding(.vertical, 10)
                }
            }
            .background(T9Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await fetch() }
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text("Fetch")
                                .font(T9Theme.font(14, .semibold))
                        }
                    }
                    .tint(T9Theme.accent)
                    .disabled(busy)
                    .accessibilityLabel("Fetch inbox")

                    NavigationLink {
                        NewChatView()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(T9Theme.accent)
                    .accessibilityLabel("New chat")
                }
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Chats")
                    .font(T9Theme.font(26, .bold))
                    .foregroundStyle(T9Theme.ink)
                Spacer(minLength: 8)
                if app.pushOnline {
                    StatusBadge(text: "Live", tone: T9Theme.teal)
                }
            }
            Text("Local copies only. Swipe a chat to clear it.")
                .font(T9Theme.font(14))
                .foregroundStyle(T9Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T9Theme.pageInset)
        .padding(.top, T9Theme.space1)
        .padding(.bottom, T9Theme.space2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(T9Theme.hair.opacity(0.35))
                .frame(height: T9Theme.rule)
        }
    }

    private func chatRow(_ chat: ChatSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.username)
                        .font(T9Theme.font(15, .semibold))
                        .foregroundStyle(T9Theme.teal)
                    Spacer(minLength: 8)
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(T9Theme.font(11, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(T9Theme.accent)
                    } else {
                        Text("\(chat.count)")
                            .font(T9Theme.font(12, .medium))
                            .foregroundStyle(T9Theme.muted)
                    }
                }
                Text(chat.latest.outbound ? "You: \(chat.latest.plaintext)" : chat.latest.plaintext)
                    .font(T9Theme.font(14, chat.unreadCount > 0 ? .semibold : .regular))
                    .foregroundStyle(T9Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func fetch() async {
        busy = true
        defer { busy = false }
        let n = await app.fetchInboxQuiet()
        app.statusLine = n > 0 ? (n == 1 ? "1 new message" : "\(n) new messages") : "fetched"
    }
}
