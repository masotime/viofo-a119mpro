import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liveVideo: LiveVideoModel
    @State private var selectedFileIDs = Set<String>()
    @State private var nextRefreshDate = Date()
    @State private var secondsUntilRefresh = 10

    private let refreshIntervalSeconds = 10

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
                let selected = model.files.filter { selectedFileIDs.contains($0.id) }
                Task { await model.downloadFiles(selected) }
            } label: {
                Label("Download Selected", systemImage: "square.and.arrow.down")
            }
            .disabled(selectedFileIDs.isEmpty || model.isDownloading)

            Button {
                Task { await model.downloadFiles(model.files) }
            } label: {
                Label("Download All", systemImage: "tray.and.arrow.down")
            }
            .disabled(model.files.isEmpty || model.isDownloading)
        }
        .padding(12)
    }

    private var filesTable: some View {
        Table(model.files, selection: $selectedFileIDs) {
            TableColumn("Name", value: \.name)
            TableColumn("Size") { file in
                Text(file.formattedSize)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("Time", value: \.time)
                .width(min: 150, ideal: 180)
            TableColumn("Folder") { file in
                Text(file.folderLabel)
            }
            .width(70)
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
