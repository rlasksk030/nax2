import Foundation
import UserNotifications

// MARK: - 알림 서비스 [CORE 1] [기능 8]
// 가격 하락 / 목표가 달성 로컬 푸시 알림 관리
// 스마트 쿨타임으로 알림 피로도 방지
// UNUserNotificationCenterDelegate로 포그라운드에서도 배너 표시

@MainActor
final class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    // MARK: - 상수
    private static let lastNotifiedPrefix = "lastNotified_"
    private static let notificationStartHourKey = "notificationStartHour"
    private static let notificationEndHourKey = "notificationEndHour"
    private static let cooldownHoursKey = "notificationCooldownHours"

    // MARK: - 기본값
    private var defaultStartHour: Int { 9  }   // 오전 9시
    private var defaultEndHour: Int   { 22 }   // 오후 10시
    private var defaultCooldownHours: Double { 6.0 }

    // MARK: - 현재 알림 설정 (UserDefaults 기반)
    var startHour: Int {
        let v = UserDefaults.standard.integer(forKey: Self.notificationStartHourKey)
        return v == 0 ? defaultStartHour : v
    }

    var endHour: Int {
        let v = UserDefaults.standard.integer(forKey: Self.notificationEndHourKey)
        return v == 0 ? defaultEndHour : v
    }

    var cooldownHours: Double {
        let v = UserDefaults.standard.double(forKey: Self.cooldownHoursKey)
        return v == 0 ? defaultCooldownHours : v
    }

    // MARK: - 초기화
    private override init() {
        super.init()
        // 포그라운드 알림 표시를 위해 delegate 등록
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - 권한 요청
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            print(granted ? "✅ 알림 권한 허용" : "❌ 알림 권한 거부")
        } catch {
            print("알림 권한 요청 오류: \(error.localizedDescription)")
        }
    }

    // MARK: - 현재 권한 상태 확인
    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - 가격 하락 알림 발송 [CORE 1]
    /// basePrice보다 내려간 경우 즉시 알림 발송
    func sendPriceDropNotification(for product: KreamProduct) async {
        guard await shouldSendNotification(for: product.kreamId) else { return }

        let content = UNMutableNotificationContent()
        content.title = "📉 가격 하락 알림"

        let sizeTag = product.displaySize.map { " [\($0)]" } ?? ""
        let deltaStr = product.priceDeltaString
        content.body = "\(product.name)\(sizeTag)\n현재 \(product.currentPriceString) (\(deltaStr)) — 기준가보다 내려갔어요!"
        content.sound = .default
        content.userInfo = [
            "kreamId": product.kreamId,
            "type": "priceDrop",
            "productName": product.name
        ]

        await deliver(content: content, identifier: "priceDrop_\(product.kreamId)")
        recordLastNotified(for: product.kreamId)
    }

    // MARK: - 목표가 달성 알림 발송 [CORE 1]
    /// 사용자 설정 targetPrice 이하로 내려온 경우 알림
    func sendTargetPriceReachedNotification(for product: KreamProduct) async {
        guard product.targetPrice > 0 else { return }
        guard await shouldSendNotification(for: product.kreamId) else { return }

        let content = UNMutableNotificationContent()
        content.title = "🎯 목표가 달성!"

        let sizeTag = product.displaySize.map { " [\($0)]" } ?? ""
        content.body = "\(product.name)\(sizeTag)\n현재 \(product.currentPriceString) ≤ 목표가 \(KreamProduct.priceString(product.targetPrice)) 🎉"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("achievement.caf"))
        content.userInfo = [
            "kreamId": product.kreamId,
            "type": "targetReached",
            "productName": product.name
        ]

        await deliver(content: content, identifier: "targetPrice_\(product.kreamId)")
        recordLastNotified(for: product.kreamId)
    }

    // MARK: - 실제 발송
    private func deliver(content: UNMutableNotificationContent, identifier: String) async {
        let request = UNNotificationRequest(
            identifier: "\(identifier)_\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil  // trigger nil = 즉시 발송
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔔 알림 발송 완료: \(content.title)")
        } catch {
            print("알림 발송 오류: \(error.localizedDescription)")
        }
    }

    // MARK: - 쿨타임 및 허용 시간대 확인 [기능 8]

    /// 알림 발송 가능 여부 (쿨타임 + 허용 시간대 동시 확인)
    private func shouldSendNotification(for productId: String) async -> Bool {
        // 권한 확인
        let status = await checkPermissionStatus()
        guard status == .authorized else { return false }

        // 쿨타임 확인
        guard !isInCooldown(for: productId) else {
            print("⏱ 쿨타임 중 — 알림 생략: \(productId)")
            return false
        }

        // 허용 시간대 확인
        guard isWithinAllowedHours() else {
            print("🌙 알림 허용 시간 외 — 생략: \(productId)")
            return false
        }

        return true
    }

    /// 마지막 알림으로부터 cooldownHours 내인지 확인
    private func isInCooldown(for productId: String) -> Bool {
        let key = Self.lastNotifiedPrefix + productId
        guard let lastDate = UserDefaults.standard.object(forKey: key) as? Date else {
            return false  // 기록 없음 → 쿨타임 아님
        }
        let elapsed = Date().timeIntervalSince(lastDate) / 3600
        return elapsed < cooldownHours
    }

    /// 현재 시각이 사용자 설정 알림 허용 시간대 내인지 확인
    private func isWithinAllowedHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= startHour && hour < endHour
    }

    /// 마지막 알림 시각 기록
    private func recordLastNotified(for productId: String) {
        let key = Self.lastNotifiedPrefix + productId
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // MARK: - 설정 업데이트 (SettingsView에서 호출)
    func updateSettings(startHour: Int, endHour: Int, cooldownHours: Double) {
        UserDefaults.standard.set(startHour, forKey: Self.notificationStartHourKey)
        UserDefaults.standard.set(endHour, forKey: Self.notificationEndHourKey)
        UserDefaults.standard.set(cooldownHours, forKey: Self.cooldownHoursKey)
    }

    // MARK: - 대기 중인 알림 목록 조회
    func pendingNotifications() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    // MARK: - 특정 상품 알림 취소
    func cancelNotifications(for productId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["priceDrop_\(productId)", "targetPrice_\(productId)"]
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate
// 포그라운드 상태에서도 알림 배너 + 사운드 표시
extension NotificationService: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 앱이 포그라운드 상태여도 배너와 사운드 모두 표시
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 알림 탭 시 처리 (향후 딥링크 연동 가능)
        let userInfo = response.notification.request.content.userInfo
        if let kreamId = userInfo["kreamId"] as? String {
            print("알림 탭 — kreamId: \(kreamId)")
            // TODO: 해당 상품 상세 화면으로 이동 (NavigationPath 연동)
        }
        completionHandler()
    }
}
