import SwiftUI
import UserNotifications

// MARK: - 설정 화면
// 월 예산 한도, 알림 시간대, 알림 쿨타임을 설정합니다.
// 모든 설정은 @AppStorage(UserDefaults)에 영구 저장됩니다.

struct SettingsView: View {

    // MARK: - 예산 설정 [기능 6]
    @AppStorage("monthlyBudget") private var monthlyBudget: Int = 0

    // MARK: - 알림 설정 [기능 8]
    @AppStorage("notificationStartHour") private var notificationStartHour: Int = 9
    @AppStorage("notificationEndHour")   private var notificationEndHour: Int = 22
    @AppStorage("notificationCooldownHours") private var cooldownHours: Double = 6.0

    // MARK: - 상태
    @State private var budgetText = ""
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetAlert = false

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {

                // 알림 권한 상태 배너
                notificationStatusSection

                // 예산 한도 설정 [기능 6]
                budgetSection

                // 알림 시간대 설정 [기능 8]
                notificationTimeSection

                // 알림 쿨타임 설정 [기능 8]
                cooldownSection

                // 앱 정보
                appInfoSection

                // 초기화
                resetSection
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await checkNotificationStatus()
            }
            .onAppear {
                budgetText = monthlyBudget > 0 ? "\(monthlyBudget)" : ""
            }
            .alert("설정 초기화", isPresented: $showResetAlert) {
                Button("초기화", role: .destructive) { resetAllSettings() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("모든 설정을 기본값으로 초기화할까요?")
            }
        }
    }

    // MARK: - 알림 권한 상태 섹션
    @ViewBuilder
    private var notificationStatusSection: some View {
        switch notificationStatus {
        case .authorized:
            Section {
                Label("알림 권한 허용됨", systemImage: "bell.fill")
                    .foregroundColor(.green)
            }
        case .denied:
            Section {
                HStack {
                    Label("알림 권한 거부됨", systemImage: "bell.slash.fill")
                        .foregroundColor(.red)
                    Spacer()
                    Button("설정 열기") {
                        openSystemSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                }
            } footer: {
                Text("가격 하락 알림을 받으려면 시스템 설정에서 알림을 허용해주세요.")
            }
        case .notDetermined:
            Section {
                Button {
                    Task { await NotificationService.shared.requestPermission() }
                } label: {
                    Label("알림 권한 요청하기", systemImage: "bell.badge")
                        .foregroundColor(.blue)
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - 예산 설정 [기능 6]
    private var budgetSection: some View {
        Section {
            HStack {
                Text("월 예산 한도")
                Spacer()
                TextField("미설정", text: $budgetText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .onChange(of: budgetText) { _, newValue in
                        let raw = Int(newValue.filter(\.isNumber)) ?? 0
                        monthlyBudget = raw
                        NotificationService.shared.updateSettings(
                            startHour: notificationStartHour,
                            endHour: notificationEndHour,
                            cooldownHours: cooldownHours
                        )
                    }
                Text("원")
                    .foregroundColor(.secondary)
            }

            if monthlyBudget > 0 {
                Text("설정된 예산: \(KreamProduct.priceString(monthlyBudget))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("예산 관리")
        } footer: {
            Text("목표가에 도달한 상품들의 합산 결제 예상금액이 이 한도를 초과하면 경고를 표시합니다.")
        }
    }

    // MARK: - 알림 시간대 설정 [기능 8]
    private var notificationTimeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("알림 시작 시각")
                    Spacer()
                    Stepper("\(notificationStartHour)시", value: $notificationStartHour, in: 0...23)
                        .fixedSize()
                        .onChange(of: notificationStartHour) { _, _ in saveNotificationSettings() }
                }

                HStack {
                    Text("알림 종료 시각")
                    Spacer()
                    Stepper("\(notificationEndHour)시", value: $notificationEndHour, in: 0...23)
                        .fixedSize()
                        .onChange(of: notificationEndHour) { _, _ in saveNotificationSettings() }
                }

                if notificationStartHour >= notificationEndHour {
                    Label("시작 시각이 종료 시각보다 늦습니다.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack {
                    Image(systemName: "moon.zzz")
                        .foregroundColor(.indigo)
                        .font(.caption)
                    Text("오전 \(notificationStartHour)시 ~ 오후 \(notificationEndHour)시에만 알림 수신")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

        } header: {
            Text("알림 허용 시간대")
        } footer: {
            Text("설정된 시간 외에는 가격 하락 알림이 발송되지 않아 알림 피로도를 줄여줍니다.")
        }
    }

    // MARK: - 알림 쿨타임 설정 [기능 8]
    private var cooldownSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("동일 상품 재알림 최소 간격")
                    Spacer()
                    Text("\(Int(cooldownHours))시간")
                        .foregroundColor(.secondary)
                        .bold()
                }

                Slider(value: $cooldownHours, in: 1...24, step: 1)
                    .tint(.blue)
                    .onChange(of: cooldownHours) { _, _ in saveNotificationSettings() }

                HStack {
                    Text("1시간")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("24시간")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("같은 상품에 대한 알림은 최소 \(Int(cooldownHours))시간 이후에 다시 받습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

        } header: {
            Text("스마트 알림 쿨타임")
        } footer: {
            Text("짧은 쿨타임은 실시간 알림을 제공하지만 알림 피로도가 높아질 수 있습니다.")
        }
    }

    // MARK: - 앱 정보
    private var appInfoSection: some View {
        Section("앱 정보") {
            HStack {
                Text("버전")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("데이터 저장")
                Spacer()
                Text("SwiftData (로컬)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("가격 갱신")
                Spacer()
                Text("앱 실행 시 자동 갱신")
                    .foregroundColor(.secondary)
            }

            Label("KREAM 공식 서비스와 무관한 개인 앱입니다.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 초기화 섹션
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("설정 초기화")
                }
            }
        }
    }

    // MARK: - 헬퍼 함수
    private func checkNotificationStatus() async {
        let status = await NotificationService.shared.checkPermissionStatus()
        notificationStatus = status
    }

    private func saveNotificationSettings() {
        NotificationService.shared.updateSettings(
            startHour: notificationStartHour,
            endHour: notificationEndHour,
            cooldownHours: cooldownHours
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func resetAllSettings() {
        monthlyBudget = 0
        notificationStartHour = 9
        notificationEndHour = 22
        cooldownHours = 6.0
        budgetText = ""
        saveNotificationSettings()
    }
}

#Preview {
    SettingsView()
}
