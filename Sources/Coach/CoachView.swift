import AuthenticationServices
import SwiftUI

struct CoachView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var health: HealthStore
    @Bindable var food: FoodStore
    @Bindable var track: TrackStore
    @Bindable var account: CoachAccount
    @Bindable var wardrobe: WardrobeStore
    @Bindable var agent: CoachAgent

    @State private var apiKey: String = APIKeyStore.load() ?? ""
    @State private var useOwnKey = CoachClient.proxyURL == nil || APIKeyStore.load() != nil
    @State private var editingKey = false
    @State private var keyDraft = ""
    @State private var editingProfile = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let calendar = Calendar.current
    private let suggestions = ["¿Qué toca ahora?", "¿Qué ceno hoy?", "¿Qué compro?", "Agrega 1 kg de arroz", "Mueve estudio a las 5 pm", "¿Qué me pongo?"]

    private var canAsk: Bool {
        if useOwnKey { return !apiKey.isEmpty }
        return account.isSignedIn && account.isSubscribed
    }

    var body: some View {
        NavigationStack {
            Group {
                if canAsk {
                    chat
                } else if useOwnKey {
                    keyEntry.padding()
                } else {
                    accessFlow.padding()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Coach")
            .toolbar {
                Menu {
                    Button("Coach profile", systemImage: "person.text.rectangle") { editingProfile = true }
                    Button("Clear chat", systemImage: "trash") { agent.chat.clear() }
                    if CoachClient.proxyURL != nil {
                        Toggle("Use my own API key", isOn: $useOwnKey)
                    }
                    if useOwnKey && !apiKey.isEmpty {
                        Button("Change API key", systemImage: "key") { keyDraft = ""; editingKey = true }
                    }
                    if account.isSignedIn {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { account.signOut() }
                    }
                    if CoachClient.proxyURL != nil {
                        Button("Restore purchases") { Task { await account.restore() } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .sheet(isPresented: $editingProfile) { ProfileEditor() }
            .sheet(isPresented: $editingKey) { keySheet }
            .task { if CoachClient.proxyURL != nil { await account.loadProduct() } }
        }
    }

    // MARK: - Chat

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if agent.chat.entries.isEmpty { emptyState }
                        ForEach(agent.chat.entries) { entry in bubble(entry).id(entry.id) }
                        if agent.isBusy {
                            HStack(spacing: 8) { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
                                .padding(.horizontal, 4).id("busy")
                        }
                        if let error = agent.lastError {
                            Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 4)
                        }
                    }
                    .padding()
                }
                .onChange(of: agent.chat.entries.count) { _, _ in
                    withAnimation { proxy.scrollTo(agent.chat.entries.last?.id, anchor: .bottom) }
                }
                .onChange(of: agent.isBusy) { _, busy in
                    if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask or tell the coach…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(agent.isBusy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
            }
            .padding(10)
            .background(.bar)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your coach knows today's plan, your training, food, study and closet — and can change them.")
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { draft = s; send() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func bubble(_ entry: ChatEntry) -> some View {
        switch entry.role {
        case .user:
            HStack { Spacer(minLength: 60)
                Text(entry.text).padding(10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
            }
        case .assistant:
            HStack { Text(entry.text).padding(10).textSelection(.enabled)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 40) }
        case .tool:
            Label(entry.text, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
    }

    private func send() {
        let text = draft
        draft = ""
        let client: CoachClient
        if useOwnKey {
            client = CoachClient(apiKey: apiKey)
        } else if let proxy = CoachClient.proxyURL, let token = account.sessionToken {
            client = CoachClient(proxy: proxy, sessionToken: token)
        } else {
            return
        }
        Task {
            await agent.send(text, client: client, systemBlocks: systemBlocks())
            if let error = agent.lastError, error.hasPrefix("API error 401"), !useOwnKey {
                account.sessionRejected()
            }
        }
    }

    private func systemBlocks() -> [[String: Any]] {
        let now = Date.now
        let blocks = DayLogic.sorted(plan.today(on: now, calendar: calendar))
        let snapshot = CoachContext.snapshot(
            blocks: blocks, now: now, completed: store.completed(on: now), calendar: calendar,
            extra: [health.coachSummary(now: now, calendar: calendar), food.coachSummary(now: now), track.coachSummary(now: now), wardrobe.coachSummary()]
        )
        return [
            ["type": "text", "text": CoachProfile.load() + CoachContext.agentRules, "cache_control": ["type": "ephemeral"]],
            ["type": "text", "text": snapshot],
        ]
    }

    // MARK: - Access

    private var accessFlow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A coach that knows your plan").font(.title3.weight(.semibold))
            Text("Ask what to do next, what to eat, or tell it to change your day, pantry or closet.")
                .foregroundStyle(.secondary)
            if !account.isSignedIn, let proxy = CoachClient.proxyURL {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    Task { await account.handleSignIn(result, proxy: proxy) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
            } else if !account.isSubscribed {
                if let product = account.product {
                    Button {
                        Task { await account.purchase() }
                    } label: {
                        Text("Subscribe · \(product.displayPrice) / month").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    ProgressView()
                }
                Button("Restore purchases") { Task { await account.restore() } }.font(.footnote)
            }
            if let error = account.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
            Spacer()
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anthropic API key").font(.headline)
            Text("Stored in the Keychain on this device only.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("sk-ant-…", text: $keyDraft)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { saveKey() }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var keySheet: some View {
        NavigationStack {
            Form {
                SecureField("sk-ant-…", text: $keyDraft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .navigationTitle("API key").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingKey = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveKey(); editingKey = false } }
            }
        }
    }

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        APIKeyStore.save(trimmed)
        apiKey = trimmed
        keyDraft = ""
    }
}

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = CoachProfile.load()

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(8)
                .navigationTitle("Coach profile").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { CoachProfile.save(text); dismiss() } }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Reset to template", role: .destructive) { text = CoachProfile.template }
                    }
                }
        }
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
