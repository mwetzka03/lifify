import SwiftUI

struct AppDateField: View {
    let title: String
    @Binding var selection: Date
    var minimum: Date?
    var includesTime = false

    private var valueText: String {
        includesTime ? "\(AppDate.numeric(selection)) · \(AppDate.time(selection))" : AppDate.numeric(selection)
    }

    var body: some View {
        DisclosureGroup {
            picker
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, AppDate.locale)
            if includesTime {
                DatePicker(L("Uhrzeit", "Time"), selection: $selection, displayedComponents: .hourAndMinute)
                    .environment(\.locale, AppDate.locale)
            }
        } label: {
            LabeledContent(title, value: valueText)
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let minimum {
            DatePicker(title, selection: $selection, in: minimum..., displayedComponents: .date)
        } else {
            DatePicker(title, selection: $selection, displayedComponents: .date)
        }
    }
}
