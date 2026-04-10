import SwiftUI

/// 현재가 vs 정가를 비교하여 보여주는 화면
struct PriceComparisonView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        NavigationStack {
            List {
                if store.products.isEmpty {
                    Text("비교할 상품이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.products) { product in
                        priceRow(product)
                    }
                }
            }
            .navigationTitle("가격 비교")
        }
    }

    @ViewBuilder
    private func priceRow(_ product: KreamProduct) -> some View {
        let diff = product.retailPrice - product.currentPrice
        let percent: Double = product.retailPrice > 0
            ? Double(diff) / Double(product.retailPrice) * 100.0
            : 0.0
        let pctText = String(format: "%.1f", percent)

        VStack(alignment: .leading, spacing: 6) {
            Text(product.brand)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(product.name)
                .font(.headline)

            HStack {
                Text("현재가")
                Spacer()
                Text("\(product.currentPrice.formatted())원").bold()
            }

            HStack {
                Text("정가")
                Spacer()
                Text("\(product.retailPrice.formatted())원")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("차액")
                Spacer()
                Text("\(diff.formatted())원 (\(pctText)%)")
                    .foregroundStyle(diff > 0 ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PriceComparisonView()
        .environmentObject(ProductStore())
}
