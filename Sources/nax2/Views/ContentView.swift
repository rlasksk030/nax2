import SwiftUI
import SwiftData

// MARK: - 탭바 컨테이너
// 앱의 메인 화면을 3개 탭으로 구성:
//   탭 1 — 위시리스트 (핵심 화면)
//   탭 2 — 가격 비교 대시보드
//   탭 3 — 설정

struct ContentView: View {

    @State private var selectedTab: Int = 0
    @Environment(\.modelContext) private var modelContext

    // 가격 갱신 서비스 (전역 ObservableObject)
    @StateObject private var priceUpdateService = PriceUpdateService.shared

    // 즐겨찾기 상품 전체 조회 (가격 갱신 시 사용)
    @Query private var products: [KreamProduct]

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: - 탭 1: 위시리스트
            WishlistView()
                .tabItem {
                    Label("위시리스트", systemImage: "heart.fill")
                }
                .tag(0)

            // MARK: - 탭 2: 가격 비교
            PriceComparisonView()
                .tabItem {
                    Label("가격 비교", systemImage: "chart.bar.fill")
                }
                .tag(1)

            // MARK: - 탭 3: 설정
            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gear")
                }
                .tag(2)
        }
        .tint(.blue)
        // 앱 실행 시 전체 가격 갱신
        .task {
            await priceUpdateService.refreshAll(
                products: products,
                modelContext: modelContext
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [KreamProduct.self, PriceHistory.self, WishlistFolder.self], inMemory: true)
}
