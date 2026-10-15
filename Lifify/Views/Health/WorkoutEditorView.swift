import SwiftUI

struct WorkoutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStore
    @State private var plan: WorkoutPlan
    @State private var weightText: [UUID: String]
    @State private var repsText: [UUID: String]
    @State private var showingSearch = false
    @State private var didApplyFrequent = false

    init(plan: WorkoutPlan) {
        _plan = State(initialValue: plan)
        var weights: [UUID: String] = [:]
        var reps: [UUID: String] = [:]
        for exercise in plan.exercises {
            for set in exercise.sets {
                weights[set.id] = WorkoutFormat.weight(set.weightKg)
                reps[set.id] = String(set.reps)
            }
        }
        _weightText = State(initialValue: weights)
        _repsText = State(initialValue: reps)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L("Name, z. B. Push", "Name, for example Push"), text: $plan.name)
                        .font(.title2.bold())
                }
                ForEach(plan.exercises) { exercise in
                    Section {
                        exerciseHeader(exercise)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    plan.exercises.removeAll { $0.id == exercise.id }
                                } label: {
                                    Label(L("Übung löschen", "Delete exercise"), systemImage: "trash")
                                }
                            }
                        restControls(exercise)
                        columnHeader
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            setRow(exercise: exercise, index: index, set: set)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeSet(exerciseID: exercise.id, setID: set.id)
                                    } label: {
                                        Label(L("Satz löschen", "Delete set"), systemImage: "trash")
                                    }
                                }
                            if index < exercise.sets.count - 1 {
                                restDivider(exercise.restSeconds)
                            }
                        }
                        Button {
                            addSet(to: exercise.id)
                        } label: {
                            Text("+ \(L("Satz", "Set")) (\(WorkoutFormat.rest(exercise.restSeconds)))")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Button {
                        showingSearch = true
                    } label: {
                        Label(L("Übung hinzufügen", "Add exercise"), systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .appCanvas()
            .navigationTitle(L("Routine bearbeiten", "Edit routine"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !didApplyFrequent else { return }
                didApplyFrequent = true
                for exerciseIndex in plan.exercises.indices {
                    let code = plan.exercises[exerciseIndex].code
                    for setIndex in plan.exercises[exerciseIndex].sets.indices {
                        guard let frequent = WorkoutProgress.frequentWeight(
                            sessions: store.sessions,
                            exerciseCode: code,
                            setIndex: setIndex
                        ) else { continue }
                        plan.exercises[exerciseIndex].sets[setIndex].weightKg = frequent
                        weightText[plan.exercises[exerciseIndex].sets[setIndex].id] = WorkoutFormat.weight(frequent)
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                ExerciseSearchView { exercise in
                    add(exercise)
                }
            }
        }
    }

    private func exerciseHeader(_ exercise: WorkoutPlanExercise) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ExerciseArtwork(code: exercise.code, name: exercise.name)
            Text(exercise.name)
                .font(.title3.weight(.semibold))
            Spacer(minLength: 8)
            Menu {
                Button(L("Nach oben", "Move up")) { move(exercise.id, by: -1) }
                Button(L("Nach unten", "Move down")) { move(exercise.id, by: 1) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
    }

    private func restControls(_ exercise: WorkoutPlanExercise) -> some View {
        HStack {
            Text(L("Pause", "Rest"))
                .foregroundStyle(.secondary)
            Spacer()
            Button { changeRest(exercise.id, by: -15) } label: { Image(systemName: "minus") }
                .disabled(exercise.restSeconds <= 0)
            Text(WorkoutFormat.rest(exercise.restSeconds))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 52)
            Button { changeRest(exercise.id, by: 15) } label: { Image(systemName: "plus") }
                .disabled(exercise.restSeconds >= 600)
        }
        .font(.body)
        .buttonStyle(.borderless)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text(L("Satz", "Set")).frame(width: 36, alignment: .leading)
            Text(L("Vorherige", "Previous")).frame(maxWidth: .infinity, alignment: .leading)
            Text("kg").frame(width: 64)
            Text(L("Wdh.", "Reps")).frame(width: 52)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func setRow(exercise: WorkoutPlanExercise, index: Int, set: WorkoutPlanSet) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(AppSurface.canvas, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                if let previous = WorkoutProgress.previousPerformance(
                    sessions: store.sessions,
                    exerciseCode: exercise.code,
                    setIndex: index
                ) {
                    Text(WorkoutFormat.previous(weight: previous.weight, reps: previous.reps))
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
                if let frequent = WorkoutProgress.frequentWeight(
                    sessions: store.sessions,
                    exerciseCode: exercise.code,
                    setIndex: index
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
        .padding(.vertical, 2)
    }

    private func weightBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { weightText[id] ?? "" },
            set: { weightText[id] = $0 }
        )
    }

    private func repsBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { repsText[id] ?? "" },
            set: { repsText[id] = $0.filter(\.isNumber) }
        )
    }

    private func add(_ exercise: WorkoutExerciseInfo) {
        let sets = (0..<3).map { _ in WorkoutPlanSet() }
        for set in sets {
            weightText[set.id] = WorkoutFormat.weight(set.weightKg)
            repsText[set.id] = String(set.reps)
        }
        plan.exercises.append(
            WorkoutPlanExercise(code: exercise.code, name: exercise.name, restSeconds: 90, sets: sets)
        )
    }

    private func addSet(to exerciseID: UUID) {
        guard let index = plan.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let previous = plan.exercises[index].sets.last
        let set = WorkoutPlanSet(weightKg: previous?.weightKg ?? 0, reps: previous?.reps ?? 8)
        weightText[set.id] = WorkoutFormat.weight(set.weightKg)
        repsText[set.id] = String(set.reps)
        plan.exercises[index].sets.append(set)
    }

    private func removeSet(exerciseID: UUID, setID: UUID) {
        guard let index = plan.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        plan.exercises[index].sets.removeAll { $0.id == setID }
    }

    private func changeRest(_ exerciseID: UUID, by delta: Int) {
        guard let index = plan.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        plan.exercises[index].restSeconds = min(600, max(0, plan.exercises[index].restSeconds + delta))
    }

    private func move(_ exerciseID: UUID, by delta: Int) {
        guard let index = plan.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let next = index + delta
        guard plan.exercises.indices.contains(next) else { return }
        plan.exercises.swapAt(index, next)
    }

    private func save() {
        for exerciseIndex in plan.exercises.indices {
            for setIndex in plan.exercises[exerciseIndex].sets.indices {
                let set = plan.exercises[exerciseIndex].sets[setIndex]
                if let text = weightText[set.id], let weight = WorkoutFormat.weight(from: text) {
                    plan.exercises[exerciseIndex].sets[setIndex].weightKg = weight
                }
                if let text = repsText[set.id], let reps = Int(text) {
                    plan.exercises[exerciseIndex].sets[setIndex].reps = reps
                }
            }
        }
        plan.name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save(plan: plan)
        dismiss()
    }
}
