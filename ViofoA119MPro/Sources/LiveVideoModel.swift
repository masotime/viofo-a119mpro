import Foundation
import AppKit

final class LiveVideoModel: ObservableObject {
    @Published var currentFrame: NSImage?
    @Published var isRunning = false
    @Published var statusMessage = "Live preview stopped"

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var jpegBuffer = Data()
    private var lastCameraIP: String?
    private let parserQueue = DispatchQueue(label: "local.viofo.live-video.parser")

    func start(cameraIP: String) {
        guard !isRunning else { return }
        isRunning = true
        lastCameraIP = cameraIP
        startProcess(cameraIP: cameraIP)
    }

    private func startProcess(cameraIP: String) {
        guard process == nil else { return }

        guard let ffmpegPath = Self.findFFmpeg() else {
            statusMessage = "ffmpeg not found. Install ffmpeg or add it to a common Homebrew path."
            isRunning = false
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let streamURL = "rtsp://\(cameraIP)/xxx.mov"

        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-rtsp_transport", "tcp",
            "-i", streamURL,
            "-an",
            "-vf", "fps=8",
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "-q:v", "5",
            "-"
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendJPEGData(data)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.statusMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.errorPipe?.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
                self.errorPipe = nil
                self.process = nil

                if self.isRunning {
                    self.statusMessage = "Live preview reconnecting..."
                    let cameraIP = self.lastCameraIP ?? cameraIP
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self, self.isRunning else { return }
                        self.startProcess(cameraIP: cameraIP)
                    }
                } else {
                    self.statusMessage = "Live preview stopped"
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            self.statusMessage = "Live preview running"
        } catch {
            statusMessage = "Could not start ffmpeg: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        parserQueue.async { [weak self] in
            self?.jpegBuffer.removeAll(keepingCapacity: false)
        }

        process = nil
        outputPipe = nil
        errorPipe = nil
        isRunning = false
        statusMessage = "Live preview stopped"
    }

    private func appendJPEGData(_ data: Data) {
        parserQueue.async { [weak self] in
            guard let self else { return }
            jpegBuffer.append(data)

            while let frameData = nextFrame() {
                guard let image = NSImage(data: frameData) else { continue }
                DispatchQueue.main.async {
                    self.currentFrame = image
                    if self.isRunning {
                        self.statusMessage = "Live preview running"
                    }
                }
            }

            if jpegBuffer.count > 4_000_000 {
                jpegBuffer.removeAll(keepingCapacity: false)
            }
        }
    }

    private func nextFrame() -> Data? {
        let startMarker = Data([0xff, 0xd8])
        let endMarker = Data([0xff, 0xd9])

        guard let startRange = jpegBuffer.range(of: startMarker) else {
            jpegBuffer.removeAll(keepingCapacity: true)
            return nil
        }

        if startRange.lowerBound > 0 {
            jpegBuffer.removeSubrange(0..<startRange.lowerBound)
        }

        let searchStart = jpegBuffer.index(jpegBuffer.startIndex, offsetBy: 2)
        guard let endRange = jpegBuffer[searchStart...].range(of: endMarker) else {
            return nil
        }

        let frameEnd = endRange.upperBound
        let frame = jpegBuffer[jpegBuffer.startIndex..<frameEnd]
        jpegBuffer.removeSubrange(jpegBuffer.startIndex..<frameEnd)
        return Data(frame)
    }

    private static func findFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }
}
