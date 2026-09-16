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

    @State private var apiKey: String = APIKeyStore.load() ?? ""
    @State private var useOwnKey = CoachClient.proxyURL == nil || APIKeyStore.load() != nil
    @State private var editingKey = false
    @State private var keyDraft = ""
    @State private var editingProfile = false
    @State private var question = ""
    @State private var answer = ""
    @State private var errorText: String?
    @State private var isLoading = false

    private let calendar = Calendar.current

    private var canAsk: Bool {
        if useOwnKey { return !apiKey.isEmpty }
        return account.isSignedIn && account.isSubscribed
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if canAsk {
                    questionArea
                } else if useOwnKey {
                    keyEntry
                } else {
                    accessFlow
                }
            }
            .padding()
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Coach")
            .toolbar {
                Menu {
                    Button("Coach profile", systemImage: "person.text.rectangle") { editingProfile = true }
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

    // MARK: - Access

    private var accessFlow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A coach that knows your plan").font(.title3.weight(.semibold))
            Text("Ask what to do next, what to eat, or how the week is going. Answers use your blocks, your Apple Health data and your food log.")
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

    // MARK: - Ask

    private var questionArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What's next? What do I eat?", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }
            Button {
                Task { await send() }
            } label: {
                if isLoading { ProgressView().frame(maxWidth: .infinity) } else { Text("Ask").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || question.trimmingCharacters(in: .whitespaces).isEmpty)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            ScrollView {
                Text(answer.isEmpty ? "Ask about today's blocks, the gym session, or a meal." : answer)
                    .foregroundStyle(answer.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func send() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        let now = Date.now
        let blocks = DayLogic.sorted(plan.today(on: now, calendar: calendar))
        let client: CoachClient
        if useOwnKey {
            client = CoachClient(apiKey: apiKey)
        } else if let proxy = CoachClient.proxyURL, let token = account.sessionToken {
            client = CoachClient(proxy: proxy, sessionToken: token)
        } else {
            return
        }
        do {
            answer = try await client.ask(
                q,
                staticSystem: CoachProfile.load(),
                snapshot: CoachContext.snapshot(
                    blocks: blocks, now: now, completed: store.completed(on: now), calendar: calendar,
                    extra: [health.coachSummary(now: now, calendar: calendar), food.coachSummary(now: now), track.coachSummary(now: now), wardrobe.coachSummary()]
                )
            )
        } catch CoachClient.CoachError.http(401, _) where !useOwnKey {
            account.sessionRejected()
            errorText = "Session expired. Sign in again."
        } catch {
            errorText = error.localizedDescription
        }
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
