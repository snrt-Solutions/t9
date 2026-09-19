import SwiftUI

struct NewChatView: View {
    @EnvironmentObject var app: AppState

    private var sortedContacts: [Contact] {
        app.contacts.sorted {
            $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if sortedContacts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    EmptyStateBlock(
                        title: "No contacts yet",
                        detail: "Pair via QR on the Contacts tab first — there is no server address book."
                    )
                    .padding(.horizontal, T9Theme.pageInset)
                    Spacer(minLength: 0)
                }
            } else {
                List {
                    ForEach(sortedContacts) { contact in
                        NavigationLink {
                            ChatThreadView(username: contact.username)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.username)
                                    .font(T9Theme.font(15, .semibold))
                                    .foregroundStyle(T9Theme.ink)
                                Text("srv \(contact.serverFingerprint)")
                                    .font(T9Theme.font(11))
                                    .foregroundStyle(
                                        contact.serverFingerprint == app.fingerprint
                                        ? T9Theme.teal
                                        : T9Theme.warn
                                    )
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(
                            top: 12,
                            leading: T9Theme.pageInset,
                            bottom: 12,
                            trailing: T9Theme.pageInset
                        ))
                        .listRowSeparatorTint(T9Theme.hair.opacity(0.12))
                        .listRowBackground(T9Theme.bg)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(T9Theme.bg.ignoresSafeArea())
        .navigationTitle("New chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
