import SwiftUI
import AppKit

private enum FileSortColumn {
    case name
    case size
    case time
    case folder

    var defaultAscending: Bool {
        switch self {
        case .name, .folder:
            return true
        case .size, .time:
            return false
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liveVideo: LiveVideoModel
    @State private var selectedFileID: String?
    @State private var fileSortColumn: FileSortColumn = .time
    @State private var fileSortAscending = FileSortColumn.time.defaultAscending
    @State private var nextRefreshDate = Date()
    @State private var secondsUntilRefresh = 10

    private let refreshIntervalSeconds = 10

    private var sortedFiles: [ViofoFile] {
        model.files.sorted { lhs, rhs in
            let primaryComparison: ComparisonResult

            switch fileSortColumn {
            case .name:
                primaryComparison = lhs.name.localizedStandardCompare(rhs.name)
            case .size:
                if lhs.size == rhs.size {
                    primaryComparison = .orderedSame
                } else {
                    primaryComparison = lhs.size < rhs.size ? .orderedAscending : .orderedDescending
                }
            case .time:
                primaryComparison = lhs.time.localizedStandardCompare(rhs.time)
            case .folder:
                primaryComparison = lhs.folderLabel.localizedStandardCompare(rhs.folderLabel)
            }

            if primaryComparison != .orderedSame {
                return fileSortAscending ? primaryComparison == .orderedAscending : primaryComparison == .orderedDescending
            }

            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private var selectedFile: ViofoFile? {
        guard let selectedFileID else { return nil }
        return model.files.first { $0.id == selectedFileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            HSplitView {
                leftPane
                    .frame(minWidth: 420, idealWidth: 480)

                rightPane
                    .frame(minWidth: 620)
            }
        }
        .task {
            await startAutoRefreshLoop()
        }
        .onDisappear {
            liveVideo.stop()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("VIOFO A119M Pro")
                .font(.headline)

            TextField("Camera IP", text: $model.cameraIP)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Button {
                Task { await refreshEverything() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)

            Text("Next refresh: \(secondsUntilRefresh)s")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            if let warning = model.timezoneWarning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            Text(model.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            livePreview
            statusPanel
            timezonePanel
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live Feed")
                    .font(.headline)
                Spacer()
                Button {
                    if liveVideo.isRunning {
                        liveVideo.stop()
                    } else {
                        liveVideo.start(cameraIP: model.cameraIP)
                    }
                } label: {
                    Label(liveVideo.isRunning ? "Stop" : "Start", systemImage: liveVideo.isRunning ? "stop.fill" : "play.fill")
                }
            }

            ZStack {
                Color.black
                if let image = liveVideo.currentFrame {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("No live frame")
                        .foregroundStyle(.secondary)
                }

                if liveVideo.isRunning {
                    LiveTimestampOverlay(timezoneRaw: model.timezoneRaw, macOSRaw: model.macOSViofoTimezoneRaw)
                        .padding(8)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(liveVideo.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera Status")
                .font(.headline)

            LabeledContent("Firmware", value: model.firmware)
            LabeledContent("Free space", value: model.formattedFreeSpace)
            LabeledContent("Movie files", value: "\(model.files.count)")
        }
    }

    private var timezonePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Zone")
                .font(.headline)

            LabeledContent("Camera", value: model.timezoneDescription)
            LabeledContent("macOS", value: model.macOSTimezoneDescription)
            LabeledContent("Sync value", value: AppModel.describeViofoTimezone(raw: model.macOSViofoTimezoneRaw))
            LabeledContent("Rendered", value: model.renderedTimestampLabel)

            if let warning = model.timezoneWarning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .fontWeight(.semibold)
            }

            HStack {
                Button {
                    Task { await model.syncTimezoneToMac() }
                } label: {
                    Label("Sync Clock", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private var rightPane: some View {
        VStack(spacing: 0) {
            filesToolbar
            Divider()
            filesTable
            Divider()
            downloadBar
        }
    }

    private var filesToolbar: some View {
        HStack(spacing: 10) {
            Text("/DCIM/Movie")
                .font(.headline)

            Spacer()

            Button {
                chooseDownloadFolder()
            } label: {
                Label("Folder", systemImage: "folder")
            }

            Button {
                if let selectedFile {
                    Task { await model.downloadFiles([selectedFile]) }
                }
            } label: {
                Label("Download Selected", systemImage: "square.and.arrow.down")
            }
            .disabled(selectedFile == nil || model.isDownloading)

            Button {
                Task { await model.downloadFiles(sortedFiles) }
            } label: {
                Label("Download All", systemImage: "tray.and.arrow.down")
            }
            .disabled(model.files.isEmpty || model.isDownloading)
        }
        .padding(12)
    }

    private var filesTable: some View {
        VStack(spacing: 0) {
            filesHeader
            Divider()

            List(sortedFiles, selection: $selectedFileID) { file in
                fileRow(file)
                    .tag(file.id)
                    .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var filesHeader: some View {
        HStack(spacing: 12) {
            sortableHeader("Name", column: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("Size", column: .size)
                .frame(width: 120, alignment: .trailing)
            sortableHeader("Time", column: .time)
                .frame(width: 180, alignment: .leading)
            sortableHeader("Folder", column: .folder)
                .frame(width: 80, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sortableHeader(_ title: String, column: FileSortColumn) -> some View {
        Button {
            setSortColumn(column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if fileSortColumn == column {
                    Image(systemName: fileSortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: column == .size ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ file: ViofoFile) -> some View {
        HStack(spacing: 12) {
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(file.formattedSize)
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)
            Text(file.time)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
            Text(file.folderLabel)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFileID = file.id
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.name), \(file.formattedSize), \(file.time), \(file.folderLabel)")
    }

    private func setSortColumn(_ column: FileSortColumn) {
        if fileSortColumn == column {
            fileSortAscending.toggle()
        } else {
            fileSortColumn = column
            fileSortAscending = column.defaultAscending
        }
    }

    private var downloadBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(model.downloadFolderPath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.isDownloading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.downloadProgress)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
    }

    @MainActor
    private func startAutoRefreshLoop() async {
        await refreshEverything()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            guard !model.isRefreshing else { continue }

            let remaining = max(0, Int(ceil(nextRefreshDate.timeIntervalSinceNow)))
            secondsUntilRefresh = remaining

            if remaining <= 0 {
                await refreshEverything()
            }
        }
    }

    @MainActor
    private func refreshEverything() async {
        await model.refreshAll()
        resetRefreshCountdown()
    }

    @MainActor
    private func resetRefreshCountdown() {
        nextRefreshDate = Date().addingTimeInterval(TimeInterval(refreshIntervalSeconds))
        secondsUntilRefresh = refreshIntervalSeconds
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.downloadFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            model.setDownloadFolder(url)
        }
    }
}

struct LiveTimestampOverlay: View {
    let timezoneRaw: Int?
    let macOSRaw: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(AppModel.renderedTimestampLabel(for: timeline.date, timezoneRaw: timezoneRaw, macOSRaw: macOSRaw))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
