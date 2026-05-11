import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var cameraIP = "192.168.1.254"
    @Published var firmware = "Unknown"
    @Published var freeSpaceBytes: Int64?
    @Published var timezoneRaw: Int?
    @Published var files: [ViofoFile] = []
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false
    @Published var isDownloading = false
    @Published var downloadProgress = ""
    @Published var downloadFolderPath: String

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: "downloadFolderPath") {
            downloadFolderPath = savedPath
        } else {
            downloadFolderPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
        }
    }

    var downloadFolderURL: URL {
        URL(fileURLWithPath: downloadFolderPath, isDirectory: true)
    }

    var formattedFreeSpace: String {
        guard let freeSpaceBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: freeSpaceBytes, countStyle: .file)
    }

    var timezoneDescription: String {
        guard let timezoneRaw else { return "Unknown" }
        return Self.describeViofoTimezone(raw: timezoneRaw)
    }

    var macOSTimezoneDescription: String {
        let zone = TimeZone.current
        let offset = zone.secondsFromGMT()
        return "\(zone.identifier) (\(Self.describeGMTOffset(seconds: offset)))"
    }

    var macOSViofoTimezoneRaw: Int {
        Self.viofoTimezoneRaw(for: TimeZone.current)
    }

    var isTimezoneAlignedWithMacOS: Bool {
        timezoneRaw == macOSViofoTimezoneRaw
    }

    var timezoneWarning: String? {
        guard let timezoneRaw else {
            return "⚠️ Camera timezone unknown"
        }

        guard timezoneRaw == macOSViofoTimezoneRaw else {
            return "⚠️ Camera timezone differs from macOS"
        }

        return nil
    }

    var renderedTimestampLabel: String {
        Self.renderedTimestampLabel(for: Date(), timezoneRaw: timezoneRaw, macOSRaw: macOSViofoTimezoneRaw)
    }

    func setDownloadFolder(_ url: URL) {
        downloadFolderPath = url.path
        UserDefaults.standard.set(url.path, forKey: "downloadFolderPath")
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = "Refreshing camera status..."
        defer { isRefreshing = false }

        do {
            async let firmwareXML = fetchString(commandURL(3012))
            async let freeXML = fetchString(commandURL(3017))
            async let stateXML = fetchString(commandURL(3014))
            async let listXML = fetchString(commandURL(3015))

            let firmwareResponse = try await firmwareXML
            firmware = XMLHelpers.firstElement("String", in: firmwareResponse) ?? "Unknown"

            let freeResponse = try await freeXML
            if let value = XMLHelpers.firstElement("Value", in: freeResponse), let bytes = Int64(value) {
                freeSpaceBytes = bytes
            }

            let stateResponse = try await stateXML
            timezoneRaw = XMLHelpers.commandStatusPairs(in: stateResponse)[9411]

            let listResponse = try await listXML
            files = Self.movieFiles(from: listResponse)

            statusMessage = "Connected to \(cameraIP)"
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func refreshStatusOnly() async {
        isRefreshing = true
        statusMessage = "Refreshing status..."
        defer { isRefreshing = false }

        do {
            async let firmwareXML = fetchString(commandURL(3012))
            async let freeXML = fetchString(commandURL(3017))
            async let stateXML = fetchString(commandURL(3014))

            firmware = XMLHelpers.firstElement("String", in: try await firmwareXML) ?? firmware

            if let value = XMLHelpers.firstElement("Value", in: try await freeXML), let bytes = Int64(value) {
                freeSpaceBytes = bytes
            }

            timezoneRaw = XMLHelpers.commandStatusPairs(in: try await stateXML)[9411]
            statusMessage = "Status refreshed"
        } catch {
            statusMessage = "Status refresh failed: \(error.localizedDescription)"
        }
    }

    func refreshFiles() async {
        isRefreshing = true
        statusMessage = "Loading /DCIM/Movie..."
        defer { isRefreshing = false }

        do {
            let xml = try await fetchString(commandURL(3015))
            files = Self.movieFiles(from: xml)
            statusMessage = "Loaded \(files.count) movie files"
        } catch {
            statusMessage = "File refresh failed: \(error.localizedDescription)"
        }
    }

    func syncTimezoneToMac() async {
        let raw = macOSViofoTimezoneRaw
        let now = Date()
        let dateString = Self.cameraDateFormatter.string(from: now)
        let timeString = Self.cameraTimeFormatter.string(from: now)
        statusMessage = "Writing camera clock..."

        do {
            _ = try await fetchString(commandURL(9411, par: raw))
            _ = try await fetchString(commandURL(3005, str: dateString))
            _ = try await fetchString(commandURL(3006, str: timeString))
            try await Task.sleep(nanoseconds: 500_000_000)
            let stateXML = try await fetchString(commandURL(3014))
            timezoneRaw = XMLHelpers.commandStatusPairs(in: stateXML)[9411]
            statusMessage = "Camera clock synced to macOS"
        } catch {
            statusMessage = "Clock sync failed: \(error.localizedDescription)"
        }
    }

    func downloadFiles(_ selectedFiles: [ViofoFile]) async {
        guard !selectedFiles.isEmpty else {
            statusMessage = "No files selected"
            return
        }

        isDownloading = true
        downloadProgress = "Preparing..."
        defer {
            isDownloading = false
        }

        do {
            try FileManager.default.createDirectory(at: downloadFolderURL, withIntermediateDirectories: true)

            for (index, file) in selectedFiles.enumerated() {
                downloadProgress = "\(index + 1)/\(selectedFiles.count): \(file.name)"
                let sourceURL = fileURL(for: file)
                let destinationURL = uniqueDestinationURL(for: file.name, in: downloadFolderURL)

                do {
                    _ = try await ProcessRunner.run(
                        executable: "/usr/bin/curl",
                        arguments: [
                            "--fail",
                            "--location",
                            "--silent",
                            "--show-error",
                            "--connect-timeout", "8",
                            "--output", destinationURL.path,
                            sourceURL.absoluteString
                        ]
                    )
                } catch {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try? FileManager.default.removeItem(at: destinationURL)
                    }
                    throw error
                }
            }

            downloadProgress = "Downloaded \(selectedFiles.count) file(s)"
            statusMessage = "Downloads complete"
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    private static func movieFiles(from xml: String) -> [ViofoFile] {
        ViofoFileListParser.parse(xml)
            .filter { $0.httpPath.hasPrefix("/DCIM/Movie/") }
            .sorted { lhs, rhs in
                if lhs.time != rhs.time {
                    return lhs.time > rhs.time
                }
                return lhs.name > rhs.name
            }
    }

    private func commandURL(_ command: Int, par: Int? = nil, str: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = cameraIP
        components.path = "/"

        var queryItems = [
            URLQueryItem(name: "custom", value: "1"),
            URLQueryItem(name: "cmd", value: "\(command)")
        ]

        if let par {
            queryItems.append(URLQueryItem(name: "par", value: "\(par)"))
        }
        if let str {
            queryItems.append(URLQueryItem(name: "str", value: str))
        }

        components.queryItems = queryItems
        return components.url!
    }

    private func fileURL(for file: ViofoFile) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = cameraIP
        components.percentEncodedPath = Self.percentEncodedPath(file.httpPath)
        return components.url!
    }

    private func fetchString(_ url: URL) async throws -> String {
        let data = try await ProcessRunner.run(
            executable: "/usr/bin/curl",
            arguments: [
                "--fail",
                "--silent",
                "--show-error",
                "--max-time", "12",
                url.absoluteString
            ]
        )

        guard let string = String(data: data, encoding: .utf8) else {
            throw ViofoError.invalidText
        }
        return string
    }

    private func uniqueDestinationURL(for filename: String, in folder: URL) -> URL {
        let base = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: base.path) else {
            return base
        }

        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent

        for index in 1...999 {
            let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return folder.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    }

    static func percentEncodedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }

    static func viofoTimezoneRaw(for timezone: TimeZone) -> Int {
        let offsetHours = Double(timezone.secondsFromGMT()) / 3600.0
        return 28 + Int(offsetHours.rounded())
    }

    static func describeViofoTimezone(raw: Int) -> String {
        let offsetHours = raw - 28
        let seconds = offsetHours * 3600
        return "\(describeGMTOffset(seconds: seconds)) (raw \(raw))"
    }

    static func renderedTimestampLabel(for date: Date, timezoneRaw: Int?, macOSRaw: Int) -> String {
        guard let timezoneRaw else {
            return "⚠️ Timezone unknown"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: (timezoneRaw - 28) * 3600) ?? .current

        let prefix = timezoneRaw == macOSRaw ? "" : "⚠️ "
        return prefix + formatter.string(from: date)
    }

    static func describeGMTOffset(seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }

    private static let cameraDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let cameraTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

enum ViofoError: LocalizedError {
    case httpStatus(Int)
    case invalidText
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .invalidText:
            return "Camera response was not UTF-8 text"
        case .processFailed(let message):
            return message
        }
    }
}

enum ProcessRunner {
    static func run(executable: String, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    let output = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorOutput, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: ViofoError.processFailed(message?.isEmpty == false ? message! : "Process failed with exit code \(process.terminationStatus)"))
                        return
                    }

                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
