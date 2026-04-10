//
//  PriceHistory.swift
//  KreamPrice
//
//  [추가 기능 5] 가격 히스토리 그래프용 SwiftData 모델.
//  상품별로 가격 갱신 시점마다 (날짜 + 가격) 레코드를 누적한다.
//  Swift Charts 로 꺾은선 그래프를 그리고, 최저점에 별표 마커를 찍는다.
//

import Foundation
import SwiftData

// MARK: - PriceHistory Model

@Model
final class PriceHistory {

    // MARK: - Stored Properties

    /// 기록된 시점의 가격(원).
    var price: Int

    /// 기록 시각.
    var recordedAt: Date

    /// 소속 상품. KreamProduct.priceHistory 의 역참조.
    var product: KreamProduct?

    // MARK: - Init

    init(price: Int, recordedAt: Date = .now, product: KreamProduct? = nil) {
        self.price = price
        self.recordedAt = recordedAt
        self.product = product
    }
}
