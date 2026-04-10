import Foundation

/// 앱 설정을 UserDefaults 기반으로 보관하는 스토어
final class SettingsStore: ObservableObject {

    private enum Keys {
        static let monthlyBudget = "settings.monthlyBudget"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let notificationCooldownHours = "settings.notificationCooldownHours"
    }

    /// 월 예산 한도 (원)
    @Published var monthlyBudget: Int {
        didSet {
            UserDefaults.standard.set(monthlyBudget, forKey: Keys.monthlyBudget)
        }
    }

    /// 알림 활성화 여부
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    /// 동일 상품에 대한 알림 쿨타임 (시간 단위)
    /// 변경 시 NotificationService 의 쿨타임도 함께 갱신됩니다.
    @Published var notificationCooldownHours: Double {
        didSet {
            let clamped = min(
                max(notificationCooldownHours, NotificationService.minCooldownHours),
                NotificationService.maxCooldownHours
            )
            if clamped != notificationCooldownHours {
                notificationCooldownHours = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.notificationCooldownHours)
            NotificationService.shared.cooldownHours = clamped
        }
    }

    init() {
        let defaults = UserDefaults.standard

        self.monthlyBudget = defaults.integer(forKey: Keys.monthlyBudget)

        if defaults.object(forKey: Keys.notificationsEnabled) == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        }

        if defaults.object(forKey: Keys.notificationCooldownHours) == nil {
            self.notificationCooldownHours = NotificationService.defaultCooldownHours
        } else {
            let stored = defaults.double(forKey: Keys.notificationCooldownHours)
            let clamped = min(
                max(stored, NotificationService.minCooldownHours),
                NotificationService.maxCooldownHours
            )
            self.notificationCooldownHours = clamped
        }

        // 저장된 값을 NotificationService 에 즉시 반영
        NotificationService.shared.cooldownHours = self.notificationCooldownHours
    }
}
