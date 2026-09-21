import PhotosUI
import SwiftUI
import UIKit

struct WardrobeView: View {
    @Bindable var wardrobe: WardrobeStore
    @Bindable var account: CoachAccount
    var home: Place? = nil
    @State private var weather = WeatherNow()
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

    private let tint = AppSection.closet.tint

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                outfitCard
                laundryCard
                closetGrid
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { now = .now }
        .task(id: home?.id) {
            guard let home, let la = home.latitude, let lo = home.longitude else { return }
            await weather.refresh(latitude: la, longitude: lo)
            if let s = weather.summary, wardrobe.weather != s.bucket { wardrobe.weather = s.bucket }
        }
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

    // MARK: - Cards

    private var outfitCard: some View {
        let worn = wardrobe.todaysOutfit(now: now) ?? []
        let suggestion = worn.isEmpty ? wardrobe.suggestion(now: now) : worn
        return VStack(alignment: .leading, spacing: 14) {
            Text(worn.isEmpty ? "TODAY'S OUTFIT" : "WEARING TODAY").font(.caption2.weight(.bold)).foregroundStyle(tint).tracking(0.5)
            if let s = weather.summary {
                Label(s.line, systemImage: s.symbol).font(.subheadline).foregroundStyle(.secondary)
            } else if home?.isPinned != true {
                Text("Pin Home in Settings → Places to get today's weather here.").font(.caption).foregroundStyle(.secondary)
            }
            if suggestion.isEmpty {
                Text("Add a top, a bottom and shoes to get an outfit.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggestion) { g in
                            VStack(spacing: 6) {
                                thumbnail(g, size: 84)
                                Text(g.name).font(.caption).lineLimit(1).frame(width: 84)
                            }
                        }
                    }
                }
                if worn.isEmpty {
                    Button { wardrobe.wear(suggestion, now: now) } label: {
                        Label("Wear this", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent).tint(tint)
                    .sensoryFeedback(.success, trigger: wardrobe.outfits.count)
                }
            }
            HStack(spacing: 10) {
                Picker("Weather", selection: $wardrobe.weather) {
                    ForEach(Weather.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Style", selection: $wardrobe.formality) {
                    ForEach(Formality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let scanError { Text(scanError).font(.footnote).foregroundStyle(.red) }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .animation(.snappy, value: wardrobe.outfits.count)
    }

    @ViewBuilder
    private var laundryCard: some View {
        let pile = wardrobe.laundry
        if !pile.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Laundry", systemImage: "washer").font(.headline)
                    Text("\(pile.count)").font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Color(uiColor: .tertiarySystemFill), in: Capsule()).foregroundStyle(.secondary)
                    Spacer()
                    Button("All washed") { wardrobe.washAll() }.font(.subheadline).buttonStyle(.glass).controlSize(.small)
                }
                FlowLayout(spacing: 8) {
                    ForEach(pile) { g in
                        Button { wardrobe.washed(id: g.id) } label: {
                            Label(g.name, systemImage: "checkmark").font(.caption.weight(.medium)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                        .buttonStyle(.glass).controlSize(.small)
                    }
                }
                Text("Tap a piece when it's washed.").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var closetGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Closet").font(.headline)
                Text("\(wardrobe.closet.count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color(uiColor: .tertiarySystemFill), in: Capsule()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            if wardrobe.closet.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Photograph your clothes — several per photo is fine — and Pacer names and files them.").foregroundStyle(.secondary)
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Take photos", systemImage: "camera") }.buttonStyle(.glassProminent).tint(tint)
                        }
                        PhotosPicker(selection: $pickedItems, maxSelectionCount: 10, matching: .images) { Label("Choose photos", systemImage: "photo.on.rectangle") }.buttonStyle(.glass)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(GarmentCategory.allCases, id: \.self) { category in
                let items = wardrobe.closet.filter { $0.category == category }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.rawValue.capitalized).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                            ForEach(items) { g in
                                VStack(spacing: 4) {
                                    thumbnail(g, size: 72)
                                        .overlay(alignment: .topTrailing) {
                                            if g.needsWash { Image(systemName: "washer.fill").font(.caption2).padding(4).background(.red, in: Circle()).foregroundStyle(.white).offset(x: 4, y: -4) }
                                        }
                                    Text(g.name).font(.caption2).lineLimit(1)
                                }
                                .contextMenu {
                                    Button("Wear today", systemImage: "tshirt") { wardrobe.wear([g], now: now) }
                                    if g.needsWash { Button("Washed", systemImage: "checkmark") { wardrobe.washed(id: g.id) } }
                                    Button("Delete", systemImage: "trash", role: .destructive) { wardrobe.remove(id: g.id) }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func thumbnail(_ g: Garment, size: CGFloat = 36) -> some View {
        Group {
            if let url = wardrobe.imageURL(for: g), let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: icon(g.category)).font(.system(size: size * 0.4)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: size > 48 ? 14 : 8))
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
