import Foundation

/// 특정 시점의 가격 스냅샷
struct PriceRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let price: Int

    init(id: UUID = UUID(), date: Date = Date(), price: Int) {
        self.id = id
        self.date = date
        self.price = price
    }
}

/// Kream 상품 모델
struct KreamProduct: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var brand: String
    var imageURL: String
    var kreamURL: String
    var currentPrice: Int
    var targetPrice: Int
    var size: String
    var retailPrice: Int
    var lastNotifiedAt: Date?
    var priceHistory: [PriceRecord]

    init(
        id: UUID = UUID(),
        name: String,
        brand: String,
        imageURL: String = "",
        kreamURL: String = "",
        currentPrice: Int,
        targetPrice: Int,
        size: String,
        retailPrice: Int,
        lastNotifiedAt: Date? = nil,
        priceHistory: [PriceRecord] = []
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.imageURL = imageURL
        self.kreamURL = kreamURL
        self.currentPrice = currentPrice
        self.targetPrice = targetPrice
        self.size = size
        self.retailPrice = retailPrice
        self.lastNotifiedAt = lastNotifiedAt
        self.priceHistory = priceHistory
    }

    /// 현재가가 정가보다 저렴한지 여부 (크더싼 필터용)
    var isCheaperThanRetail: Bool {
        currentPrice < retailPrice
    }

    /// 목표가 도달 여부
    var hasReachedTarget: Bool {
        currentPrice <= targetPrice
    }
}
