// Developer: gengyun
// Purpose: Presents a consolidated weekly grocery preview and confirms an atomic append through an injected port.

import RecipeCore
import SwiftUI

/// A point-in-time copy of the plan and recipes that feed the preview. The
/// sheet never reads the store; the caller supplies and refreshes this snapshot.
struct WeeklyGrocerySnapshot {
    var entries: [MealPlanEntry]
    var recipes: [Recipe]
}

/// Injected atomic-append boundary. The store-backed implementation validates
/// the source revision, records the operation id in the same commit that
/// appends the rows, and returns an idempotent outcome. The sheet only reacts
/// to the outcome; it never mutates the grocery list directly.
typealias WeeklyGroceryAppendPort = (WeeklyGroceryAppendRequest) -> WeeklyGroceryAppendOutcome

struct WeeklyGroceryPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let calendar: Calendar
    private let weekDates: [Date]
    private let refresh: () -> WeeklyGrocerySnapshot
    private let append: WeeklyGroceryAppendPort

    @State private var snapshot: WeeklyGrocerySnapshot
    @State private var result: RecipeWeeklyGroceryPreview.BuildResult
    @State private var sourceSignature: String
    @State private var isConfirming = false
    @State private var errorMessage: String?
    @State private var staleNotice: String?

    init(
        calendar: Calendar,
        weekDates: [Date],
        snapshot: WeeklyGrocerySnapshot,
        refresh: @escaping () -> WeeklyGrocerySnapshot,
        append: @escaping WeeklyGroceryAppendPort
    ) {
        self.calendar = calendar
        self.weekDates = weekDates
        self.refresh = refresh
        self.append = append

        _snapshot = State(initialValue: snapshot)
        _result = State(
            initialValue: RecipeWeeklyGroceryPreview.build(
                entries: snapshot.entries,
                recipes: snapshot.recipes,
                weekDates: weekDates,
                calendar: calendar
            )
        )
        _sourceSignature = State(
            initialValue: RecipeWeeklyGroceryPreview.sourceSignature(
                entries: snapshot.entries,
                recipes: snapshot.recipes
            )
        )
    }

    private var keptCount: Int {
        result.lines.filter(\.isKept).count
    }

    var body: some View {
        NavigationStack {
            List {
                if let notice = staleNotice {
                    Section {
                        Label(notice, systemImage: "exclamationmark.circle")
                            .font(
                                RecipeTheme.text(
                                    15, weight: .regular, relativeTo: .subheadline
                                )
                            )
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(RecipeTheme.card)
                }

                if result.lines.isEmpty {
                    emptyState
                } else {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(result.lines.count) items")
                                .font(RecipeTheme.heading(.section))
                            Spacer()
                            Text("Uncheck anything you already have")
                                .font(
                                    RecipeTheme.text(
                                        15, weight: .regular, relativeTo: .subheadline
                                    )
                                )
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)
                    )

                    Section {
                        ForEach(result.lines) { line in
                            previewRow(line, isKept: keptBinding(for: line.id))
                        }
                    }
                    .listRowBackground(RecipeTheme.card)
                }

                if !result.missingRecipes.isEmpty {
                    Section {
                        Label(
                            "Some planned meals no longer have a recipe and were skipped.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(
                            RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline)
                        )
                        .foregroundStyle(.secondary)
                    }
                    .listRowBackground(RecipeTheme.card)
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
            .listSectionSpacing(RecipeSpacing.medium)
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .navigationTitle("Weekly Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .tint(RecipeTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        confirm()
                    } label: {
                        if isConfirming {
                            ProgressView()
                        } else {
                            Text("Add to Groceries")
                        }
                    }
                    .disabled(keptCount == 0 || isConfirming)
                }
            }
            .alert(
                "Couldn't add to groceries",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
        .interactiveDismissDisabled(isConfirming)
    }

    private var emptyState: some View {
        let title =
            result.missingRecipes.isEmpty
            ? "No meals planned this week"
            : "Planned meals are unavailable"
        let message =
            result.missingRecipes.isEmpty
            ? "Plan meals for the week to build a grocery list."
            : "The recipes for this week's meals were removed, so there is nothing to add."
        return EmptyStateView(
            title: title, message: message, systemImage: "basket"
        )
        .frame(maxWidth: .infinity, minHeight: 260)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func previewRow(
        _ line: RecipeWeeklyGroceryPreview.Line,
        isKept: Binding<Bool>
    ) -> some View {
        let kept = isKept.wrappedValue
        return HStack(alignment: .top, spacing: 12) {
            Button {
                isKept.wrappedValue.toggle()
            } label: {
                Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        kept ? RecipeTheme.accentForeground : Color.secondary
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                kept
                    ? LocalizedStringKey("Keep \(line.name)")
                    : LocalizedStringKey("Skip \(line.name), already have it")
            )

            VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                Text(line.name)
                    .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .body))
                    .strikethrough(!kept)
                    .foregroundStyle(kept ? Color.primary : Color.secondary)
                if !line.amountText.isEmpty {
                    Text(line.amountText)
                        .font(
                            RecipeTheme.text(
                                15, weight: .regular, relativeTo: .subheadline
                            )
                        )
                        .foregroundStyle(.secondary)
                }
                let summary = sourceSummary(for: line)
                if !summary.isEmpty {
                    Text(summary)
                        .font(
                            RecipeTheme.text(12, weight: .regular, relativeTo: .caption)
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    /// Binds a row's keep-state back into the editable preview result.
    private func keptBinding(for lineID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                result.lines.first(where: { $0.id == lineID })?.isKept ?? true
            },
            set: { newValue in
                guard let index = result.lines.firstIndex(where: { $0.id == lineID }) else {
                    return
                }
                result.lines[index].isKept = newValue
            }
        )
    }

    private func sourceSummary(
        for line: RecipeWeeklyGroceryPreview.Line
    ) -> String {
        line.sources.map { source in
            let slotName = String(
                localized: String.LocalizationValue(source.slot.rawValue),
                locale: RecipeLanguage.active
            )
            let title = source.recipeTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let label = title.isEmpty ? "Recipe" : title
            return "\(label) · \(dayLabel(source.date)) · \(slotName)"
        }.joined(separator: ", ")
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = RecipeLanguage.active
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func confirm() {
        guard !isConfirming else { return }
        let keptLines = result.lines.filter(\.isKept)
        guard !keptLines.isEmpty else { return }

        isConfirming = true
        defer { isConfirming = false }

        let items = keptLines.map(WeeklyGroceryAppendItem.init(line:))
        let operationID = RecipeWeeklyGroceryPreview.operationID(
            sourceSignature: sourceSignature, items: items
        )
        let request = WeeklyGroceryAppendRequest(
            operationID: operationID, items: items, sourceSignature: sourceSignature
        )

        switch append(request) {
        case .appended, .alreadyCommitted:
            dismiss()
        case .staleSource:
            rebuild()
        case .failed(let message):
            errorMessage = message
        }
    }

    /// The source changed after the preview was built. Rebuild from a fresh
    /// snapshot so the user re-confirms the current materials instead of
    /// silently appending stale ones.
    private func rebuild() {
        let fresh = refresh()
        snapshot = fresh
        result = RecipeWeeklyGroceryPreview.build(
            entries: fresh.entries,
            recipes: fresh.recipes,
            weekDates: weekDates,
            calendar: calendar
        )
        sourceSignature = RecipeWeeklyGroceryPreview.sourceSignature(
            entries: fresh.entries,
            recipes: fresh.recipes
        )
        staleNotice = "Your meal plan changed, so the preview was refreshed. Review and confirm again."
    }
}

/// Reference implementation of the injected append port. It rejects duplicate
/// operation ids, validates the source revision against the live plan, and
/// delegates the actual row insertion to an injected atomic store transaction.
///
/// The operation id is recorded after a successful append so a double-tap,
/// retry, or restart that repeats the same operation cannot append twice. The
/// store-backed transaction that records the id inside the library's single
/// commit belongs to the shared `RecipeStore` handover; this coordinator keeps
/// the dedup and revision gates independent of that wiring. That transaction
/// must reuse the existing grocery safe merge, which consolidates only exact
/// same-name/same-unit rows and never merges into already-checked rows.
@MainActor
final class WeeklyGroceryAppendCoordinator {
    private let defaults: UserDefaults
    private let liveSignature: () -> String
    private let atomicAppend: ([WeeklyGroceryAppendItem]) throws -> Void

    init(
        defaults: UserDefaults = .standard,
        liveSignature: @escaping () -> String,
        atomicAppend: @escaping ([WeeklyGroceryAppendItem]) throws -> Void
    ) {
        self.defaults = defaults
        self.liveSignature = liveSignature
        self.atomicAppend = atomicAppend
    }

    func append(_ request: WeeklyGroceryAppendRequest) -> WeeklyGroceryAppendOutcome {
        if committedOperationIDs.contains(request.operationID) {
            return .alreadyCommitted
        }
        guard liveSignature() == request.sourceSignature else {
            return .staleSource
        }
        do {
            try atomicAppend(request.items)
            record(request.operationID)
            return .appended
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private var committedOperationIDs: Set<UUID> {
        let strings = defaults.stringArray(forKey: Self.operationLogKey) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private func record(_ operationID: UUID) {
        var strings = defaults.stringArray(forKey: Self.operationLogKey) ?? []
        guard !strings.contains(operationID.uuidString) else { return }
        strings.append(operationID.uuidString)
        defaults.set(strings, forKey: Self.operationLogKey)
    }

    private static let operationLogKey = "recipe.weeklyGroceries.committedOperations"
}
