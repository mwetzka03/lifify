import SwiftUI
import UIKit

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStore
    let plan: WorkoutPlan
    @State private var draft: WorkoutSession
    @State private var weightText: [UUID: String]
    @State private var repsText: [UUID: String]
    @State private var restEndsAt: Date?
    @State private var restTotal = 0
    @State private var restSetID: UUID?
    @State private var restToken = UUID()
    @State private var showDiscard = false
    @State private var didApplyFrequent = false
    @State private var finishSummary: WorkoutFinishSummary?

    init(plan: WorkoutPlan) {
        self.plan = plan
        let session = WorkoutSession(plan: plan)
        _draft = State(initialValue: session)
        var weights: [UUID: String] = [:]
        var reps: [UUID: String] = [:]
        for exercise in session.exercises {
            for set in exercise.sets {
                weights[set.id] = WorkoutFormat.weight(set.weightKg)
                reps[set.id] = String(set.reps)
            }
        }
        _weightText = State(initialValue: weights)
        _repsText = State(initialValue: reps)
    }

    var body: some View {
        List {
            Section {
                Text(plan.name)
                    .font(.largeTitle.bold())
                    .listRowBackground(Color.clear)
            }
            if draft.exercises.isEmpty {
                ContentUnavailableView(
                    L("Keine Übungen", "No exercises"),
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text(L("Füge der Routine zuerst Übungen hinzu.", "Add exercises to the routine first."))
                )
            }
            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                Section {
                    exerciseHeader(exercise)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteExercise(exercise.id)
                            } label: {
                                Label(L("Übung löschen", "Delete exercise"), systemImage: "trash")
                            }
                        }
                    if WorkoutProgress.readyToProgress(
                        sessions: store.sessions,
                        planID: plan.id,
                        exerciseCode: exercise.code
                    ) {
                        suggestion(index: index, exercise: exercise)
                    }
                    columnHeader
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                        setRow(exerciseIndex: index, exercise: exercise, setIndex: setIndex, set: set)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteSet(exerciseID: exercise.id, setID: set.id)
                                } label: {
                                    Label(L("Satz löschen", "Delete set"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .appCanvas()
        .navigationTitle(L("Training", "Workout"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background {
            WorkoutSwipeBackLock()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            guard !didApplyFrequent else { return }
            didApplyFrequent = true
            applyFrequentWeights()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { requestClose() } label: { Image(systemName: "xmark") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Fertig", "Done")) { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasCompletedSet)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Fertig", "Done")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .confirmationDialog(
            L("Training verwerfen?", "Discard workout?"),
            isPresented: $showDiscard,
            titleVisibility: .visible
        ) {
            Button(L("Verwerfen", "Discard"), role: .destructive) { dismiss() }
            Button(L("Weiter trainieren", "Keep training"), role: .cancel) {}
        }
        .task(id: restToken) {
            await chimeWhenRestEnds()
        }
        .sheet(item: $finishSummary, onDismiss: { dismiss() }) { summary in
            WorkoutFinishSheet(summary: summary)
        }
    }

    private var hasCompletedSet: Bool {
        draft.exercises.contains { exercise in exercise.sets.contains(where: \.completed) }
    }

    private func exerciseHeader(_ exercise: WorkoutSessionExercise) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ExerciseArtwork(code: exercise.code, name: exercise.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                Text("\(L("Pause", "Rest")) \(WorkoutFormat.rest(exercise.restSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
    }

    private func suggestion(index: Int, exercise: WorkoutSessionExercise) -> some View {
        let baseWeight = exercise.sets.first?.targetWeightKg ?? 0
        let baseReps = exercise.sets.first?.targetReps ?? 0
        let nextWeight = WorkoutFormat.rounded(baseWeight + 2.5)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L(
                "Drei Trainings in Folge geschafft. Steigere Gewicht oder Wiederholungen.",
                "You hit the plan three workouts in a row. Add weight or reps."
            ))
            .font(.subheadline)
            HStack(spacing: 8) {
                Button("\(WorkoutFormat.weight(nextWeight)) kg") {
                    applyWeight(nextWeight, exerciseIndex: index)
                }
                .buttonStyle(.bordered)
                Button("\(baseReps + 1) \(L("Wdh.", "reps"))") {
                    applyReps(baseReps + 1, exerciseIndex: index)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text(L("Satz", "Set")).frame(width: 36, alignment: .leading)
            Text(L("Vorherige", "Previous")).frame(maxWidth: .infinity, alignment: .leading)
            Text("kg").frame(width: 64)
            Text(L("Wdh.", "Reps")).frame(width: 52)
            Image(systemName: "checkmark").frame(width: 32)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func setRow(
        exerciseIndex: Int,
        exercise: WorkoutSessionExercise,
        setIndex: Int,
        set: WorkoutSessionSet
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("\(setIndex + 1)")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(AppSurface.canvas, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    if let previous = WorkoutProgress.previousPerformance(
                        sessions: store.sessions,
                        exerciseCode: exercise.code,
                        setIndex: setIndex
                    ) {
                        Text(WorkoutFormat.previous(weight: previous.weight, reps: previous.reps))
                    } else {
                        Text("–").foregroundStyle(.tertiary)
                    }
                    if let frequent = WorkoutProgress.frequentWeight(
                        sessions: store.sessions,
                        exerciseCode: exercise.code,
                        setIndex: setIndex
                    ) {
                        Text("\(L("Häufig", "Usual")) \(WorkoutFormat.weight(frequent)) kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                TextField("0", text: weightBinding(set.id))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold))
                    .frame(width: 64, height: 36)
                    .background(AppSurface.canvas, in: RoundedRectangle(cornerRadius: 8))
                TextField("0", text: repsBinding(set.id))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold))
                    .frame(width: 52, height: 36)
                    .background(AppSurface.canvas, in: RoundedRectangle(cornerRadius: 8))
                Button { toggle(exerciseIndex: exerciseIndex, setIndex: setIndex) } label: {
                    Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(set.completed ? Color.green : Color.secondary)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.borderless)
            }
            if restSetID == set.id, let restEndsAt {
                RestCountdown(endsAt: restEndsAt, total: restTotal)
            } else if setIndex < exercise.sets.count - 1 {
                restDivider(exercise.restSeconds)
            }
        }
    }

    private func restDivider(_ seconds: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.accentColor.opacity(0.45)).frame(height: 2)
            Text(WorkoutFormat.rest(seconds))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Rectangle().fill(Color.accentColor.opacity(0.45)).frame(height: 2)
        }
    }

    private func weightBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { weightText[id] ?? "" }, set: { newValue in
            weightText[id] = newValue
            guard let weight = WorkoutFormat.weight(from: newValue) else { return }
            for exerciseIndex in draft.exercises.indices {
                guard let setIndex = draft.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == id }) else { continue }
                draft.exercises[exerciseIndex].sets[setIndex].weightKg = weight
            }
        })
    }

    private func repsBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { repsText[id] ?? "" }, set: { repsText[id] = $0.filter(\.isNumber) })
    }

    private func applyFrequentWeights() {
        for exerciseIndex in draft.exercises.indices {
            let code = draft.exercises[exerciseIndex].code
            for setIndex in draft.exercises[exerciseIndex].sets.indices {
                guard let frequent = WorkoutProgress.frequentWeight(
                    sessions: store.sessions,
                    exerciseCode: code,
                    setIndex: setIndex
                ) else { continue }
                let id = draft.exercises[exerciseIndex].sets[setIndex].id
                draft.exercises[exerciseIndex].sets[setIndex].weightKg = frequent
                weightText[id] = WorkoutFormat.weight(frequent)
            }
        }
    }

    private func deleteExercise(_ id: UUID) {
        if let exercise = draft.exercises.first(where: { $0.id == id }) {
            for set in exercise.sets {
                weightText[set.id] = nil
                repsText[set.id] = nil
                if restSetID == set.id {
                    restEndsAt = nil
                    restSetID = nil
                }
            }
        }
        draft.exercises.removeAll { $0.id == id }
    }

    private func deleteSet(exerciseID: UUID, setID: UUID) {
        guard let exerciseIndex = draft.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        draft.exercises[exerciseIndex].sets.removeAll { $0.id == setID }
        weightText[setID] = nil
        repsText[setID] = nil
        if restSetID == setID {
            restEndsAt = nil
            restSetID = nil
        }
    }

    private func applyWeight(_ weightKg: Double, exerciseIndex: Int) {
        for setIndex in draft.exercises[exerciseIndex].sets.indices {
            guard !draft.exercises[exerciseIndex].sets[setIndex].completed else { continue }
            draft.exercises[exerciseIndex].sets[setIndex].weightKg = weightKg
            weightText[draft.exercises[exerciseIndex].sets[setIndex].id] = WorkoutFormat.weight(weightKg)
        }
    }

    private func applyReps(_ reps: Int, exerciseIndex: Int) {
        for setIndex in draft.exercises[exerciseIndex].sets.indices {
            guard !draft.exercises[exerciseIndex].sets[setIndex].completed else { continue }
            draft.exercises[exerciseIndex].sets[setIndex].reps = reps
            repsText[draft.exercises[exerciseIndex].sets[setIndex].id] = String(reps)
        }
    }

    private func toggle(exerciseIndex: Int, setIndex: Int) {
        commitTexts()
        draft.exercises[exerciseIndex].sets[setIndex].completed.toggle()
        let set = draft.exercises[exerciseIndex].sets[setIndex]
        if set.completed {
            startRest(setID: set.id, seconds: draft.exercises[exerciseIndex].restSeconds)
        } else if restSetID == set.id {
            restEndsAt = nil
            restSetID = nil
        }
    }

    private func startRest(setID: UUID, seconds: Int) {
        guard seconds > 0 else {
            restEndsAt = nil
            restSetID = nil
            return
        }
        restTotal = seconds
        restSetID = setID
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(seconds))
        restToken = UUID()
    }

    private func chimeWhenRestEnds() async {
        guard let end = restEndsAt else { return }
        let delay = end.timeIntervalSinceNow
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        guard !Task.isCancelled, restEndsAt == end else { return }
        RestChime.play()
    }

    private func commitTexts() {
        for exerciseIndex in draft.exercises.indices {
            for setIndex in draft.exercises[exerciseIndex].sets.indices {
                let set = draft.exercises[exerciseIndex].sets[setIndex]
                if let text = weightText[set.id], let weight = WorkoutFormat.weight(from: text) {
                    draft.exercises[exerciseIndex].sets[setIndex].weightKg = weight
                }
                if let text = repsText[set.id], let reps = Int(text) {
                    draft.exercises[exerciseIndex].sets[setIndex].reps = reps
                }
            }
        }
    }

    private func requestClose() {
        commitTexts()
        if hasCompletedSet {
            showDiscard = true
        } else {
            dismiss()
        }
    }

    private func finish() {
        commitTexts()
        guard hasCompletedSet else { return }
        draft.finishedAt = .now
        draft.planName = plan.name
        let grade = WorkoutProgress.grade(of: draft, comparedWith: store.sessions)
        let records = WorkoutProgress.personalRecords(in: draft, sessions: store.sessions)
        let phrase = WorkoutProgress.motivation(for: grade, seed: draft.id.hashValue)
        store.save(session: draft)
        finishSummary = WorkoutFinishSummary(
            phrase: phrase,
            volume: WorkoutProgress.volume(of: draft),
            records: records
        )
    }
}

private struct WorkoutFinishSummary: Identifiable {
    let id = UUID()
    let phrase: String
    let volume: Double
    let records: [WorkoutPersonalRecord]
}

private struct WorkoutFinishSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: WorkoutFinishSummary

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(summary.phrase)
                        .font(.title.bold())
                    Text("\(L("Volumen", "Volume")) \(WorkoutProgress.volumeText(summary.volume))")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if summary.records.isEmpty {
                        Text(L("Kein neuer Rekord.", "No new record."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.records) { record in
                            HStack(spacing: 8) {
                                RecordBadge()
                                Text(record.exerciseName)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Text("\(WorkoutFormat.weight(record.weightKg)) kg × \(record.reps)")
                                    .monospacedDigit()
                            }
                            .font(.body)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(L("Training fertig", "Workout finished"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct WorkoutSwipeBackLock: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

private struct RestCountdown: View {
    let endsAt: Date
    let total: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            VStack(spacing: 4) {
                Text(remaining <= 0 ? L("Pause vorbei", "Rest finished") : WorkoutFormat.rest(Int(remaining.rounded(.up))))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remaining <= 0 ? Color.green : Color.accentColor)
                ProgressView(value: total == 0 ? 1 : min(1, max(0, 1 - remaining / Double(total))))
                    .tint(remaining <= 0 ? .green : .accentColor)
            }
            .padding(.vertical, 4)
        }
    }
}
