import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TradeRepublicExtractDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TradeRepublicSignInControls: View {
    @Environment(\.modelContext) private var context
    var showsSkip: Bool
    var onContinue: () -> Void

    @State private var phone = ""
    @State private var pin = ""
    @State private var code = ""
    @State private var phase: Phase = .idle
    @State private var note: String?
    @State private var processId = ""
    @State private var cookies = ""
    @State private var deadline = Date()
    @State private var task: Task<Void, Never>?
    @State private var advance = false
    @State private var openingBalance = ""
    @State private var openingDate: Date?
    @State private var client = TradeRepublicClient()
    @AppStorage(TradeRepublicSample.revisionKey) private var sampleRevision = 0
    @State private var exportingExtract = false
    @State private var extractDocument = TradeRepublicExtractDocument()

    var body: some View {
        Section {
            Button(TradeRepublicCopy.signIn) {
                hideKeyboard()
                clearSecrets()
                phase = .credentials
            }
            let _ = sampleRevision
            Button {
                guard phase == .idle, !exportingExtract else { return }
                hideKeyboard()
                extractDocument = TradeRepublicExtractDocument(data: TradeRepublicSample.exportData())
                exportingExtract = true
            } label: {
                Label(TradeRepublicCopy.saveExtract, systemImage: "square.and.arrow.down")
            }
            .disabled(!TradeRepublicSample.hasContent || phase != .idle)
            NavigationLink {
                TradeRepublicSampleView()
            } label: {
                Label(TradeRepublicCopy.extract, systemImage: "doc.on.doc")
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
        .onAppear {
            TradeRepublicSessionStore.clear()
            TradeRepublicSample.purgeLegacyPreferences()
        }
        .fileExporter(
            isPresented: $exportingExtract,
            document: extractDocument,
            contentType: .plainText,
            defaultFilename: TradeRepublicSample.exportFilename
        ) { _ in }
        .fullScreenCover(isPresented: coverShown) {
            popup
                .presentationBackground(.clear)
                .interactiveDismissDisabled(phase == .waiting || phase == .loading)
        }
    }

    private var coverShown: Binding<Bool> {
        Binding(
            get: { phase != .idle && !exportingExtract },
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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func start() {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = pin
        self.pin = ""
        hideKeyboard()
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
        hideKeyboard()
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
        cookies = ""
        phase = .loading
        let snapshot = try await TradeRepublicClient().snapshot(cookies: header)
        TradeRepublicSessionStore.clear()
        let count = try await TradeRepublicDepotApplier.apply(snapshot: snapshot, context: context)
        note = snapshot.positions.isEmpty && count == 0
            ? TradeRepublicCopy.noPositions
            : String(format: TradeRepublicCopy.importedFormat, count)
        advance = true
        presentResult()
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
    @Environment(\.modelContext) private var context
    @AppStorage(TradeRepublicSample.revisionKey) private var sampleRevision = 0
    @State private var note: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument = TradeRepublicExtractDocument()

    var body: some View {
        let _ = sampleRevision
        Form {
            Section {
                Button {
                    guard !exporting, !importing else { return }
                    exportDocument = TradeRepublicExtractDocument(data: TradeRepublicSample.exportData())
                    exporting = true
                } label: {
                    Label(TradeRepublicCopy.saveExtract, systemImage: "square.and.arrow.down")
                }
                .disabled(!TradeRepublicSample.hasContent || exporting || importing)
                Button {
                    guard !exporting, !importing else { return }
                    importing = true
                } label: {
                    Label(TradeRepublicCopy.loadExtract, systemImage: "square.and.arrow.up")
                }
                .disabled(exporting || importing)
                Button {
                    guard !exporting, !importing else { return }
                    Task { await paste() }
                } label: {
                    Label(TradeRepublicCopy.pasteExtract, systemImage: "doc.on.clipboard")
                }
                .disabled(exporting || importing)
            } footer: {
                Text(TradeRepublicCopy.sampleNote)
            }
            .appGlassRow()
            Section {
                if TradeRepublicSample.hasContent {
                    Text(TradeRepublicCopy.extractReady(TradeRepublicSample.byteCount))
                        .font(.footnote)
                    Text(TradeRepublicSample.preview())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(12)
                } else {
                    Text(TradeRepublicCopy.emptyExtract)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                }
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(TradeRepublicCopy.extract)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            TradeRepublicSample.purgeLegacyPreferences()
            TradeRepublicSample.finish()
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: TradeRepublicSample.exportFilename
        ) { _ in }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await load(from: url) }
            }
        }
    }

    @MainActor
    private func paste() async {
        await applyExtract(UIPasteboard.general.string ?? "")
    }

    @MainActor
    private func load(from url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        await applyExtract(text)
    }

    @MainActor
    private func applyExtract(_ text: String) async {
        if TradeRepublicCopy.looksLikeBackup(text) {
            note = TradeRepublicCopy.pasteWasBackup
            return
        }
        guard let snapshot = TradeRepublicSample.snapshot(from: text) else {
            note = TradeRepublicCopy.pasteFailed
            return
        }
        TradeRepublicSample.replaceWithImported(text)
        do {
            let count = try await TradeRepublicDepotApplier.apply(snapshot: snapshot, context: context)
            note = TradeRepublicCopy.appliedExtract(count)
        } catch {
            note = error.localizedDescription
        }
    }
}
