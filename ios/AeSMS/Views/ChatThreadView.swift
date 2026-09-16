import SwiftUI

struct ChatThreadView: View {
    @EnvironmentObject var app: AppState
    let username: String

    @State private var confirmClear = false

    private var messages: [LocalMessage] { app.messages(fromUsername: username) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(username)
                    .font(T9Theme.font(28, .bold))
                    .foregroundStyle(T9Theme.ink)
                Text("Swipe a message to delete.")
                    .font(T9Theme.font(14))
                    .foregroundStyle(T9Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(T9Theme.hair).frame(height: T9Theme.stroke)
            }

            HStack {
                Spacer()
                Button("Clear chat") {
                    confirmClear = true
                }
                .font(T9Theme.font(13, .semibold))
                .foregroundStyle(T9Theme.warn)
                .disabled(messages.isEmpty)
                .opacity(messages.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if messages.isEmpty {
                Text("No messages")
                    .font(T9Theme.font(15))
                    .foregroundStyle(T9Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 28)
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(messages) { msg in
                        VStack(alignment: msg.outbound ? .trailing : .leading, spacing: 6) {
                            Text(msg.outbound ? "You" : msg.fromUsername)
                                .font(T9Theme.font(11, .semibold))
                                .foregroundStyle(msg.outbound ? T9Theme.ink : T9Theme.teal)
                            Text(msg.plaintext)
                                .font(T9Theme.font(16))
                                .foregroundStyle(T9Theme.ink)
                                .frame(maxWidth: .infinity, alignment: msg.outbound ? .trailing : .leading)
                                .multilineTextAlignment(msg.outbound ? .trailing : .leading)
                            Text(msg.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(T9Theme.font(11))
                                .foregroundStyle(T9Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: msg.outbound ? .trailing : .leading)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparatorTint(T9Theme.hair.opacity(0.25))
                        .listRowBackground(T9Theme.bg)
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
        .navigationBarTitleDisplayMode(.inline)
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
}
