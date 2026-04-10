//
//  KreamPriceApp.swift
//  KreamPrice
//
//  앱 진입점.
//  - SwiftData ModelContainer 주입
//  - NotificationService 초기화 및 권한 요청
//  - scenePhase 가 .active 로 전환될 때 PriceUpdateService 로 전체 가격 갱신
//  - BGTaskScheduler 로 백그라운드 주기 갱신 (선택)
//

import SwiftUI
import SwiftData
import BackgroundTasks

// MARK: - Background Task Identifier

/// Info.plist > BGTaskSchedulerPermittedIdentifiers 에 등록해야 하는 식별자.
enum BackgroundTaskID {
    static let priceRefresh = "com.kreamprice.priceRefresh"
}

// MARK: - App Entry Point

@main
struct KreamPriceApp: App {

    // MARK: - SwiftData Container

    /// SwiftData 컨테이너. v1 스키마.
    /// > 마이그레이션 주의: 모델 시그니처를 변경하면 VersionedSchema 로 명시적 마이그레이션 플랜을 작성할 것.
    let container: ModelContainer = {
        let schema = Schema([
            KreamProduct.self,
            PriceHistory.self,
            WishlistFolder.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 초기화 실패: \(error)")
        }
    }()

    // MARK: - Services

    @StateObject private var notificationService = NotificationService()

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationService)
                .task {
                    // 최초 실행 시 알림 권한 요청
                    await notificationService.requestAuthorizationIfNeeded()
                    // 앱 실행 직후 1회 갱신
                    await refreshPrices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await refreshPrices() }
                    } else if newPhase == .background {
                        scheduleBackgroundRefresh()
                    }
                }
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(BackgroundTaskID.priceRefresh)) {
            // 백그라운드에서 호출되는 경우에도 같은 갱신 로직 재사용
            await handleBackgroundRefresh()
        }
    }

    // MARK: - Refresh Helpers

    /// 포그라운드 갱신: 메인 컨텍스트에서 PriceUpdateService 구동.
    @MainActor
    private func refreshPrices() async {
        let service = PriceUpdateService(
            modelContext: container.mainContext,
            notificationService: notificationService
        )
        await service.refreshAllProducts()
    }

    /// 백그라운드 갱신: 별도 ModelContext 가 아닌 메인 컨텍스트를 재사용.
    /// (SwiftData 는 MainActor 에서 접근해야 안전하므로)
    @MainActor
    private func handleBackgroundRefresh() async {
        await refreshPrices()
        // 다음 실행 예약
        scheduleBackgroundRefresh()
    }

    /// [CORE 1] 주기적으로 가격을 갱신할 수 있도록 BGTask 예약.
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskID.priceRefresh)
        // 최소 간격: 1시간
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
