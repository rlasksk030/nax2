import SwiftUI

/// 루트 뷰 - 4개 탭을 제공합니다.
/// 탭1: 위시리스트, 탭2: 가격비교, 탭3: 설정, 탭4: 추가(시트)
struct ContentView: View {
    @StateObject private var store = ProductStore()
    @StateObject private var settings = SettingsStore()

    @State private var selectedTab: Int = 0
    @State private var showingAddSheet: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            WishlistView()
                .tabItem {
                    Label("위시리스트", systemImage: "heart.fill")
                }
                .tag(0)

            PriceComparisonView()
                .tabItem {
                    Label("가격비교", systemImage: "chart.bar.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(2)

            // 4번째 탭은 선택 시 AddProductView 시트를 띄우는 트리거로 사용합니다.
            Color.clear
                .tabItem {
                    Label("추가", systemImage: "plus.circle.fill")
                }
                .tag(3)
        }
        .environmentObject(store)
        .environmentObject(settings)
        .onChange(of: selectedTab) {
            if selectedTab == 3 {
                showingAddSheet = true
                selectedTab = 0
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddProductView()
                .environmentObject(store)
        }
    }
}

#Preview {
    ContentView()
}
