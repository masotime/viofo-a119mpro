import Foundation

enum XMLHelpers {
    static func firstElement(_ name: String, in xml: String) -> String? {
        let pattern = "<\(name)>(.*?)</\(name)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func commandStatusPairs(in xml: String) -> [Int: Int] {
        let pattern = "<Cmd>(\\d+)</Cmd>\\s*<Status>(-?\\d+)</Status>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [:]
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)

        var pairs: [Int: Int] = [:]
        for match in matches where match.numberOfRanges == 3 {
            guard let cmdRange = Range(match.range(at: 1), in: xml),
                  let statusRange = Range(match.range(at: 2), in: xml),
                  let cmd = Int(xml[cmdRange]),
                  let status = Int(xml[statusRange]) else {
                continue
            }
            pairs[cmd] = status
        }
        return pairs
    }
}

final class ViofoFileListParser: NSObject, XMLParserDelegate {
    private var files: [ViofoFile] = []
    private var currentFile: ViofoFileBuilder?
    private var currentElement = ""
    private var currentText = ""

    static func parse(_ xml: String) -> [ViofoFile] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = ViofoFileListParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.files
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "File" {
            currentFile = ViofoFileBuilder()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if var builder = currentFile {
            switch elementName {
            case "NAME":
                builder.name = value
            case "FPATH":
                builder.fpath = value
            case "SIZE":
                builder.size = Int64(value) ?? 0
            case "TIME":
                builder.time = value
            case "ATTR":
                builder.attr = Int(value) ?? 0
            case "File":
                if let file = builder.build() {
                    files.append(file)
                }
                currentFile = nil
                currentElement = ""
                currentText = ""
                return
            default:
                break
            }
            currentFile = builder
        }

        currentElement = ""
        currentText = ""
    }
}
