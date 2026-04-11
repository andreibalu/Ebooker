//
//  BookDescriptionFormatting.swift
//  Pageless
//

import Foundation

enum BookDescriptionFormatting {
    /// Turns common HTML fragments from catalog APIs into readable plain text (line breaks, no raw tags).
    static func plainText(fromHTMLFragment raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Block / line breaks (order matters: handle explicit breaks before stripping tags)
        s = s.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</li\\s*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)

        // Strip remaining tags (including <p>, <span>, <b>, etc.)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        s = decodeHTMLEntities(s)

        // Tidy excessive blank lines while keeping paragraph breaks
        s = s.replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var s = replaceNumericCharacterReferences(in: string, pattern: "(?i)&#x([0-9a-fA-F]{1,6});", radix: 16)
        s = replaceNumericCharacterReferences(in: s, pattern: "&#(\\d{1,7});", radix: 10)

        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        s = s.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        s = s.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
        s = s.replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
        s = s.replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
        s = s.replacingOccurrences(of: "&mdash;", with: "\u{2014}")
        s = s.replacingOccurrences(of: "&ndash;", with: "\u{2013}")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&amp;", with: "&")

        return s
    }

    private static func replaceNumericCharacterReferences(in string: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
        let ns = string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: string, options: [], range: fullRange)
        var s = string
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range, in: s),
                  match.numberOfRanges > 1,
                  let capRange = Range(match.range(at: 1), in: s) else { continue }
            let digits = String(s[capRange])
            guard let codePoint = UInt32(digits, radix: radix), let scalar = UnicodeScalar(codePoint) else { continue }
            s.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return s
    }
}
