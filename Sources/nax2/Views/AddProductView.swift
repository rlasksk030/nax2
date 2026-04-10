import SwiftUI
import SwiftData

// MARK: - 상품 추가 화면
// 클립보드에서 KREAM URL 자동 감지 후 상품 정보를 입력합니다.
// 사이즈, 발매가, 목표가, 폴더까지 한 화면에서 설정 가능합니다.

struct AddProductView: View {

    // MARK: - SwiftData
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WishlistFolder.createdAt) private var folders: [WishlistFolder]

    // MARK: - 입력 상태
    @State private var name = ""
    @State private var brand = ""
    @State private var size = ""           // [기능 7]
    @State private var kreamId = ""
    @State private var kreamUrlInput = ""

    // 가격 입력 (문자열로 받아서 Int 변환)
    @State private var retailPriceText = ""   // [기능 4] 공식 발매가
    @State private var basePriceText = ""     // 기준가 (필수)
    @State private var targetPriceText = ""   // [기능 1] 목표가

    // 폴더 선택 [기능 9]
    @State private var selectedFolder: WishlistFolder?

    // UI 상태
    @State private var clipboardDetected = false
    @State private var showClipboardAlert = false
    @State private var detectedURL = ""
    @State private var validationError: String?
    @State private var showFolderPicker = false

    // MARK: - 계산 속성
    private var basePrice: Int { Int(basePriceText.filter(\.isNumber)) ?? 0 }
    private var retailPrice: Int { Int(retailPriceText.filter(\.isNumber)) ?? 0 }
    private var targetPrice: Int { Int(targetPriceText.filter(\.isNumber)) ?? 0 }
    private var isFormValid: Bool { !name.isEmpty && basePrice > 0 }

    // 예상 결제금액 미리 계산 (입력하면서 실시간 표시)
    private var previewEstimate: Int? {
        guard basePrice > 0 else { return nil }
        let temp = KreamProduct(name: name, brand: brand, basePrice: basePrice)
        return temp.estimatedTotalPayment
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {

                // 클립보드 감지 배너
                if clipboardDetected {
                    Section {
                        ClipboardDetectedBanner(url: detectedURL) {
                            applyClipboardData()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // KREAM URL 입력
                Section("KREAM 링크") {
                    HStack {
                        TextField("https://kream.co.kr/products/...", text: $kreamUrlInput)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: kreamUrlInput) { _, newValue in
                                if let id = KreamLinkParser.parseKreamId(from: newValue) {
                                    kreamId = id
                                }
                            }
                        if !kreamId.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    if !kreamId.isEmpty {
                        Text("상품 ID: \(kreamId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 기본 정보
                Section("상품 정보") {
                    TextField("상품명 *", text: $name)
                    TextField("브랜드", text: $brand)

                    // [기능 7] 사이즈 입력
                    HStack {
                        TextField("사이즈", text: $size)
                            .frame(width: 80)
                        Text("예: 270, M, L, FREE")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 가격 설정
                Section("가격 설정") {

                    // 기준가 (필수)
                    PriceInputRow(
                        label: "기준가 *",
                        placeholder: "즐겨찾기 추가 시점 가격",
                        text: $basePriceText,
                        tint: .primary
                    )

                    // [기능 4] 공식 발매가
                    PriceInputRow(
                        label: "공식 발매가",
                        placeholder: "크더싼 필터 기준 (선택)",
                        text: $retailPriceText,
                        tint: .secondary
                    )

                    // [기능 1] 목표가
                    PriceInputRow(
                        label: "내 목표가",
                        placeholder: "이 가격이면 산다! (선택)",
                        text: $targetPriceText,
                        tint: .green
                    )
                }

                // 결제 예상금액 미리보기 [CORE 3]
                if let estimate = previewEstimate {
                    Section("예상 결제금액") {
                        HStack {
                            Text("즉시구매가")
                            Spacer()
                            Text(KreamProduct.priceString(basePrice))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("검수비 (약 1%)")
                            Spacer()
                            Text(KreamProduct.priceString(max(1000, Int(Double(basePrice) * 0.01))))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("배송비")
                            Spacer()
                            Text("3,000원")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("총 예상 금액")
                                .bold()
                            Spacer()
                            Text(KreamProduct.priceString(estimate))
                                .bold()
                                .foregroundColor(.blue)
                        }
                    }
                }

                // [기능 9] 폴더 선택
                Section("폴더") {
                    if folders.isEmpty {
                        Text("폴더가 없어요. 위시리스트 탭에서 폴더를 만들어보세요.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("폴더 선택", selection: $selectedFolder) {
                            Text("폴더 없음").tag(Optional<WishlistFolder>.none)
                            ForEach(folders) { folder in
                                Text(folder.name).tag(Optional(folder))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                // 유효성 오류 메시지
                if let error = validationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("상품 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("추가") { save() }
                        .bold()
                        .disabled(!isFormValid)
                }
            }
            .onAppear {
                checkClipboard()
            }
        }
    }

    // MARK: - 클립보드 확인
    private func checkClipboard() {
        guard let detected = KreamLinkParser.detectFromClipboard() else { return }
        detectedURL = detected.url
        clipboardDetected = true
    }

    private func applyClipboardData() {
        guard let detected = KreamLinkParser.detectFromClipboard() else { return }
        kreamId = detected.kreamId
        kreamUrlInput = detected.url
        clipboardDetected = false
    }

    // MARK: - 저장
    private func save() {
        // 유효성 검사
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "상품명을 입력해주세요."
            return
        }
        guard basePrice > 0 else {
            validationError = "기준가를 입력해주세요."
            return
        }

        validationError = nil

        let product = KreamProduct(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            size: size.trimmingCharacters(in: .whitespaces),
            imageUrl: "",
            kreamId: kreamId,
            retailPrice: retailPrice,
            basePrice: basePrice,
            targetPrice: targetPrice
        )

        // 폴더 할당 [기능 9]
        product.folder = selectedFolder

        // 초기 가격 히스토리 생성 [기능 5]
        let initialHistory = PriceHistory(price: basePrice)
        initialHistory.product = product
        product.priceHistory.append(initialHistory)

        modelContext.insert(product)
        modelContext.insert(initialHistory)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationError = "저장 오류: \(error.localizedDescription)"
        }
    }
}

// MARK: - 가격 입력 행 컴포넌트
private struct PriceInputRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let tint: Color

    private var formattedValue: String {
        guard let number = Int(text.filter(\.isNumber)), number > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: number)) ?? "\(number)") + "원"
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(tint == .secondary ? .secondary : .primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 180)
                if !formattedValue.isEmpty {
                    Text(formattedValue)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - 클립보드 감지 배너
private struct ClipboardDetectedBanner: View {
    let url: String
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("KREAM URL이 클립보드에 있어요!")
                    .font(.caption.bold())
                Text(url)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("적용") { onApply() }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    AddProductView()
        .modelContainer(for: [KreamProduct.self, PriceHistory.self, WishlistFolder.self], inMemory: true)
}
