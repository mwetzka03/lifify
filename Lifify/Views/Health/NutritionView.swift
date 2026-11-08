import PhotosUI
import SwiftUI

struct NutritionBoard: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage(UserProfile.birthKey) private var birthRaw = ""
    @AppStorage(UserBody.heightKey) private var heightRaw = 0.0
    @AppStorage(UserBody.weightKey) private var weightRaw = 0.0
    @AppStorage(UserBody.sexKey) private var sexRaw = BodySex.unspecified.rawValue
    @AppStorage(UserBody.goalKey) private var goalRaw = BodyGoal.maintain.rawValue
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var meals: [MealRecord] = []
    @State private var edited: MealRecord?
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let _ = birthRaw
        let key = NutritionPlan.dayKey(day, calendar: calendar)
        let dayMeals = NutritionPlan.onDay(key, meals: meals)
        let trained = NutritionPlan.trained(on: day, sessions: store.sessions, calendar: calendar)
        let measures = BodyMeasures(
            heightCm: heightRaw,
            weightKg: weightRaw,
            sex: BodySex.resolved(sexRaw),
            goal: BodyGoal.resolved(goalRaw)
        )
        let target = NutritionPlan.dayTarget(
            measures: measures,
            birth: UserProfile.birth(),
            on: day,
            trained: trained,
            calendar: calendar
        )
        VStack(alignment: .leading, spacing: 12) {
            dayBar(today: today, calendar: calendar)
            targetCard(target: target, meals: dayMeals, trained: trained, measures: measures)
            addRow
            mealCard(dayMeals)
            Text(NutritionCopy.estimateNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: reload)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attach(item, on: key) }
        }
        .sheet(item: $edited) { meal in
            MealEditor(meal: meal) { saved in
                MealLog.upsert(saved)
                reload()
            } onDelete: { removed in
                MealPhotoStore.remove(removed.photoName)
                MealLog.remove(id: removed.id)
                reload()
            }
        }
    }

    private func dayBar(today: Date, calendar: Calendar) -> some View {
        HStack {
            Button {
                shift(by: -1, calendar: calendar, today: today)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text(calendar.isDate(day, inSameDayAs: today) ? L("Heute", "Today") : AppDate.weekdayWide(day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppDate.numeric(day))
                    .font(.headline)
            }
            Spacer()
            Button {
                shift(by: 1, calendar: calendar, today: today)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(calendar.isDate(day, inSameDayAs: today))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .appGlassCard(radius: 18)
    }

    private func targetCard(target: Int?, meals: [MealRecord], trained: Bool, measures: BodyMeasures) -> some View {
        let eaten = NutritionPlan.rounded(.calories, meals: meals)
        let protein = NutritionPlan.rounded(.protein, meals: meals)
        return VStack(alignment: .leading, spacing: 8) {
            if let target {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Ziel", "Target"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(target) kcal")
                        .font(.title3.weight(.semibold))
                }
                HStack {
                    nutrientLine(L("Gegessen", "Eaten"), "\(eaten) kcal")
                    Spacer()
                    nutrientLine(L("Übrig", "Left"), "\(target - eaten) kcal")
                }
                nutrientLine(Nutrient.protein.label, "\(protein) \(Nutrient.protein.unit)")
                if trained {
                    Text(L(
                        "Training an diesem Tag: +\(NutritionPlan.trainingBonus) kcal.",
                        "Workout on this day: +\(NutritionPlan.trainingBonus) kcal."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if !measures.isComplete {
                Text(L(
                    "Trag Größe und Gewicht unter Nutzer ein. Daraus wird das Tagesziel.",
                    "Add height and weight under User. That sets the daily target."
                ))
                .foregroundStyle(.secondary)
            }
            Text("\(BodyGoal.resolved(goalRaw).label) · \(BodySex.resolved(sexRaw).label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(radius: 18)
    }

    private func nutrientLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Button {
                showsPhotoPicker = true
            } label: {
                Label(L("Foto", "Photo"), systemImage: "camera")
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .appGlassCard(radius: 18)
            }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
            Button {
                let key = NutritionPlan.dayKey(day)
                edited = MealRecord(
                    dayKey: key,
                    title: "",
                    source: .manual,
                    status: .confirmed
                )
            } label: {
                Label(L("Manuell", "Manual"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .appGlassCard(radius: 18)
            }
            .buttonStyle(.plain)
        }
    }

    private func mealCard(_ dayMeals: [MealRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if dayMeals.isEmpty {
                Text(NutritionCopy.emptyDay)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            ForEach(Array(dayMeals.enumerated()), id: \.element.id) { index, meal in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                Button {
                    edited = meal
                } label: {
                    mealRow(meal)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        MealPhotoStore.remove(meal.photoName)
                        MealLog.remove(id: meal.id)
                        reload()
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(radius: 18)
    }

    private func mealRow(_ meal: MealRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title.isEmpty ? L("Mahlzeit", "Meal") : meal.title)
                    .foregroundStyle(.primary)
                Text(mealCaption(meal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(NutritionPlan.rounded(.calories, meals: [meal])) kcal")
                .font(.body.weight(.semibold))
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func mealCaption(_ meal: MealRecord) -> String {
        let protein = NutritionPlan.rounded(.protein, meals: [meal])
        var parts = ["\(protein) \(Nutrient.protein.unit) \(Nutrient.protein.label)"]
        if meal.status == .draft { parts.append(L("Entwurf", "Draft")) }
        if meal.source == .photo, !MealRecognition.isConnected {
            parts.append(NutritionCopy.recognitionPending)
        }
        return parts.joined(separator: " · ")
    }

    private func shift(by delta: Int, calendar: Calendar, today: Date) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: day) else { return }
        day = min(calendar.startOfDay(for: next), today)
    }

    private func reload() {
        meals = MealLog.all()
    }

    private func attach(_ item: PhotosPickerItem, on key: String) async {
        let data = try? await item.loadTransferable(type: Data.self)
        let id = UUID()
        let photoName = data.flatMap { MealPhotoStore.save($0, id: id) }
        let meal = MealRecord(
            id: id,
            dayKey: key,
            title: L("Mahlzeit", "Meal"),
            note: NutritionCopy.recognitionPending,
            source: .photo,
            status: .draft,
            photoName: photoName
        )
        MealLog.upsert(meal)
        photoItem = nil
        reload()
        edited = meal
    }
}

private struct MealEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var meal: MealRecord
    @State private var amounts: [String: String]
    @State private var showsMore = false
    let onSave: (MealRecord) -> Void
    let onDelete: (MealRecord) -> Void

    init(meal: MealRecord, onSave: @escaping (MealRecord) -> Void, onDelete: @escaping (MealRecord) -> Void) {
        _meal = State(initialValue: meal)
        var text: [String: String] = [:]
        for nutrient in Nutrient.allCases {
            let value = meal.amount(nutrient)
            text[nutrient.rawValue] = value > 0 ? MealEditor.amountText(value) : ""
        }
        _amounts = State(initialValue: text)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name", "Name"), text: $meal.title)
                    if meal.source == .photo {
                        Text(NutritionCopy.recognitionPending)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(
                            L("Rückmeldung an die Erkennung", "Feedback for recognition"),
                            text: $meal.correction,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                    }
                }
                .appGlassRow()
                Section {
                    ForEach(Nutrient.allCases.filter(\.isPrimary)) { nutrient in
                        amountField(nutrient)
                    }
                    MoreSettingsToggle(isExpanded: $showsMore)
                    if showsMore {
                        ForEach(Nutrient.allCases.filter { !$0.isPrimary }) { nutrient in
                            amountField(nutrient)
                        }
                    }
                }
                .appGlassRow()
                if meal.source == .photo, meal.status == .draft {
                    Section {
                        Button(L("Nur Rückmeldung merken", "Keep the feedback only")) {
                            store(status: .draft)
                        }
                    } footer: {
                        Text(L(
                            "Die Rückmeldung bleibt auf dem Gerät. Sie geht erst raus, wenn die Erkennung verbunden ist.",
                            "The feedback stays on the device. It is sent only once recognition is connected."
                        ))
                    }
                    .appGlassRow()
                }
            }
            .appGlassList()
            .navigationTitle(meal.source == .photo ? L("Foto prüfen", "Review photo") : L("Mahlzeit", "Meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    if MealLog.all().contains(where: { $0.id == meal.id }) {
                        Button(L("Löschen", "Delete"), role: .destructive) {
                            onDelete(meal)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(meal.source == .photo ? L("Stimmt", "Correct") : L("Sichern", "Save")) {
                        store(status: .confirmed)
                    }
                }
            }
        }
    }

    private func amountField(_ nutrient: Nutrient) -> some View {
        HStack {
            Text(nutrient.label)
            Spacer()
            TextField("0", text: binding(nutrient))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(nutrient.unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func binding(_ nutrient: Nutrient) -> Binding<String> {
        Binding(
            get: { amounts[nutrient.rawValue] ?? "" },
            set: { amounts[nutrient.rawValue] = $0 }
        )
    }

    private func store(status: MealStatus) {
        var saved = meal
        if saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved.title = L("Mahlzeit", "Meal")
        }
        var nutrients: [String: Double] = [:]
        for nutrient in Nutrient.allCases {
            let value = NutritionPlan.amount(from: amounts[nutrient.rawValue] ?? "")
            if value > 0 { nutrients[nutrient.rawValue] = value }
        }
        saved.nutrients = nutrients
        saved.status = status
        onSave(saved)
        dismiss()
    }

    private static func amountText(_ value: Double) -> String {
        let shown = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        if UserDefaults.standard.string(forKey: "appLanguage") == "en" { return shown }
        return shown.replacingOccurrences(of: ".", with: ",")
    }
}
