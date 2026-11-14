import SwiftUI

private enum EventPickerAnchor {
    static let today = "event-picker-today"
}

struct ChallengeEventPicker: View {
    @Binding var selection: UUID?
    let events: [ChallengeCalendarEvent]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [ChallengeCalendarEvent] {
        guard !trimmedQuery.isEmpty else { return events }
        return events.filter { $0.title.localizedStandardContains(trimmedQuery) }
    }

    private var buckets: [DayBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: AppClock.now)
        let ordered = visible.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var days: [Date] = []
        var map: [Date: [ChallengeCalendarEvent]] = [:]
        for event in ordered {
            let day = calendar.startOfDay(for: event.startDate)
            if map[day] == nil { days.append(day) }
            map[day, default: []].append(event)
        }
        if trimmedQuery.isEmpty, map[today] == nil {
            let index = days.firstIndex { $0 > today } ?? days.count
            days.insert(today, at: index)
            map[today] = []
        }
        return days.map { DayBucket(day: $0, events: map[$0] ?? []) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !buckets.contains(where: { Calendar.current.isDateInToday($0.day) }) {
                    Section { noneButton }
                        .appGlassRow()
                }
                ForEach(buckets) { bucket in
                    daySection(bucket)
                }
            }
            .appGlassList()
            .navigationTitle(L("Termin", "Event"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: L("Termin suchen", "Search events"))
            .onAppear {
                guard trimmedQuery.isEmpty else { return }
                Task { @MainActor in
                    proxy.scrollTo(EventPickerAnchor.today, anchor: .top)
                    try? await Task.sleep(for: .milliseconds(80))
                    proxy.scrollTo(EventPickerAnchor.today, anchor: .top)
                }
            }
        }
    }

    private func daySection(_ bucket: DayBucket) -> some View {
        let today = Calendar.current.isDateInToday(bucket.day)
        return Section {
            Text(today ? L("Heute", "Today") : AppDate.weekdayAndNumeric(bucket.day))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .id(today ? EventPickerAnchor.today : "day-\(bucket.id)")
            if today {
                noneButton
            }
            if bucket.events.isEmpty, today, trimmedQuery.isEmpty {
                Text(L("Kein freier Termin", "No free event"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(bucket.events) { event in
                eventButton(event)
            }
        }
        .appGlassRow()
    }

    private var noneButton: some View {
        Button {
            selection = nil
            dismiss()
        } label: {
            HStack {
                Text(L("Keiner", "None"))
                Spacer()
                if selection == nil {
                    Image(systemName: "checkmark")
                        .appAccentForeground()
                }
            }
        }
    }

    private func eventButton(_ event: ChallengeCalendarEvent) -> some View {
        Button {
            selection = event.id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                    Text(eventCaption(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selection == event.id {
                    Image(systemName: "checkmark")
                        .appAccentForeground()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func eventCaption(_ event: ChallengeCalendarEvent) -> String {
        let slot = ChallengeTimeStore.plannedMinutes(for: event.id)
            ?? ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
        let linked = ChallengeTimeStore.memberIDs(for: event.id).compactMap { ChallengeTimeStore.minutes(for: $0) }
        return ChallengeTimeRules.scheduleCaption(
            allDay: event.isAllDay,
            dateText: AppDate.numeric(event.startDate),
            timeText: AppDate.time(event.startDate),
            slotMinutes: slot,
            linkedMinutes: linked
        )
    }
}

private struct DayBucket: Identifiable {
    var day: Date
    var events: [ChallengeCalendarEvent]
    var id: TimeInterval { day.timeIntervalSinceReferenceDate }
}
