import Foundation

/// 상품 목록을 보관하고 갱신하는 스토어
final class ProductStore: ObservableObject {
    @Published var products: [KreamProduct] = []

    init() {
        loadSamples()
    }

    // MARK: - CRUD

    func add(_ product: KreamProduct) {
        products.append(product)
    }

    func remove(id: UUID) {
        products.removeAll { $0.id == id }
    }

    func update(_ product: KreamProduct) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        products[idx] = product
    }

    // MARK: - Notification hook

    /// 목표가에 도달한 경우 NotificationService 에 알림을 요청하고
    /// 성공하면 lastNotifiedAt 을 갱신합니다.
    @discardableResult
    func checkPriceAndNotify(for id: UUID) -> Bool {
        guard let idx = products.firstIndex(where: { $0.id == id }) else { return false }
        var product = products[idx]
        guard product.hasReachedTarget else { return false }

        if let newDate = NotificationService.shared.tryNotify(product: product) {
            product.lastNotifiedAt = newDate
            products[idx] = product
            return true
        }
        return false
    }

    // MARK: - Sample data

    private func loadSamples() {
        let calendar = Calendar.current
        let today = Date()

        func history(base: Int, variances: [Int]) -> [PriceRecord] {
            variances.enumerated().map { (offset, variance) in
                let daysAgo = (variances.count - 1 - offset) * 2
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
                return PriceRecord(date: day, price: base + variance)
            }
        }

        products = [
            KreamProduct(
                name: "Air Force 1 '07",
                brand: "Nike",
                currentPrice: 133_000,
                targetPrice: 125_000,
                size: "270",
                retailPrice: 139_000,
                priceHistory: history(
                    base: 135_000,
                    variances: [0, -2_000, 1_500, -3_500, 2_500, -1_000, 500, -2_000]
                )
            ),
            KreamProduct(
                name: "Samba OG",
                brand: "adidas",
                currentPrice: 158_000,
                targetPrice: 140_000,
                size: "265",
                retailPrice: 149_000,
                priceHistory: history(
                    base: 160_000,
                    variances: [0, 3_000, -1_000, 2_500, -2_500, 500, -2_000, -2_000]
                )
            ),
            KreamProduct(
                name: "Dunk Low Panda",
                brand: "Nike",
                currentPrice: 145_000,
                targetPrice: 130_000,
                size: "275",
                retailPrice: 129_000,
                priceHistory: history(
                    base: 150_000,
                    variances: [0, -1_000, -2_000, 1_500, -500, -1_000, -500, -5_000]
                )
            )
        ]
    }
}
