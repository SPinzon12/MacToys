import Foundation

/// Pure text transforms: everything here is a plain function of its input,
/// no pasteboard, no I/O, no AppKit — which is exactly what the unit tests cover.
enum TextTransforms {

    // MARK: - Plain text

    /// HTML → plain text: tags stripped, entities decoded, block tags become
    /// paragraph breaks. No markdown conversion happens here.
    static func plainText(fromHTML html: String) -> String {
        var out = ""
        var dropDepth = 0 // inside <script>/<style>/<head>/<title>…
        for token in HTMLTokenizer.tokenize(html) {
            switch token {
            case .text(let text):
                guard dropDepth == 0 else { continue }
                out += decodeEntities(text)
            case .open(let name, _, _):
                if HTMLTokenizer.dropContentTags.contains(name) {
                    dropDepth += 1
                } else if dropDepth == 0, name == "br" {
                    out += "\n"
                }
            case .close(let name):
                if HTMLTokenizer.dropContentTags.contains(name) {
                    dropDepth = max(0, dropDepth - 1)
                } else if dropDepth == 0, HTMLTokenizer.blockTags.contains(name) {
                    out += "\n\n"
                }
            }
        }
        // Collapse the blank-line runs block tags leave behind, trim the edges.
        while out.contains("\n\n\n") {
            out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The clipboard-content flavor: prefer stripping HTML (that is the point
    /// of the transform), fall back to the plain-text flavor as-is.
    static func plainText(from content: ClipboardContent) -> String? {
        if content.hasHTML { return plainText(fromHTML: content.html!) }
        if content.hasText { return content.text }
        return nil
    }

    // MARK: - HTML → Markdown

    /// Minimal subset — h1–h6, p, br, strong/b, em/i, a[href], ul/ol/li, code,
    /// pre, blockquote. Everything else is stripped to its text. Malformed
    /// input never crashes: unclosed tags just end with unbalanced markers.
    static func htmlToMarkdown(_ html: String) -> String {
        var renderer = MarkdownRenderer()
        for token in HTMLTokenizer.tokenize(html) {
            renderer.consume(token)
        }
        renderer.finish()
        return renderer.out
    }

    // MARK: - Structured text → JSON

    /// Leading `<` (after trimming) means XML, anything else is CSV.
    static func structuredToJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("<") { return xmlToJSON(text) }
        return csvToJSON(text)
    }

    /// RFC4180-ish CSV: quoted fields may contain commas, quotes (`""`) and
    /// newlines; the header row names the keys of every following record.
    static func csvToJSON(_ text: String) -> String? {
        let records = parseCSV(text)
        guard let header = records.first, !header.isEmpty else { return nil }
        var rows: [[String: String]] = []
        for record in records.dropFirst() {
            var row: [String: String] = [:]
            for (index, column) in header.enumerated() {
                row[column] = index < record.count ? record[index] : ""
            }
            rows.append(row)
        }
        return prettyJSON(rows)
    }

    /// XML → JSON: element → object, attributes as keys, `#text` for text
    /// content, children nested by tag name (duplicates become an array).
    static func xmlToJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else { return nil }
        return prettyJSON(root)
    }

    /// Compact CSV record parser. Blank lines (a single empty field) are
    /// skipped; everything else is kept in order.
    static func parseCSV(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var index = 0

        func endField() {
            record.append(field)
            field = ""
        }
        func endRecord() {
            endField()
            if !(record.count == 1 && record[0].isEmpty) {
                records.append(record)
            }
            record = []
        }

        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    // `""` inside a quoted field is a literal quote.
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(char)
                index += 1
                continue
            }
            switch char {
            case "\"":
                // A quote only opens a field at the field start; elsewhere it
                // is literal (`he said "hi"` stays one unquoted field).
                if field.isEmpty {
                    inQuotes = true
                } else {
                    field.append(char)
                }
                index += 1
            case ",":
                endField()
                index += 1
            case "\n":
                endRecord()
                index += 1
            case "\r":
                endRecord()
                if index + 1 < chars.count, chars[index + 1] == "\n" {
                    index += 2
                } else {
                    index += 1
                }
            default:
                field.append(char)
                index += 1
            }
        }
        if !field.isEmpty || !record.isEmpty {
            endRecord()
        }
        return records
    }

    // MARK: - Shared helpers

    private static func prettyJSON(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              )
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Named + numeric HTML entities (`&amp;`, `&#39;`, `&#x27;`).
    /// Unknown or malformed entities are kept verbatim.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while let amp = text[index...].firstIndex(of: "&") {
            out += text[index..<amp]
            let searchEnd = text.index(amp, offsetBy: 13, limitedBy: text.endIndex) ?? text.endIndex
            guard let semicolon = text[amp..<searchEnd].firstIndex(of: ";") else {
                out.append("&")
                index = text.index(after: amp)
                continue
            }
            let name = String(text[text.index(after: amp)..<semicolon])
            if let decoded = Self.entityValue(name) {
                out += decoded
                index = text.index(after: semicolon)
            } else {
                out.append("&")
                index = text.index(after: amp)
            }
        }
        out += text[index...]
        return out
    }

    private static func entityValue(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " " // ponytail: non-breaking space → plain space
        case "#39": return "'"
        default: break
        }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value: UInt32? = if digits.lowercased().hasPrefix("x") {
            UInt32(digits.dropFirst(2), radix: 16)
        } else {
            UInt32(digits)
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }
}

// MARK: - HTML tokenizer

enum HTMLToken: Equatable {
    case text(String)
    case open(name: String, attrs: [String: String], isVoid: Bool)
    case close(name: String)
}

/// Small hand-rolled tokenizer: no regex dependency, lenient about malformed
/// markup. A `<` that does not start a plausible tag stays literal text.
enum HTMLTokenizer {
    /// Tags whose *content* (not just their markup) must be dropped.
    static let dropContentTags: Set<String> = ["script", "style", "head", "title", "noscript"]
    /// Tags that end a plain-text block.
    static let blockTags: Set<String> = [
        "p", "div", "section", "article", "aside", "header", "footer", "main",
        "nav", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "dl",
        "dt", "dd", "tr", "table", "thead", "tbody", "blockquote", "pre",
        "form", "figure", "figcaption", "address", "body", "html"
    ]
    private static let voidTags: Set<String> = [
        "br", "hr", "img", "meta", "link", "input", "source", "track",
        "wbr", "area", "base", "col", "embed", "param"
    ]

    static func tokenize(_ html: String) -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        let chars = Array(html)
        var index = 0
        var textStart = 0

        func flushText(_ end: Int) {
            if end > textStart {
                tokens.append(.text(String(chars[textStart..<end])))
            }
        }

        while index < chars.count {
            guard chars[index] == "<" else {
                index += 1
                continue
            }
            // HTML comment: skip to `-->` (comments may contain `>`).
            if matches(chars, at: index, "<!--") {
                flushText(index)
                if let end = find(chars, "-->", from: index + 4) {
                    index = end + 3
                } else {
                    index = chars.count
                }
                textStart = index
                continue
            }
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            guard let next, next.isLetter || next == "/" else {
                index += 1 // `<` not opening a tag (e.g. `a < b`) → literal
                continue
            }
            guard let end = findTagEnd(chars, from: index + 1) else {
                index += 1 // no `>` (outside quotes) before the end → literal
                continue
            }
            let inner = String(chars[(index + 1)..<end])
            if inner.first == "!" || inner.first == "?" {
                // Doctype / processing instruction: drop silently.
                flushText(index)
                index = end + 1
                textStart = index
                continue
            }
            guard let token = parseTag(inner) else {
                index += 1
                continue
            }
            flushText(index)
            tokens.append(token)
            index = end + 1
            textStart = index
        }
        flushText(chars.count)
        return tokens
    }

    private static func matches(_ chars: [Character], at index: Int, _ needle: String) -> Bool {
        let needle = Array(needle)
        guard index + needle.count <= chars.count else { return false }
        return Array(chars[index..<(index + needle.count)]) == needle
    }

    private static func find(_ chars: [Character], _ needle: String, from start: Int) -> Int? {
        let needle = Array(needle)
        guard start < chars.count else { return nil }
        var i = start
        while i + needle.count <= chars.count {
            if Array(chars[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return nil
    }

    /// Position of the `>` closing a tag opened at `start`, skipping `>`
    /// inside quoted attribute values (`<a href="a>b">`).
    private static func findTagEnd(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        var quote: Character?
        while i < chars.count {
            let char = chars[i]
            if let open = quote {
                if char == open { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == ">" {
                return i
            }
            i += 1
        }
        return nil
    }

    /// `inner` is everything between `<` and `>`.
    private static func parseTag(_ inner: String) -> HTMLToken? {
        if inner.hasPrefix("/") {
            let name = inner.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, name.first!.isLetter else { return nil }
            return .close(name: name)
        }
        var body = Substring(inner)
        let isVoid: Bool
        if body.hasSuffix("/") {
            body = body.dropLast()
            isVoid = true
        } else {
            isVoid = false
        }
        guard let nameEnd = body.firstIndex(where: { !$0.isLetter && !$0.isNumber }),
              nameEnd > body.startIndex
        else {
            let whole = body.trimmingCharacters(in: .whitespaces).lowercased()
            guard whole.first?.isLetter == true else { return nil }
            return .open(name: whole, attrs: [:], isVoid: voidTags.contains(whole))
        }
        let name = String(body[..<nameEnd]).lowercased()
        guard name.first?.isLetter == true else { return nil }
        let attrs = parseAttributes(String(body[nameEnd...]))
        return .open(name: name, attrs: attrs, isVoid: isVoid || voidTags.contains(name))
    }

    private static func parseAttributes(_ text: String) -> [String: String] {
        var attrs: [String: String] = [:]
        var rest = Substring(text)
        while !rest.isEmpty {
            rest = rest.drop(while: { $0.isWhitespace || $0 == "=" })
            guard let nameEnd = rest.firstIndex(where: { $0.isWhitespace || $0 == "=" }) else {
                if !rest.isEmpty { attrs[String(rest).lowercased()] = "" }
                break
            }
            let name = String(rest[..<nameEnd]).lowercased()
            rest = rest[nameEnd...].drop(while: { $0.isWhitespace })
            var value = ""
            if rest.first == "=" {
                rest = rest.dropFirst().drop(while: { $0.isWhitespace })
                if let quote = rest.first, quote == "\"" || quote == "'" {
                    rest = rest.dropFirst()
                    if let close = rest.firstIndex(of: quote) {
                        value = String(rest[..<close])
                        rest = rest[rest.index(after: close)...]
                    } else {
                        value = String(rest) // unterminated quote → take the rest
                        rest = ""
                    }
                } else {
                    let end = rest.firstIndex(where: { $0.isWhitespace }) ?? rest.endIndex
                    value = String(rest[..<end])
                    rest = rest[end...]
                }
            }
            if !name.isEmpty { attrs[name] = decodeAttrValue(value) }
        }
        return attrs
    }

    private static func decodeAttrValue(_ value: String) -> String {
        TextTransforms.decodeEntities(value)
    }
}

// MARK: - Markdown renderer

/// Streaming HTML → Markdown renderer over tokenizer output. State is the
/// current inline run, the block output, the list stack and the quote depth.
private struct MarkdownRenderer {
    var out = ""
    var inline = ""
    var lists: [(ordered: Bool, index: Int)] = []
    var quoteDepth = 0
    var inListItem = false
    var headingLevel: Int?
    var preText: String?
    var codeDepth = 0
    var dropDepth = 0
    var links: [(href: String, offset: Int)] = []

    mutating func consume(_ token: HTMLToken) {
        switch token {
        case .text(let text):
            guard dropDepth == 0 else { return }
            if preText != nil {
                preText! += text
            } else {
                appendText(TextTransforms.decodeEntities(text))
            }
        case .open(let name, let attrs, let isVoid):
            handleOpen(name, attrs: attrs, isVoid: isVoid)
        case .close(let name):
            handleClose(name)
        }
    }

    /// Unclosed constructs at end of input: flush what we have.
    mutating func finish() {
        flushPending()
        if let preText {
            emitFence(preText)
            self.preText = nil
        }
    }

    private mutating func handleOpen(_ name: String, attrs: [String: String], isVoid: Bool) {
        if HTMLTokenizer.dropContentTags.contains(name) {
            dropDepth += 1
            return
        }
        guard dropDepth == 0 else { return }
        guard preText == nil else { return } // tags inside <pre> are ignored

        switch name {
        case "br":
            inline += "\n"
        case "strong", "b":
            inline += "**"
        case "em", "i":
            inline += "*"
        case "code":
            codeDepth += 1
            inline += "`"
        case "a":
            links.append((attrs["href"] ?? "", inline.count))
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushPending()
            headingLevel = name.dropFirst().first?.wholeNumberValue // "h3" → 3
        case "li":
            flushPending()
            inListItem = true
            if lists.isEmpty { lists.append((ordered: false, index: 0)) }
            lists[lists.count - 1].index += 1
        case "ul", "ol":
            flushPending()
            lists.append((ordered: name == "ol", index: 0))
        case "blockquote":
            flushPending()
            quoteDepth += 1
        case "pre":
            flushPending()
            preText = ""
        case "p", "div", "section", "article", "aside", "header", "footer",
             "main", "nav", "dl", "dt", "dd", "tr", "table", "thead", "tbody",
             "form", "figure", "figcaption", "address":
            flushPending() // a new block ends whatever the previous one left
        default:
            // Unknown/void tags are dropped; their text content still lands
            // in the output through the .text branch.
            break
        }
        _ = isVoid // void-ness only matters for the tag itself; we ignore it
    }

    private mutating func handleClose(_ name: String) {
        if HTMLTokenizer.dropContentTags.contains(name) {
            dropDepth = max(0, dropDepth - 1)
            return
        }
        guard dropDepth == 0 else { return }
        if preText != nil {
            if name == "pre", let buffered = preText {
                emitFence(buffered)
                preText = nil
            }
            return
        }

        switch name {
        case "strong", "b":
            inline += "**"
        case "em", "i":
            inline += "*"
        case "code":
            if codeDepth > 0 {
                codeDepth -= 1
                inline += "`"
            }
        case "a":
            guard let link = links.popLast() else { break }
            let content = String(inline.dropFirst(link.offset))
            inline = String(inline.prefix(link.offset)) + "[\(content)](\(link.href))"
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushPending()
            headingLevel = nil
        case "li":
            flushPending()
            inListItem = false
        case "ul", "ol":
            flushPending()
            if !lists.isEmpty { lists.removeLast() }
        case "blockquote":
            flushPending()
            quoteDepth = max(0, quoteDepth - 1)
        case "p", "div", "section", "article", "aside", "header", "footer",
             "main", "nav", "dl", "dt", "dd", "tr", "table", "thead", "tbody",
             "form", "figure", "figcaption", "address":
            flushPending()
        default:
            break
        }
    }

    private mutating func appendText(_ raw: String) {
        guard codeDepth == 0 else {
            // Inline code must not break the line structure.
            inline += raw.replacingOccurrences(of: "\n", with: " ")
            return
        }
        var collapsed = raw.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        if collapsed.isEmpty { return }
        if inline.hasSuffix(" ") || inline.hasSuffix("\n") || inline.isEmpty {
            while collapsed.hasPrefix(" ") { collapsed.removeFirst() }
        }
        inline += collapsed
    }

    /// Routes the pending inline run: list item when inside `<li>`, block
    /// otherwise (heading prefix applies there).
    private mutating func flushPending() {
        guard !inline.trimmingCharacters(in: .whitespaces).isEmpty else {
            inline = ""
            return
        }
        if inListItem {
            flushAsItem()
        } else {
            flushAsBlock()
        }
    }

    private mutating func flushAsItem() {
        let text = inline.trimmingCharacters(in: .whitespaces)
        inline = ""
        guard !text.isEmpty, !lists.isEmpty else { return }
        let bullet = lists[lists.count - 1].ordered
            ? "\(lists[lists.count - 1].index). "
            : "- "
        let indent = String(repeating: "  ", count: lists.count - 1)
        out += quoted(indent + bullet + text) + "\n"
    }

    private mutating func flushAsBlock() {
        let text = inline.trimmingCharacters(in: .whitespaces)
        inline = ""
        guard !text.isEmpty else { return }
        var body = text
        if let level = headingLevel {
            body = String(repeating: "#", count: level) + " " + body
        }
        // Every line of a quoted block gets its own `> ` prefix.
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { quoted(String($0)) }
            .joined(separator: "\n")
        out += lines + "\n\n"
    }

    private func quoted(_ line: String) -> String {
        String(repeating: "> ", count: quoteDepth) + line
    }

    private mutating func emitFence(_ raw: String) {
        let body = raw.trimmingCharacters(in: .newlines)
        out += "```\n" + body + "\n```\n\n"
    }
}

// MARK: - XML tree builder

/// `XMLParser` delegate building the JSON object tree: attributes become
/// keys, text becomes `#text`, children nest under their element name.
private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private(set) var root: [String: Any]?

    private var stack: [(name: String, attrs: [String: String], children: [String: Any], text: String)] = []

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attrs: [String: String] = [:]
    ) {
        stack.append((name: name, attrs: attrs, children: [:], text: ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement name: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard let node = stack.popLast() else { return }
        var object: [String: Any] = node.attrs
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { object["#text"] = text }
        for (key, value) in node.children {
            insert(value, into: &object, key: key)
        }
        if stack.isEmpty {
            root = object
        } else {
            insert(object, into: &stack[stack.count - 1].children, key: name)
        }
    }

    private func insert(_ value: Any, into object: inout [String: Any], key: String) {
        if let existing = object[key] {
            if var array = existing as? [Any] {
                array.append(value)
                object[key] = array
            } else {
                object[key] = [existing, value]
            }
        } else {
            object[key] = value
        }
    }
}
