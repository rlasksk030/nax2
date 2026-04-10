import SwiftUI
import SwiftData
import Charts

// MARK: - 상품 상세 화면
// 가격 히스토리 그래프, 결제 예상금액 계산기, 공유 기능,
// KREAM 앱 바로가기를 모두 제공합니다.

struct ProductDetailView: View {

    // MARK: - 데이터
    @Bindable var product: KreamProduct
    @Environment(\.modelContext) private var modelContext
    @StateObject private var updateService = PriceUpdateService.shared

    // MARK: - 상태
    @State private var chartPeriod: ChartPeriod = .week  // [기능 5] 그래프 기간
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var showEditTarget = false
    @State private var targetPriceText = ""

    // MARK: - 기간별 히스토리 필터 [기능 5]
    private var filteredHistory: [PriceHistory] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -chartPeriod.days, to: Date()) ?? Date()
        let sorted = product.priceHistory
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
        return sorted
    }

    private var chartMinPrice: Int {
        (filteredHistory.map(\.price).min() ?? product.currentPrice) - 5000
    }

    private var chartMaxPrice: Int {
        (filteredHistory.map(\.price).max() ?? product.currentPrice) + 5000
    }

    // 그래프에서 최저가 지점 [기능 5]
    private var lowestPoint: PriceHistory? {
        filteredHistory.min(by: { $0.price < $1.price })
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // 상품 헤더
                productHeader

                Divider()

                // 현재가 + 변동 요약
                priceOverviewSection

                // 가격 히스토리 그래프 [기능 5]
                priceHistoryChart

                Divider()

                // 결제 예상금액 계산기 [CORE 3]
                paymentCalculator

                Divider()

                // 목표가 설정/수정 [기능 1]
                targetPriceSection

                Divider()

                // 크더싼 정보 [기능 4]
                if product.retailPrice > 0 {
                    cheaperThanRetailSection
                }

                // 액션 버튼들
                actionButtons
            }
            .padding()
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    generateShareImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [image])
            }
        }
        .sheet(isPresented: $showEditTarget) {
            targetPriceEditSheet
        }
        .refreshable {
            await updateService.updateSingleProduct(product, modelContext: modelContext)
        }
    }

    // MARK: - 상품 헤더
    private var productHeader: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: product.imageUrl)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }
            .frame(width: 90, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(product.brand)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(product.name)
                    .font(.headline)
                    .lineLimit(3)

                // 사이즈 태그 [기능 7]
                if let size = product.displaySize {
                    Text("SIZE \(size)")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // 크더싼 배지 [기능 4]
                if product.isCheaperThanRetail {
                    Text("크더싼 🏷️")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    // MARK: - 현재가 + 변동 요약 [CORE 2]
    private var priceOverviewSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("현재가")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(product.currentPriceString)
                        .font(.largeTitle.bold())
                        .foregroundColor(product.priceDirection.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("기준가 대비")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: product.priceDirection.sfSymbol)
                        Text(product.priceDeltaString)
                    }
                    .font(.title3.bold())
                    .foregroundColor(product.priceDirection.color)

                    Text(product.priceChangeRateString)
                        .font(.subheadline)
                        .foregroundColor(product.priceDirection.color)
                }
            }

            HStack {
                Label("기준가: \(product.basePriceString)", systemImage: "bookmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Label(
                    "갱신: \(product.lastUpdatedAt.formatted(.relative(presentation: .named)))",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 가격 히스토리 그래프 [기능 5]
    @ViewBuilder
    private var priceHistoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("가격 히스토리")
                    .font(.headline)
                Spacer()
                // 기간 선택 탭
                Picker("기간", selection: $chartPeriod) {
                    ForEach(ChartPeriod.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            if filteredHistory.isEmpty {
                Text("아직 가격 이력이 없어요.\n앱을 열 때마다 누적됩니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
            } else {
                Chart {
                    ForEach(filteredHistory) { history in
                        // 꺾은선 그래프
                        LineMark(
                            x: .value("날짜", history.recordedAt),
                            y: .value("가격", history.price)
                        )
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.catmullRom)

                        // 데이터 포인트
                        PointMark(
                            x: .value("날짜", history.recordedAt),
                            y: .value("가격", history.price)
                        )
                        .foregroundStyle(
                            history.recordedAt == lowestPoint?.recordedAt ? Color.yellow : Color.blue
                        )
                        .symbolSize(
                            history.recordedAt == lowestPoint?.recordedAt ? 80 : 30
                        )
                        .annotation(position: .top) {
                            // 최저점에 별표 마커 표시 [기능 5]
                            if history.recordedAt == lowestPoint?.recordedAt {
                                VStack(spacing: 0) {
                                    Text("⭐")
                                        .font(.caption)
                                    Text("최저")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }

                    // 기준가 기준선
                    RuleMark(y: .value("기준가", product.basePrice))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("기준가")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                    // 목표가 기준선 [기능 1]
                    if product.targetPrice > 0 {
                        RuleMark(y: .value("목표가", product.targetPrice))
                            .foregroundStyle(Color.green.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("목표")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }
                    }
                }
                .chartYScale(domain: chartMinPrice...chartMaxPrice)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let price = value.as(Int.self) {
                                Text("\(price / 1000)k")
                                    .font(.system(size: 10))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
            }

            // 최저가/최고가 요약
            if !filteredHistory.isEmpty {
                HStack {
                    VStack(alignment: .leading) {
                        Text("최저").font(.caption2).foregroundColor(.secondary)
                        Text(KreamProduct.priceString(filteredHistory.map(\.price).min() ?? 0))
                            .font(.caption.bold()).foregroundColor(.blue)
                    }
                    Spacer()
                    VStack {
                        Text("평균").font(.caption2).foregroundColor(.secondary)
                        let avg = filteredHistory.map(\.price).reduce(0, +) / filteredHistory.count
                        Text(KreamProduct.priceString(avg))
                            .font(.caption.bold()).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("최고").font(.caption2).foregroundColor(.secondary)
                        Text(KreamProduct.priceString(filteredHistory.map(\.price).max() ?? 0))
                            .font(.caption.bold()).foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 결제 예상금액 계산기 [CORE 3]
    private var paymentCalculator: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("결제 예상금액")
                .font(.headline)

            VStack(spacing: 8) {
                PaymentRow(label: "즉시구매가", amount: product.currentPrice, color: .primary)
                PaymentRow(label: "검수비 (약 1%)", amount: product.inspectionFee, color: .secondary)
                PaymentRow(label: "배송비", amount: product.shippingFee, color: .secondary)

                Divider()

                HStack {
                    Text("총 결제 예상액")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(KreamProduct.priceString(product.estimatedTotalPayment))
                        .font(.title3.bold())
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            // KREAM 앱에서 바로 구매 버튼
            Button {
                KreamLinkParser.openProduct(kreamId: product.kreamId)
            } label: {
                HStack {
                    Image(systemName: "bag.fill")
                    Text("크림 앱에서 바로 구매")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(product.kreamId.isEmpty ? Color.gray : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(product.kreamId.isEmpty)
        }
    }

    // MARK: - 목표가 섹션 [기능 1]
    private var targetPriceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("내 목표가")
                    .font(.headline)
                Spacer()
                Button("수정") { showEditTarget = true }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
            }

            if product.targetPrice > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(KreamProduct.priceString(product.targetPrice))
                            .font(.title3.bold())
                            .foregroundColor(.green)
                        Text(product.hasReachedTargetPrice ? "🎯 목표가 달성!" : "아직 도달하지 않았어요")
                            .font(.caption)
                            .foregroundColor(product.hasReachedTargetPrice ? .green : .secondary)
                    }
                    Spacer()
                    if !product.hasReachedTargetPrice {
                        let gap = product.currentPrice - product.targetPrice
                        VStack(alignment: .trailing) {
                            Text("목표까지")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("▼ \(KreamProduct.priceString(gap))")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(product.hasReachedTargetPrice ? Color.green.opacity(0.1) : Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    showEditTarget = true
                } label: {
                    HStack {
                        Image(systemName: "target")
                        Text("목표가를 설정해보세요")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 크더싼 섹션 [기능 4]
    @ViewBuilder
    private var cheaperThanRetailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("발매가 비교")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("공식 발매가")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(KreamProduct.priceString(product.retailPrice))
                        .font(.subheadline)
                }

                Spacer()

                if product.isCheaperThanRetail {
                    let saving = product.retailPrice - product.currentPrice
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("크더싼 🏷️")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        Text("발매가보다 \(KreamProduct.priceString(saving)) 저렴")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else {
                    let premium = product.currentPrice - product.retailPrice
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("발매가 초과")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text("발매가보다 \(KreamProduct.priceString(premium)) 비쌈")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(product.isCheaperThanRetail ? Color.blue.opacity(0.08) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 액션 버튼들 [기능 10]
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 공유 버튼
            Button {
                generateShareImage()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("친구에게 이 상품 공유하기")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding()
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 목표가 수정 시트
    private var targetPriceEditSheet: some View {
        NavigationStack {
            Form {
                Section("목표가 설정") {
                    TextField("목표가 (원)", text: $targetPriceText)
                        .keyboardType(.numberPad)
                    Text("이 가격 이하가 되면 알림을 드려요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("목표가 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { showEditTarget = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
                        let raw = Int(targetPriceText.filter(\.isNumber)) ?? 0
                        product.targetPrice = raw
                        try? modelContext.save()
                        showEditTarget = false
                    }
                    .bold()
                }
            }
            .onAppear {
                targetPriceText = product.targetPrice > 0 ? "\(product.targetPrice)" : ""
            }
        }
    }

    // MARK: - 공유 이미지 생성 [기능 10]
    /// UIGraphicsImageRenderer로 상품 카드를 이미지로 렌더링
    private func generateShareImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 200))
        let image = renderer.image { ctx in
            // 배경
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 360, height: 200))

            // 카드 배경 (라운드 사각형)
            let cardPath = UIBezierPath(
                roundedRect: CGRect(x: 16, y: 16, width: 328, height: 168),
                cornerRadius: 16
            )
            UIColor.systemGray6.setFill()
            cardPath.fill()

            // 브랜드명
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.secondaryLabel
            ]
            product.brand.draw(at: CGPoint(x: 32, y: 32), withAttributes: brandAttrs)

            // 상품명
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: UIColor.label
            ]
            let nameStr = product.name as NSString
            nameStr.draw(
                in: CGRect(x: 32, y: 52, width: 260, height: 44),
                withAttributes: nameAttrs
            )

            // 현재가
            let priceAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: product.priceDelta < 0 ? UIColor.systemBlue : UIColor.label
            ]
            product.currentPriceString.draw(at: CGPoint(x: 32, y: 104), withAttributes: priceAttrs)

            // 변동폭
            let deltaColor: UIColor = product.priceDelta < 0 ? .systemBlue
                : product.priceDelta > 0 ? .systemRed : .secondaryLabel
            let deltaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: deltaColor
            ]
            let deltaStr = "\(product.priceDeltaString) (\(product.priceChangeRateString))"
            deltaStr.draw(at: CGPoint(x: 32, y: 140), withAttributes: deltaAttrs)

            // 크더싼 배지
            if product.isCheaperThanRetail {
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: UIColor.white
                ]
                let badgePath = UIBezierPath(
                    roundedRect: CGRect(x: 268, y: 140, width: 76, height: 24),
                    cornerRadius: 12
                )
                UIColor.systemBlue.setFill()
                badgePath.fill()
                "크더싼 🏷️".draw(at: CGPoint(x: 274, y: 144), withAttributes: badgeAttrs)
            }
        }

        shareImage = image
        showShareSheet = true
    }
}

// MARK: - 결제 금액 행 컴포넌트
private struct PaymentRow: View {
    let label: String
    let amount: Int
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(color == .secondary ? .secondary : .primary)
            Spacer()
            Text(KreamProduct.priceString(amount))
                .font(.subheadline)
                .foregroundColor(color)
        }
    }
}

// MARK: - 공유 시트 래퍼 [기능 10]
/// UIActivityViewController를 SwiftUI에서 사용하기 위한 래퍼
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 그래프 기간 열거형 [기능 5]
enum ChartPeriod: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:  return "7일"
        case .month: return "30일"
        }
    }
    var days: Int {
        switch self {
        case .week:  return 7
        case .month: return 30
        }
    }
}

#Preview {
    let product = KreamProduct(name: "Nike Dunk Low", brand: "NIKE", size: "270", basePrice: 150_000)
    product.currentPrice = 135_000
    product.retailPrice = 119_000
    product.targetPrice = 130_000
    return NavigationStack {
        ProductDetailView(product: product)
    }
    .modelContainer(for: [KreamProduct.self, PriceHistory.self, WishlistFolder.self], inMemory: true)
}
