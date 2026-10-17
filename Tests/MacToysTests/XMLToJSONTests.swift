import Foundation
import Testing
@testable import MacToys

/// XML → JSON: element → object, attributes as keys, `#text` for text,
/// children nested by tag name (duplicate names become an array).
struct XMLToJSONTests {
    private func parse(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }

    @Test func attributesAndChildText() throws {
        let json = try #require(TextTransforms.xmlToJSON(
            #"<book id="42"><title>Dune</title></book>"#
        ))
        let root = try parse(json)
        #expect(root["id"] as? String == "42")
        let title = try #require(root["title"] as? [String: Any])
        #expect(title["#text"] as? String == "Dune")
    }

    @Test func elementWithAttributeAndText() throws {
        let json = try #require(TextTransforms.xmlToJSON(
            #"<a href="https://example.com">click</a>"#
        ))
        let root = try parse(json)
        #expect(root["href"] as? String == "https://example.com")
        #expect(root["#text"] as? String == "click")
    }

    @Test func nestedElements() throws {
        let json = try #require(TextTransforms.xmlToJSON(
            "<root><outer><inner>deep</inner></outer></root>"
        ))
        let root = try parse(json)
        let outer = try #require(root["outer"] as? [String: Any])
        let inner = try #require(outer["inner"] as? [String: Any])
        #expect(inner["#text"] as? String == "deep")
    }

    @Test func duplicateChildNamesBecomeArray() throws {
        let json = try #require(TextTransforms.xmlToJSON(
            "<root><item><name>A</name></item><item><name>B</name></item></root>"
        ))
        let root = try parse(json)
        let items = try #require(root["item"] as? [[String: Any]])
        #expect(items.count == 2)
        let first = try #require(items[0]["name"] as? [String: Any])
        #expect(first["#text"] as? String == "A")
    }

    @Test func prettyPrintedWhitespaceIsIgnored() throws {
        let json = try #require(TextTransforms.xmlToJSON("""
        <root>
            <name>Alice</name>
        </root>
        """))
        let root = try parse(json)
        let name = try #require(root["name"] as? [String: Any])
        #expect(name["#text"] as? String == "Alice")
        #expect(json.contains("\n"), "output must be pretty-printed")
    }

    @Test func malformedXMLReturnsNil() {
        #expect(TextTransforms.xmlToJSON("<root><unclosed></root>") == nil)
        #expect(TextTransforms.xmlToJSON("not xml at all") == nil)
    }

    @Test func structuredDetectionRoutesByLeadingAngleBracket() throws {
        let xml = try #require(TextTransforms.structuredToJSON("<a>x</a>"))
        #expect(try parse(xml)["#text"] as? String == "x")
        let csv = try #require(TextTransforms.structuredToJSON("a,b\n1,2"))
        let rows = try JSONSerialization.jsonObject(with: Data(csv.utf8))
        #expect((rows as? [[String: String]])?.first?["a"] == "1")
        // Leading whitespace must not defeat the `<` detection.
        #expect(TextTransforms.structuredToJSON("  <a>x</a>") != nil)
    }
}
