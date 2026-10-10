import SwiftData
import SwiftUI

struct VisionBoardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VisionBoard.createdAt) private var boards: [VisionBoard]
    @Query private var elements: [VisionBoardElement]
    @Query(sort: \BucketListItem.targetYear) private var bucketItems: [BucketListItem]
    @State private var selectedBoardID: UUID?
    @State private var selectedElement: VisionBoardElement?
    @State private var showingNewBoard = false
    @State private var showingBucketItem = false

    private var selectedBoard: VisionBoard? {
        boards.first { $0.id == selectedBoardID } ?? boards.first
    }

    var body: some View {
        List {
            Section(L("Bucketlist", "Bucket list")) {
                ForEach(bucketItems) { item in
                    Button {
                        item.isCompleted.toggle()
                        try? context.save()
                    } label: {
                        HStack {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(item.title).foregroundStyle(.primary)
                                Text("\(item.targetYear)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { bucketItems[$0] }.forEach(context.delete)
                    try? context.save()
                }
                Button {
                    showingBucketItem = true
                } label: {
                    Label(L("Wunsch hinzufügen", "Add wish"), systemImage: "plus")
                }
            }

            Section {
                if boards.isEmpty {
                    ContentUnavailableView(L("Noch kein Visionboard", "No vision board yet"), systemImage: "rectangle.3.group")
                    Button(L("Visionboard erstellen", "Create vision board")) { showingNewBoard = true }
                } else {
                    Picker(L("Board", "Board"), selection: Binding(
                        get: { selectedBoard?.id },
                        set: { selectedBoardID = $0 }
                    )) {
                        ForEach(boards) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if let board = selectedBoard {
                        VisionCanvas(
                            board: board,
                            elements: elements.filter { $0.boardID == board.id },
                            selectedElement: $selectedElement
                        )
                        .frame(height: 420)
                        .listRowInsets(EdgeInsets())
                        elementToolbar(board: board)
                    }
                }
            } header: {
                HStack {
                    Text(L("Visionboard", "Vision board"))
                    Spacer()
                    Button { showingNewBoard = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .navigationTitle(L("Visionboard", "Vision board"))
        .sheet(isPresented: $showingNewBoard) { NewBoardForm() }
        .sheet(isPresented: $showingBucketItem) { BucketItemForm() }
        .sheet(item: $selectedElement) { VisionElementForm(element: $0) }
        .onAppear { selectedBoardID = selectedBoardID ?? boards.first?.id }
    }

    @ViewBuilder
    private func elementToolbar(board: VisionBoard) -> some View {
        HStack {
            Menu {
                ForEach(VisionElementType.allCases) { type in
                    Button(type.label) {
                        context.insert(VisionBoardElement(boardID: board.id, type: type, text: type == .text ? L("Neuer Text", "New text") : ""))
                        try? context.save()
                    }
                }
            } label: {
                Label(L("Element", "Element"), systemImage: "plus")
            }
            Spacer()
            Button(role: .destructive) {
                let boardElements = elements.filter { $0.boardID == board.id }
                boardElements.forEach(context.delete)
                context.delete(board)
                try? context.save()
                selectedBoardID = boards.first { $0.id != board.id }?.id
            } label: {
                Label(L("Board löschen", "Delete board"), systemImage: "trash")
            }
        }
    }
}

private struct VisionCanvas: View {
    let board: VisionBoard
    let elements: [VisionBoardElement]
    @Binding var selectedElement: VisionBoardElement?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: board.backgroundHex).opacity(board.backgroundOpacity)
                ForEach(elements) { element in
                    VisionElementShape(element: element)
                        .frame(width: element.width, height: element.height)
                        .rotationEffect(.degrees(element.rotation))
                        .position(
                            x: min(max(element.x, 30), proxy.size.width - 30),
                            y: min(max(element.y, 30), proxy.size.height - 30)
                        )
                        .onTapGesture { selectedElement = element }
                        .gesture(
                            DragGesture().onEnded {
                                element.x += $0.translation.width
                                element.y += $0.translation.height
                                try? element.modelContext?.save()
                            }
                        )
                }
            }
            .clipped()
        }
        .background(Color.secondary.opacity(0.08))
    }
}

private struct VisionElementShape: View {
    let element: VisionBoardElement

    var body: some View {
        Group {
            switch element.type {
            case .text:
                Text(element.text)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
            case .rectangle:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: element.colorHex))
                    .overlay(Text(element.text))
            case .circle:
                Circle()
                    .fill(Color(hex: element.colorHex))
                    .overlay(Text(element.text))
            }
        }
        .shadow(radius: 2)
    }
}

private struct NewBoardForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form { TextField(L("Titel", "Title"), text: $title) }
                .navigationTitle(L("Neues Visionboard", "New vision board"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Speichern", "Save")) {
                            guard !title.isEmpty else { return }
                            context.insert(VisionBoard(title: title))
                            try? context.save()
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct VisionElementForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let element: VisionBoardElement
    @State private var text: String
    @State private var width: Double
    @State private var height: Double
    @State private var rotation: Double

    init(element: VisionBoardElement) {
        self.element = element
        _text = State(initialValue: element.text)
        _width = State(initialValue: element.width)
        _height = State(initialValue: element.height)
        _rotation = State(initialValue: element.rotation)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Text", "Text"), text: $text, axis: .vertical)
                Slider(value: $width, in: 60...300) { Text(L("Breite", "Width")) }
                Slider(value: $height, in: 40...240) { Text(L("Höhe", "Height")) }
                Slider(value: $rotation, in: -180...180) { Text(L("Drehung", "Rotation")) }
                Button(L("Element löschen", "Delete element"), role: .destructive) {
                    context.delete(element)
                    try? context.save()
                    dismiss()
                }
            }
            .navigationTitle(L("Element", "Element"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        element.text = text
                        element.width = width
                        element.height = height
                        element.rotation = rotation
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BucketItemForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var details = ""
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var createReward = false
    @State private var rewardPrice = 500

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Wunsch", "Wish"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                Stepper("\(L("Zieljahr", "Target year")): \(year)", value: $year, in: 2000...2200)
                Toggle(L("Belohnung im Shop anlegen", "Create reward in shop"), isOn: $createReward)
                if createReward {
                    Stepper("\(L("Preis", "Price")): \(rewardPrice) 🪙", value: $rewardPrice, in: 0...100_000)
                }
            }
            .navigationTitle(L("Bucketlist", "Bucket list"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !title.isEmpty else { return }
                        let item = BucketListItem(title: title, details: details, targetYear: year)
                        if createReward {
                            let reward = RewardItem(title: title, details: details, price: rewardPrice, bucketListItemID: item.id)
                            item.linkedRewardID = reward.id
                            context.insert(reward)
                        }
                        context.insert(item)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
