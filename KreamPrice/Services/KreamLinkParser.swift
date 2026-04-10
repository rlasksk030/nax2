//
//  KreamLinkParser.swift
//  KreamPrice
//
//  KREAM 공유 URL 파싱 및 URL Scheme 생성 유틸리티.
//  - 상품 추가 시 클립보드에 복사된 링크에서 kreamId 추출
//  - 상품 상세에서 "크림 앱에서 바로 구매" 버튼에 사용할 URL 생성
//

import Foundation

// MARK: - KreamLinkParser

/// KREAM 상품 링크를 파싱하고, 거꾸로 URL Scheme 을 만들어주는 순수 유틸리티.
///
/// 지원하는 입력 형식 (예시):
/// - https://kream.co.kr/products/12345
/// - https://kream.co.kr/products/12345?size=270
/// - kream://products/12345
/// - https://www.kream.co.kr/products/12345-some-slug
enum KreamLinkParser {

    // MARK: - Types

    struct ParsedLink: Equatable, Sendable {
        let kreamId: String
        let size: String?
    }

    // MARK: - Parse

    /// 임의의 문자열에서 KREAM 상품 링크를 찾아 kreamId 와 size 를 추출한다.
    /// 링크가 아니거나 파싱 실패 시 nil 반환.
    static func parse(_ raw: String) -> ParsedLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // URL 로 변환 시도
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() ?? (url.scheme == "kream" ? "kream" : nil)
        else {
            return nil
        }

        // host 가 kream.co.kr 계열이거나, scheme 이 kream:// 인지 확인
        let isKreamHost = host.contains("kream.co.kr") || host == "kream"
        guard isKreamHost else { return nil }

        // pathComponents 예: ["/", "products", "12345"] 또는 ["/", "products", "12345-slug"]
        let components = url.pathComponents
        guard let productsIdx = components.firstIndex(where: { $0.lowercased() == "products" }),
              productsIdx + 1 < components.count
        else {
            return nil
        }

        let rawId = components[productsIdx + 1]
        // "12345-some-slug" 형태에서 앞쪽 숫자 부분만 추출
        let idPart = rawId.split(separator: "-").first.map(String.init) ?? rawId
        guard !idPart.isEmpty else { return nil }

        // 쿼리에서 size 추출 (있으면)
        let sizeValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "size" })?
            .value

        return ParsedLink(kreamId: idPart, size: sizeValue)
    }

    // MARK: - Build

    /// 크림 앱(설치되어 있다면) 딥링크. 상세 화면에서 "크림 앱에서 바로 구매" 버튼에 사용.
    static func appDeepLink(for kreamId: String) -> URL? {
        URL(string: "kream://products/\(kreamId)")
    }

    /// 크림 웹 URL. 앱이 없을 때 폴백용.
    static func webURL(for kreamId: String) -> URL? {
        URL(string: "https://kream.co.kr/products/\(kreamId)")
    }
}
