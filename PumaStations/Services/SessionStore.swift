import Foundation
import Observation

/// Holds the logged-in user for the whole app.
@Observable
final class SessionStore {
    var currentUser: UserAccount?

    @ObservationIgnored private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    func start(with user: UserAccount) {
        currentUser = user
    }

    /// Leaves the app and closes the Supabase session (pending uploads finish first).
    func logout() {
        currentUser = nil
        store.signOut()
    }
}
