import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    init(store: DataStore, session: SessionStore) {
        _viewModel = State(initialValue: LoginViewModel(store: store, session: session))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                    .padding(.top, 56)

                VStack(alignment: .leading, spacing: 14) {
                    LabeledInput(title: "Correo electrónico", systemImage: "envelope") {
                        TextField("correo@puma.sv", text: $viewModel.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }

                    LabeledInput(title: "Contraseña", systemImage: "lock") {
                        SecureField("Contraseña", text: $viewModel.password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.brandRed)
                    }
                }

                Button {
                    submit()
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Iniciar sesión")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSubmit)

                demoAccounts
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.screenBackground)
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.login() }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image("PumaLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 64)
            VStack(spacing: 6) {
                Text("Control de estaciones")
                    .font(.title.bold())
                Text("Inicia sesión con tu cuenta asignada")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var demoAccounts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cuentas de prueba (contraseña: \(LoginViewModel.demoPassword))")
                .font(.footnote.weight(.semibold))
            Text("Gerente general: gerente@puma.sv")
            Text("Gerente de sucursal: rmartinez@puma.sv")
            Text("Empleado: mrivas@puma.sv")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Text input with a caption above and an icon inside.
struct LabeledInput<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                content
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
        }
    }
}
