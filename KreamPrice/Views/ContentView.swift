//
//  ContentView.swift
//  KreamPrice
//
//  탭바 컨테이너 — 3개 탭.
//  1. 즐겨찾기 (WishlistView)
//  2. 가격 비교 (PriceComparisonView)
//  3. 설정 (SettingsView)
//

import SwiftUI
import SwiftData

// MARK: - ContentView

struct ContentView: View {

    // MARK: - State

    @State private var selectedTab: Tab = .wishlist

    enum Tab: Hashable {
        case wishlist
        case comparison
        case settings
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            WishlistView()
                .tabItem {
                    Label("즐겨찾기", systemImage: "heart.fill")
                }
                .tag(Tab.wishlist)

            PriceComparisonView()
                .tabItem {
                    Label("가격 비교", systemImage: "chart.bar.fill")
                }
                .tag(Tab.comparison)

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(.blue)
    }
}
