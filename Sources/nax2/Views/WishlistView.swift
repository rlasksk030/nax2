import SwiftUI
import SwiftData

// MARK: - 위시리스트 메인 화면
// 즐겨찾기 상품 목록, 크더싼 필터, 폴더별 그룹핑,
// 예산 경고 배지, 상품 추가/삭제 기능을 제공합니다.

struct WishlistView: View {

    // MARK: - SwiftData
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KreamProduct.addedAt, order: .reverse)
    private var allProducts: [KreamProduct]

    @Query(sort: \WishlistFolder.createdAt)
    private var folders: [WishlistFolder]

    // MARK: - 상태
    @State private var showAddProduct = false
    @State private var filterCheaperThanRetail = false  // [기능 4] 크더싼 필터
    @State private var selectedFolder: WishlistFolder?  // [기능 9] 폴더 필터
    @State private var showFolderManager = false
    @State private var searchText = ""
    @State private var productToDelete: KreamProduct?
    @State private var showDeleteAlert = false

    // MARK: - 예산 설정 [기능 6]
    @AppStorage("monthlyBudget") private var monthlyBudget: Int = 0

    // MARK: - 필터링된 상품 목록
    private var filteredProducts: [KreamProduct] {
        var result = allProducts

        // 폴더 필터
        if let folder = selectedFolder {
            result = result.filter { $0.folder?.name == folder.name }
        }

        // 크더싼 필터 [기능 4]
        if filterCheaperThanRetail {
            result = result.filter { $0.isCheaperThanRetail }
        }

        // 검색 필터
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.brand.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    // MARK: - 예산 초과 여부 [기능 6]
    private var budgetWarning: BudgetStatus {
        guard monthlyBudget > 0 else { return .notSet }
        // 목표가 도달 상품들의 합산 금액
        let targetReachedTotal = allProducts
            .filter { $0.hasReachedTargetPrice }
            .reduce(0) { $0 + $1.estimatedTotalPayment }
        if targetReachedTotal > monthlyBudget {
            return .exceeded(targetReachedTotal)
        }
        return .ok(targetReachedTotal)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // 예산 경고 배너 [기능 6]
                budgetBannerView

                // 필터 툴바
                filterBar

                // 상품 목록
                if filteredProducts.isEmpty {
                    emptyStateView
                } else {
                    productListView
                }
            }
            .navigationTitle("위시리스트")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "상품명 또는 브랜드 검색")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showFolderManager = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddProduct = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddProduct) {
                AddProductView()
            }
            .sheet(isPresented: $showFolderManager) {
                FolderManagerView(selectedFolder: $selectedFolder)
            }
            .alert("상품 삭제", isPresented: $showDeleteAlert, presenting: productToDelete) { product in
                Button("삭제", role: .destructive) { delete(product) }
                Button("취소", role: .cancel) {}
            } message: { product in
                Text("\(product.name)을(를) 위시리스트에서 삭제할까요?")
            }
        }
    }

    // MARK: - 예산 배너 [기능 6]
    @ViewBuilder
    private var budgetBannerView: some View {
        switch budgetWarning {
        case .exceeded(let total):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("예산 한도 초과!")
                        .font(.caption.bold())
                    Text("목표가 도달 상품 합계: \(KreamProduct.priceString(total))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                NavigationLink(destination: SettingsView()) {
                    Text("설정")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12))

        case .ok(let total) where monthlyBudget > 0:
            let remaining = monthlyBudget - total
            let progress = Double(total) / Double(monthlyBudget)
            VStack(spacing: 4) {
                HStack {
                    Text("이번달 예산")
                        .font(.caption.bold())
                    Spacer()
                    Text("잔여 \(KreamProduct.priceString(remaining))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ProgressView(value: progress)
                    .tint(progress > 0.8 ? .orange : .blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

        default:
            EmptyView()
        }
    }

    // MARK: - 필터 바
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {

                // 전체 필터
                FilterChip(
                    title: "전체",
                    isSelected: selectedFolder == nil && !filterCheaperThanRetail
                ) {
                    selectedFolder = nil
                    filterCheaperThanRetail = false
                }

                // 크더싼 필터 [기능 4]
                FilterChip(
                    title: "크더싼 🏷️",
                    isSelected: filterCheaperThanRetail
                ) {
                    filterCheaperThanRetail.toggle()
                    selectedFolder = nil
                }

                // 폴더 필터 칩 [기능 9]
                ForEach(folders) { folder in
                    FilterChip(
                        title: folder.name,
                        isSelected: selectedFolder?.id == folder.id
                    ) {
                        selectedFolder = selectedFolder?.id == folder.id ? nil : folder
                        filterCheaperThanRetail = false
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 상품 목록
    private var productListView: some View {
        List {
            // 상품 통계 헤더
            Section {
                HStack {
                    Label("\(filteredProducts.count)개", systemImage: "heart.fill")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Spacer()
                    if filterCheaperThanRetail {
                        Text("크더싼 상품만 표시 중")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            // 상품 카드 목록
            ForEach(filteredProducts) { product in
                NavigationLink(destination: ProductDetailView(product: product)) {
                    ProductRowView(product: product)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        productToDelete = product
                        showDeleteAlert = true
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        // 폴더 할당 (향후 폴더 선택 시트 추가)
                    } label: {
                        Label("폴더", systemImage: "folder.badge.plus")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 빈 상태
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(filterCheaperThanRetail ? "크더싼 상품이 없어요" : "위시리스트가 비어있어요")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("KREAM 상품 URL을 붙여넣어 추가해보세요")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("상품 추가") { showAddProduct = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 상품 삭제
    private func delete(_ product: KreamProduct) {
        modelContext.delete(product)
        try? modelContext.save()
    }
}

// MARK: - 상품 행 카드 뷰
struct ProductRowView: View {

    let product: KreamProduct

    var body: some View {
        HStack(spacing: 12) {

            // 상품 이미지 (placeholder)
            AsyncImage(url: URL(string: product.imageUrl)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 상품 정보
            VStack(alignment: .leading, spacing: 4) {

                // 상단: 브랜드 + 배지
                HStack(spacing: 4) {
                    Text(product.brand)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 크더싼 배지 [기능 4]
                    if product.isCheaperThanRetail {
                        Text("크더싼 🏷️")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }

                    // 목표가 달성 배지
                    if product.hasReachedTargetPrice {
                        Text("목표가 🎯")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }

                // 상품명
                Text(product.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                // 사이즈 태그 [기능 7]
                if let size = product.displaySize {
                    Text("[\(size)]")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Spacer()

            // 가격 정보
            VStack(alignment: .trailing, spacing: 4) {

                // 현재가
                Text(product.currentPriceString)
                    .font(.subheadline.bold())

                // 변동폭 [CORE 2]
                HStack(spacing: 2) {
                    Image(systemName: product.priceDirection.sfSymbol)
                        .font(.caption2)
                    Text(product.priceDeltaString)
                        .font(.caption)
                }
                .foregroundColor(product.priceDelta == 0 ? .secondary : product.priceDirection.color)

                // 변동률
                if product.priceDelta != 0 {
                    Text(product.priceChangeRateString)
                        .font(.caption2)
                        .foregroundColor(product.priceDirection.color)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 필터 칩 컴포넌트
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - 예산 상태 열거형 [기능 6]
private enum BudgetStatus {
    case notSet
    case ok(Int)
    case exceeded(Int)
}

// MARK: - 폴더 관리 시트 [기능 9]
struct FolderManagerView: View {

    @Binding var selectedFolder: WishlistFolder?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WishlistFolder.createdAt) private var folders: [WishlistFolder]
    @State private var newFolderName = ""
    @State private var showAddFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showAddFolder = true
                    } label: {
                        Label("새 폴더 추가", systemImage: "folder.badge.plus")
                    }
                }

                Section("내 폴더") {
                    ForEach(folders) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading) {
                                Text(folder.name).font(.body)
                                Text("\(folder.productCountString) · 예상 \(folder.totalEstimatedPaymentString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFolder = selectedFolder?.id == folder.id ? nil : folder
                            dismiss()
                        }
                    }
                    .onDelete(perform: deleteFolders)
                }
            }
            .navigationTitle("폴더 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
            .alert("새 폴더", isPresented: $showAddFolder) {
                TextField("폴더 이름", text: $newFolderName)
                Button("만들기") { createFolder() }
                Button("취소", role: .cancel) { newFolderName = "" }
            }
        }
    }

    private func createFolder() {
        guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let folder = WishlistFolder(name: newFolderName)
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
    }

    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(folders[index])
        }
        try? modelContext.save()
    }
}

#Preview {
    WishlistView()
        .modelContainer(for: [KreamProduct.self, PriceHistory.self, WishlistFolder.self], inMemory: true)
}
