import Foundation
import Observation

/// Holds the logged-in user for the whole app.
@Observable
final class SessionStore {
    var currentUser: UserAccount?

    func start(with user: UserAccount) {
        currentUser = user
    }

    func logout() {
        currentUser = nil
    }
}
