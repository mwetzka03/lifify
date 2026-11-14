import SwiftData
import SwiftUI

struct TradeRepublicSignInControls: View {
    @Environment(\.modelContext) private var context
    var showsSkip: Bool
    var onContinue: () -> Void

    @State private var phone = ""
    @State private var pin = ""
    @State private var code = ""
    @State private var phase: Phase = .idle
    @State private var note: String?
    @State private var sessionSaved = false
    @State private var processId = ""
    @State private var cookies = ""
    @State private var deadline = Date()
    @State private var task: Task<Void, Never>?
    @State private var advance = false

    var body: some View {
        Section {
            LabeledContent(
                "Trade Republic",
                value: sessionSaved ? TradeRepublicCopy.sessionSaved : TradeRepublicCopy.noSession
            )
            Button(sessionSaved ? TradeRepublicCopy.signInAgain : TradeRepublicCopy.signIn) {
                clearSecrets()
                phase = .phone
            }
            Button(TradeRepublicCopy.refresh) { refresh() }
                .disabled(!sessionSaved || phase == .loading)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsSkip {
                Button(TradeRepublicCopy.skip, action: onContinue)
            }
        } header: {
            if showsSkip {
                Text(OnboardingSteps.tradeRepublicSignIn)
            }
        } footer: {
            Text(TradeRepublicCopy.footnote)
        }
        .appGlassRow()
        .onAppear { sessionSaved = TradeRepublicSessionStore.hasSession }
        .fullScreenCover(isPresented: coverShown) {
            popup
                .presentationBackground(.clear)
                .interactiveDismissDisabled(phase == .waiting || phase == .loading)
        }
    }

    private var coverShown: Binding<Bool> {
        Binding(
            get: { phase != .idle },
            set: { shown in
                if !shown, phase != .waiting, phase != .loading { close() }
            }
        )
    }

    private var popup: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(popupTitle)
                    .font(.headline)
                popupBody
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(28)
        }
    }

    private var popupTitle: String {
        switch phase {
        case .phone: TradeRepublicCopy.phone
        case .pin: TradeRepublicCopy.pin
        case .waiting: TradeRepublicCopy.signIn
        case .code: TradeRepublicCopy.codePrompt
        case .loading: "Trade Republic"
        case .message: TradeRepublicCopy.signIn
        case .idle: ""
        }
    }

    @ViewBuilder
    private var popupBody: some View {
        switch phase {
        case .phone:
            TextField(TradeRepublicCopy.phone, text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            popupActions(
                confirm: TradeRepublicCopy.next,
                enabled: !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                phase = .pin
            }
        case .pin:
            SecureField(TradeRepublicCopy.pin, text: $pin)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            popupActions(confirm: TradeRepublicCopy.signIn, enabled: !pin.isEmpty) {
                start()
            }
        case .waiting:
            ProgressView()
                .frame(maxWidth: .infinity)
            Text(TradeRepublicCopy.waiting)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(TradeRepublicCopy.cancel, action: close)
        case .code:
            SecureField(TradeRepublicCopy.codePrompt, text: $code)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
            popupActions(
                confirm: TradeRepublicCopy.confirmCode,
                enabled: !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                submitCode()
            }
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
            Text(TradeRepublicCopy.loading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .message:
            if let note {
                Text(note)
                    .font(.subheadline)
            }
            Button(TradeRepublicCopy.close, action: close)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .idle:
            EmptyView()
        }
    }

    private func popupActions(confirm: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Button(TradeRepublicCopy.cancel, action: close)
            Spacer()
            Button(confirm, action: action)
                .disabled(!enabled)
        }
    }

    private func start() {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = pin
        self.pin = ""
        phase = .waiting
        task?.cancel()
        task = Task { await run(phone: phone, pin: pin) }
    }

    private func run(phone: String, pin: String) async {
        let client = TradeRepublicClient()
        do {
            let challenge = try await client.begin(phone: phone, pin: pin)
            processId = challenge.processId
            cookies = challenge.cookies
            deadline = Date().addingTimeInterval(TimeInterval(max(challenge.countdownSeconds, 30)))
            try await poll(client)
        } catch is CancellationError {
            return
        } catch let failure as TradeRepublicFailure {
            fail(failure)
        } catch {
            fail(.transport)
        }
    }

    private func poll(_ client: TradeRepublicClient) async throws {
        while !Task.isCancelled, Date() < deadline {
            let step = try await client.poll(processId: processId, cookies: cookies)
            cookies = step.cookies
            if step.needsCode {
                phase = .code
                return
            }
            if step.confirmed {
                try await finish(step.cookies)
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
        if !Task.isCancelled { fail(.notConfirmed) }
    }

    private func submitCode() {
        let entered = code
        code = ""
        phase = .waiting
        let client = TradeRepublicClient()
        task?.cancel()
        task = Task {
            do {
                cookies = try await client.submit(code: entered, processId: processId, cookies: cookies)
                try await poll(client)
            } catch is CancellationError {
                return
            } catch let failure as TradeRepublicFailure {
                fail(failure)
            } catch {
                fail(.transport)
            }
        }
    }

    private func finish(_ header: String) async throws {
        guard TradeRepublicCookies.keepsSession(header) else { throw TradeRepublicFailure.unreadable }
        TradeRepublicSessionStore.save(header)
        cookies = ""
        phase = .loading
        let snapshot = try await TradeRepublicClient().snapshot(cookies: header)
        let count = try await TradeRepublicDepotApplier.apply(snapshot: snapshot, context: context)
        sessionSaved = true
        note = snapshot.positions.isEmpty && count == 0
            ? TradeRepublicCopy.noPositions
            : String(format: TradeRepublicCopy.importedFormat, count)
        advance = true
        phase = .message
    }

    private func refresh() {
        guard phase != .loading else { return }
        phase = .loading
        task?.cancel()
        task = Task {
            let text = await TradeRepublicActions.refresh(context: context)
            guard !Task.isCancelled else { return }
            note = text
            sessionSaved = TradeRepublicSessionStore.hasSession
            phase = .message
        }
    }

    private func fail(_ failure: TradeRepublicFailure) {
        guard !Task.isCancelled else { return }
        note = failure.message
        phase = .message
        clearSecrets()
    }

    private func close() {
        task?.cancel()
        let shouldAdvance = advance
        advance = false
        phase = .idle
        clearSecrets()
        if shouldAdvance { onContinue() }
    }

    private func clearSecrets() {
        pin = ""
        code = ""
        cookies = ""
        processId = ""
    }

    private enum Phase {
        case idle
        case phone
        case pin
        case waiting
        case code
        case loading
        case message
    }
}

@MainActor
enum TradeRepublicActions {
    static func refresh(context: ModelContext) async -> String {
        guard TradeRepublicRefresh.manualOnly, !TradeRepublicRefresh.onLaunch, !TradeRepublicRefresh.onTimer, !TradeRepublicRefresh.onFinanceOpen else {
            return TradeRepublicCopy.footnote
        }
        guard !TradeRepublicRefresh.usesStoredPIN else { return TradeRepublicCopy.footnote }
        guard let cookies = TradeRepublicSessionStore.cookies(), TradeRepublicCookies.keepsSession(cookies) else {
            return TradeRepublicCopy.noSession
        }
        do {
            let snapshot = try await TradeRepublicClient().snapshot(cookies: cookies)
            let count = try await TradeRepublicDepotApplier.apply(snapshot: snapshot, context: context)
            if snapshot.positions.isEmpty && count == 0 { return TradeRepublicCopy.noPositions }
            return String(format: TradeRepublicCopy.importedFormat, count)
        } catch let failure as TradeRepublicFailure {
            if failure == .sessionDead { TradeRepublicSessionStore.clear() }
            return failure.message
        } catch {
            return TradeRepublicFailure.transport.message
        }
    }
}
