import SwiftUI

/// Profile screen shared by both roles.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            if let user = session.currentUser {
                Section {
                    HStack(spacing: 14) {
                        InitialsAvatar(initials: user.initials, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.fullName)
                                .font(.headline)
                            Text(user.role.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(user.email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Datos") {
                    LabeledContent("DUI", value: user.dui.isEmpty ? "—" : user.dui)
                    LabeledContent("Teléfono", value: user.phone.isEmpty ? "—" : user.phone)
                    if let branch = user.branch {
                        LabeledContent("Sucursal", value: branch.name)
                        LabeledContent("Bombas", value: "\(branch.pumps.count)")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    session.logout()
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Perfil")
    }
}
