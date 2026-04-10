//
//  ProductRowView.swift
//  KreamPrice
//
//  즐겨찾기 목록 카드 디자인.
//  - 썸네일
//  - 브랜드 / 상품명 / 사이즈 태그
//  - [CORE 2] basePrice 대비 변동폭 + 변동률 (파랑=하락, 빨강=상승)
//  - [추가 기능 4] "크더싼 🏷️" 배지
//  - [CORE 1] 목표가 도달 시 🎯 배지
//

import SwiftUI

// MARK: - ProductRowView

struct ProductRowView: View {

    let product: KreamProduct

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 썸네일
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                // 브랜드
                Text(product.brand)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 상품명
                Text(product.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                // 뱃지들
                HStack(spacing: 6) {
                    // 사이즈 태그
                    Text("[\(product.size)]")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())

                    // "크더싼" 배지 [추가 기능 4]
                    if product.isCheaperThanRetail {
                        Text("크더싼 🏷️")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }

                    // 목표가 도달 배지 [CORE 1]
                    if product.hasReachedTarget {
                        Text("🎯 목표가")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }

                // 현재가 + 변동폭
                HStack(spacing: 8) {
                    Text("\(formatKRW(product.currentPrice))원")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    priceDeltaBadge
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        AsyncImage(url: URL(string: product.imageUrl)) { phase in
            switch phase {
            case .success(let img):
                img
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: 72, height: 72)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    // MARK: - Price Delta Badge

    /// [CORE 2] basePrice 대비 변동폭을 색상으로 표시.
    @ViewBuilder
    private var priceDeltaBadge: some View {
        let delta = product.priceDelta
        let ratio = product.priceDeltaRatio
        let color: Color = delta < 0 ? .blue : (delta > 0 ? .red : .secondary)
        let arrow = delta < 0 ? "📉" : (delta > 0 ? "📈" : "⏸︎")
        let sign = delta > 0 ? "+" : ""
        HStack(spacing: 2) {
            Text(arrow)
            Text("\(sign)\(formatKRW(delta))원")
            Text(String(format: "(%@%.1f%%)", sign, ratio))
        }
        .font(.caption)
        .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatKRW(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
