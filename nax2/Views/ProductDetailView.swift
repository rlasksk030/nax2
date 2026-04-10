import SwiftUI
import Charts

/// 상품 상세 화면
/// - 결제 예상금액 계산기 (현재가 + 검수비 1% + 배송비 3,000원)
/// - Swift Charts 기반 가격 변동 꺾은선 그래프
struct ProductDetailView: View {
    let product: KreamProduct

    /// 고정 배송비
    private let shippingFee: Int = 3_000

    /// 검수비: 현재가의 1% (반올림)
    private var inspectionFee: Int {
        Int((Double(product.currentPrice) * 0.01).rounded())
    }

    /// 결제 예상금액
    private var estimatedPayment: Int {
        product.currentPrice + inspectionFee + shippingFee
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                calculatorCard
                chartCard
            }
            .padding()
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.brand)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(product.name)
                .font(.title2).bold()
            Text("사이즈 \(product.size)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            infoRow(label: "현재가", value: product.currentPrice, emphasized: true)
            infoRow(label: "정가", value: product.retailPrice)
            infoRow(label: "목표가", value: product.targetPrice)

            if let last = product.lastNotifiedAt {
                Text("마지막 알림: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Calculator

    private var calculatorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("결제 예상금액", systemImage: "creditcard.fill")
                .font(.headline)

            lineItem(title: "상품가", value: product.currentPrice)
            lineItem(title: "검수비 (1%)", value: inspectionFee)
            lineItem(title: "배송비", value: shippingFee)

            Divider()

            HStack {
                Text("총 결제금액")
                    .font(.subheadline).bold()
                Spacer()
                Text("\(estimatedPayment.formatted())원")
                    .font(.title3).bold()
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("가격 변동", systemImage: "chart.xyaxis.line")
                .font(.headline)

            if product.priceHistory.isEmpty {
                Text("기록된 가격 데이터가 없습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                Chart(product.priceHistory) { record in
                    LineMark(
                        x: .value("날짜", record.date),
                        y: .value("가격", record.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("날짜", record.date),
                        y: .value("가격", record.price)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value.formatted())원")
                .font(emphasized ? .title3 : .body)
                .fontWeight(emphasized ? .bold : .regular)
        }
    }

    private func lineItem(title: String, value: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value.formatted())원")
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack {
        ProductDetailView(
            product: KreamProduct(
                name: "Air Force 1 '07",
                brand: "Nike",
                currentPrice: 133_000,
                targetPrice: 125_000,
                size: "270",
                retailPrice: 139_000,
                priceHistory: [
                    PriceRecord(date: Date().addingTimeInterval(-86400 * 14), price: 138_000),
                    PriceRecord(date: Date().addingTimeInterval(-86400 * 10), price: 135_500),
                    PriceRecord(date: Date().addingTimeInterval(-86400 * 7), price: 136_000),
                    PriceRecord(date: Date().addingTimeInterval(-86400 * 3), price: 134_000),
                    PriceRecord(date: Date(), price: 133_000)
                ]
            )
        )
    }
}
