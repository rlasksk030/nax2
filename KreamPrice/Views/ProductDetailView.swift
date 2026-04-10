//
//  ProductDetailView.swift
//  KreamPrice
//
//  상품 상세 화면. 다음을 통합:
//  - [CORE 3] 결제 예상금액 계산기 (breakdown)
//  - [추가 기능 5] 가격 히스토리 그래프 (Swift Charts, 7일/30일 탭)
//  - "크림 앱에서 바로 구매" 버튼 (URL Scheme)
//  - [추가 기능 10] 공유 기능 (카드 이미지 + UIActivityViewController)
//

import SwiftUI
import SwiftData
import Charts
import UIKit

// MARK: - ProductDetailView

struct ProductDetailView: View {

    // MARK: - Input

    let product: KreamProduct

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    // MARK: - UI State

    enum HistoryRange: String, CaseIterable, Identifiable {
        case week = "7일"
        case month = "30일"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    @State private var historyRange: HistoryRange = .week
    @State private var shareItems: [Any]?
    @State private var showShareSheet: Bool = false

    // MARK: - Derived

    private var filteredHistory: [PriceHistory] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -historyRange.days, to: .now) ?? .now
        return product.priceHistory
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private var lowestHistory: PriceHistory? {
        filteredHistory.min { $0.price < $1.price }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                chartCard
                calculatorCard
                actionsCard
            }
            .padding()
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    share()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareItems {
                ShareSheet(items: shareItems)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: URL(string: product.imageUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                case .failure: placeholder
                case .empty: placeholder
                @unknown default: placeholder
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(product.brand)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(product.name)
                .font(.title3)
                .fontWeight(.bold)
            HStack(spacing: 6) {
                Text("[\(product.size)]")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                if product.isCheaperThanRetail {
                    Text("크더싼 🏷️")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
    }

    // MARK: - Chart Card [추가 기능 5]

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("가격 히스토리")
                    .font(.headline)
                Spacer()
                Picker("", selection: $historyRange) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            if filteredHistory.isEmpty {
                Text("아직 기록된 히스토리가 없어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(filteredHistory) { point in
                        LineMark(
                            x: .value("날짜", point.recordedAt),
                            y: .value("가격", point.price)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.blue)

                        PointMark(
                            x: .value("날짜", point.recordedAt),
                            y: .value("가격", point.price)
                        )
                        .foregroundStyle(Color.blue.opacity(0.6))
                        .symbolSize(20)
                    }

                    // 최저점 별표 마커
                    if let low = lowestHistory {
                        PointMark(
                            x: .value("날짜", low.recordedAt),
                            y: .value("가격", low.price)
                        )
                        .symbol(.asterisk)
                        .symbolSize(200)
                        .foregroundStyle(Color.yellow)
                        .annotation(position: .top) {
                            Text("최저 \(formatKRW(low.price))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    // MARK: - Calculator Card [CORE 3]

    private var calculatorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("결제 예상금액")
                .font(.headline)

            priceRow(label: "즉시구매가", value: product.currentPrice)
            priceRow(label: "검수비 (약 1%)", value: product.inspectionFee)
            priceRow(label: "배송비", value: KreamProduct.shippingFee)

            Divider().padding(.vertical, 2)

            HStack {
                Text("총 결제 예상")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(formatKRW(product.estimatedTotalPrice))원")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }

            if product.retailPrice > 0 {
                HStack {
                    Text("공식 발매가")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatKRW(product.retailPrice))원")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    private func priceRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(formatKRW(value))원")
                .font(.subheadline)
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                openInKreamApp()
            } label: {
                Label("크림 앱에서 바로 구매", systemImage: "bag.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .controlSize(.large)

            Button {
                share()
            } label: {
                Label("친구에게 이 상품 공유하기", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Actions

    /// 크림 앱 딥링크 → 실패 시 웹 폴백.
    private func openInKreamApp() {
        guard !product.kreamId.isEmpty else { return }
        if let deep = KreamLinkParser.appDeepLink(for: product.kreamId) {
            openURL(deep) { accepted in
                if !accepted, let web = KreamLinkParser.webURL(for: product.kreamId) {
                    openURL(web)
                }
            }
        } else if let web = KreamLinkParser.webURL(for: product.kreamId) {
            openURL(web)
        }
    }

    /// [추가 기능 10] 카드 렌더링 후 공유.
    private func share() {
        let card = ShareCardView(product: product)
            .frame(width: 320, height: 420)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        var items: [Any] = []
        if let uiImage = renderer.uiImage {
            items.append(uiImage)
        }
        let summary = "\(product.brand) \(product.name) [\(product.size)]\n"
            + "현재가 \(formatKRW(product.currentPrice))원"
        items.append(summary)
        self.shareItems = items
        self.showShareSheet = true
    }

    // MARK: - Helpers

    private func formatKRW(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - ShareCardView

/// [추가 기능 10] 캡처용 카드 뷰. 이미지로 렌더링되어 공유된다.
private struct ShareCardView: View {
    let product: KreamProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KreamPrice")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text(product.brand)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
            Text(product.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("[\(product.size)]")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text("현재가")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Text("\(formatKRW(product.currentPrice))원")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .foregroundStyle(.white)

            let delta = product.priceDelta
            let sign = delta > 0 ? "+" : ""
            Text("기준가 대비 \(sign)\(formatKRW(delta))원")
                .font(.subheadline)
                .foregroundStyle(delta < 0 ? .cyan : (delta > 0 ? .pink : .white))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [.black, .gray.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func formatKRW(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - ShareSheet

/// UIActivityViewController 래퍼.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
