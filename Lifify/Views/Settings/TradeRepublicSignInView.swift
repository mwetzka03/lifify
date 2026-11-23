import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The extract file for the system's exporter.
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

/// The Trade Republic sign-in.
struct TradeRepublicSignInControls: View {
    @Environment(\.modelContext) private var context
    var showsSkip: Bool
    var onUploadStatement: (() -> Void)? = nil
    var onSignedIn: (() -> Void)? = nil
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
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @State private var exportingExtract = false
    @State private var extractDocument = TradeRepublicExtractDocument()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            if let onUploadStatement {
                Button(action: onUploadStatement) {
                    TradeRepublicPathRow(
                        variant: TradeRepublicCopy.variantA,
                        title: L("Kontoauszug hochladen", "Upload statement"),
                        systemImage: "doc.badge.plus",
                        hint: TradeRepublicCopy.variantAHint
                    )
                }
                .buttonStyle(.plain)
                Button(action: beginSignIn) {
                    TradeRepublicPathRow(
                        variant: TradeRepublicCopy.variantB,
                        title: TradeRepublicCopy.signIn,
                        systemImage: "person.badge.key.fill",
                        hint: TradeRepublicCopy.variantBHint
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: beginSignIn) {
                    TradeRepublicPathRow(
                        variant: nil,
                        title: TradeRepublicCopy.signIn,
                        systemImage: "person.badge.key.fill",
                        hint: nil
                    )
                }
                .buttonStyle(.plain)
            }
            let _ = sampleRevision
            if developerMode {
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
            if onUploadStatement != nil {
                Text("Trade Republic")
            } else if showsSkip {
                Text(OnboardingSteps.tradeRepublicSignIn)
            }
        } footer: {
            if onUploadStatement != nil {
                Text("\(TradeRepublicCopy.twoUpdatePaths) \(TradeRepublicCopy.footnote)")
            } else {
                Text(TradeRepublicCopy.footnote)
            }
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
        .background {
            LififyFrontOverlayBridge(shown: phase != .idle && !exportingExtract, colorScheme: colorScheme) {
                popup
            }
        }
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
                succeed()
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

    /// A titled field.
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

    /// The popup's buttons.
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

    /// Opens the sign-in.
    private func beginSignIn() {
        hideKeyboard()
        clearSecrets()
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, phase == .idle else { return }
            phase = .credentials
        }
    }

    /// Hides the keyboard.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Starts the sign-in.
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

    /// Runs the sign-in until the app confirms.
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

    /// Waits for the confirmation.
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

    /// Submits a typed code.
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

    /// Loads and applies the depot data.
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
        presentResult()
    }

    /// Shows a failure.
    private func fail(_ failure: TradeRepublicFailure) {
        guard !Task.isCancelled else { return }
        note = failure.message
        phase = .message
        clearSecrets()
    }

    /// Shows the result.
    private func presentResult() {
        if let date = TradeRepublicOpeningBalance.missingDate(context: context) {
            openingDate = date
            openingBalance = ""
            phase = .balance
            return
        }
        succeed()
    }

    /// Finishes successfully.
    private func succeed() {
        advance = true
        if let onSignedIn {
            phase = .idle
            clearSecrets()
            onSignedIn()
        } else {
            phase = .message
        }
    }

    /// Closes and clears the sign-in.
    private func close() {
        task?.cancel()
        client.invalidate()
        let shouldAdvance = advance
        advance = false
        phase = .idle
        clearSecrets()
        if shouldAdvance { onContinue() }
    }

    /// Clears the PIN and code from memory.
    private func clearSecrets() {
        pin = ""
        code = ""
        cookies = ""
        processId = ""
    }

    /// The steps of the sign-in.
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

/// One way to bring in Trade Republic data.
private struct TradeRepublicPathRow: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue
    var variant: String?
    var title: String
    var systemImage: String
    var hint: String?

    var body: some View {
        let accent = AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                if let variant {
                    Text(variant)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .foregroundStyle(.primary)
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// One window for the sign-in popup. A sheet on the Form tries to present more than once.
private struct LififyFrontOverlayBridge<Content: View>: UIViewRepresentable {
    var shown: Bool
    var colorScheme: ColorScheme
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if shown {
            LififyFrontOverlay.show(
                content()
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.locale, AppDate.locale)
                    .appAccentTint(),
                from: uiView
            )
        } else {
            LififyFrontOverlay.hideSoon()
        }
    }
}

/// Shows a view above all sheets.
@MainActor
private enum LififyFrontOverlay {
    private static var generation = 0
    private static var window: UIWindow?
    private static var host: UIHostingController<AnyView>?

    /// Shows the overlay.
    static func show<V: View>(_ view: V, from source: UIView) {
        generation += 1
        let root = AnyView(view)
        if let host {
            host.rootView = root
            window?.isHidden = false
            return
        }
        let scene = source.window?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.host = host
        self.window = window
    }

    /// Hides the overlay shortly.
    static func hideSoon() {
        let current = generation
        DispatchQueue.main.async {
            guard current == generation else { return }
            hide()
        }
    }

    /// Hides the overlay.
    private static func hide() {
        generation += 1
        let closing = window
        window?.isHidden = true
        window = nil
        host = nil
        if let scene = closing?.windowScene {
            scene.windows.first { $0 !== closing && !$0.isHidden }?.makeKey()
        }
        closing?.rootViewController = nil
    }
}

/// Shows and shares the diagnostic extract.
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

    /// Reads an extract from the clipboard.
    @MainActor
    private func paste() async {
        await applyExtract(UIPasteboard.general.string ?? "")
    }

    /// Reads an extract from a file.
    @MainActor
    private func load(from url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        await applyExtract(text)
    }

    /// Applies an extract.
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
