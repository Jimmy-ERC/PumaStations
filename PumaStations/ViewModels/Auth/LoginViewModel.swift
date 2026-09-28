import Foundation
import Observation

@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    var errorMessage: String?

    private let store: DataStore
    private let session: SessionStore

    init(store: DataStore, session: SessionStore) {
        self.store = store
        self.session = session
    }

    var canSubmit: Bool {
        !email.trimmed.isEmpty && !password.isEmpty
    }

    func login() {
        let normalizedEmail = email.trimmed.lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Ingresa tu correo y contraseña."
            return
        }

        let hash = PasswordHasher.hash(password)
        guard let user = store.users().first(where: { $0.email == normalizedEmail && $0.passwordHash == hash }) else {
            errorMessage = "Correo o contraseña incorrectos."
            return
        }
        guard user.isActive else {
            errorMessage = "Tu cuenta está desactivada. Contacta a la gerencia general."
            return
        }

        errorMessage = nil
        password = ""
        session.start(with: user)
    }
}
