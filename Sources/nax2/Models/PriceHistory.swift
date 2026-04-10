import Foundation
import SwiftData

// MARK: - 가격 히스토리 모델 [기능 5]
// 상품 가격을 갱신할 때마다 날짜 + 가격을 누적 저장하여 그래프에 활용
// KreamProduct.priceHistory 배열과 cascade 관계로 연결됨

@Model
final class PriceHistory {

    // MARK: - 속성
    var price: Int          // 기록 당시 가격
    var recordedAt: Date    // 기록 일시

    // KreamProduct와 역방향 참조 (SwiftData가 자동으로 inverse 추론)
    var product: KreamProduct?

    init(price: Int, recordedAt: Date = Date()) {
        self.price = price
        self.recordedAt = recordedAt
        self.product = nil
    }
}

// MARK: - 차트 데이터 관련
extension PriceHistory {

    /// 날짜 포맷 문자열 (차트 레이블용)
    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: recordedAt)
    }
}
