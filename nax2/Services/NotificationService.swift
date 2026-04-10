import Foundation
import UserNotifications

/// 로컬 푸시 알림을 담당하는 서비스
final class NotificationService {

    static let shared = NotificationService()

    /// 쿨타임 허용 범위 (UI Stepper 에서도 사용)
    static let minCooldownHours: Double = 1
    static let maxCooldownHours: Double = 72
    static let defaultCooldownHours: Double = 6

    /// 쿨타임 길이 (시간 단위). 기본 6시간.
    /// SettingsStore 또는 UI 에서 자유롭게 변경할 수 있습니다.
    var cooldownHours: Double {
        didSet {
            let clamped = min(max(cooldownHours, Self.minCooldownHours), Self.maxCooldownHours)
            if clamped != cooldownHours {
                cooldownHours = clamped
            }
        }
    }

    /// 초 단위로 환산된 쿨타임
    var cooldown: TimeInterval {
        cooldownHours * 60 * 60
    }

    private init() {
        self.cooldownHours = NotificationService.defaultCooldownHours
    }

    /// 알림 권한 요청
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// 쿨타임이 남아있지 않은 경우에만 알림을 전송합니다.
    /// - Parameters:
    ///   - product: 알림 대상 상품
    ///   - overrideCooldownHours: 호출 시점에 다른 쿨타임 값을 강제로 사용하고 싶을 때 지정
    /// - Returns: 알림이 성공적으로 전송된 경우 갱신된 lastNotifiedAt 값, 쿨타임이 남아있으면 nil
    @discardableResult
    func tryNotify(product: KreamProduct, overrideCooldownHours: Double? = nil) -> Date? {
        let effectiveHours = overrideCooldownHours ?? cooldownHours
        let effectiveCooldown = effectiveHours * 60 * 60

        if let last = product.lastNotifiedAt,
           Date().timeIntervalSince(last) < effectiveCooldown {
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

    /// 특정 상품에 대해 쿨타임이 몇 초 남았는지 반환합니다. 쿨타임이 지났다면 0.
    func remainingCooldown(for product: KreamProduct, now: Date = Date()) -> TimeInterval {
        guard let last = product.lastNotifiedAt else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        return max(0, cooldown - elapsed)
    }
}
