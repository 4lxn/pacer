import SwiftUI

/// Renders the subset of Markdown the Coach produces: paragraphs, "-"/"*"/"1." lists, `#`
/// headings (as bold lines), and inline **bold** / *italic* / `code` via AttributedString.
/// SwiftUI's `Text(markdown)` only understands inline syntax, so blocks are split here.
struct MarkdownText: View {
    let text: String

    private enum Line: Identifiable {
        case paragraph(String), bullet(String), numbered(String, String), heading(String), blank
        var id: String {
            switch self {
            case .paragraph(let s): "p-\(s)"
            case .bullet(let s): "b-\(s)"
            case .numbered(let n, let s): "n-\(n)-\(s)"
            case .heading(let s): "h-\(s)"
            case .blank: "blank-\(UUID())"
            }
        }
    }

    private var lines: [Line] {
        var out: [Line] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { if case .blank? = out.last {} else { out.append(.blank) }; continue }
            if line.hasPrefix("#") {
                out.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                out.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                out.append(.numbered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                out.append(.paragraph(line))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                switch line {
                case .paragraph(let s): inline(s)
                case .heading(let s): inline(s).font(.body.weight(.semibold))
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(s)
                    }
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                        inline(s)
                    }
                case .blank: Color.clear.frame(height: 2)
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        if let attributed = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(s)
    }
}
