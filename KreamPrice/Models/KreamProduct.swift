//
//  KreamProduct.swift
//  KreamPrice
//
//  KREAM 한정판 거래 플랫폼 가격 추적 앱의 메인 상품 모델.
//  [CORE 1] basePrice / currentPrice / targetPrice 추적
//  [CORE 3] 결제 예상금액 계산 (검수비 1%, 배송비 3000)
//  [추가 4] retailPrice 대비 "크더싼" 판정
//  [추가 5] priceHistory 누적
//  [추가 7] size 필드로 사이즈별 분기 추적
//  [추가 8] lastNotifiedAt 으로 알림 쿨타임 제어
//  [추가 9] folder 릴레이션십으로 카테고리 분류
//

import Foundation
import SwiftData

// MARK: - KreamProduct Model

/// KREAM 상품 한 건을 나타내는 SwiftData 모델.
///
/// > 마이그레이션 주의: SwiftData 는 `@Model` 클래스 시그니처가 바뀌면 자동 마이그레이션이 실패할 수 있음.
/// > 필드를 추가하거나 타입을 변경할 때는 `VersionedSchema` + `SchemaMigrationPlan` 으로 명시적으로 처리할 것.
/// > 지금은 초기 스키마(v1) 이므로 기본 컨테이너로 충분하다.
@Model
final class KreamProduct {

    // MARK: - Stored Properties

    /// 상품명 (예: "Nike Dunk Low Retro White Black")
    var name: String

    /// 브랜드명 (예: "Nike")
    var brand: String

    /// 사이즈 태그 — [추가 기능 7] 사이즈별 가격 분기 추적용.
    /// 신발은 "270", 의류는 "L" 등 자유 입력.
    var size: String

    /// 공식 발매가 (retail price) — [추가 기능 4] "크더싼" 판정 기준.
    var retailPrice: Int

    /// 즐겨찾기를 추가한 시점에 스냅샷된 가격.
    /// 이후 현재가와 비교하여 변동폭을 계산한다.
    var basePrice: Int

    /// 가장 최근에 갱신된 실시간 가격.
    var currentPrice: Int

    /// 사용자가 직접 지정한 목표가 — [CORE 1] targetPrice 이하 도달 시 별도 알림.
    var targetPrice: Int

    /// KREAM 앱의 상품 ID — URL Scheme (`kream://products/{id}`) 연동용.
    var kreamId: String

    /// 상품 이미지 URL.
    var imageUrl: String

    /// 마지막 알림 발송 시각 — [추가 기능 8] 6시간 쿨타임 판단용.
    var lastNotifiedAt: Date?

    /// 상품 추가 시각.
    var addedAt: Date

    /// 마지막으로 현재가를 갱신한 시각 — [CORE 2] 대시보드 "마지막 갱신" 표기용.
    var lastPriceUpdatedAt: Date?

    /// [추가 기능 9] 소속 폴더. 없으면 "미분류" 로 간주.
    var folder: WishlistFolder?

    /// [추가 기능 5] 가격 히스토리. 상품 삭제 시 함께 삭제.
    @Relationship(deleteRule: .cascade, inverse: \PriceHistory.product)
    var priceHistory: [PriceHistory] = []

    // MARK: - Init

    init(
        name: String,
        brand: String,
        size: String,
        retailPrice: Int,
        basePrice: Int,
        currentPrice: Int,
        targetPrice: Int,
        kreamId: String,
        imageUrl: String,
        folder: WishlistFolder? = nil
    ) {
        self.name = name
        self.brand = brand
        self.size = size
        self.retailPrice = retailPrice
        self.basePrice = basePrice
        self.currentPrice = currentPrice
        self.targetPrice = targetPrice
        self.kreamId = kreamId
        self.imageUrl = imageUrl
        self.lastNotifiedAt = nil
        self.addedAt = .now
        self.lastPriceUpdatedAt = nil
        self.folder = folder
    }
}

// MARK: - Computed Helpers

extension KreamProduct {

    /// basePrice 대비 현재가 변동폭 (음수면 하락).
    var priceDelta: Int {
        currentPrice - basePrice
    }

    /// basePrice 대비 변동률(%). basePrice == 0 이면 0 반환.
    var priceDeltaRatio: Double {
        guard basePrice > 0 else { return 0 }
        return Double(priceDelta) / Double(basePrice) * 100.0
    }

    /// [추가 기능 4] "크더싼" 여부 — 현재가가 공식 발매가보다 낮으면 true.
    var isCheaperThanRetail: Bool {
        retailPrice > 0 && currentPrice < retailPrice
    }

    /// [CORE 1] 목표가에 도달했는지 여부.
    var hasReachedTarget: Bool {
        targetPrice > 0 && currentPrice <= targetPrice
    }

    /// [CORE 1] basePrice 보다 내려갔는지 여부.
    var isBelowBase: Bool {
        currentPrice < basePrice
    }

    // MARK: - [CORE 3] 결제 예상금액 계산

    /// 검수비 비율 — 크림 정책상 약 1%.
    static let inspectionFeeRate: Double = 0.01
    /// 배송비 — 통상 3,000원.
    static let shippingFee: Int = 3_000

    /// 검수비 (원 단위 반올림).
    var inspectionFee: Int {
        Int((Double(currentPrice) * Self.inspectionFeeRate).rounded())
    }

    /// 실제 결제 예상액 = 현재가 + 검수비 + 배송비.
    var estimatedTotalPrice: Int {
        currentPrice + inspectionFee + Self.shippingFee
    }
}
