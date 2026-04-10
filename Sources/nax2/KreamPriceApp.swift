import SwiftUI
import SwiftData
import UserNotifications

// MARK: - 앱 진입점
// ⚙️ Xcode 설정 필요 항목:
//   1. Signing & Capabilities → + Capability → Push Notifications 추가
//   2. Signing & Capabilities → + Capability → Background Modes → Background fetch 체크
//   3. Info.plist → NSUserNotificationsUsageDescription 키 추가
//      값 예시: "가격 하락 및 목표가 달성 시 알림을 보내드려요."
//   4. Info.plist → LSApplicationQueriesSchemes 배열에 "kream" 추가
//      (KreamLinkParser.isKreamAppInstalled()이 kream:// URL을 조회하기 위해 필요)
//   5. Swift Language Version: Swift 6

@main
struct KreamPriceApp: App {

    // MARK: - SwiftData 컨테이너
    // ⚠️ 스키마 변경 시 마이그레이션 필요:
    //    ModelContainer에 migrationPlan: 파라미터를 추가하여 SchemaMigrationPlan을 지정하세요.
    //    개발 중 스키마 변경은 앱 삭제 후 재설치로 해결 가능합니다.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            KreamProduct.self,
            PriceHistory.self,
            WishlistFolder.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false  // true로 변경하면 SwiftUI Preview용 인메모리 스토어
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // ModelContainer 생성 실패 시 앱을 계속 실행할 수 없음
            fatalError("SwiftData ModelContainer 초기화 실패: \(error)")
        }
    }()

    // MARK: - 앱 델리게이트 어댑터
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 앱 실행 시 알림 권한 요청
                    await NotificationService.shared.requestPermission()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - App Delegate (백그라운드 작업 처리)
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // BGTaskScheduler 등록 (향후 백그라운드 가격 갱신에 활용)
        // BGTaskScheduler.shared.register(
        //     forTaskWithIdentifier: "com.yourapp.priceupdate",
        //     using: nil
        // ) { task in
        //     // 백그라운드 가격 갱신 처리
        //     task.setTaskCompleted(success: true)
        // }
        return true
    }

    // MARK: - 딥링크 처리 (KREAM URL Scheme로 앱 진입 시)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // kream:// 딥링크 처리 (향후 NavigationPath 연동)
        print("딥링크 수신: \(url)")
        return true
    }
}
