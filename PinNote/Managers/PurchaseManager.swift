import StoreKit
import Foundation

extension Notification.Name {
    static let pnPurchaseStateChanged = Notification.Name("pnPurchaseStateChanged")
    static let pnPurchaseError        = Notification.Name("pnPurchaseError")
    static let pnRestoreStateChanged  = Notification.Name("pnRestoreStateChanged")
}

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    let monthlyProductID  = "com.pinnote.pro.monthly"
    let lifetimeProductID = "com.pinnote.pro.lifetime"

    private let trialStartKey = "pnTrialStart"
    private let trialDuration: TimeInterval = 14 * 24 * 60 * 60  // 14 days

    @Published private(set) var isPro = false
    @Published private(set) var isRestoring = false
    @Published private(set) var purchaseError: String? = nil
    @Published private(set) var products: [String: Product] = [:]

    var monthlyDisplayPrice: String {
        products[monthlyProductID]?.displayPrice ?? NSLocalizedString("settings_price_loading", comment: "")
    }

    var lifetimeDisplayPrice: String {
        products[lifetimeProductID]?.displayPrice ?? NSLocalizedString("settings_price_loading", comment: "")
    }

    // MARK: - Trial

    var trialStartDate: Date {
        // UserDefaults = primary (per device, cleared on uninstall → fresh trial on new install)
        if let stored = UserDefaults.standard.object(forKey: trialStartKey) as? Date {
            return stored
        }
        // First launch on this device — start trial now
        let now = Date()
        UserDefaults.standard.set(now, forKey: trialStartKey)
        return now
    }

    /// Days left, rounded up (0 = expired)
    var trialDaysRemaining: Int {
        let remaining = trialDuration - Date().timeIntervalSince(trialStartDate)
        return max(0, Int(ceil(remaining / 86_400)))
    }

    var trialEndDate: Date {
        trialStartDate.addingTimeInterval(trialDuration)
    }

    var isTrialActive: Bool {
        !isPro && trialDaysRemaining > 0
    }

    func allowsProFeatures(at date: Date = Date()) -> Bool {
        isPro || date <= trialEndDate
    }

    /// 0.0 = just started, 1.0 = expired
    var trialProgress: Double {
        min(1.0, Date().timeIntervalSince(trialStartDate) / trialDuration)
    }

    // MARK: - Init

    private init() {
        _ = trialStartDate          // record start date on first launch
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
        Task { await listenForTransactions() }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: [monthlyProductID, lifetimeProductID])
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            NotificationCenter.default.post(name: .pnPurchaseStateChanged, object: nil)
        } catch {
            print("[Purchase] Product load failed: \(error)")
            purchaseError = NSLocalizedString("purchase_error_products_unavailable", comment: "")
            NotificationCenter.default.post(name: .pnPurchaseError, object: nil)
        }
    }

    // MARK: - Purchase

    func purchase(productID: String) async {
        do {
            let product = try await product(for: productID)
            guard let product else {
                print("[Purchase] Product not found: \(productID)")
                purchaseError = NSLocalizedString("purchase_error_products_unavailable", comment: "")
                NotificationCenter.default.post(name: .pnPurchaseError, object: nil)
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = NSLocalizedString("purchase_error_unverified", comment: "")
                    NotificationCenter.default.post(name: .pnPurchaseError, object: nil)
                    return
                }
                await tx.finish()
                isPro = true
                NotificationCenter.default.post(name: .pnPurchaseStateChanged, object: nil)
                // Do NOT call refreshEntitlements() here — it races against tx.finish()
                // and can flip isPro back to false before StoreKit settles.
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("[Purchase] Error: \(error)")
            purchaseError = NSLocalizedString("purchase_error_failed", comment: "")
            NotificationCenter.default.post(name: .pnPurchaseError, object: nil)
        }
    }

    private func product(for productID: String) async throws -> Product? {
        if let product = products[productID] {
            return product
        }
        let loaded = try await Product.products(for: [productID])
        if let product = loaded.first {
            products[productID] = product
            NotificationCenter.default.post(name: .pnPurchaseStateChanged, object: nil)
            return product
        }
        return nil
    }

    // MARK: - Restore

    func restore() async {
        isRestoring = true
        NotificationCenter.default.post(name: .pnRestoreStateChanged, object: nil)
        do {
            try await AppStore.sync()
        } catch {
            print("[Restore] AppStore.sync failed: \(error)")
            purchaseError = NSLocalizedString("purchase_error_restore_failed", comment: "")
            NotificationCenter.default.post(name: .pnPurchaseError, object: nil)
        }
        await refreshEntitlements()
        isRestoring = false
        NotificationCenter.default.post(name: .pnRestoreStateChanged, object: nil)
    }

    // MARK: - Entitlements

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.revocationDate == nil else { continue }
            if tx.productID == monthlyProductID || tx.productID == lifetimeProductID {
                active = true
                break
            }
        }
        if isPro != active {
            isPro = active
            NotificationCenter.default.post(name: .pnPurchaseStateChanged, object: nil)
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let tx) = result else { continue }
            if tx.productID == monthlyProductID || tx.productID == lifetimeProductID {
                await tx.finish()
                await refreshEntitlements()
            }
        }
    }
}
