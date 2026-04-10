import Foundation
import SwiftData

// MARK: - 위시리스트 폴더 모델 [기능 9]
// 사용자가 원하는 이름으로 폴더를 만들어 상품을 분류
// 예: "이번달 목표", "언젠간 살것들", "생일 선물 후보"
// KreamProduct.folder (Optional) 와 1:N 관계

@Model
final class WishlistFolder {

    // MARK: - 속성
    var name: String
    var createdAt: Date

    // inverse: \KreamProduct.folder — 폴더 삭제 시 상품의 folder를 nil로 설정 (nullify)
    @Relationship(deleteRule: .nullify, inverse: \KreamProduct.folder)
    var products: [KreamProduct]

    init(name: String) {
        self.name = name
        self.createdAt = Date()
        self.products = []
    }
}

// MARK: - 계산 속성
extension WishlistFolder {

    /// 폴더 내 상품들의 총 예상 결제금액
    var totalEstimatedPayment: Int {
        products.reduce(0) { $0 + $1.estimatedTotalPayment }
    }

    /// 목표가 도달 상품 수
    var targetReachedCount: Int {
        products.filter { $0.hasReachedTargetPrice }.count
    }

    /// 크더싼 상품 수
    var cheaperThanRetailCount: Int {
        products.filter { $0.isCheaperThanRetail }.count
    }

    /// 총 예상 결제금액 문자열
    var totalEstimatedPaymentString: String {
        KreamProduct.priceString(totalEstimatedPayment)
    }

    /// 상품 수 표시 문자열
    var productCountString: String {
        "\(products.count)개"
    }
}
