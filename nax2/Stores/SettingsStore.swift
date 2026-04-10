import Foundation

/// 앱 설정을 UserDefaults 기반으로 보관하는 스토어
final class SettingsStore: ObservableObject {

    private enum Keys {
        static let monthlyBudget = "settings.monthlyBudget"
        static let notificationsEnabled = "settings.notificationsEnabled"
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

    init() {
        let defaults = UserDefaults.standard
        self.monthlyBudget = defaults.integer(forKey: Keys.monthlyBudget)
        if defaults.object(forKey: Keys.notificationsEnabled) == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        }
    }
}
