import SwiftUI

/// 사용자 설정 화면 (월 예산 한도, 알림 등)
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var budgetText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                budgetSection
                notificationSection
                aboutSection
            }
            .navigationTitle("설정")
            .onAppear {
                budgetText = settings.monthlyBudget > 0 ? String(settings.monthlyBudget) : ""
            }
        }
    }

    // MARK: - Sections

    private var budgetSection: some View {
        Section {
            TextField("월 예산 (원)", text: $budgetText)
                .keyboardType(.numberPad)
                .onChange(of: budgetText) { newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits != newValue {
                        budgetText = digits
                    }
                    settings.monthlyBudget = Int(digits) ?? 0
                }

            HStack {
                Text("현재 설정")
                Spacer()
                Text("\(settings.monthlyBudget.formatted())원")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("월 예산 한도")
        } footer: {
            Text("한 달 동안 지출할 수 있는 최대 금액을 설정하세요.")
        }
    }

    private var notificationSection: some View {
        Section("알림") {
            Toggle("가격 알림 받기", isOn: $settings.notificationsEnabled)
            Text("동일한 상품에 대한 알림은 최대 6시간에 한 번만 전송됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("정보") {
            HStack {
                Text("앱 이름")
                Spacer()
                Text("nax2")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("버전")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}
