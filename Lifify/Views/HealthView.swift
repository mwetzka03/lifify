import SwiftUI

enum HealthRoute: Hashable {
    case plan(UUID)
    case session(UUID)
    case history(UUID)
}

struct HealthView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(WorkoutAPIKey.storageKey) private var apiKey = ""
    @State private var editorPlan: WorkoutPlan?
    @State private var showingKey = false

    var body: some View {
        List {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Button {
                        showingKey = true
                    } label: {
                        Label(L("Workout-API-Schlüssel hinterlegen", "Add Workout API key"), systemImage: "key")
                    }
                } footer: {
                    Text(L(
                        "Übungen und Bilder kommen aus der Workout API.",
                        "Exercises and images come from the Workout API."
                    ))
                }
            }
            Section(L("Trainingspläne", "Workout plans")) {
                if store.plans.isEmpty {
                    Text(L("Noch kein Trainingsplan.", "No workout plan yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.plans) { plan in
                    NavigationLink(value: HealthRoute.plan(plan.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name)
                                    .font(.body.weight(.semibold))
                                Text(planSummary(plan))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: -10) {
                                ForEach(plan.exercises.prefix(3)) { exercise in
                                    ExerciseArtwork(code: exercise.code, side: 36)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deletePlan(id: plan.id)
                        } label: {
                            Label(L("Löschen", "Delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            editorPlan = plan
                        } label: {
                            Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            Section(L("Verlauf", "History")) {
                if store.sessions.isEmpty {
                    Text(L("Noch kein abgeschlossenes Training.", "No finished workout yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.sessions) { session in
                    NavigationLink(value: HealthRoute.history(session.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.planName)
                                    .font(.body.weight(.semibold))
                                Text(AppDate.numeric(session.finishedAt))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: -10) {
                                ForEach(session.exercises.prefix(3)) { exercise in
                                    ExerciseArtwork(code: exercise.code, side: 36)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteSession(id: session.id)
                        } label: {
                            Label(L("Löschen", "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Gesundheit", "Health"))
        .navigationDestination(for: HealthRoute.self) { HealthRouteScreen(route: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingKey = true } label: { Image(systemName: "key") }
                    .accessibilityLabel(L("API-Schlüssel", "API key"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPlan = WorkoutPlan(name: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L("Trainingsplan anlegen", "Create workout plan"))
            }
        }
        .sheet(item: $editorPlan) { plan in
            WorkoutEditorView(plan: plan)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingKey) {
            WorkoutAPIKeySheet()
        }
    }

    private func planSummary(_ plan: WorkoutPlan) -> String {
        let exercises = plan.exercises.count
        let sets = plan.exercises.reduce(0) { $0 + $1.sets.count }
        return L(
            "\(exercises) Übungen · \(sets) Sätze",
            "\(exercises) exercises · \(sets) sets"
        )
    }
}

struct HealthRouteScreen: View {
    let route: HealthRoute

    var body: some View {
        screen
            .navigationDestination(for: HealthRoute.self) { HealthRouteScreen(route: $0) }
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .plan(let id):
            WorkoutPlanDetailView(planID: id)
        case .session(let id):
            WorkoutSessionRoute(planID: id)
        case .history(let id):
            WorkoutHistoryView(sessionID: id)
        }
    }
}

private struct WorkoutSessionRoute: View {
    @EnvironmentObject private var store: WorkoutStore
    let planID: UUID

    var body: some View {
        if let plan = store.plan(id: planID) {
            WorkoutSessionView(plan: plan)
        } else {
            ContentUnavailableView(L("Plan nicht gefunden", "Plan not found"), systemImage: "figure.strengthtraining.traditional")
        }
    }
}

struct WorkoutPlanDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    let planID: UUID
    @State private var editorPlan: WorkoutPlan?

    var body: some View {
        Group {
            if let plan = store.plan(id: planID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink(value: HealthRoute.session(plan.id)) {
                            Text(L("Training starten", "Start workout"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.exercises.isEmpty)

                        ForEach(plan.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    ExerciseArtwork(code: exercise.code)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                            .font(.title3.weight(.semibold))
                                        Text("\(L("Pause", "Rest")) \(WorkoutFormat.rest(exercise.restSeconds))")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                    HStack {
                                        Text("\(L("Satz", "Set")) \(index + 1)")
                                        Spacer()
                                        Text("\(WorkoutFormat.weight(set.weightKg)) kg × \(set.reps)")
                                            .monospacedDigit()
                                    }
                                    .font(.body)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(12)
                }
                .appCanvas()
                .navigationTitle(plan.name)
                .toolbar {
                    Button(L("Bearbeiten", "Edit")) { editorPlan = plan }
                }
                .sheet(item: $editorPlan) { plan in
                    WorkoutEditorView(plan: plan)
                        .environmentObject(store)
                }
            } else {
                ContentUnavailableView(L("Plan nicht gefunden", "Plan not found"), systemImage: "figure.strengthtraining.traditional")
            }
        }
    }
}

struct WorkoutHistoryView: View {
    @EnvironmentObject private var store: WorkoutStore
    let sessionID: UUID

    var body: some View {
        Group {
            if let session = store.session(id: sessionID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(AppDate.numeric(session.finishedAt))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        ForEach(session.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    ExerciseArtwork(code: exercise.code)
                                    Text(exercise.name)
                                        .font(.title3.weight(.semibold))
                                }
                                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                    HStack {
                                        Text("\(index + 1)")
                                            .frame(width: 24, alignment: .leading)
                                        Text("\(WorkoutFormat.weight(set.weightKg)) kg × \(set.reps)")
                                            .monospacedDigit()
                                        Spacer()
                                        Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(set.completed ? Color.green : Color.secondary)
                                    }
                                    .font(.body)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(12)
                }
                .appCanvas()
                .navigationTitle(session.planName)
            } else {
                ContentUnavailableView(L("Training nicht gefunden", "Workout not found"), systemImage: "clock")
            }
        }
    }
}

private struct WorkoutAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WorkoutAPIKey.storageKey) private var apiKey = ""
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField(L("API-Schlüssel", "API key"), text: $draft)
                Text(L(
                    "Den Schlüssel findest du im Konto auf workoutapi.com. Er bleibt nur auf diesem Gerät gespeichert.",
                    "The key is in your workoutapi.com account. It stays on this device only."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(L("Workout API", "Workout API"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        apiKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { draft = apiKey }
        }
    }
}
