import Foundation
import UserNotifications

/// 로컬 푸시 알림을 담당하는 서비스
final class NotificationService {

    static let shared = NotificationService()

    /// 동일 상품에 대한 알림 쿨타임 (6시간)
    let cooldown: TimeInterval = 6 * 60 * 60

    private init() {}

    /// 알림 권한 요청
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// 쿨타임이 남아있지 않은 경우에만 알림을 전송합니다.
    /// - Parameter product: 알림 대상 상품
    /// - Returns: 알림이 성공적으로 전송된 경우 갱신된 lastNotifiedAt 값, 쿨타임이 남아있으면 nil
    @discardableResult
    func tryNotify(product: KreamProduct) -> Date? {
        if let last = product.lastNotifiedAt,
           Date().timeIntervalSince(last) < cooldown {
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = "\(product.brand) \(product.name)"
        content.body = "목표가 도달! 현재가 \(product.currentPrice.formatted())원 (사이즈 \(product.size))"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "price-\(product.id.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

        return Date()
    }

    /// 쿨타임이 남아있는지 여부를 반환합니다.
    func isInCooldown(product: KreamProduct, now: Date = Date()) -> Bool {
        guard let last = product.lastNotifiedAt else { return false }
        return now.timeIntervalSince(last) < cooldown
    }
}
