import Charts
import SwiftUI

/// Money: what came in, what went out, what stayed.
struct MoneyContent: View {
    @Bindable var track: TrackStore
    var agent: CoachAgent? = nil
    @State private var now = Date.now
    @State private var addingExpense = false
    @State private var addingIncome = false
    @State private var editingBudget: String?
    @State private var budgetDraft = ""
    @State private var editingIncomeGoal = false
    @State private var incomeGoalDraft = ""
    @State private var editingRecurring: RecurringEntry?
    @State private var addingRecurring = false

    private let calendar = Calendar.current
    private let tint = AppSection.money.tint
    private var currency: String { Locale.current.currency?.identifier ?? "MXN" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                budgetsCard
                trendCard
                incomeCard
                recurringCard
                recentCard
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { now = .now; track.applyRecurring(now: now) }
        .sheet(item: $editingRecurring) { r in RecurringForm(entry: r, currency: currency, categories: track.expenseCategories) { track.upsertRecurring($0); track.applyRecurring(now: now) } onDelete: { track.deleteRecurring(id: $0) } }
        .sheet(isPresented: $addingRecurring) { RecurringForm(entry: RecurringEntry(kind: .expense, name: "", amount: 0, dayOfMonth: 1), isNew: true, currency: currency, categories: track.expenseCategories) { track.upsertRecurring($0); track.applyRecurring(now: now) } onDelete: { _ in } }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let agent { Button { agent.queued = "Where did my money go this month, and what should I watch?" } label: { Label("Ask the coach", systemImage: "sparkles") } }
                Button { addingIncome = true } label: { Label("Add income", systemImage: "plus.circle") }
                Button { addingExpense = true } label: { Label("Add expense", systemImage: "minus.circle") }
            }
        }
        .sheet(isPresented: $addingExpense) { ExpenseForm(currency: currency, categories: track.expenseCategories) { track.addExpense(category: $0, amount: $1, note: $2, on: $3) } }
        .sheet(isPresented: $addingIncome) { IncomeForm(currency: currency) { track.addIncome(source: $0, amount: $1, on: $2) } }
        .alert("Budget for \(editingBudget ?? "") (\(currency) / month)", isPresented: Binding(get: { editingBudget != nil }, set: { if !$0 { editingBudget = nil } })) {
            TextField("Amount", text: $budgetDraft).keyboardType(.decimalPad)
            Button("Save") { if let c = editingBudget { track.setBudget(Decimal(string: budgetDraft.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0, category: c) }; editingBudget = nil }
            Button("Cancel", role: .cancel) { editingBudget = nil }
        }
        .alert("Monthly income goal (\(currency))", isPresented: $editingIncomeGoal) {
            TextField("Amount", text: $incomeGoalDraft).keyboardType(.decimalPad)
            Button("Save") { track.monthlyIncomeGoal = Decimal(string: incomeGoalDraft.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
            Button("Cancel", role: .cancel) {}
        }
        .animation(.snappy, value: track.expenses.count)
        .animation(.snappy, value: track.income.count)
    }

    // MARK: - Hero

    private var hero: some View {
        let income = track.incomeTotal(monthOf: now), spent = track.expenseTotal(monthOf: now), saved = track.saved(monthOf: now)
        let rate = track.savingsRate(monthOf: now)
        let spentFraction = income > 0 ? min(1, NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: income).doubleValue) : (spent > 0 ? 1 : 0)
        return VStack(alignment: .leading, spacing: 14) {
            Text(now.formatted(.dateTime.month(.wide).year()).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(tint).tracking(0.5)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved, format: .currency(code: currency).precision(.fractionLength(0))).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    Text(saved >= 0 ? "saved so far" : "over income").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let rate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int((rate * 100).rounded()))%").font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(rate >= 0.2 ? .green : rate >= 0 ? tint : .red)
                        Text("savings rate").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule().fill(spentFraction >= 1 && income > 0 ? Color.red : Color(uiColor: .secondaryLabel).opacity(0.5)).frame(width: geo.size.width * spentFraction)
                }
            }
            .frame(height: 10)
            HStack {
                Label { Text(income, format: .currency(code: currency).precision(.fractionLength(0))) } icon: { Circle().fill(tint.opacity(0.4)).frame(width: 8, height: 8) }
                Text("in").foregroundStyle(.secondary)
                Spacer()
                Label { Text(spent, format: .currency(code: currency).precision(.fractionLength(0))) } icon: { Circle().fill(Color(uiColor: .secondaryLabel).opacity(0.6)).frame(width: 8, height: 8) }
                Text("out").foregroundStyle(.secondary)
            }
            .font(.caption).monospacedDigit()
            HStack(spacing: 10) {
                Button { addingExpense = true } label: { Label("Expense", systemImage: "minus").frame(maxWidth: .infinity) }.buttonStyle(.glass)
                Button { addingIncome = true } label: { Label("Income", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).tint(tint)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Budgets

    private var budgetsCard: some View {
        let rows = track.expensesByCategory(monthOf: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spending").font(.headline)
                Spacer()
                Text(track.expenseTotal(monthOf: now), format: .currency(code: currency).precision(.fractionLength(0))).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 4)
            if rows.isEmpty {
                Text("Log what you spend; tap a category to give it a monthly budget.").font(.subheadline).foregroundStyle(.secondary).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.category) { row in
                        let budget = track.budgets[row.category]
                        Button { editingBudget = row.category; budgetDraft = budget.map { "\($0)" } ?? "" } label: {
                            HStack(spacing: 12) {
                                Image(systemName: ExpenseCategory.symbol(row.category)).foregroundStyle(tint).frame(width: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(row.category).foregroundStyle(Color.primary)
                                        Spacer()
                                        Text(row.amount, format: .currency(code: currency).precision(.fractionLength(0))).monospacedDigit().foregroundStyle(Color.secondary)
                                        if let budget { Text("/ \(budget, format: .currency(code: currency).precision(.fractionLength(0)))").font(.caption).foregroundStyle(Color.secondary).monospacedDigit() }
                                    }
                                    if let budget, budget > 0 {
                                        let f = NSDecimalNumber(decimal: row.amount).doubleValue / NSDecimalNumber(decimal: budget).doubleValue
                                        ProgressView(value: min(1, f)).tint(f > 1 ? .red : f > 0.85 ? .orange : tint)
                                    }
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if row.category != rows.last?.category { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Trend

    private var trendCard: some View {
        let months = track.moneyByMonth(months: 6, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Last 6 months").font(.headline)
            Chart {
                ForEach(months, id: \.month) { m in
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("In", NSDecimalNumber(decimal: m.income).doubleValue), width: .ratio(0.35))
                        .foregroundStyle(by: .value("Kind", "In")).position(by: .value("Kind", "In")).cornerRadius(3)
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Out", NSDecimalNumber(decimal: m.spent).doubleValue), width: .ratio(0.35))
                        .foregroundStyle(by: .value("Kind", "Out")).position(by: .value("Kind", "Out")).cornerRadius(3)
                }
            }
            .chartForegroundStyleScale(["In": tint, "Out": Color(uiColor: .secondaryLabel).opacity(0.5)])
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow), centered: true) } }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .chartLegend(position: .bottom, spacing: 6)
            .frame(height: 140)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Income

    private var incomeCard: some View {
        let goal = track.monthlyIncomeGoal
        let total = track.incomeTotal(monthOf: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Income").font(.headline)
                Spacer()
                Text("Year \(track.incomeTotal(yearOf: now), format: .currency(code: currency).precision(.fractionLength(0)))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Button { incomeGoalDraft = goal > 0 ? "\(goal)" : ""; editingIncomeGoal = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(goal > 0 ? "Goal" : "Set a monthly goal").foregroundStyle(Color.primary)
                        Spacer()
                        Text(total, format: .currency(code: currency).precision(.fractionLength(0))).monospacedDigit().foregroundStyle(Color.secondary)
                        if goal > 0 { Text("/ \(goal, format: .currency(code: currency).precision(.fractionLength(0)))").font(.caption).monospacedDigit().foregroundStyle(Color.secondary) }
                    }
                    if goal > 0 {
                        ProgressView(value: min(1, NSDecimalNumber(decimal: total).doubleValue / max(1, NSDecimalNumber(decimal: goal).doubleValue))).tint(total >= goal ? .green : tint)
                    }
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            ForEach(track.incomeBySource(monthOf: now), id: \.source) { row in
                HStack {
                    Text(row.source).font(.subheadline)
                    Spacer()
                    Text(row.amount, format: .currency(code: currency).precision(.fractionLength(0))).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recurring

    private var recurringCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Every month").font(.headline)
                Spacer()
                Button { addingRecurring = true } label: { Image(systemName: "plus") }.buttonStyle(.glass).controlSize(.small)
            }
            .padding(.horizontal, 4)
            if track.recurring.isEmpty {
                Text("Salary, rent, subscriptions — add them once and they land on their day each month.").font(.subheadline).foregroundStyle(.secondary).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(track.recurring.sorted { $0.dayOfMonth < $1.dayOfMonth }) { r in
                        Button { editingRecurring = r } label: {
                            HStack(spacing: 12) {
                                Image(systemName: r.kind == .income ? "arrow.down.left.circle.fill" : ExpenseCategory.symbol(r.name)).foregroundStyle(r.kind == .income ? tint : .secondary).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).foregroundStyle(Color.primary)
                                    Text("day \(r.dayOfMonth)" + (r.note.isEmpty ? "" : " · \(r.note)")).font(.caption).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Text((r.kind == .income ? "+" : "−") + "\(r.amount.formatted(.currency(code: currency).precision(.fractionLength(0))))").monospacedDigit()
                                    .foregroundStyle(r.kind == .income ? tint : Color.primary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if r.id != track.recurring.sorted(by: { $0.dayOfMonth < $1.dayOfMonth }).last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Recent

    private enum Row: Identifiable {
        case income(IncomeEntry), expense(ExpenseEntry)
        var id: String { switch self { case .income(let e): "i-\(e.id)"; case .expense(let e): "e-\(e.id)" } }
        var date: Date { switch self { case .income(let e): e.date; case .expense(let e): e.date } }
    }

    private var recentCard: some View {
        let rows: [Row] = (track.incomeEntries(monthOf: now).map(Row.income) + track.expenses(monthOf: now).map(Row.expense)).sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            Text("This month").font(.headline).padding(.horizontal, 4)
            if rows.isEmpty {
                Text("Nothing logged this month yet.").font(.subheadline).foregroundStyle(.secondary).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            switch row {
                            case .income(let e):
                                Image(systemName: "arrow.down.left.circle.fill").foregroundStyle(tint).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.source)
                                    Text(e.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(e.amount, format: .currency(code: currency).precision(.fractionLength(0)))").monospacedDigit().foregroundStyle(tint)
                            case .expense(let e):
                                Image(systemName: ExpenseCategory.symbol(e.category)).foregroundStyle(.secondary).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.note.isEmpty ? e.category : e.note)
                                    Text("\(e.category) · \(e.date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("−\(e.amount, format: .currency(code: currency).precision(.fractionLength(0)))").monospacedDigit()
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                switch row { case .income(let e): track.deleteIncome(id: e.id); case .expense(let e): track.deleteExpense(id: e.id) }
                            }
                        }
                        if row.id != rows.last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct ExpenseForm: View {
    let currency: String
    let categories: [String]
    let onSave: (String, Decimal, String, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var category = ""
    @State private var custom = ""
    @State private var note = ""
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    private var value: Decimal? { Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(currency).foregroundStyle(.secondary)
                        TextField("0", text: $amount).keyboardType(.decimalPad).font(.system(size: 34, weight: .bold, design: .rounded)).focused($amountFocused)
                    }
                }
                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button {
                                category = c; custom = ""
                            } label: {
                                Label(c, systemImage: ExpenseCategory.symbol(c)).font(.caption.weight(.medium)).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
                                    .background(category == c ? AppSection.money.tint.opacity(0.18) : Color(uiColor: .tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(category == c ? AppSection.money.tint : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Or a new category", text: $custom).onChange(of: custom) { _, v in if !v.isEmpty { category = "" } }
                }
                Section {
                    TextField("Note (optional)", text: $note)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Expense").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value { onSave(custom.isEmpty ? category : custom.trimmingCharacters(in: .whitespaces), value, note, date) }
                        dismiss()
                    }
                    .disabled(value == nil || (category.isEmpty && custom.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .onAppear { amountFocused = true; category = categories.first ?? "Other" }
        }
    }
}


struct RecurringForm: View {
    @State var entry: RecurringEntry
    var isNew = false
    let currency: String
    let categories: [String]
    let onSave: (RecurringEntry) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $entry.kind) {
                    Text("Income").tag(RecurringEntry.Kind.income)
                    Text("Expense").tag(RecurringEntry.Kind.expense)
                }
                .pickerStyle(.segmented)
                TextField(entry.kind == .income ? "Source (Salary…)" : "Category (Rent, Bills…)", text: $entry.name)
                if entry.kind == .expense && !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(categories, id: \.self) { c in Button(c) { entry.name = c }.buttonStyle(.glass).controlSize(.small) } }
                    }
                }
                HStack { Text(currency).foregroundStyle(.secondary); TextField("Amount", text: $amount).keyboardType(.decimalPad) }
                Stepper("Day of month: \(entry.dayOfMonth)", value: $entry.dayOfMonth, in: 1...28)
                TextField("Note (optional)", text: $entry.note)
                if !isNew { Section { Button("Delete", role: .destructive) { onDelete(entry.id); dismiss() } } }
            }
            .navigationTitle(isNew ? "Every month" : entry.name).navigationBarTitleDisplayMode(.inline)
            .onAppear { amount = entry.amount > 0 ? "\(entry.amount)" : "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var e = entry
                        e.amount = Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0
                        onSave(e); dismiss()
                    }
                    .disabled(entry.name.trimmingCharacters(in: .whitespaces).isEmpty || (Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0) <= 0)
                }
            }
        }
    }
}
