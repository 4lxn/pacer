import PhotosUI
import SwiftUI
import UIKit

struct WardrobeView: View {
    @Bindable var wardrobe: WardrobeStore
    @Bindable var account: CoachAccount
    @State private var now = Date.now
    @State private var scanning = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showCamera = false
    @State private var scanError: String?
    @State private var isScanning = false
    @State private var draft: Garment?

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
                    Button("Take a photo", systemImage: "camera") { showCamera = true }
                }
                PhotosPicker(selection: $pickedItem, matching: .images) { Label("Choose a photo", systemImage: "photo") }
                Button("Add without photo", systemImage: "plus") {
                    draft = Garment(name: "", category: .top, color: "", warmth: 2, formality: .casual, washAfter: 1)
                }
            } label: { Image(systemName: "plus") }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in showCamera = false; if let image { Task { await scan(image) } } }
                .ignoresSafeArea()
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await scan(image)
                }
                pickedItem = nil
            }
        }
        .sheet(item: $draft) { g in
            GarmentForm(garment: g, image: pendingImage) { saved in
                wardrobe.add(saved, imageData: pendingImage?.jpegData(compressionQuality: 0.7))
                pendingImage = nil
            }
        }
        .overlay {
            if isScanning {
                ProgressView("Looking at the photo…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                    Button("Wear this") { wardrobe.wear(suggestion, now: now) }.buttonStyle(.borderedProminent)
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
                Text("Photograph your clothes; the coach names and files them.").foregroundStyle(.secondary)
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
                    Text("\(g.color) · warmth \(g.warmth) · \(g.formality.rawValue)" + (g.washAfter > 0 ? " · worn \(g.wearsSinceWash)/\(g.washAfter)" : ""))
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

    // MARK: - Scan

    private func scan(_ image: UIImage) async {
        isScanning = true
        scanError = nil
        defer { isScanning = false }
        let scaled = image.scaled(maxSide: 1024)
        pendingImage = scaled
        guard let jpeg = scaled.jpegData(compressionQuality: 0.7) else { return }
        let client: CoachClient?
        if let key = APIKeyStore.load(), !key.isEmpty {
            client = CoachClient(apiKey: key)
        } else if let proxy = CoachClient.proxyURL, let token = account.sessionToken, account.isSubscribed {
            client = CoachClient(proxy: proxy, sessionToken: token)
        } else {
            client = nil
        }
        var guess: GarmentGuess?
        if let client {
            do {
                guess = GarmentGuess.parse(try await client.describe(jpeg: jpeg, prompt: GarmentGuess.prompt))
                if guess == nil { scanError = "Couldn't read the garment; fill it in by hand." }
            } catch {
                scanError = error.localizedDescription
            }
        } else {
            scanError = "Set up the Coach (key or subscription) to auto-name clothes; filling in by hand."
        }
        let g = guess ?? GarmentGuess(name: "", category: .top, color: "", warmth: 2, formality: .casual)
        draft = Garment(name: g.name, category: g.category, color: g.color, warmth: g.warmth, formality: g.formality, washAfter: g.category.defaultWashAfter)
    }
}

struct GarmentForm: View {
    @State var garment: Garment
    let image: UIImage?
    let onSave: (Garment) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).frame(maxWidth: .infinity)
                }
                TextField("Name", text: $garment.name)
                Picker("Category", selection: $garment.category) {
                    ForEach(GarmentCategory.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .onChange(of: garment.category) { _, c in garment.washAfter = c.defaultWashAfter }
                TextField("Color", text: $garment.color)
                Picker("Warmth", selection: $garment.warmth) {
                    Text("Light").tag(1); Text("Mid").tag(2); Text("Warm").tag(3)
                }
                Picker("Style", selection: $garment.formality) {
                    ForEach(Formality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Wash after \(garment.washAfter) wear\(garment.washAfter == 1 ? "" : "s")" + (garment.washAfter == 0 ? " (never)" : ""), value: $garment.washAfter, in: 0...30)
            }
            .navigationTitle("New garment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var g = garment
                        if g.name.trimmingCharacters(in: .whitespaces).isEmpty { g.name = "\(g.color) \(g.category.rawValue)".trimmingCharacters(in: .whitespaces) }
                        onSave(g)
                        dismiss()
                    }
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
