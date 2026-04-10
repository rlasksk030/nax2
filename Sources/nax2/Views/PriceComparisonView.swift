import SwiftUI
import SwiftData

// MARK: - 가격 비교 대시보드 [CORE 2]
// 기준가 vs 현재가 변동폭 및 변동률을 한눈에 비교합니다.
// 가격 하락 → 파란색, 상승 → 빨간색으로 강조합니다.

struct PriceComparisonView: View {

    // MARK: - SwiftData
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KreamProduct.addedAt, order: .reverse)
    private var products: [KreamProduct]

    // MARK: - 서비스
    @StateObject private var updateService = PriceUpdateService.shared

    // MARK: - 상태
    @State private var sortOption: SortOption = .biggestDrop
    @State private var showOnlyChanges = false

    // MARK: - 정렬 옵션
    private var sortedProducts: [KreamProduct] {
        var list = showOnlyChanges ? products.filter { $0.priceDelta != 0 } : products
        switch sortOption {
        case .biggestDrop:
            list.sort { $0.priceDelta < $1.priceDelta }  // 가장 많이 내린 순
        case .biggestRise:
            list.sort { $0.priceDelta > $1.priceDelta }  // 가장 많이 오른 순
        case .changeRate:
            list.sort { $0.priceChangeRate < $1.priceChangeRate }  // 변동률 낮은 순
        case .recentlyUpdated:
            list.sort { $0.lastUpdatedAt > $1.lastUpdatedAt }
        }
        return list
    }

    // MARK: - 요약 통계
    private var stats: DashboardStats {
        let drops = products.filter { $0.priceDelta < 0 }
        let rises = products.filter { $0.priceDelta > 0 }
        let targets = products.filter { $0.hasReachedTargetPrice }
        return DashboardStats(
            totalCount: products.count,
            dropCount: drops.count,
            riseCount: rises.count,
            targetReachedCount: targets.count,
            totalDropAmount: drops.reduce(0) { $0 + abs($1.priceDelta) }
        )
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                // 요약 통계 카드
                Section {
                    statsCardView
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // 마지막 갱신 시각 + 새로고침
                Section {
                    lastUpdatedRow
                }

                // 필터 & 정렬 옵션
                Section {
                    sortAndFilterRow
                }

                // 상품 목록
                Section("\(sortedProducts.count)개 상품") {
                    ForEach(sortedProducts) { product in
                        NavigationLink(destination: ProductDetailView(product: product)) {
                            PriceComparisonRow(product: product)
                        }
                    }
                }
            }
            .navigationTitle("가격 비교")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await updateService.refreshAll(
                    products: products,
                    modelContext: modelContext
                )
            }
        }
    }

    // MARK: - 요약 통계 카드
    private var statsCardView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatCard(
                    value: "\(stats.dropCount)",
                    label: "가격 하락",
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )
                Divider().frame(height: 60)
                StatCard(
                    value: "\(stats.riseCount)",
                    label: "가격 상승",
                    icon: "arrow.up.circle.fill",
                    color: .red
                )
                Divider().frame(height: 60)
                StatCard(
                    value: "\(stats.targetReachedCount)",
                    label: "목표가 달성",
                    icon: "target",
                    color: .green
                )
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))

            if stats.dropCount > 0 {
                HStack {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("총 \(KreamProduct.priceString(stats.totalDropAmount)) 절감 가능")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 마지막 갱신 행
    private var lastUpdatedRow: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
                .font(.caption)
            Text("마지막 갱신: \(updateService.lastUpdatedString)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if updateService.isUpdating {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("지금 갱신") {
                    Task {
                        await updateService.refreshAll(
                            products: products,
                            modelContext: modelContext
                        )
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - 정렬/필터 행
    private var sortAndFilterRow: some View {
        HStack {
            Picker("정렬", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Toggle("변동 있는 것만", isOn: $showOnlyChanges)
                .font(.caption)
                .toggleStyle(.button)
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - 가격 비교 행
struct PriceComparisonRow: View {

    let product: KreamProduct

    var body: some View {
        HStack(spacing: 12) {

            // 상품명 + 브랜드
            VStack(alignment: .leading, spacing: 3) {
                Text(product.brand)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(product.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if let size = product.displaySize {
                    Text("SIZE \(size)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            // 가격 비교 [CORE 2]
            VStack(alignment: .trailing, spacing: 4) {

                // 현재가 (색상 강조)
                Text(product.currentPriceString)
                    .font(.subheadline.bold())
                    .foregroundColor(product.priceDirection.color)

                // 기준가
                Text("기준 \(product.basePriceString)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .strikethrough(product.priceDelta != 0, color: .secondary)

                // 변동폭 + 변동률
                if product.priceDelta != 0 {
                    HStack(spacing: 3) {
                        Image(systemName: product.priceDirection.sfSymbol)
                            .font(.caption2)
                        Text(product.priceDeltaString)
                            .font(.caption2.bold())
                        Text("(\(product.priceChangeRateString))")
                            .font(.caption2)
                    }
                    .foregroundColor(product.priceDirection.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(product.priceDirection.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("변동 없음")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 통계 카드 컴포넌트
private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 요약 통계 구조체
private struct DashboardStats {
    let totalCount: Int
    let dropCount: Int
    let riseCount: Int
    let targetReachedCount: Int
    let totalDropAmount: Int
}

// MARK: - 정렬 옵션
private enum SortOption: String, CaseIterable, Identifiable {
    case biggestDrop = "biggest_drop"
    case biggestRise = "biggest_rise"
    case changeRate = "change_rate"
    case recentlyUpdated = "recently_updated"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .biggestDrop:       return "많이 내린 순"
        case .biggestRise:       return "많이 오른 순"
        case .changeRate:        return "변동률 낮은 순"
        case .recentlyUpdated:   return "최근 갱신 순"
        }
    }
}

#Preview {
    PriceComparisonView()
        .modelContainer(for: [KreamProduct.self, PriceHistory.self, WishlistFolder.self], inMemory: true)
}
