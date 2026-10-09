import Foundation
import Observation

@Observable
final class LoginViewModel {
    /// Password of the demo accounts created by `supabase/seed.sql`.
    static let demoPassword = "Puma2026"

    var email = ""
    var password = ""
    var errorMessage: String?
    private(set) var isLoading = false

    private let store: DataStore
    private let session: SessionStore

    init(store: DataStore, session: SessionStore) {
        self.store = store
        self.session = session
    }

    var canSubmit: Bool {
        !email.trimmed.isEmpty && !password.isEmpty && !isLoading
    }

    /// Signs in with Supabase Auth and downloads the data the user is allowed to see.
    @MainActor
    func login() async {
        let normalizedEmail = email.trimmed.lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Ingresa tu correo y contraseña."
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await store.signIn(email: normalizedEmail, password: password)
            password = ""
            session.start(with: user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
