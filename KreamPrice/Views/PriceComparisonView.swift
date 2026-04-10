//
//  PriceComparisonView.swift
//  KreamPrice
//
//  [CORE 2] 실시간 가격 비교 대시보드.
//  - basePrice vs currentPrice 변동폭 / 변동률
//  - 하락 파랑 / 상승 빨강 강조
//  - 마지막 갱신 시각
//  - 총 하락 합계 / 총 상승 합계 요약
//  - [추가 기능 6] 월 예산 잔여 진행 바
//

import SwiftUI
import SwiftData

// MARK: - PriceComparisonView

struct PriceComparisonView: View {

    // MARK: - Queries

    @Query(sort: \KreamProduct.addedAt, order: .reverse)
    private var products: [KreamProduct]

    // MARK: - AppStorage (예산 설정)

    @AppStorage("budget.monthlyLimit") private var monthlyBudgetLimit: Int = 0

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService

    // MARK: - State

    @State private var isRefreshing = false

    // MARK: - Derived

    private var totalDropAmount: Int {
        products.reduce(0) { acc, p in
            let d = p.priceDelta
            return d < 0 ? acc + (-d) : acc
        }
    }

    private var totalRiseAmount: Int {
        products.reduce(0) { acc, p in
            let d = p.priceDelta
            return d > 0 ? acc + d : acc
        }
    }

    /// [추가 기능 6] 목표가 도달한 상품들의 합산 금액.
    private var targetReachedSpending: Int {
        products
            .filter { $0.hasReachedTarget }
            .reduce(0) { $0 + $1.estimatedTotalPrice }
    }

    private var lastUpdatedText: String {
        let latest = products.compactMap(\.lastPriceUpdatedAt).max()
        guard let latest else { return "갱신 이력 없음" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .short
        return "마지막 갱신 " + f.localizedString(for: latest, relativeTo: .now)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    budgetCard
                    productsList
                }
                .padding()
            }
            .navigationTitle("가격 비교")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("오늘의 변동 요약")
                    .font(.headline)
                Spacer()
                Text(lastUpdatedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                metricBox(
                    title: "하락 합계",
                    value: "-\(formatKRW(totalDropAmount))원",
                    symbol: "📉",
                    color: .blue
                )
                metricBox(
                    title: "상승 합계",
                    value: "+\(formatKRW(totalRiseAmount))원",
                    symbol: "📈",
                    color: .red
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    private func metricBox(title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(symbol) \(title)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Budget Card [추가 기능 6]

    @ViewBuilder
    private var budgetCard: some View {
        if monthlyBudgetLimit > 0 {
            let progress = min(1.0, Double(targetReachedSpending) / Double(monthlyBudgetLimit))
            let isOver = targetReachedSpending > monthlyBudgetLimit
            let remaining = max(0, monthlyBudgetLimit - targetReachedSpending)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("이달 예산")
                        .font(.headline)
                    Spacer()
                    if isOver {
                        Text("⚠︎ 예산 초과")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                ProgressView(value: progress)
                    .tint(isOver ? .red : .green)

                HStack {
                    Text("목표가 도달: \(formatKRW(targetReachedSpending))원")
                        .font(.caption)
                    Spacer()
                    Text("한도: \(formatKRW(monthlyBudgetLimit))원")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(isOver
                     ? "한도를 \(formatKRW(targetReachedSpending - monthlyBudgetLimit))원 초과했어요."
                     : "잔여 \(formatKRW(remaining))원")
                    .font(.caption2)
                    .foregroundStyle(isOver ? .red : .secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        } else {
            EmptyView()
        }
    }

    // MARK: - Products List

    @ViewBuilder
    private var productsList: some View {
        if products.isEmpty {
            Text("등록된 상품이 없어요.\n즐겨찾기 탭에서 상품을 추가해주세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 32)
        } else {
            VStack(spacing: 10) {
                ForEach(products) { product in
                    comparisonRow(product: product)
                }
            }
        }
    }

    private func comparisonRow(product: KreamProduct) -> some View {
        let delta = product.priceDelta
        let color: Color = delta < 0 ? .blue : (delta > 0 ? .red : .secondary)

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(product.brand) · [\(product.size)]")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(formatKRW(product.currentPrice))원")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(deltaText(for: product))
                    .font(.caption2)
                    .foregroundStyle(color)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func deltaText(for product: KreamProduct) -> String {
        let delta = product.priceDelta
        let ratio = product.priceDeltaRatio
        let sign = delta > 0 ? "+" : ""
        let arrow = delta < 0 ? "📉" : (delta > 0 ? "📈" : "⏸")
        return "\(arrow) \(sign)\(formatKRW(delta))원 (\(sign)\(String(format: "%.1f", ratio))%)"
    }

    // MARK: - Actions

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let service = PriceUpdateService(
            modelContext: modelContext,
            notificationService: notificationService
        )
        await service.refreshAllProducts()
    }

    // MARK: - Helpers

    private func formatKRW(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
