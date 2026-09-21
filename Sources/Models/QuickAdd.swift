import Foundation

/// "gym 7pm 45m" → Gym, 19:00–19:45. The offline capture path: one line, no pickers.
enum QuickAdd {
    struct Parse: Equatable {
        var label: String
        var start: DateComponents?
        var end: DateComponents?
    }

    /// Grammar: `<label> [at] <time> [for] [<n>m|<n>h]` · `<label> <time>-<time>` · `<label>` alone.
    /// Times: `7pm`, `7:30pm`, `19:00`, `7:30`, `noon`, `midnight`. Default length 30 min.
    static func parse(_ text: String, defaultMinutes: Int = 30) -> Parse? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var minutes: Int?
        if let m = s.firstMatch(of: /\s+(?:for\s+)?(\d+)\s*(m|min|mins|h|hr|hrs)\b\s*$/.ignoresCase()) {
            let n = Int(m.1) ?? 0
            minutes = m.2.lowercased().hasPrefix("h") ? n * 60 : n
            s.removeSubrange(m.range)
        }
        var start: Int?, end: Int?
        if let m = s.firstMatch(of: /\s+(?:at\s+|from\s+)?(\S+?)\s*(?:-|–|to)\s*(\S+)\s*$/.ignoresCase()), let a = time(String(m.1), bareHour: true), var b = time(String(m.2), bareHour: true) {
            if b <= a { b += 12 * 60 }   // "9:30-11" and "1-3pm" read as the same half of the day
            start = a; end = b <= a ? nil : b
            s.removeSubrange(m.range)
        } else if let m = s.firstMatch(of: /\s+(?:at\s+)?(\S+)\s*$/.ignoresCase()), let a = time(String(m.1)) {
            start = a
            s.removeSubrange(m.range)
        }
        let label = s.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, time(label) == nil else { return nil }   // "7pm" alone is not a block
        guard let start else { return Parse(label: capitalized(label), start: nil, end: nil) }
        let finish = min(23 * 60 + 59, max(start + 5, end ?? start + (minutes ?? defaultMinutes)))
        return Parse(label: capitalized(label), start: .hm(start / 60, start % 60), end: .hm(finish / 60, finish % 60))
    }

    /// Minutes since midnight, or nil when the token isn't a time.
    static func time(_ raw: String, bareHour: Bool = false) -> Int? {
        let t = raw.lowercased()
        if t == "noon" { return 12 * 60 }
        if t == "midnight" { return 0 }
        guard let m = t.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?/) else { return nil }
        guard var h = Int(m.1), h <= 24 else { return nil }
        let min = m.2.flatMap { Int($0) } ?? 0
        guard min < 60 else { return nil }
        if let ap = m.3 {
            if ap.hasPrefix("p"), h < 12 { h += 12 }
            if ap.hasPrefix("a"), h == 12 { h = 0 }
        } else if m.2 == nil, !bareHour {
            return nil   // a bare number is a label, not a time
        }
        return h == 24 ? 0 : h * 60 + min
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}
