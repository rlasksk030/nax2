import Foundation
import SwiftData

// MARK: - 가격 갱신 서비스 [CORE 1] [CORE 2]
// 앱 실행 시 모든 즐겨찾기 상품의 현재가를 갱신하고
// 가격 히스토리를 누적 저장한 뒤 알림 조건을 확인합니다.
//
// ⚠️ 실제 KREAM API 비공개 정책:
// KREAM은 공개 API를 제공하지 않습니다.
// 실제 서비스 시 웹뷰 스크래핑 또는 KREAM 파트너 API 계약이 필요합니다.
// 현재 구현은 시뮬레이션 모드로 동작합니다.

@MainActor
final class PriceUpdateService: ObservableObject {

    static let shared = PriceUpdateService()

    // MARK: - 상태
    @Published var isUpdating = false
    @Published var lastUpdatedAt: Date?
    @Published var updateError: String?

    private init() {}

    // MARK: - 전체 상품 일괄 갱신
    /// 앱 실행 시 또는 당겨서 새로고침 시 호출
    func refreshAll(products: [KreamProduct], modelContext: ModelContext) async {
        guard !isUpdating else { return }
        isUpdating = true
        updateError = nil

        defer { isUpdating = false }

        // 각 상품을 순차적으로 갱신 (API 요청 간 간격 두기)
        for product in products {
            await updateSingleProduct(product, modelContext: modelContext)
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms 간격
        }

        lastUpdatedAt = Date()
        print("✅ 전체 가격 갱신 완료 (\(products.count)개)")
    }

    // MARK: - 단일 상품 가격 갱신
    func updateSingleProduct(_ product: KreamProduct, modelContext: ModelContext) async {
        do {
            // 실제 구현에서는 fetchPriceFromKream(kreamId:)을 호출
            let newPrice = try await fetchCurrentPrice(for: product)

            let previousPrice = product.currentPrice

            // 현재가 업데이트
            product.currentPrice = newPrice
            product.lastUpdatedAt = Date()

            // 가격 히스토리 추가 [기능 5]
            recordPriceHistory(newPrice, for: product, in: modelContext)

            // 알림 조건 확인 [CORE 1]
            await checkAndNotify(
                product: product,
                previousPrice: previousPrice,
                newPrice: newPrice
            )

            try modelContext.save()

        } catch {
            print("가격 갱신 오류 (\(product.name)): \(error.localizedDescription)")
            updateError = error.localizedDescription
        }
    }

    // MARK: - 가격 히스토리 기록 [기능 5]
    private func recordPriceHistory(_ price: Int, for product: KreamProduct, in context: ModelContext) {
        let history = PriceHistory(price: price, recordedAt: Date())
        history.product = product
        product.priceHistory.append(history)
        context.insert(history)

        // 히스토리를 최대 90일치만 유지 (오래된 데이터 자동 정리)
        pruneOldHistory(for: product, in: context)
    }

    /// 90일 이전 히스토리 삭제
    private func pruneOldHistory(for product: KreamProduct, in context: ModelContext) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let oldRecords = product.priceHistory.filter { $0.recordedAt < cutoffDate }
        for record in oldRecords {
            context.delete(record)
        }
    }

    // MARK: - 알림 조건 확인 [CORE 1]
    private func checkAndNotify(
        product: KreamProduct,
        previousPrice: Int,
        newPrice: Int
    ) async {
        let notificationService = NotificationService.shared

        // 조건 1: basePrice보다 내려간 경우 (+ 이전보다도 내려간 경우)
        if newPrice < product.basePrice && newPrice < previousPrice {
            await notificationService.sendPriceDropNotification(for: product)
        }

        // 조건 2: 목표가 이하로 처음 진입한 경우
        if product.targetPrice > 0,
           newPrice <= product.targetPrice,
           previousPrice > product.targetPrice {
            await notificationService.sendTargetPriceReachedNotification(for: product)
        }
    }

    // MARK: - 가격 fetch (실제 API 연동 포인트)
    private func fetchCurrentPrice(for product: KreamProduct) async throws -> Int {
        // ✅ 실제 KREAM API 연동 시 이 함수를 교체하세요.
        // 예시: URLSession을 사용한 웹 API 호출
        //
        // guard let url = URL(string: "https://kream.co.kr/api/products/\(product.kreamId)") else {
        //     throw URLError(.badURL)
        // }
        // let (data, _) = try await URLSession.shared.data(from: url)
        // let response = try JSONDecoder().decode(KreamProductResponse.self, from: data)
        // return response.currentPrice

        // 현재: 시뮬레이션 모드 (-5% ~ +5% 랜덤 변동)
        return simulatedPrice(for: product)
    }

    // MARK: - 시뮬레이션 가격 생성 (개발/테스트용)
    /// 기준가 기준 ±5% 범위에서 1,000원 단위 랜덤 가격
    private func simulatedPrice(for product: KreamProduct) -> Int {
        let changeRate = Double.random(in: -0.05...0.05)
        let rawPrice = Double(product.basePrice) * (1.0 + changeRate)
        return (Int(rawPrice) / 1_000) * 1_000  // 1,000원 단위 절사
    }

    // MARK: - 마지막 갱신 시각 표시 문자열
    var lastUpdatedString: String {
        guard let date = lastUpdatedAt else { return "아직 갱신되지 않음" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - KREAM API 응답 모델 (실제 연동 시 사용)
// private struct KreamProductResponse: Codable {
//     let currentPrice: Int
//     let name: String
// }
