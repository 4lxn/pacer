import SwiftUI

struct CoachView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore

    @State private var apiKey: String = APIKeyStore.load() ?? ""
    @State private var editingKey = false
    @State private var keyDraft = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var errorText: String?
    @State private var isLoading = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coach").font(.title2.weight(.semibold))
            if apiKey.isEmpty || editingKey {
                keyEntry
            } else {
                questionArea
            }
        }
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
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
            HStack {
                Button("Save") {
                    let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    APIKeyStore.save(trimmed)
                    apiKey = trimmed
                    keyDraft = ""
                    editingKey = false
                }
                .buttonStyle(.borderedProminent)
                if editingKey {
                    Button("Cancel") { editingKey = false }
                }
            }
            Spacer()
        }
    }

    private var questionArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What's next? What do I eat?", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }
            HStack {
                Button {
                    Task { await send() }
                } label: {
                    if isLoading { ProgressView() } else { Text("Ask") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || question.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Change key") { editingKey = true }
                    .font(.caption)
            }
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
        do {
            let client = CoachClient(apiKey: apiKey)
            answer = try await client.ask(
                q,
                staticSystem: CoachContext.training,
                snapshot: CoachContext.snapshot(blocks: blocks, now: now, completed: store.completed(on: now), calendar: calendar)
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}
