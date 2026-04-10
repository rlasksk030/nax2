import Foundation
import SwiftData
import SwiftUI

// MARK: - 메인 상품 모델
// ⚠️ SwiftData 마이그레이션 주의사항:
// 프로덕션 배포 후 필드 추가/삭제 시 기존 스토어와 충돌합니다.
// 스키마 변경이 필요할 때는 반드시 VersionedSchema + SchemaMigrationPlan을 적용하세요.
// 개발 단계에서는 앱을 삭제 후 재설치하면 스키마 초기화됩니다.

@Model
final class KreamProduct {

    // MARK: - 기본 정보
    var name: String
    var brand: String
    var size: String           // [기능 7] 사이즈별 가격 추적 (예: "270", "M", "FREE")
    var imageUrl: String
    var kreamId: String        // KREAM 상품 ID (URL Scheme: kream://products/{kreamId})

    // MARK: - 가격 정보
    var retailPrice: Int       // [기능 4] 공식 발매가 (크더싼 필터 기준)
    var basePrice: Int         // 즐겨찾기 추가 시점의 기준가
    var currentPrice: Int      // 앱 실행 시마다 갱신되는 현재가
    var targetPrice: Int       // [기능 1] 사용자가 직접 설정한 목표가 (0이면 미설정)

    // MARK: - 메타데이터
    var addedAt: Date
    var lastUpdatedAt: Date
    var lastNotifiedAt: Date?  // [기능 8] 알림 쿨타임 관리용 (마지막 알림 발송 시각)

    // MARK: - 관계 (SwiftData Relationship)
    var folder: WishlistFolder?  // [기능 9] 위시리스트 폴더 (nullify: 폴더 삭제 시 nil)

    @Relationship(deleteRule: .cascade)
    var priceHistory: [PriceHistory]  // [기능 5] 가격 히스토리 (cascade: 상품 삭제 시 함께 삭제)

    init(
        name: String,
        brand: String,
        size: String = "",
        imageUrl: String = "",
        kreamId: String = "",
        retailPrice: Int = 0,
        basePrice: Int,
        targetPrice: Int = 0
    ) {
        self.name = name
        self.brand = brand
        self.size = size
        self.imageUrl = imageUrl
        self.kreamId = kreamId
        self.retailPrice = retailPrice
        self.basePrice = basePrice
        self.currentPrice = basePrice  // 최초에는 기준가 = 현재가
        self.targetPrice = targetPrice
        self.addedAt = Date()
        self.lastUpdatedAt = Date()
        self.lastNotifiedAt = nil
        self.folder = nil
        self.priceHistory = []
    }
}

// MARK: - 가격 계산 관련 computed properties
extension KreamProduct {

    /// 가격 변동폭 (음수: 하락, 양수: 상승)
    var priceDelta: Int {
        currentPrice - basePrice
    }

    /// 변동률 (%)
    var priceChangeRate: Double {
        guard basePrice > 0 else { return 0.0 }
        return Double(priceDelta) / Double(basePrice) * 100.0
    }

    /// [기능 4] 크더싼 여부 — 발매가보다 현재 리셀가가 저렴한 경우
    var isCheaperThanRetail: Bool {
        guard retailPrice > 0 else { return false }
        return currentPrice < retailPrice
    }

    /// [기능 1] 목표가 도달 여부
    var hasReachedTargetPrice: Bool {
        guard targetPrice > 0 else { return false }
        return currentPrice <= targetPrice
    }

    /// 가격 방향
    var priceDirection: PriceDirection {
        if priceDelta < 0 { return .down }
        if priceDelta > 0 { return .up }
        return .stable
    }
}

// MARK: - 결제 예상금액 관련 (CORE 3)
extension KreamProduct {

    /// 검수비 — 구매가의 약 1% (최소 1,000원)
    var inspectionFee: Int {
        max(1_000, Int(Double(currentPrice) * 0.01))
    }

    /// 배송비 고정 3,000원
    var shippingFee: Int { 3_000 }

    /// 최종 결제 예상금액 = 현재가 + 검수비 + 배송비
    var estimatedTotalPayment: Int {
        currentPrice + inspectionFee + shippingFee
    }
}

// MARK: - URL 관련
extension KreamProduct {

    /// KREAM 웹사이트 URL
    var kreamWebURL: URL? {
        guard !kreamId.isEmpty else { return nil }
        return URL(string: "https://kream.co.kr/products/\(kreamId)")
    }

    /// KREAM 앱 URL Scheme — 앱이 설치된 경우 바로 열기
    var kreamAppURL: URL? {
        guard !kreamId.isEmpty else { return nil }
        return URL(string: "kream://products/\(kreamId)")
    }
}

// MARK: - 표시 관련 helpers
extension KreamProduct {

    /// 숫자를 한국식 통화 문자열로 변환 (예: 150,000원)
    static func priceString(_ price: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: price)) ?? "\(price)"
        return "\(formatted)원"
    }

    /// 현재가 문자열
    var currentPriceString: String { KreamProduct.priceString(currentPrice) }

    /// 기준가 문자열
    var basePriceString: String { KreamProduct.priceString(basePrice) }

    /// 변동폭 문자열 (예: -15,000원 / +8,000원)
    var priceDeltaString: String {
        let prefix = priceDelta >= 0 ? "+" : ""
        return "\(prefix)\(KreamProduct.priceString(priceDelta))"
    }

    /// 변동률 문자열 (예: -3.5%)
    var priceChangeRateString: String {
        String(format: "%+.1f%%", priceChangeRate)
    }

    /// 사이즈 표시용 (빈 값이면 nil 반환)
    var displaySize: String? {
        size.trimmingCharacters(in: .whitespaces).isEmpty ? nil : size
    }
}

// MARK: - 가격 방향 열거형
enum PriceDirection: Sendable {
    case up, down, stable

    /// SwiftUI 색상
    var color: Color {
        switch self {
        case .up:     return .red
        case .down:   return .blue
        case .stable: return .secondary
        }
    }

    /// SF Symbol 아이콘 이름
    var sfSymbol: String {
        switch self {
        case .up:     return "arrow.up.right"
        case .down:   return "arrow.down.right"
        case .stable: return "minus"
        }
    }

    /// 이모지 아이콘
    var emoji: String {
        switch self {
        case .up:     return "📈"
        case .down:   return "📉"
        case .stable: return "➡️"
        }
    }
}
