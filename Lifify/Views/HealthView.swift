import SwiftData
import SwiftUI

enum HealthRoute: Hashable {
    case plan(UUID)
    case session(UUID)
    case history(UUID)
    case historyList
}

struct HealthView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: WorkoutStore
    @State private var editorPlan: WorkoutPlan?

    var body: some View {
        List {
            Section {
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
                                    ExerciseArtwork(code: exercise.code, name: exercise.name, side: 36, playsVideo: false)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            WorkoutLinkStore.removePlan(plan.id)
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
                Button {
                    editorPlan = WorkoutPlan(name: "")
                } label: {
                    Label(L("Training anlegen", "Create workout"), systemImage: "plus")
                }
                NavigationLink(value: HealthRoute.historyList) {
                    Label(L("Trainingsverlauf", "Workout history"), systemImage: "clock")
                }
            } header: {
                sectionTitle(L("Training", "Training"))
            }
            Section {
                Text(L("Noch nicht verfügbar", "Not available yet"))
                    .foregroundStyle(.secondary)
            } header: {
                sectionTitle(L("Ernährung", "Nutrition"))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: HealthRoute.self) { HealthRouteScreen(route: $0) }
        .sheet(item: $editorPlan) { plan in
            WorkoutEditorView(plan: plan)
                .environmentObject(store)
        }
        .onAppear {
            Task { await WorkoutCalendarSync.cleanup(context: context, sessions: store.sessions) }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
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
        case .historyList:
            WorkoutHistoryListView()
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

                        WorkoutLinkSection(planID: plan.id)

                        ForEach(plan.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    ExerciseArtwork(code: exercise.code, name: exercise.name)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ExerciseName.formatted(exercise.name))
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
                        Text("\(L("Dauer", "Duration")) \(WorkoutFormat.duration(seconds: session.durationSeconds))")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("\(L("Volumen", "Volume")) \(WorkoutProgress.volumeText(WorkoutProgress.volume(of: session)))")
                            .font(.title3.weight(.semibold))
                        let performed = session.performedExercises
                        if performed.isEmpty {
                            Text(L("Keine abgeschlossene Übung.", "No completed exercise."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(performed) { exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    ExerciseArtwork(code: exercise.code, name: exercise.name)
                                    Text(ExerciseName.formatted(exercise.name))
                                        .font(.title3.weight(.semibold))
                                    Spacer(minLength: 8)
                                    Text(WorkoutProgress.volumeText(WorkoutProgress.volume(of: exercise)))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                    HStack {
                                        Text("\(index + 1)")
                                            .frame(width: 24, alignment: .leading)
                                        Text("\(WorkoutFormat.weight(set.weightKg)) kg × \(set.reps)")
                                            .monospacedDigit()
                                        Spacer()
                                        if WorkoutProgress.isPersonalRecord(
                                            set: set,
                                            exerciseCode: exercise.code,
                                            session: session,
                                            sessions: store.sessions
                                        ) {
                                            RecordBadge()
                                        }
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.green)
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

struct WorkoutHistoryListView: View {
    @EnvironmentObject private var store: WorkoutStore

    var body: some View {
        List {
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
                            Text("\(AppDate.numeric(session.finishedAt)) · \(WorkoutFormat.duration(seconds: session.durationSeconds)) · \(WorkoutProgress.volumeText(WorkoutProgress.volume(of: session)))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if !WorkoutProgress.personalRecords(in: session, sessions: store.sessions).isEmpty {
                            RecordBadge()
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
        .navigationTitle(L("Trainingsverlauf", "Workout history"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
            Text("PR")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.orange)
    }
}
