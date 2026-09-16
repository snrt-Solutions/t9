import SwiftUI

struct ChatThreadView: View {
    @EnvironmentObject var app: AppState
    let username: String

    @State private var confirmClear = false

    private var messages: [LocalMessage] { app.messages(fromUsername: username) }

    var body: some View {
        Group {
            if messages.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    EmptyStateBlock(
                        title: "No messages",
                        detail: "Nothing stored locally for this chat yet."
                    )
                    .padding(.horizontal, T9Theme.pageInset)
                    Spacer(minLength: 0)
                }
            } else {
                List {
                    ForEach(messages) { msg in
                        messageBubble(msg)
                            .listRowInsets(EdgeInsets(
                                top: 8,
                                leading: T9Theme.pageInset,
                                bottom: 8,
                                trailing: T9Theme.pageInset
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    app.deleteMessage(id: msg.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    app.deleteMessage(id: msg.id)
                                } label: {
                                    Label("Delete message", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(T9Theme.bg.ignoresSafeArea())
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.markChatRead(username: username) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    confirmClear = true
                }
                .font(T9Theme.font(14, .semibold))
                .foregroundStyle(T9Theme.warn)
                .disabled(messages.isEmpty)
                .opacity(messages.isEmpty ? 0.4 : 1)
            }
        }
        .confirmationDialog(
            "Clear chat with \(username)?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear chat", role: .destructive) {
                app.deleteChat(fromUsername: username)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes all local messages in this chat (sent and received).")
        }
    }

    private func messageBubble(_ msg: LocalMessage) -> some View {
        HStack {
            if msg.outbound { Spacer(minLength: 40) }
            VStack(alignment: msg.outbound ? .trailing : .leading, spacing: 6) {
                Text(msg.outbound ? "You" : msg.fromUsername)
                    .font(T9Theme.font(11, .semibold))
                    .foregroundStyle(msg.outbound ? T9Theme.muted : T9Theme.teal)
                Text(msg.plaintext)
                    .font(T9Theme.font(15))
                    .foregroundStyle(T9Theme.ink)
                    .multilineTextAlignment(msg.outbound ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(msg.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(T9Theme.font(11))
                    .foregroundStyle(T9Theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 300, alignment: msg.outbound ? .trailing : .leading)
            .background(msg.outbound ? T9Theme.ink.opacity(0.06) : T9Theme.surface)
            .overlay(
                Rectangle().stroke(
                    T9Theme.hair.opacity(msg.outbound ? 0.18 : 0.4),
                    lineWidth: T9Theme.stroke
                )
            )
            if !msg.outbound { Spacer(minLength: 40) }
        }
    }
}
