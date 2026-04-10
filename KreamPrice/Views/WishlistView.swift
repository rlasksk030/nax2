//
//  WishlistView.swift
//  KreamPrice
//
//  즐겨찾기 목록 — 앱의 핵심 화면.
//  - [추가 기능 4] "크더싼 상품만 보기" 토글 필터
//  - [추가 기능 9] 폴더별 그룹핑
//  - Pull-to-Refresh 로 가격 갱신 [CORE 1]
//  - NavigationLink 로 상세 화면 진입
//  - 상단 "+" 버튼으로 상품 추가 [CORE 1]
//

import SwiftUI
import SwiftData

// MARK: - WishlistView

struct WishlistView: View {

    // MARK: - SwiftData Queries

    @Query(sort: \KreamProduct.addedAt, order: .reverse)
    private var products: [KreamProduct]

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService

    // MARK: - UI State

    @State private var onlyCheaperThanRetail: Bool = false
    @State private var showingAddProduct: Bool = false
    @State private var isRefreshing: Bool = false

    // MARK: - Derived

    /// 필터 적용 후 남은 상품들.
    private var filteredProducts: [KreamProduct] {
        if onlyCheaperThanRetail {
            return products.filter { $0.isCheaperThanRetail }
        }
        return products
    }

    /// 그룹 한 블록 — ForEach 에서 안정적으로 식별되도록 문자열 id 포함.
    struct ProductGroup: Identifiable {
        let id: String          // "folder-<uuid>" 또는 "unclassified"
        let folder: WishlistFolder?
        let items: [KreamProduct]
    }

    /// 폴더별로 그룹핑된 상품. (nil 폴더 = "미분류")
    private var groupedProducts: [ProductGroup] {
        let items = filteredProducts
        let grouped = Dictionary(grouping: items, by: { $0.folder })
        // 폴더가 있는 그룹 먼저, 그 다음 미분류.
        let foldered: [ProductGroup] = grouped
            .compactMap { (key, value) -> ProductGroup? in
                guard let key else { return nil }
                return ProductGroup(
                    id: "folder-\(key.persistentModelID.hashValue)",
                    folder: key,
                    items: value
                )
            }
            .sorted { ($0.folder?.createdAt ?? .distantFuture) < ($1.folder?.createdAt ?? .distantFuture) }

        var result = foldered
        if let unclassified = grouped[nil], !unclassified.isEmpty {
            result.append(
                ProductGroup(id: "unclassified", folder: nil, items: unclassified)
            )
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if products.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("즐겨찾기")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $onlyCheaperThanRetail) {
                        Label("크더싼", systemImage: "tag.fill")
                    }
                    .toggleStyle(.button)
                    .tint(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddProduct = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddProduct) {
                AddProductView()
            }
            .refreshable {
                await refresh()
            }
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        List {
            ForEach(groupedProducts) { group in
                Section {
                    ForEach(group.items) { product in
                        NavigationLink(value: product) {
                            ProductRowView(product: product)
                        }
                    }
                    .onDelete { offsets in
                        delete(at: offsets, in: group.items)
                    }
                } header: {
                    HStack {
                        Text(group.folder?.name ?? "미분류")
                        Spacer()
                        if let folder = group.folder {
                            Text("합계 \(formatKRW(folder.totalEstimatedSpending))원")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: KreamProduct.self) { product in
            ProductDetailView(product: product)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("즐겨찾기가 비어있어요", systemImage: "heart.slash")
        } description: {
            Text("오른쪽 위 + 버튼으로 KREAM 상품을 추가해보세요.\n크림 앱에서 링크를 복사하면 자동으로 감지해요.")
        } actions: {
            Button("상품 추가하기") { showingAddProduct = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func delete(at offsets: IndexSet, in items: [KreamProduct]) {
        for idx in offsets {
            let product = items[idx]
            modelContext.delete(product)
        }
        try? modelContext.save()
    }

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
