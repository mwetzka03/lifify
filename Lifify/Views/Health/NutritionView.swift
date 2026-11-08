import PhotosUI
import SwiftData
import SwiftUI

struct NutritionBoard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: WorkoutStore
    @Query private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
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
    @State private var showsDayPicker = false
    @State private var recognizing = false

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
        .onChange(of: day) {
            let start = min(calendar.startOfDay(for: day), today)
            if start != day { day = start }
        }
        .sheet(isPresented: $showsDayPicker) {
            NavigationStack {
                DatePicker(
                    L("Tag", "Day"),
                    selection: $day,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(L("Tag", "Day"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Fertig", "Done")) { showsDayPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attach(item, on: key) }
        }
        .sheet(item: $edited) { meal in
            MealEditor(
                meal: meal,
                trained: NutritionPlan.trained(
                    on: NutritionPlan.date(from: meal.dayKey) ?? day,
                    sessions: store.sessions
                )
            ) { saved in
                MealLog.upsert(saved)
                reload()
            } onDelete: { removed in
                NutritionLedger.forget(removed, context: context)
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
            Button {
                showsDayPicker = true
            } label: {
                VStack(spacing: 2) {
                    Text(calendar.isDate(day, inSameDayAs: today) ? L("Heute", "Today") : AppDate.weekdayWide(day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppDate.numeric(day))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
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
                calorieReward(target: target, meals: meals)
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
            fastFoodCharge(meals)
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
                Label(recognizing ? NutritionCopy.recognizing : L("Foto", "Photo"), systemImage: recognizing ? "hourglass" : "camera")
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .appGlassCard(radius: 18)
            }
            .disabled(recognizing)
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
                        NutritionLedger.forget(meal, context: context)
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
        parts.append(meal.kind.label)
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

    private func calorieReward(target: Int?, meals: [MealRecord]) -> some View {
        let confirmed = meals.filter { $0.status == .confirmed }
        let eaten = NutritionPlan.rounded(.calories, meals: confirmed)
        let base = MealScore.coins(eaten: eaten, target: target, kinds: confirmed.map(\.kind))
        let challenge = challenges.first { $0.externalIdentifier == NutritionLedger.challengeMark }
        let streak = challenge.map {
            ChallengeService.status(for: $0, endingOn: day, completions: completions, events: calendarEvents).count
        } ?? 0
        let coins: Int
        if let challenge, base > 0 {
            coins = ChallengeService.projectedCoins(
                challenge: challenge,
                on: day,
                completions: completions,
                events: calendarEvents,
                baseCoins: base
            )
        } else {
            coins = base
        }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Unter dem Kalorienziel", "Under the calorie target"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if streak > 0 {
                    Text("\(L("Serie", "Streak")) \(streak)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if coins > 0 {
                CoinAmountView(amount: coins, showsPlus: true)
            } else {
                Text(L("0 Coins", "0 coins"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fastFoodCharge(_ meals: [MealRecord]) -> some View {
        let count = meals.filter { $0.kind == .fastFood }.count
        if count > 0 {
            HStack {
                Text(L("Fast Food im Shop", "Fast food in the shop"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("−\(count * MealScore.fastFoodPrice)")
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
    }

    private func reload() {
        NutritionLedger.settle(context: context, sessions: store.sessions)
        meals = MealLog.all()
    }

    private func person(on key: String) -> MealPerson {
        let measures = UserBody.current()
        let calendar = Calendar.current
        let date = NutritionPlan.date(from: key, calendar: calendar) ?? day
        let age = UserProfile.birth().map { NutritionPlan.age(birth: $0, on: date, calendar: calendar) } ?? 30
        return MealPerson(
            heightCm: measures.heightCm,
            weightKg: measures.weightKg,
            age: age,
            sex: measures.sex.label,
            goal: measures.goal.label,
            trained: NutritionPlan.trained(on: date, sessions: store.sessions, calendar: calendar)
        )
    }

    private func attach(_ item: PhotosPickerItem, on key: String) async {
        let data = try? await item.loadTransferable(type: Data.self)
        let id = UUID()
        let photoName = data.flatMap { MealPhotoStore.save($0, id: id) }
        var meal = MealRecord(
            id: id,
            dayKey: key,
            title: L("Mahlzeit", "Meal"),
            note: MealRecognition.isConnected ? NutritionCopy.recognizing : NutritionCopy.recognitionPending,
            source: .photo,
            status: .draft,
            photoName: photoName
        )
        MealLog.upsert(meal)
        photoItem = nil
        reload()
        guard MealRecognition.isConnected, let data else {
            edited = meal
            return
        }
        recognizing = true
        let reading = await MealRecognition.read(image: data, person: person(on: key), correction: "")
        recognizing = false
        if let reading {
            meal.title = reading.title
            meal.kind = reading.kind
            meal.note = reading.note
            meal.nutrients = reading.nutrients
        } else {
            meal.note = NutritionCopy.recognitionFailed
        }
        MealLog.upsert(meal)
        reload()
        edited = meal
    }
}

private struct MealEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var meal: MealRecord
    @State private var amounts: [String: String]
    @State private var showsMore = false
    @State private var rereading = false
    let trained: Bool
    let onSave: (MealRecord) -> Void
    let onDelete: (MealRecord) -> Void

    init(meal: MealRecord, trained: Bool, onSave: @escaping (MealRecord) -> Void, onDelete: @escaping (MealRecord) -> Void) {
        _meal = State(initialValue: meal)
        var text: [String: String] = [:]
        for nutrient in Nutrient.allCases {
            let value = meal.amount(nutrient)
            text[nutrient.rawValue] = value > 0 ? MealEditor.amountText(value) : ""
        }
        _amounts = State(initialValue: text)
        self.trained = trained
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name", "Name"), text: $meal.title)
                    Picker(L("Art", "Kind"), selection: Binding(
                        get: { meal.kind },
                        set: { meal.kind = $0 }
                    )) {
                        ForEach(MealKind.allCases) { Text($0.label).tag($0) }
                    }
                    if meal.source == .photo {
                        Text(MealRecognition.isConnected ? meal.note : NutritionCopy.recognitionPending)
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
                        Button(rereading ? NutritionCopy.recognizing : L("Nur Rückmeldung merken", "Keep the feedback only")) {
                            Task { await keepFeedback() }
                        }
                        .disabled(rereading)
                    } footer: {
                        Text(MealRecognition.isConnected
                            ? L(
                                "Die Rückmeldung geht mit dem Foto noch einmal an die Erkennung. Stimmt übernimmt die Werte.",
                                "The feedback goes back to recognition with the photo. Correct keeps the values."
                            )
                            : L(
                                "Die Rückmeldung bleibt auf dem Gerät. Sie geht erst raus, wenn unter Gesundheit ein Schlüssel steht.",
                                "The feedback stays on the device. It is sent only once a key is saved under Health."
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

    private func keepFeedback() async {
        guard MealRecognition.isConnected,
              let name = meal.photoName,
              let data = MealPhotoStore.load(name)
        else {
            store(status: .draft)
            return
        }
        rereading = true
        let measures = UserBody.current()
        let calendar = Calendar.current
        let date = NutritionPlan.date(from: meal.dayKey, calendar: calendar) ?? .now
        let person = MealPerson(
            heightCm: measures.heightCm,
            weightKg: measures.weightKg,
            age: UserProfile.birth().map { NutritionPlan.age(birth: $0, on: date, calendar: calendar) } ?? 30,
            sex: measures.sex.label,
            goal: measures.goal.label,
            trained: trained
        )
        if let reading = await MealRecognition.read(image: data, person: person, correction: meal.correction) {
            meal.title = reading.title
            meal.kind = reading.kind
            meal.note = reading.note
            for nutrient in Nutrient.allCases {
                let value = reading.nutrients[nutrient.rawValue] ?? 0
                amounts[nutrient.rawValue] = value > 0 ? MealEditor.amountText(value) : ""
            }
        } else {
            meal.note = NutritionCopy.recognitionFailed
        }
        rereading = false
        store(status: .draft)
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
