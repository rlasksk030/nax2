import Foundation

/// Kream 상품 페이지에서 파싱한 정보
struct KreamProductInfo {
    var brand: String?
    var name: String?
    var size: String?
    var currentPrice: Int?
    var retailPrice: Int?
    var imageURL: String?
}

enum KreamServiceError: LocalizedError {
    case invalidURL
    case notKreamURL
    case networkFailure(Int?)
    case decodingFailure
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "올바른 URL 형식이 아닙니다."
        case .notKreamURL:
            return "Kream(kream.co.kr) 링크가 아닙니다."
        case .networkFailure(let code):
            if let code {
                return "네트워크 오류 (HTTP \(code))"
            }
            return "네트워크 오류가 발생했습니다."
        case .decodingFailure:
            return "페이지 내용을 읽지 못했습니다."
        case .emptyResult:
            return "상품 정보를 찾지 못했습니다."
        }
    }
}

/// Kream 상품 페이지를 가져와 Open Graph / JSON-LD / 정규식으로 정보를 추출하는 서비스
final class KreamService {

    static let shared = KreamService()

    private init() {}

    // MARK: - Public

    /// Kream 링크에서 상품 정보를 가져옵니다.
    func fetchProductInfo(from urlString: String) async throws -> KreamProductInfo {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw KreamServiceError.invalidURL
        }
        guard isKreamURL(url) else {
            throw KreamServiceError.notKreamURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw KreamServiceError.networkFailure(nil)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KreamServiceError.networkFailure(http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw KreamServiceError.decodingFailure
        }

        let info = parse(html: html)
        if info.brand == nil && info.name == nil && info.currentPrice == nil {
            throw KreamServiceError.emptyResult
        }
        return info
    }

    /// kream.co.kr 도메인의 URL 인지 검증
    func isKreamURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("kream.co.kr")
    }

    // MARK: - Parsing

    private func parse(html: String) -> KreamProductInfo {
        var info = KreamProductInfo()

        // 1) Open Graph 기본 메타데이터
        if let ogImage = metaContent(html: html, property: "og:image") {
            info.imageURL = ogImage
        }

        let rawTitle = metaContent(html: html, property: "og:title")
            ?? metaContent(html: html, name: "title")
            ?? extractTitleTag(from: html)

        if let title = rawTitle {
            let (brand, name) = splitBrandAndName(from: title)
            info.brand = brand
            info.name = name
        }

        // 2) JSON-LD 구조화 데이터
        if let ld = extractJSONLD(from: html) {
            if info.brand == nil, let b = ld.brand {
                info.brand = b
            }
            if info.name == nil, let n = ld.name {
                info.name = n
            }
            if let price = ld.price {
                info.currentPrice = price
            }
        }

        // 3) 정규식으로 가격 보강 (JSON-LD 에 없는 경우)
        if info.currentPrice == nil {
            info.currentPrice = extractPrice(from: html, patterns: [
                "\"releasePrice\"\\s*:\\s*\"?([0-9]+)",
                "\"price\"\\s*:\\s*\"?([0-9]+)",
                "즉시\\s*구매가[^0-9]*([0-9,]+)\\s*원",
                "즉시[^0-9]{0,10}([0-9,]+)\\s*원"
            ])
        }

        info.retailPrice = extractPrice(from: html, patterns: [
            "\"originalPrice\"\\s*:\\s*\"?([0-9]+)",
            "\"retailPrice\"\\s*:\\s*\"?([0-9]+)",
            "발매가[^0-9]*([0-9,]+)\\s*원",
            "정가[^0-9]*([0-9,]+)\\s*원"
        ])

        return info
    }

    // MARK: - Meta tag helpers

    private func metaContent(html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let forward = "<meta[^>]*property=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']+)[\"']"
        if let match = firstMatch(pattern: forward, in: html) {
            return match
        }
        let reversed = "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*property=[\"']\(escaped)[\"']"
        return firstMatch(pattern: reversed, in: html)
    }

    private func metaContent(html: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let forward = "<meta[^>]*name=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']+)[\"']"
        if let match = firstMatch(pattern: forward, in: html) {
            return match
        }
        let reversed = "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*name=[\"']\(escaped)[\"']"
        return firstMatch(pattern: reversed, in: html)
    }

    private func extractTitleTag(from html: String) -> String? {
        return firstMatch(pattern: "<title[^>]*>([^<]+)</title>", in: html)
    }

    // MARK: - JSON-LD

    private struct JSONLDProduct {
        var brand: String?
        var name: String?
        var price: Int?
    }

    private func extractJSONLD(from html: String) -> JSONLDProduct? {
        let pattern = "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        for match in matches {
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[r])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = jsonString.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) else { continue }

            if let parsed = parseJSONLDObject(json) {
                return parsed
            }
        }
        return nil
    }

    private func parseJSONLDObject(_ json: Any) -> JSONLDProduct? {
        if let array = json as? [Any] {
            for item in array {
                if let parsed = parseJSONLDObject(item) {
                    return parsed
                }
            }
            return nil
        }

        guard let dict = json as? [String: Any] else { return nil }

        if let graph = dict["@graph"] as? [Any] {
            for item in graph {
                if let parsed = parseJSONLDObject(item) {
                    return parsed
                }
            }
        }

        let typeString: String? = {
            if let t = dict["@type"] as? String { return t }
            if let arr = dict["@type"] as? [String] { return arr.first }
            return nil
        }()

        guard typeString?.localizedCaseInsensitiveContains("product") == true else {
            return nil
        }

        var result = JSONLDProduct()
        result.name = dict["name"] as? String

        if let brand = dict["brand"] as? String {
            result.brand = brand
        } else if let brandDict = dict["brand"] as? [String: Any],
                  let brandName = brandDict["name"] as? String {
            result.brand = brandName
        }

        if let offers = dict["offers"] as? [String: Any] {
            result.price = priceValue(from: offers["price"])
        } else if let offersArr = dict["offers"] as? [[String: Any]],
                  let first = offersArr.first {
            result.price = priceValue(from: first["price"])
        }

        return result
    }

    private func priceValue(from any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String {
            let digits = s.filter { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    // MARK: - Regex helpers

    private func extractPrice(from text: String, patterns: [String]) -> Int? {
        for pattern in patterns {
            if let raw = firstMatch(pattern: pattern, in: text) {
                let digits = raw.filter { $0.isNumber }
                if let value = Int(digits), value > 1_000 {
                    return value
                }
            }
        }
        return nil
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }

    // MARK: - Title splitting

    /// "Nike Air Force 1 '07 | KREAM" → brand: "Nike", name: "Air Force 1 '07"
    private func splitBrandAndName(from title: String) -> (brand: String?, name: String?) {
        let suffixes = ["| KREAM", "| 크림", "- KREAM", "- 크림"]
        var cleaned = title
        for suffix in suffixes {
            if let range = cleaned.range(of: suffix, options: .caseInsensitive) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return (nil, nil) }

        let parts = cleaned.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (nil, cleaned)
    }
}
