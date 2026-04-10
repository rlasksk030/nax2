import SwiftUI

/// 현재가 vs 정가를 비교하여 보여주는 화면.
/// 각 상품마다 "크림에서 보기" 버튼을 제공합니다.
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

        VStack(alignment: .leading, spacing: 8) {
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

            kreamLinkButton(for: product)
        }
        .padding(.vertical, 4)
    }

    /// Kream 링크가 저장된 상품에 한해 "크림에서 보기" 버튼을 표시.
    @ViewBuilder
    private func kreamLinkButton(for product: KreamProduct) -> some View {
        if !product.kreamURL.isEmpty, let url = URL(string: product.kreamURL) {
            HStack {
                Spacer()
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("크림에서 보기")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }
}

#Preview {
    PriceComparisonView()
        .environmentObject(ProductStore())
}
