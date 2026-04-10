import SwiftUI

/// 새 상품을 위시리스트에 추가하는 시트.
/// 상단의 Kream URL 입력란에 링크를 붙여넣으면
/// 자동으로 상품 정보가 채워집니다.
struct AddProductView: View {
    @EnvironmentObject var store: ProductStore
    @Environment(\.dismiss) private var dismiss

    // Kream URL 자동 입력
    @State private var kreamURL: String = ""
    @State private var isFetching: Bool = false
    @State private var fetchError: String? = nil
    @State private var fetchStatus: String? = nil
    @State private var lastFetchedURL: String = ""

    // 상품 정보
    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var size: String = ""
    @State private var imageURL: String = ""
    @State private var currentPriceText: String = ""
    @State private var targetPriceText: String = ""
    @State private var retailPriceText: String = ""

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let current = Int(currentPriceText) ?? 0
        return !trimmedName.isEmpty && !trimmedBrand.isEmpty && current > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                kreamLinkSection
                productInfoSection
                priceSection
            }
            .navigationTitle("상품 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveAndDismiss() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: kreamURL) {
                autoFetchIfNeeded()
            }
        }
    }

    // MARK: - Sections

    private var kreamLinkSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("https://kream.co.kr/products/…", text: $kreamURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { fetchInfoTask(force: true) }

                if isFetching {
                    ProgressView()
                } else if !kreamURL.isEmpty {
                    Button {
                        fetchInfoTask(force: true)
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let status = fetchStatus {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let err = fetchError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Kream 링크")
        } footer: {
            Text("크림 상품 페이지 URL을 붙여넣으면 브랜드·상품명·가격이 자동으로 채워집니다.")
        }
    }

    private var productInfoSection: some View {
        Section("상품 정보") {
            TextField("브랜드 (예: Nike)", text: $brand)
            TextField("상품명", text: $name)
            TextField("사이즈 (예: 270)", text: $size)
        }
    }

    private var priceSection: some View {
        Section("가격") {
            TextField("현재가", text: $currentPriceText)
                .keyboardType(.numberPad)
            TextField("목표가", text: $targetPriceText)
                .keyboardType(.numberPad)
            TextField("정가", text: $retailPriceText)
                .keyboardType(.numberPad)
        }
    }

    // MARK: - Fetch logic

    /// 사용자가 URL을 타이핑/붙여넣기 할 때 자동으로 유효한 Kream 링크인지 판별해 fetch 수행
    private func autoFetchIfNeeded() {
        let trimmed = kreamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastFetchedURL,
              trimmed.lowercased().hasPrefix("http"),
              trimmed.lowercased().contains("kream.co.kr/products/") else {
            return
        }
        fetchInfoTask(force: false)
    }

    private func fetchInfoTask(force: Bool) {
        let url = kreamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        if !force && url == lastFetchedURL { return }

        lastFetchedURL = url
        isFetching = true
        fetchError = nil
        fetchStatus = nil

        Task { @MainActor in
            defer { isFetching = false }
            do {
                let info = try await KreamService.shared.fetchProductInfo(from: url)
                applyFetchedInfo(info)
            } catch let error as KreamServiceError {
                fetchError = error.errorDescription
            } catch {
                fetchError = "가져오기 실패: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func applyFetchedInfo(_ info: KreamProductInfo) {
        var filled: [String] = []

        if let b = info.brand, !b.isEmpty {
            brand = b
            filled.append("브랜드")
        }
        if let n = info.name, !n.isEmpty {
            name = n
            filled.append("상품명")
        }
        if let img = info.imageURL, !img.isEmpty {
            imageURL = img
        }
        if let p = info.currentPrice, p > 0 {
            currentPriceText = String(p)
            filled.append("현재가")
            // 목표가 기본값: 현재가의 95%
            if targetPriceText.isEmpty {
                targetPriceText = String(Int(Double(p) * 0.95))
            }
        }
        if let r = info.retailPrice, r > 0 {
            retailPriceText = String(r)
            filled.append("정가")
        }

        if filled.isEmpty {
            fetchError = "상품 정보를 찾지 못했습니다. 수동으로 입력해주세요."
        } else {
            fetchStatus = "자동 입력: \(filled.joined(separator: ", "))"
        }
    }

    // MARK: - Save

    private func saveAndDismiss() {
        let current = Int(currentPriceText) ?? 0
        let target = Int(targetPriceText) ?? current
        let retail = Int(retailPriceText) ?? current
        let savedURL = kreamURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let product = KreamProduct(
            name: name,
            brand: brand,
            imageURL: imageURL,
            kreamURL: savedURL,
            currentPrice: current,
            targetPrice: target,
            size: size,
            retailPrice: retail,
            priceHistory: [PriceRecord(price: current)]
        )
        store.add(product)
        dismiss()
    }
}

#Preview {
    AddProductView()
        .environmentObject(ProductStore())
}
