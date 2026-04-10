//
//  NotificationService.swift
//  KreamPrice
//
//  [CORE 1] 가격 하락 / 목표가 도달 로컬 푸시 발송 서비스.
//  [추가 기능 8] 알림 쿨타임 (동일 상품 6시간 이내 재알림 금지)
//               및 허용 시간대 제어.
//  [추가 기능 8] 포그라운드에서도 배너가 뜨도록 UNUserNotificationCenterDelegate 제공.
//

import Foundation
import UserNotifications
import SwiftUI

// MARK: - NotificationPreferences

/// 알림 관련 사용자 설정. UserDefaults 에 영속화.
struct NotificationPreferences: Sendable, Equatable {
    var cooldownHours: Int
    var quietStartHour: Int   // 0...23
    var quietEndHour: Int     // 0...24 (24 = 자정)
    var isEnabled: Bool

    static let `default` = NotificationPreferences(
        cooldownHours: 6,
        quietStartHour: 9,
        quietEndHour: 22,
        isEnabled: true
    )
}

// MARK: - NotificationService

/// 로컬 푸시 알림 전담 서비스.
/// 쿨타임과 허용 시간대를 관리해 알림 피로도를 줄인다.
@MainActor
final class NotificationService: NSObject, ObservableObject {

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let cooldownHours = "notif.cooldownHours"
        static let quietStart = "notif.quietStartHour"
        static let quietEnd = "notif.quietEndHour"
        static let enabled = "notif.isEnabled"
        static let lastNotifiedPrefix = "notif.lastNotifiedAt."
    }

    // MARK: - Published State

    @Published var preferences: NotificationPreferences

    // MARK: - Init

    override init() {
        let defaults = UserDefaults.standard
        let cooldown = defaults.object(forKey: DefaultsKey.cooldownHours) as? Int
            ?? NotificationPreferences.default.cooldownHours
        let start = defaults.object(forKey: DefaultsKey.quietStart) as? Int
            ?? NotificationPreferences.default.quietStartHour
        let end = defaults.object(forKey: DefaultsKey.quietEnd) as? Int
            ?? NotificationPreferences.default.quietEndHour
        let enabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool
            ?? NotificationPreferences.default.isEnabled

        self.preferences = NotificationPreferences(
            cooldownHours: cooldown,
            quietStartHour: start,
            quietEndHour: end,
            isEnabled: enabled
        )
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// 알림 권한 요청. 앱 최초 실행 시 또는 설정 화면에서 호출.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        guard current.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Preferences

    func updatePreferences(_ new: NotificationPreferences) {
        self.preferences = new
        let defaults = UserDefaults.standard
        defaults.set(new.cooldownHours, forKey: DefaultsKey.cooldownHours)
        defaults.set(new.quietStartHour, forKey: DefaultsKey.quietStart)
        defaults.set(new.quietEndHour, forKey: DefaultsKey.quietEnd)
        defaults.set(new.isEnabled, forKey: DefaultsKey.enabled)
    }

    // MARK: - Send Notifications

    /// [CORE 1] basePrice 이하로 내려간 경우 알림 발송.
    func sendPriceDropNotification(
        for product: KreamProduct,
        oldPrice: Int,
        newPrice: Int
    ) async {
        guard canNotify(productId: product.kreamId) else { return }

        let title = "가격 하락 알림 📉"
        let priceDropAmount = product.basePrice - newPrice
        let body = "\(product.brand) \(product.name) [\(product.size)]\n"
            + "기준가 \(formatKRW(product.basePrice))원 → 현재 \(formatKRW(newPrice))원 "
            + "(\(formatKRW(priceDropAmount))원 하락)"

        await scheduleLocalNotification(
            identifier: "pricedrop.\(product.kreamId).\(Int(Date.now.timeIntervalSince1970))",
            title: title,
            body: body,
            userInfo: ["kreamId": product.kreamId, "kind": "priceDrop"]
        )
        markNotified(productId: product.kreamId, at: .now, product: product)
    }

    /// [CORE 1] 사용자 목표가 도달 알림.
    func sendTargetReachedNotification(
        for product: KreamProduct,
        newPrice: Int
    ) async {
        guard canNotify(productId: product.kreamId) else { return }

        let title = "🎯 목표가 도달!"
        let body = "\(product.brand) \(product.name) [\(product.size)]\n"
            + "목표가 \(formatKRW(product.targetPrice))원 이하로 떨어졌어요. "
            + "현재 \(formatKRW(newPrice))원"

        await scheduleLocalNotification(
            identifier: "target.\(product.kreamId).\(Int(Date.now.timeIntervalSince1970))",
            title: title,
            body: body,
            userInfo: ["kreamId": product.kreamId, "kind": "targetReached"]
        )
        markNotified(productId: product.kreamId, at: .now, product: product)
    }

    // MARK: - Cooldown & Quiet Hours

    /// [추가 기능 8] 알림 가능 여부 판단.
    /// - 알림 전역 OFF 면 불가
    /// - 현재 시각이 quietStart ~ quietEnd 범위를 벗어나면 불가
    /// - 같은 상품이 쿨타임 내에 이미 알림을 받았으면 불가
    private func canNotify(productId: String) -> Bool {
        guard preferences.isEnabled else { return false }
        guard isInAllowedHours(date: .now) else { return false }

        let key = DefaultsKey.lastNotifiedPrefix + productId
        if let last = UserDefaults.standard.object(forKey: key) as? Date {
            let cooldown = TimeInterval(preferences.cooldownHours * 3600)
            if Date.now.timeIntervalSince(last) < cooldown {
                return false
            }
        }
        return true
    }

    private func markNotified(productId: String, at date: Date, product: KreamProduct) {
        UserDefaults.standard.set(date, forKey: DefaultsKey.lastNotifiedPrefix + productId)
        product.lastNotifiedAt = date
    }

    /// 현재 시각이 사용자가 지정한 허용 시간대 안인지 확인.
    /// quietStart < quietEnd 인 정상 케이스만 가정. (예: 9시 ~ 22시)
    private func isInAllowedHours(date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let start = preferences.quietStartHour
        let end = preferences.quietEndHour
        if start <= end {
            return hour >= start && hour < end
        } else {
            // 예: 22시 ~ 6시 처럼 자정을 넘는 경우
            return hour >= start || hour < end
        }
    }

    // MARK: - Low-Level Scheduling

    private func scheduleLocalNotification(
        identifier: String,
        title: String,
        body: String,
        userInfo: [String: Any]
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        // 즉시 발송 (1초 뒤, 반복 없음)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func formatKRW(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// [CORE 1] 포그라운드에서도 배너 + 사운드가 뜨도록.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// 사용자가 알림을 탭했을 때. (딥링크 처리 확장 지점)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
