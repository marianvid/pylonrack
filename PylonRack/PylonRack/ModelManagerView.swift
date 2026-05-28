import SwiftUI

// MARK: - Data models

struct HFModel: Identifiable, Decodable {
    let id:          String
    let downloads:   Int?
    let likes:       Int?
    let description: String?

    var displayName: String { id }

    enum CodingKeys: String, CodingKey {
        case id, downloads, likes
        case description = "description"
    }
}

struct HFModelFile: Identifiable {
    let id   = UUID()
    let name: String
    let size: Int
    var sizeGB: Double { Double(size) / 1_073_741_824 }
    var quantType: String {
        let n = name.uppercased()
        for q in ["Q8_0","Q6_K","Q5_K_M","Q5_K_S","Q5_0","Q4_K_M","Q4_K_S","Q4_0","Q3_K_M","Q3_K_S","Q3_K_L","Q2_K","IQ4_NL","IQ3_M","IQ2_M","BF16","F16","F32"] {
            if n.contains(q) { return q }
        }
        return "?"
    }
}

struct LocalGGUF: Identifiable {
    let id          = UUID()
    let displayName: String
    let fullPath:    String
    let sizeGB:      Double
}

// MARK: - ModelManagerView

struct ModelManagerView: View {
    @ObservedObject var conn: SlotConnection

    enum Tab { case local, browse }
    @State private var tab:            Tab        = .local
    @State private var localModels:    [LocalGGUF] = []
    @State private var searchQuery:    String     = ""
    @State private var searchResults:  [HFModel]  = []
    @State private var isSearching:    Bool       = false
    @State private var selectedModel:  HFModel?   = nil
    @State private var modelFiles:     [HFModelFile] = []
    @State private var isLoadingFiles: Bool       = false
    @State private var downloadingFile: String?   = nil
    @State private var downloadProgress: Double   = 0
    @State private var statusMessage:  String     = ""
    @State private var deleteTarget:   LocalGGUF? = nil
    @State private var showDeleteAlert: Bool      = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("Local Models", tab: .local, icon: "internaldrive")
                tabButton("Browse HuggingFace", tab: .browse, icon: "magnifyingglass")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if tab == .local {
                localTab
            } else {
                browseTab
            }
        }
        .onAppear { loadLocalModels() }
        .onChange(of: conn.actionResultToken) { _, _ in
            if let result = conn.lastActionResult { handleControlsUpdate(result) }
        }
    }

    // MARK: - Tab button

    private func tabButton(_ label: String, tab t: Tab, icon: String) -> some View {
        Button {
            tab = t
            // Don't refresh local models during active download — would show partial file
            if t == .local && downloadingFile == nil { loadLocalModels() }
            if t == .browse && searchResults.isEmpty { searchHF() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(tab == t ? Color.accentColor.opacity(0.12) : Color.clear)
            .foregroundStyle(tab == t ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Local tab

    private var localTab: some View {
        VStack(spacing: 0) {
            if localModels.isEmpty {
                emptyLocal
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(localModels) { model in
                            localModelRow(model)
                            Divider().padding(.leading, 25)
                        }
                    }
                    .padding(.horizontal, 15)
                }
            }
        }
        .alert("Delete Model", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { deleteModel(t) }
            }
        } message: {
            Text("Delete \(deleteTarget?.displayName ?? "this model")? This cannot be undone.")
        }
    }

    private var emptyLocal: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.system(size: 32)).foregroundStyle(.quaternary)
            Text("No models downloaded")
                .font(.title3).foregroundStyle(.secondary)
            Text("Browse HuggingFace to download models.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func localModelRow(_ model: LocalGGUF) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(String(format: "%.1f GB", model.sizeGB))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                deleteTarget    = model
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete model")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Browse tab

    private var browseTab: some View {
        HSplitView {
            // Left: search + results
            VStack(spacing: 0) {
                searchBar
                    .padding(10)
                Divider()
                searchResultsList
            }
            .frame(minWidth: 220, maxWidth: 280)

            // Right: model detail + files
            modelDetailPanel
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Filter models…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { searchHF() }
            if isSearching {
                ProgressView().scaleEffect(0.6)
            } else if !searchQuery.isEmpty {
                Button { searchHF() } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var searchResultsList: some View {
        Group {
            if searchResults.isEmpty && !isSearching {
                VStack(spacing: 6) {
                    ProgressView()
                    Text("Loading top models…")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isSearching {
                VStack(spacing: 6) {
                    ProgressView()
                    Text("Searching…")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    if let d = model.downloads {
                                        Text("↓ \(d.formatted())")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedModel?.id == model.id
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedModel = model
                                loadFiles(for: model)
                            }
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
        }
    }

    private var modelDetailPanel: some View {
        VStack(spacing: 0) {
            if let model = selectedModel {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 12) {
                        if let d = model.downloads {
                            Label("\(d.formatted()) downloads", systemImage: "arrow.down.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if let l = model.likes {
                            Label("\(l)", systemImage: "heart")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let desc = model.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Files
                if isLoadingFiles {
                    ProgressView("Loading files…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if modelFiles.isEmpty {
                    Text("No GGUF files found")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    filesList(model: model)
                }

                // Status bar
                if !statusMessage.isEmpty {
                    Divider()
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 28)).foregroundStyle(.quaternary)
                    Text("Select a model")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func filesList(model: HFModel) -> some View {
        List(modelFiles) { file in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(file.quantType)
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(String(format: "%.1f GB", file.sizeGB))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                downloadButton(model: model, file: file)
            }
            .padding(.vertical, 3)
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func downloadButton(model: HFModel, file: HFModelFile) -> some View {
        let alreadyDownloaded = localModels.contains {
            $0.fullPath.hasSuffix(file.name)
        }
        if alreadyDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
                .help("Already downloaded")
        } else if downloadingFile == file.name {
            HStack(spacing: 6) {
                ProgressView(value: downloadProgress)
                    .frame(width: 60)
                Text("\(Int(downloadProgress * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                downloadFile(model: model, file: file)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(downloadingFile != nil)
            .help("Download")
        }
    }

    // MARK: - Actions

    private func loadLocalModels() {
        conn.sendAction("list_local_models")
    }

    private func searchHF() {
        isSearching   = true
        // Don't clear searchResults — keep old list visible until new response arrives
        // Clearing causes blank panel for the full search duration (10-30s)
        selectedModel = nil
        modelFiles    = []
        conn.sendAction("hf_search", value: searchQuery)
    }

    private func loadFiles(for model: HFModel) {
        isLoadingFiles = true
        modelFiles     = []
        conn.sendAction("hf_model_files", value: model.id)
    }

    private func downloadFile(model: HFModel, file: HFModelFile) {
        downloadingFile  = file.name
        downloadProgress = 0
        statusMessage    = "Starting download…"
        conn.sendAction("hf_download", value: "\(model.id)/\(file.name)")
    }

    private func deleteModel(_ model: LocalGGUF) {
        conn.sendAction("delete_model", value: model.fullPath)
        statusMessage = "Deleting \(model.displayName)…"
    }

    // MARK: - Handle incoming updates from slot app

    func handleControlsUpdate(_ update: [String: Any]) {
        if let type = update["type"] as? String {
            switch type {
            case "hf_search_results":
                isSearching = false
                if let results = update["results"] as? [[String: Any]] {
                    let parsed = results.compactMap { r -> HFModel? in
                        guard let id = r["id"] as? String else { return nil }
                        return HFModel(
                            id: id,
                            downloads: r["downloads"] as? Int,
                            likes: r["likes"] as? Int,
                            description: r["description"] as? String
                        )
                    }
                    // Only replace if we got results — keep old list on empty response
                    if !parsed.isEmpty { searchResults = parsed }
                }
            case "hf_model_files_result":
                isLoadingFiles = false
                if let files = update["files"] as? [[String: Any]] {
                    modelFiles = files.compactMap { f in
                        guard let name = f["name"] as? String,
                              let size = f["size"] as? Int else { return nil }
                        return HFModelFile(name: name, size: size)
                    }
                }
            case "download_progress":
                downloadProgress = (update["progress"] as? Double) ?? 0
                statusMessage    = "Downloading… \(Int(downloadProgress * 100))%"
            case "download_complete":
                downloadingFile  = nil
                downloadProgress = 0
                statusMessage    = "Downloaded successfully"
                loadLocalModels()
            case "download_error":
                downloadingFile = nil
                statusMessage   = update["message"] as? String ?? "Download failed"
            case "local_models":
                if let models = update["models"] as? [[String: Any]] {
                    localModels = models.compactMap { m in
                        guard let name = m["display_name"] as? String,
                              let path = m["full_path"] as? String,
                              let size = m["size_gb"] as? Double else { return nil }
                        return LocalGGUF(displayName: name, fullPath: path, sizeGB: size)
                    }
                }
            case "delete_complete":
                statusMessage = "Deleted"
                loadLocalModels()
            default: break
            }
        }
    }
}

// MARK: - HFModel Equatable/Hashable for List selection

extension HFModel: Equatable, Hashable {
    static func == (lhs: HFModel, rhs: HFModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
