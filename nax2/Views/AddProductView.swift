import SwiftUI

/// 새 상품을 위시리스트에 추가하는 시트
struct AddProductView: View {
    @EnvironmentObject var store: ProductStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var size: String = ""
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
                Section("상품 정보") {
                    TextField("브랜드 (예: Nike)", text: $brand)
                    TextField("상품명", text: $name)
                    TextField("사이즈 (예: 270)", text: $size)
                }

                Section("가격") {
                    TextField("현재가", text: $currentPriceText)
                        .keyboardType(.numberPad)
                    TextField("목표가", text: $targetPriceText)
                        .keyboardType(.numberPad)
                    TextField("정가", text: $retailPriceText)
                        .keyboardType(.numberPad)
                }
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
        }
    }

    private func saveAndDismiss() {
        let current = Int(currentPriceText) ?? 0
        let target = Int(targetPriceText) ?? current
        let retail = Int(retailPriceText) ?? current

        let product = KreamProduct(
            name: name,
            brand: brand,
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
