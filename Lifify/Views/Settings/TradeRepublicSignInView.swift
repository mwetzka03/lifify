import SwiftData
import SwiftUI

struct TradeRepublicSignInControls: View {
    @Environment(\.modelContext) private var context
    var showsSkip: Bool
    var title: String = OnboardingSteps.tradeRepublicSignIn
    var onContinue: () -> Void

    @State private var phone = ""
    @State private var pin = ""
    @State private var code = ""
    @State private var phase: Phase = .form
    @State private var note: String?
    @State private var processId = ""
    @State private var cookies = ""
    @State private var deadline = Date()
    @State private var task: Task<Void, Never>?

    var body: some View {
        Section {
            if phase == .done {
                if let note {
                    Text(note)
                        .foregroundStyle(.green)
                }
                Button(L("Weiter", "Continue"), action: onContinue)
            } else if phase == .code {
                SecureField(TradeRepublicCopy.codePrompt, text: $code)
                    .textContentType(.oneTimeCode)
                Button(TradeRepublicCopy.confirmCode) { submitCode() }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(TradeRepublicCopy.cancel, action: reset)
            } else if phase == .waiting {
                ProgressView(TradeRepublicCopy.waiting)
                Button(TradeRepublicCopy.cancel, action: reset)
            } else {
                TextField(TradeRepublicCopy.phone, text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(TradeRepublicCopy.pin, text: $pin)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(TradeRepublicCopy.signIn, action: start)
                    .disabled(phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pin.isEmpty)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showsSkip {
                    Button(TradeRepublicCopy.skip, action: onContinue)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(TradeRepublicCopy.footnote)
        }
        .appGlassRow()
        .onDisappear(perform: clearSecrets)
    }

    private func start() {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = pin
        self.pin = ""
        note = TradeRepublicCopy.waiting
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
                note = TradeRepublicCopy.codePrompt
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
        note = TradeRepublicCopy.waiting
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
        do {
            let positions = try await TradeRepublicClient().positions(cookies: header)
            let count = try TradeRepublicDepotApplier.apply(positions: positions, context: context)
            note = positions.isEmpty
                ? TradeRepublicCopy.noPositions
                : String(format: TradeRepublicCopy.importedFormat, count)
            phase = .done
        } catch let failure as TradeRepublicFailure {
            if failure == .sessionDead { TradeRepublicSessionStore.clear() }
            throw failure
        }
    }

    private func fail(_ failure: TradeRepublicFailure) {
        note = failure.message
        phase = .form
        clearSecrets()
    }

    private func reset() {
        task?.cancel()
        note = nil
        phase = .form
        clearSecrets()
    }

    private func clearSecrets() {
        pin = ""
        code = ""
        cookies = ""
        processId = ""
    }

    private enum Phase {
        case form
        case waiting
        case code
        case done
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
            let positions = try await TradeRepublicClient().positions(cookies: cookies)
            let count = try TradeRepublicDepotApplier.apply(positions: positions, context: context)
            if positions.isEmpty { return TradeRepublicCopy.noPositions }
            return String(format: TradeRepublicCopy.importedFormat, count)
        } catch let failure as TradeRepublicFailure {
            if failure == .sessionDead { TradeRepublicSessionStore.clear() }
            return failure.message
        } catch {
            return TradeRepublicFailure.transport.message
        }
    }
}
