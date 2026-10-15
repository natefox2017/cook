// Developer: gengyun
// Purpose: Standalone context upgrade component showing remaining quota, reset time and the upgrade prompt for one capability.

import RecipeCore
import SwiftUI

/// Self-contained capability gate component. Features embed this next to a gated action to show
/// the remaining quota/reset time and, when required, route the upgrade through `UpgradeRouter`.
struct RecipeUpgradeContextView: View {
    let capability: RecipeCapability
    /// Optional stable pending operation id to resume the original action after upgrade.
    var pendingID: String? = nil

    @Environment(RecipeAccessStore.self) private var access
    @Environment(UpgradeRouter.self) private var router

    var body: some View {
        Group {
            if router.requiresUpgrade(capability) {
                upgradePrompt
            } else if let context = quotaContext {
                Text(context)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var upgradePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RecipeLanguage.localized("This feature is part of Recipe Pals Premium."))
                .font(.subheadline)
            Button {
                if let pendingID {
                    router.showUpgrade(capability: capability, pendingID: pendingID)
                }
            } label: {
                Text(RecipeLanguage.localized("Upgrade"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var quotaContext: String? {
        guard let quota = access.access(for: capability)?.quota else {
            return nil
        }
        let remaining = quota.remaining
        if let resetDate = access.resetAt(for: capability) {
            let reset = resetDate.formatted(date: .abbreviated, time: .shortened)
            return RecipeLanguage.localized(
                "%d remaining · resets %@", remaining, reset)
        }
        return RecipeLanguage.localized("%d remaining", remaining)
    }
}
