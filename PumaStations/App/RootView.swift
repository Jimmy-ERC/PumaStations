import SwiftUI
import SwiftData

/// Decides which experience to show based on the logged-in user's role.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DataStore.self) private var store

    var body: some View {
        Group {
            if let user = session.currentUser {
                switch user.role {
                case .generalManager:
                    GeneralTabView()
                case .branchManager:
                    BranchTabView(user: user)
                case .employee:
                    EmployeeTabView(user: user)
                }
            } else {
                LoginView(store: store, session: session)
            }
        }
        .animation(.default, value: session.currentUser?.persistentModelID)
        .alert("No se pudo sincronizar", isPresented: syncErrorBinding) {
            Button("Reintentar") { store.retrySync() }
            Button("Cerrar sesión", role: .destructive) { session.logout() }
        } message: {
            Text(store.syncErrorMessage ?? "")
        }
    }

    /// Shown while an upload to Supabase is stuck on an error.
    private var syncErrorBinding: Binding<Bool> {
        Binding(
            get: { session.currentUser != nil && store.syncErrorMessage != nil },
            set: { _ in }
        )
    }
}
