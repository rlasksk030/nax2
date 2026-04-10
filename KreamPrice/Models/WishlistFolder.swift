//
//  WishlistFolder.swift
//  KreamPrice
//
//  [추가 기능 9] 위시리스트 폴더 / 카테고리 분류.
//  사용자가 폴더명을 직접 만들어 상품을 분류할 수 있다.
//  폴더별 총 예상 지출액을 자동 합산하여 표시.
//

import Foundation
import SwiftData

// MARK: - WishlistFolder Model

@Model
final class WishlistFolder {

    // MARK: - Stored Properties

    /// 폴더명 (예: "이번달 목표", "언젠간 살것들", "생일 선물 후보")
    var name: String

    /// 폴더 생성 시각.
    var createdAt: Date

    /// 폴더에 속한 상품들. 상품 삭제 시 폴더 연결만 해제(nullify).
    @Relationship(deleteRule: .nullify, inverse: \KreamProduct.folder)
    var products: [KreamProduct] = []

    // MARK: - Init

    init(name: String) {
        self.name = name
        self.createdAt = .now
    }
}

// MARK: - Aggregations

extension WishlistFolder {

    /// 폴더 내 모든 상품의 결제 예상금액 합산.
    var totalEstimatedSpending: Int {
        products.reduce(0) { $0 + $1.estimatedTotalPrice }
    }

    /// 폴더 내 상품 중 목표가 도달한 상품들의 결제 예상금액 합산.
    /// [추가 기능 6] 예산 한도 초과 경고에 사용.
    var totalEstimatedTargetReached: Int {
        products
            .filter { $0.hasReachedTarget }
            .reduce(0) { $0 + $1.estimatedTotalPrice }
    }
}
