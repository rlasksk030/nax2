import Foundation
import UIKit

// MARK: - KREAM URL 파싱 유틸리티
// KREAM 웹 URL에서 상품 ID를 추출하고
// 클립보드 자동 감지를 지원합니다.
//
// 지원 URL 패턴:
//   https://kream.co.kr/products/12345
//   https://kream.co.kr/products/12345?size=270
//   kream://products/12345  (앱 딥링크)

struct KreamLinkParser {

    // MARK: - KREAM 상품 URL 파싱

    /// URL 문자열에서 KREAM 상품 ID 추출
    /// - Returns: 상품 ID 문자열, 유효하지 않으면 nil
    static func parseKreamId(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }

        // 웹 URL: kream.co.kr/products/{id}
        if let host = url.host, host.contains("kream.co.kr") {
            return extractIdFromPath(url.pathComponents)
        }

        // 앱 딥링크: kream://products/{id}
        if url.scheme == "kream", url.host == "products" {
            return url.pathComponents.first { !$0.isEmpty && $0 != "/" }
        }

        return nil
    }

    /// URL 경로 컴포넌트에서 products/ 다음 ID 추출
    private static func extractIdFromPath(_ components: [String]) -> String? {
        guard let index = components.firstIndex(of: "products"),
              components.count > index + 1 else { return nil }
        let id = components[index + 1]
        // 숫자만 포함된 ID인지 확인 (KREAM 상품 ID는 숫자)
        return id.isEmpty ? nil : id
    }

    // MARK: - 클립보드 자동 감지

    /// 클립보드에서 KREAM URL을 자동 감지
    /// - Returns: (kreamId, originalURL) 튜플, 없으면 nil
    static func detectFromClipboard() -> (kreamId: String, url: String)? {
        // iOS 16+ 에서는 UIPasteboard 접근 시 시스템 배너가 표시됨
        guard let clipboardString = UIPasteboard.general.string,
              !clipboardString.isEmpty else { return nil }

        guard let kreamId = parseKreamId(from: clipboardString) else { return nil }

        return (kreamId: kreamId, url: clipboardString)
    }

    // MARK: - URL 유효성 검사

    /// 유효한 KREAM 상품 URL인지 확인
    static func isValidKreamURL(_ urlString: String) -> Bool {
        parseKreamId(from: urlString) != nil
    }

    // MARK: - URL 생성

    /// 상품 ID로 KREAM 웹 URL 생성
    static func makeWebURL(kreamId: String) -> URL? {
        URL(string: "https://kream.co.kr/products/\(kreamId)")
    }

    /// 상품 ID로 KREAM 앱 URL Scheme 생성
    static func makeAppURL(kreamId: String) -> URL? {
        URL(string: "kream://products/\(kreamId)")
    }

    /// KREAM 앱 설치 여부 확인
    static func isKreamAppInstalled() -> Bool {
        guard let url = URL(string: "kream://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// KREAM 상품 페이지 열기 (앱 우선, 없으면 웹)
    @MainActor
    static func openProduct(kreamId: String) {
        if isKreamAppInstalled(), let appURL = makeAppURL(kreamId: kreamId) {
            UIApplication.shared.open(appURL)
        } else if let webURL = makeWebURL(kreamId: kreamId) {
            UIApplication.shared.open(webURL)
        }
    }
}
