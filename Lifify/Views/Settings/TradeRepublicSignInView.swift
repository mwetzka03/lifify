import SwiftData
import SwiftUI
import UIKit

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
    @State private var openingBalance = ""
    @State private var openingDate: Date?
    @State private var client = TradeRepublicClient()
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(TradeRepublicSample.revisionKey) private var sampleRevision = 0

    var body: some View {
        Section {
            LabeledContent(
                "Trade Republic",
                value: sessionSaved ? TradeRepublicCopy.sessionSaved : TradeRepublicCopy.noSession
            )
            Button(sessionSaved ? TradeRepublicCopy.signInAgain : TradeRepublicCopy.signIn) {
                clearSecrets()
                phase = .credentials
            }
            Button(TradeRepublicCopy.refresh) { refresh() }
                .disabled(!sessionSaved || phase == .loading)
            if developerMode, sampleRevision > 0, !TradeRepublicSample.text.isEmpty {
                NavigationLink {
                    TradeRepublicSampleView()
                } label: {
                    Label(TradeRepublicCopy.sample, systemImage: "doc.on.doc")
                }
            }
            if let note, phase == .idle {
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
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(popupTitle)
                    .font(.headline)
                popupBody
            }
            .padding(20)
            .frame(maxWidth: 360)
            .appGlassCard(radius: 22)
            .padding(28)
        }
        .appAccentTint()
    }

    private var popupTitle: String {
        switch phase {
        case .credentials, .waiting, .loading, .balance, .message: TradeRepublicCopy.signIn
        case .code: TradeRepublicCopy.codePrompt
        case .idle: ""
        }
    }

    @ViewBuilder
    private var popupBody: some View {
        switch phase {
        case .credentials:
            field(TradeRepublicCopy.phone) {
                TextField(TradeRepublicCopy.phone, text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field(TradeRepublicCopy.pin) {
                SecureField(TradeRepublicCopy.pin, text: $pin)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            popupActions(
                confirm: TradeRepublicCopy.signIn,
                enabled: !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !pin.isEmpty
            ) {
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
            field(TradeRepublicCopy.codePrompt) {
                SecureField(TradeRepublicCopy.codePrompt, text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
            }
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
        case .balance:
            if let openingDate {
                Text(TradeRepublicCopy.balancePrompt(AppDate.numeric(openingDate)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            field(L("Kontostand", "Account balance")) {
                TextField(L("Kontostand", "Account balance"), text: $openingBalance)
                    .keyboardType(.decimalPad)
            }
            popupActions(
                confirm: TradeRepublicCopy.balanceSave,
                enabled: Money.cents(from: openingBalance) != nil
            ) {
                if let cents = Money.cents(from: openingBalance) {
                    TradeRepublicOpeningBalance.store(cents, context: context)
                }
                phase = .message
            }
        case .message:
            if let note {
                Text(note)
                    .font(.subheadline)
            }
            HStack {
                Spacer()
                Button(TradeRepublicCopy.close, action: close)
                    .buttonStyle(.borderedProminent)
            }
        case .idle:
            EmptyView()
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .appTintedPlate(radius: 14)
    }

    private func popupActions(confirm: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Button(TradeRepublicCopy.cancel, action: close)
                .foregroundStyle(.secondary)
            Spacer()
            Button(confirm, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(!enabled)
        }
    }

    private func start() {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = pin
        self.pin = ""
        phase = .waiting
        task?.cancel()
        client.invalidate()
        let fresh = TradeRepublicClient()
        client = fresh
        task = Task { await run(client: fresh, phone: phone, pin: pin) }
    }

    private func run(client: TradeRepublicClient, phone: String, pin: String) async {
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
        let current = client
        task?.cancel()
        task = Task {
            do {
                cookies = try await current.submit(code: entered, processId: processId, cookies: cookies)
                try await poll(current)
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
        guard TradeRepublicCookies.keepsSession(header) else { throw TradeRepublicFailure.sessionNotKept }
        client.invalidate()
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
        presentResult()
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
            presentResult()
        }
    }

    private func fail(_ failure: TradeRepublicFailure) {
        guard !Task.isCancelled else { return }
        note = failure.message
        phase = .message
        clearSecrets()
    }

    private func presentResult() {
        if let date = TradeRepublicOpeningBalance.missingDate(context: context) {
            openingDate = date
            openingBalance = ""
            phase = .balance
            return
        }
        phase = .message
    }

    private func close() {
        task?.cancel()
        client.invalidate()
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
        case credentials
        case waiting
        case code
        case loading
        case balance
        case message
    }
}

struct TradeRepublicSampleView: View {
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(TradeRepublicCopy.sampleNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(TradeRepublicSample.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .appGlassList()
        .navigationTitle(TradeRepublicCopy.sample)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(copied ? TradeRepublicCopy.copied : TradeRepublicCopy.sample) {
                    UIPasteboard.general.string = TradeRepublicSample.text
                    copied = true
                }
            }
        }
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
