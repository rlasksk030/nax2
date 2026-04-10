import SwiftUI

/// 저장된 상품의 위시리스트를 보여주는 화면.
/// "크더싼" 토글을 켜면 현재가 < 정가인 상품만 필터링합니다.
struct WishlistView: View {
    @EnvironmentObject var store: ProductStore
    @State private var cheaperThanRetailOnly: Bool = false

    private var filteredProducts: [KreamProduct] {
        if cheaperThanRetailOnly {
            return store.products.filter { $0.currentPrice < $0.retailPrice }
        }
        return store.products
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if filteredProducts.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredProducts) { product in
                            NavigationLink(destination: ProductDetailView(product: product)) {
                                WishlistRow(product: product)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("위시리스트")
        }
    }

    private var filterBar: some View {
        Toggle(isOn: $cheaperThanRetailOnly) {
            VStack(alignment: .leading, spacing: 2) {
                Text("크더싼")
                    .font(.subheadline).bold()
                Text("정가보다 현재가가 저렴한 상품만 보기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(cheaperThanRetailOnly ? "크더싼 상품이 없습니다." : "저장된 상품이 없습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(at offsets: IndexSet) {
        let idsToRemove = offsets.map { filteredProducts[$0].id }
        store.products.removeAll { idsToRemove.contains($0.id) }
    }
}

private struct WishlistRow: View {
    let product: KreamProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(product.brand)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("사이즈 \(product.size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(product.name)
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text("\(product.currentPrice.formatted())원")
                    .font(.title3).bold()
                Spacer()
                Text("목표 \(product.targetPrice.formatted())원")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if product.isCheaperThanRetail {
                let diff = product.retailPrice - product.currentPrice
                Label("정가 대비 \(diff.formatted())원 저렴", systemImage: "arrow.down.right.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WishlistView()
        .environmentObject(ProductStore())
}
