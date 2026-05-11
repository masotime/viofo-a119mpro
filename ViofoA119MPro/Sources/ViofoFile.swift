import Foundation

struct ViofoFile: Identifiable, Hashable {
    let name: String
    let fpath: String
    let size: Int64
    let time: String
    let attr: Int

    var id: String { fpath }

    var httpPath: String {
        var path = fpath
        if let driveRange = path.range(of: ":\\") {
            path = String(path[driveRange.upperBound...])
        }
        path = path.replacingOccurrences(of: "\\", with: "/")
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        return path
    }

    var isProtected: Bool {
        attr == 33 || fpath.contains("\\RO\\")
    }

    var folderLabel: String {
        isProtected ? "RO" : "Movie"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct ViofoFileBuilder {
    var name = ""
    var fpath = ""
    var size: Int64 = 0
    var time = ""
    var attr = 0

    func build() -> ViofoFile? {
        guard !name.isEmpty, !fpath.isEmpty else { return nil }
        return ViofoFile(name: name, fpath: fpath, size: size, time: time, attr: attr)
    }
}
