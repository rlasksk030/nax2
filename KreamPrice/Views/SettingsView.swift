//
//  SettingsView.swift
//  KreamPrice
//
//  설정 화면.
//  - [추가 기능 6] 월 예산 한도
//  - [추가 기능 8] 알림 쿨타임 시간 / 허용 시간대 / 전체 ON-OFF
//  - [추가 기능 9] 폴더 관리 (추가/삭제)
//

import SwiftUI
import SwiftData

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService

    // MARK: - Budget [추가 기능 6]

    @AppStorage("budget.monthlyLimit") private var monthlyBudgetLimit: Int = 0
    @State private var budgetText: String = ""

    // MARK: - Notification State [추가 기능 8]

    @State private var prefs: NotificationPreferences = .default

    // MARK: - Folder Management [추가 기능 9]

    @Query(sort: \WishlistFolder.createdAt, order: .forward)
    private var folders: [WishlistFolder]

    @State private var newFolderName: String = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                budgetSection
                notificationSection
                folderSection
                aboutSection
            }
            .navigationTitle("설정")
            .onAppear {
                prefs = notificationService.preferences
                budgetText = monthlyBudgetLimit > 0 ? String(monthlyBudgetLimit) : ""
            }
            .onChange(of: prefs) { _, newValue in
                notificationService.updatePreferences(newValue)
            }
        }
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        Section("월 예산 한도 [충동구매 방지]") {
            HStack {
                TextField("한도 (원)", text: $budgetText)
                    .keyboardType(.numberPad)
                Button("저장") {
                    monthlyBudgetLimit = Int(budgetText) ?? 0
                }
                .disabled(Int(budgetText) ?? -1 < 0)
            }
            if monthlyBudgetLimit > 0 {
                Text("현재 한도: \(formatKRW(monthlyBudgetLimit))원")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        Section("알림 [피로도 방지]") {
            Toggle("알림 받기", isOn: $prefs.isEnabled)

            Stepper(value: $prefs.cooldownHours, in: 1...48) {
                HStack {
                    Text("쿨타임")
                    Spacer()
                    Text("\(prefs.cooldownHours)시간")
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $prefs.quietStartHour, in: 0...23) {
                HStack {
                    Text("시작 시각")
                    Spacer()
                    Text("\(prefs.quietStartHour)시")
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $prefs.quietEndHour, in: 1...24) {
                HStack {
                    Text("종료 시각")
                    Spacer()
                    Text("\(prefs.quietEndHour)시")
                        .foregroundStyle(.secondary)
                }
            }

            Text("동일 상품은 \(prefs.cooldownHours)시간 내에 중복 알림되지 않으며, \(prefs.quietStartHour)시~\(prefs.quietEndHour)시 사이에만 알림이 울려요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Folder Section

    private var folderSection: some View {
        Section("폴더 관리") {
            ForEach(folders) { folder in
                HStack {
                    Text(folder.name)
                    Spacer()
                    Text("\(folder.products.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: deleteFolder)

            HStack {
                TextField("새 폴더명", text: $newFolderName)
                Button("추가") {
                    addFolder()
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("앱 정보") {
            HStack {
                Text("버전")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
            Text("KreamPrice — 개인 가격 추적 및 스마트 쇼핑 보조 앱")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func addFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = WishlistFolder(name: trimmed)
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
    }

    private func deleteFolder(at offsets: IndexSet) {
        for idx in offsets {
            modelContext.delete(folders[idx])
        }
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func formatKRW(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
