import SwiftUI

/// 사용자 설정 화면 (월 예산 한도, 알림, 쿨타임 등)
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var budgetText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                budgetSection
                notificationSection
                cooldownSection
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
                .onChange(of: budgetText) {
                    let digits = budgetText.filter { $0.isNumber }
                    if digits != budgetText {
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
        }
    }

    private var cooldownSection: some View {
        Section {
            Stepper(
                value: $settings.notificationCooldownHours,
                in: NotificationService.minCooldownHours...NotificationService.maxCooldownHours,
                step: 1
            ) {
                HStack {
                    Text("쿨타임")
                    Spacer()
                    Text("\(Int(settings.notificationCooldownHours))시간")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                quickButton(hours: 1)
                quickButton(hours: 3)
                quickButton(hours: 6)
                quickButton(hours: 12)
                quickButton(hours: 24)
            }
        } header: {
            Text("알림 쿨타임")
        } footer: {
            Text("동일한 상품에 대한 알림은 설정한 시간에 한 번만 전송됩니다. (\(Int(NotificationService.minCooldownHours))~\(Int(NotificationService.maxCooldownHours))시간)")
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

    // MARK: - Helpers

    private func quickButton(hours: Double) -> some View {
        let isSelected = Int(settings.notificationCooldownHours) == Int(hours)
        return Button {
            settings.notificationCooldownHours = hours
        } label: {
            Text("\(Int(hours))h")
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}
