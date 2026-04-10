//
//  AddProductView.swift
//  KreamPrice
//
//  상품 추가 화면.
//  - 클립보드에 KREAM 링크가 있으면 자동 감지 후 kreamId / size 선입력
//  - 필수 필드: 이름 / 브랜드 / 사이즈 / 발매가 / 현재가 / 목표가 / 이미지 URL
//  - basePrice 는 currentPrice 를 그대로 스냅샷 저장
//  - [추가 기능 9] 폴더 선택 (기존 폴더 선택 또는 새로 만들기)
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - AddProductView

struct AddProductView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var size: String = ""
    @State private var retailPriceText: String = ""
    @State private var currentPriceText: String = ""
    @State private var targetPriceText: String = ""
    @State private var kreamId: String = ""
    @State private var imageUrl: String = ""

    @State private var selectedFolder: WishlistFolder?
    @State private var newFolderName: String = ""
    @State private var showCreateFolder: Bool = false

    @State private var showClipboardHint: Bool = false

    // MARK: - Folder Query

    @Query(sort: \WishlistFolder.createdAt, order: .forward)
    private var folders: [WishlistFolder]

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !brand.trimmingCharacters(in: .whitespaces).isEmpty
        && !size.trimmingCharacters(in: .whitespaces).isEmpty
        && Int(currentPriceText) ?? 0 > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if showClipboardHint {
                    Section {
                        Label("클립보드에서 KREAM 링크를 감지했어요!", systemImage: "link")
                            .foregroundStyle(.blue)
                    }
                }

                Section("기본 정보") {
                    TextField("브랜드 (예: Nike)", text: $brand)
                    TextField("상품명 (예: Dunk Low Retro)", text: $name)
                    TextField("사이즈 (예: 270)", text: $size)
                }

                Section("가격 정보") {
                    TextField("공식 발매가 (원)", text: $retailPriceText)
                        .keyboardType(.numberPad)
                    TextField("현재가 (원)", text: $currentPriceText)
                        .keyboardType(.numberPad)
                    TextField("목표가 (원)", text: $targetPriceText)
                        .keyboardType(.numberPad)
                }

                Section("KREAM 연동") {
                    TextField("KREAM 상품 ID", text: $kreamId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("이미지 URL", text: $imageUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("클립보드에서 링크 불러오기", systemImage: "doc.on.clipboard")
                    }
                }

                Section("폴더 (선택)") {
                    Picker("폴더", selection: $selectedFolder) {
                        Text("미분류").tag(nil as WishlistFolder?)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(folder as WishlistFolder?)
                        }
                    }

                    if showCreateFolder {
                        HStack {
                            TextField("새 폴더명", text: $newFolderName)
                            Button("생성") {
                                createFolder()
                            }
                            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button("새 폴더 만들기") { showCreateFolder = true }
                    }
                }
            }
            .navigationTitle("상품 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { save() }
                        .disabled(!isValid)
                        .fontWeight(.bold)
                }
            }
            .task {
                // 화면 진입 시 클립보드 자동 감지
                pasteFromClipboard(silentIfMissing: true)
            }
        }
    }

    // MARK: - Actions

    /// 클립보드에서 KREAM 링크를 읽어 kreamId 및 size 자동 채움.
    private func pasteFromClipboard(silentIfMissing: Bool = false) {
        guard let raw = UIPasteboard.general.string else {
            if !silentIfMissing { showClipboardHint = false }
            return
        }
        guard let parsed = KreamLinkParser.parse(raw) else {
            if !silentIfMissing { showClipboardHint = false }
            return
        }
        kreamId = parsed.kreamId
        if let s = parsed.size, !s.isEmpty {
            size = s
        }
        showClipboardHint = true
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = WishlistFolder(name: trimmed)
        modelContext.insert(folder)
        try? modelContext.save()
        selectedFolder = folder
        newFolderName = ""
        showCreateFolder = false
    }

    private func save() {
        let current = Int(currentPriceText) ?? 0
        let retail = Int(retailPriceText) ?? 0
        let target = Int(targetPriceText) ?? 0

        let product = KreamProduct(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            size: size.trimmingCharacters(in: .whitespaces),
            retailPrice: retail,
            basePrice: current,     // [CORE 1] 추가 시점 스냅샷
            currentPrice: current,
            targetPrice: target,
            kreamId: kreamId.trimmingCharacters(in: .whitespaces),
            imageUrl: imageUrl.trimmingCharacters(in: .whitespaces),
            folder: selectedFolder
        )

        modelContext.insert(product)

        // [추가 기능 5] 초기 히스토리 한 건도 함께 기록
        let initialHistory = PriceHistory(price: current, recordedAt: .now, product: product)
        modelContext.insert(initialHistory)
        product.priceHistory.append(initialHistory)

        try? modelContext.save()
        dismiss()
    }
}
