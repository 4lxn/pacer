import PhotosUI
import SwiftUI
import UIKit

struct WardrobeView: View {
    @Bindable var wardrobe: WardrobeStore
    @Bindable var account: CoachAccount
    @State private var now = Date.now
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var scanError: String?
    @State private var queue: [UIImage] = []          // photos waiting to be scanned
    @State private var queueTotal = 0
    @State private var isScanning = false
    @State private var review: ReviewBatch?           // garments found in one photo, awaiting the user

    struct ReviewBatch: Identifiable {
        let id = UUID()
        let image: UIImage
        var garments: [Garment]
    }

    var body: some View {
        List {
            outfitSection
            laundrySection
            closetSection
        }
        .onAppear { now = .now }
        .toolbar {
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photos", systemImage: "camera") { showCamera = true }
                }
                PhotosPicker(selection: $pickedItems, maxSelectionCount: 10, matching: .images) { Label("Choose photos", systemImage: "photo.on.rectangle") }
                Button("Add by hand", systemImage: "plus") {
                    review = ReviewBatch(image: UIImage(), garments: [Garment(name: "", category: .top, color: "", warmth: 2, formality: .casual, washAfter: 1)])
                }
            } label: { Image(systemName: "plus") }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { enqueue([image]) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
                }
                pickedItems = []
                enqueue(images)
            }
        }
        .sheet(item: $review, onDismiss: { Task { await scanNext() } }) { batch in
            ReviewSheet(batch: batch, hasMore: !queue.isEmpty) { kept in
                let jpeg = batch.image.size == .zero ? nil : batch.image.jpegData(compressionQuality: 0.7)
                for g in kept { wardrobe.add(g, imageData: jpeg) }
            }
        }
        .overlay {
            if isScanning {
                ProgressView(queueTotal > 1 ? "Looking at photo \(queueTotal - queue.count) / \(queueTotal)…" : "Looking at the photo…")
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Sections

    private var outfitSection: some View {
        Section {
            Picker("Weather", selection: $wardrobe.weather) {
                ForEach(Weather.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Style", selection: $wardrobe.formality) {
                ForEach(Formality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            if let worn = wardrobe.todaysOutfit(now: now), !worn.isEmpty {
                Text("Wearing today: " + worn.map(\.name).joined(separator: ", ")).font(.subheadline)
            } else {
                let suggestion = wardrobe.suggestion(now: now)
                if suggestion.isEmpty {
                    Text("Add a top, a bottom and shoes to get an outfit.").foregroundStyle(.secondary)
                } else {
                    ForEach(suggestion) { garmentRow($0, compact: true) }
                    Button("Wear this") { wardrobe.wear(suggestion, now: now) }.buttonStyle(.glassProminent)
                }
            }
            if let scanError { Text(scanError).font(.footnote).foregroundStyle(.red) }
        } header: { Text("Today's outfit") }
    }

    @ViewBuilder
    private var laundrySection: some View {
        let pile = wardrobe.laundry
        if !pile.isEmpty {
            Section {
                ForEach(pile) { g in
                    HStack {
                        garmentRow(g, compact: true)
                        Spacer()
                        Button("Washed") { wardrobe.washed(id: g.id) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Button("Everything washed") { wardrobe.washAll() }
            } header: { Text("Laundry · \(pile.count)") }
        }
    }

    private var closetSection: some View {
        Section("Closet · \(wardrobe.closet.count)") {
            if wardrobe.closet.isEmpty {
                Text("Photograph your clothes — several per photo is fine — and the coach names and files them.").foregroundStyle(.secondary)
            }
            ForEach(GarmentCategory.allCases, id: \.self) { category in
                let items = wardrobe.closet.filter { $0.category == category }
                if !items.isEmpty {
                    Text(category.rawValue.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(items) { g in
                        garmentRow(g, compact: false)
                            .swipeActions {
                                Button(role: .destructive) { wardrobe.remove(id: g.id) } label: { Label("Delete", systemImage: "trash") }
                                Button { wardrobe.wear([g], now: now) } label: { Label("Wear", systemImage: "tshirt") }.tint(.accentColor)
                            }
                    }
                }
            }
        }
    }

    private func garmentRow(_ g: Garment, compact: Bool) -> some View {
        HStack(spacing: 10) {
            thumbnail(g)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).foregroundStyle(g.needsWash ? .red : .primary)
                if !compact {
                    Text("\(g.color)\(g.pattern == "solid" ? "" : " \(g.pattern)") · warmth \(g.warmth) · \(g.formality.rawValue)" + (g.washAfter > 0 ? " · worn \(g.wearsSinceWash)/\(g.washAfter)" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func thumbnail(_ g: Garment) -> some View {
        Group {
            if let url = wardrobe.imageURL(for: g), let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: icon(g.category)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func icon(_ c: GarmentCategory) -> String {
        switch c {
        case .top: "tshirt"
        case .bottom: "figure.walk"
        case .shoes: "shoe"
        case .outer: "cloud.snow"
        case .accessory: "eyeglasses"
        }
    }

    // MARK: - Scan queue

    private func enqueue(_ images: [UIImage]) {
        queue.append(contentsOf: images)
        queueTotal = queue.count
        if review == nil { Task { await scanNext() } }
    }

    private func scanNext() async {
        guard review == nil, !queue.isEmpty else { if queue.isEmpty { queueTotal = 0 }; return }
        let image = queue.removeFirst().scaled(maxSide: 1024)
        isScanning = true
        scanError = nil
        defer { isScanning = false }
        var guesses: [GarmentGuess] = []
        if let jpeg = image.jpegData(compressionQuality: 0.7), let client = visionClient() {
            do {
                guesses = GarmentGuess.parseMany(try await client.describe(jpeg: jpeg, prompt: GarmentGuess.prompt))
                if guesses.isEmpty { scanError = "Couldn't read the garment; fill it in by hand." }
            } catch {
                scanError = error.localizedDescription
            }
        } else if visionClient() == nil {
            scanError = "Set up the Coach (key or subscription) to auto-name clothes; filling in by hand."
        }
        let garments = guesses.isEmpty
            ? [Garment(name: "", category: .top, color: "", warmth: 2, formality: .casual, washAfter: 1)]
            : guesses.map { $0.garment() }
        review = ReviewBatch(image: image, garments: garments)
    }

    private func visionClient() -> CoachClient? {
        if let key = APIKeyStore.load(), !key.isEmpty { return CoachClient(apiKey: key) }
        if let proxy = CoachClient.proxyURL, let token = account.sessionToken, account.isSubscribed {
            return CoachClient(proxy: proxy, sessionToken: token)
        }
        return nil
    }
}

/// Everything the vision call found in one photo; each row is editable and can be dropped.
struct ReviewSheet: View {
    @State var batch: WardrobeView.ReviewBatch
    let hasMore: Bool
    let onSave: ([Garment]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if batch.image.size != .zero {
                    Image(uiImage: batch.image).resizable().scaledToFit().frame(maxHeight: 180).frame(maxWidth: .infinity)
                }
                ForEach($batch.garments) { $g in
                    Section {
                        TextField("Name", text: $g.name)
                        Picker("Category", selection: $g.category) {
                            ForEach(GarmentCategory.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        TextField("Color", text: $g.color)
                        Picker("Warmth", selection: $g.warmth) { Text("Light").tag(1); Text("Mid").tag(2); Text("Warm").tag(3) }
                        Picker("Style", selection: $g.formality) {
                            ForEach(Formality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Stepper("Wash after \(g.washAfter) wear\(g.washAfter == 1 ? "" : "s")" + (g.washAfter == 0 ? " (never)" : ""), value: $g.washAfter, in: 0...30)
                        if batch.garments.count > 1 {
                            Button("Not a garment / skip", role: .destructive) { batch.garments.removeAll { $0.id == g.id } }
                        }
                    } header: { Text(g.name.isEmpty ? "Garment" : g.name) }
                }
            }
            .navigationTitle(batch.garments.count > 1 ? "\(batch.garments.count) garments" : "New garment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip photo") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasMore ? "Save & next" : "Save") {
                        let kept = batch.garments.map { g -> Garment in
                            var c = g
                            if c.name.trimmingCharacters(in: .whitespaces).isEmpty { c.name = "\(c.color) \(c.category.rawValue)".trimmingCharacters(in: .whitespaces) }
                            return c
                        }
                        onSave(kept)
                        dismiss()
                    }
                    .disabled(batch.garments.isEmpty)
                }
            }
        }
    }
}

/// UIKit camera, because SwiftUI has no camera view.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}

extension UIImage {
    func scaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let ratio = maxSide / longest
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
