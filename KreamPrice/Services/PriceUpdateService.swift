//
//  PriceUpdateService.swift
//  KreamPrice
//
//  [CORE 1] URLSession 으로 KREAM 상품 현재가를 갱신하는 서비스.
//  - 앱 foreground 복귀 시 호출
//  - BGTaskScheduler 로 주기 갱신 가능
//  - 갱신 결과에 따라 NotificationService 로 푸시 트리거
//  - 갱신 성공 시 PriceHistory 에 스냅샷 누적
//
//  ⚠️ KREAM 은 공식 공개 API 를 제공하지 않는다.
//     실제 앱에서는 웹 상품 페이지 HTML 스크래핑 또는
//     사내 프록시 서버를 두는 방식을 권장.
//     본 구현은 그 지점을 `fetchRemotePrice(for:)` 로 추상화했고,
//     기본 구현에서는 안전한 더미 로직(소폭 랜덤 변동)을 사용한다.
//     운영 배포 시 이 함수만 교체하면 된다.
//

import Foundation
import SwiftData

// MARK: - PriceUpdateResult

struct PriceUpdateResult: Sendable, Equatable {
    let productPersistentID: PersistentIdentifier
    let oldPrice: Int
    let newPrice: Int
    let didDropBelowBase: Bool
    let didReachTarget: Bool
}

// MARK: - PriceUpdateService

/// 가격 갱신 전담 서비스. MainActor 에서 ModelContext 에 접근하도록 격리.
@MainActor
final class PriceUpdateService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let notificationService: NotificationService
    private let session: URLSession

    // MARK: - Init

    init(
        modelContext: ModelContext,
        notificationService: NotificationService,
        session: URLSession = .shared
    ) {
        self.modelContext = modelContext
        self.notificationService = notificationService
        self.session = session
    }

    // MARK: - Public API

    /// 즐겨찾기에 등록된 모든 상품의 가격을 갱신한다.
    /// [CORE 1] + [CORE 2] + [추가 기능 5] + [추가 기능 8] 의 진입점.
    @discardableResult
    func refreshAllProducts() async -> [PriceUpdateResult] {
        // 즐겨찾기 전체를 가져온다.
        let descriptor = FetchDescriptor<KreamProduct>()
        guard let products = try? modelContext.fetch(descriptor), !products.isEmpty else {
            return []
        }

        var results: [PriceUpdateResult] = []
        results.reserveCapacity(products.count)

        for product in products {
            if let result = await refresh(product: product) {
                results.append(result)
            }
        }

        // 변경 사항 저장
        try? modelContext.save()
        return results
    }

    /// 개별 상품의 가격을 갱신하고, 히스토리 누적 및 알림 조건을 확인한다.
    @discardableResult
    func refresh(product: KreamProduct) async -> PriceUpdateResult? {
        let oldPrice = product.currentPrice

        // 원격 가격 조회 (실패 시 기존 값 유지)
        guard let remotePrice = await fetchRemotePrice(for: product) else {
            return nil
        }

        product.currentPrice = remotePrice
        product.lastPriceUpdatedAt = .now

        // [추가 기능 5] 히스토리 누적
        let history = PriceHistory(price: remotePrice, recordedAt: .now, product: product)
        modelContext.insert(history)
        product.priceHistory.append(history)

        let didDropBelowBase = remotePrice < product.basePrice
        let didReachTarget = product.targetPrice > 0 && remotePrice <= product.targetPrice

        // [CORE 1] + [추가 기능 8] 알림 조건 판단
        if didReachTarget {
            await notificationService.sendTargetReachedNotification(
                for: product,
                newPrice: remotePrice
            )
        } else if didDropBelowBase {
            await notificationService.sendPriceDropNotification(
                for: product,
                oldPrice: oldPrice,
                newPrice: remotePrice
            )
        }

        return PriceUpdateResult(
            productPersistentID: product.persistentModelID,
            oldPrice: oldPrice,
            newPrice: remotePrice,
            didDropBelowBase: didDropBelowBase,
            didReachTarget: didReachTarget
        )
    }

    // MARK: - Remote Fetch (Abstracted)

    /// KREAM 상품의 현재가를 가져온다.
    ///
    /// ⚠️ 운영 배포 시 실제 네트워크 호출로 교체할 것. 예:
    /// ```swift
    /// let url = URL(string: "https://api.myproxy.com/kream/\(product.kreamId)")!
    /// let (data, _) = try await session.data(from: url)
    /// let decoded = try JSONDecoder().decode(PriceDTO.self, from: data)
    /// return decoded.price
    /// ```
    ///
    /// 현재는 빌드 가능한 더미 구현으로, 기존 가격에서 ±3% 범위의 랜덤 변동을 돌려준다.
    /// 이렇게 하면 개발 중에도 [CORE 2] 대시보드와 [추가 기능 5] 그래프가 의미 있게 움직인다.
    private func fetchRemotePrice(for product: KreamProduct) async -> Int? {
        // 실 서비스에서는 여기를 교체
        let base = Double(product.currentPrice)
        guard base > 0 else { return nil }
        let delta = Double.random(in: -0.03...0.03)
        let next = Int((base * (1.0 + delta)).rounded())
        // 너무 작은 값 방지
        return max(next, 1_000)
    }
}
