import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var isManagingSubscriptions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "leaf.circle.fill").font(.system(size: 64)).foregroundStyle(CookTheme.accent)
                Text("Cook Premium").font(CookTheme.title(34))
                Text("Keep automated imports and cloud sync available across your devices.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)

                switch subscriptions.state {
                case .active:
                    Label("Subscription active", systemImage: "checkmark.seal.fill").foregroundStyle(CookTheme.accent)
                    Button("Manage subscription") { isManagingSubscriptions = true }
                case .loading:
                    ProgressView("Checking subscription…")
                case .free, .unavailable:
                    ForEach(subscriptions.products, id: \.id) { product in
                        Button {
                            Task { await subscriptions.purchase(product) }
                        } label: {
                            VStack(spacing: 4) {
                                Text(product.displayName).font(.headline)
                                Text(product.displayPrice).font(.subheadline)
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(subscriptions.isWorking)
                    }
                    if subscriptions.products.isEmpty {
                        Text("Subscriptions are not available in this build yet.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Restore Purchases") { Task { await subscriptions.restore() } }
                        .frame(minHeight: 44)
                        .disabled(subscriptions.isWorking)
                }

                Link("Terms of Use", destination: URL(string:"https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("Prices, billing periods and introductory offers are supplied by the App Store.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24)
        }
        .background(CookTheme.canvas)
        .navigationTitle("Subscription")
        .manageSubscriptionsSheet(isPresented: $isManagingSubscriptions)
        .task { await subscriptions.load() }
        .alert("Subscription", isPresented: Binding(get:{subscriptions.message != nil},set:{if !$0{subscriptions.message=nil}})) {
            Button("OK",role:.cancel){subscriptions.message=nil}
        } message: { Text(subscriptions.message ?? "") }
    }
}
