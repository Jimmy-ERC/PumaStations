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
                }
            } else {
                LoginView(store: store, session: session)
            }
        }
        .animation(.default, value: session.currentUser?.persistentModelID)
    }
}
