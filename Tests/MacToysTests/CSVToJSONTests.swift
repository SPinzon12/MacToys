import Foundation
import Testing
@testable import MacToys

/// CSV → JSON: header row maps every record into `{"col": "val", ...}`.
struct CSVToJSONTests {
    private func parse(_ json: String) throws -> [[String: String]] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [[String: String]])
    }

    @Test func headerRowMapsEveryRecord() throws {
        let json = try #require(TextTransforms.csvToJSON("""
        name,age
        Alice,30
        Bob,25
        """))
        let rows = try parse(json)
        #expect(rows.count == 2)
        #expect(rows[0] == ["name": "Alice", "age": "30"])
        #expect(rows[1] == ["name": "Bob", "age": "25"])
    }

    @Test func commasAndEscapedQuotesInsideQuotedFields() throws {
        let json = try #require(TextTransforms.csvToJSON(#"""
        city,note
        "Springfield, IL","says ""hi"""
        """#))
        let rows = try parse(json)
        #expect(rows.count == 1)
        #expect(rows[0]["city"] == "Springfield, IL")
        #expect(rows[0]["note"] == "says \"hi\"")
    }

    @Test func emptyLinesAreSkipped() throws {
        let json = try #require(TextTransforms.csvToJSON("\nname\n\nAlice\n\n"))
        let rows = try parse(json)
        #expect(rows.count == 1)
        #expect(rows[0] == ["name": "Alice"])
    }

    @Test func newlineInsideQuotedFieldStaysOneRecord() throws {
        let json = try #require(TextTransforms.csvToJSON(
            "a,b\n\"line1\nline2\",x\n"
        ))
        let rows = try parse(json)
        #expect(rows.count == 1)
        #expect(rows[0]["a"] == "line1\nline2")
        #expect(rows[0]["b"] == "x")
    }

    @Test func missingValueBecomesEmptyString() throws {
        let json = try #require(TextTransforms.csvToJSON("a,b,c\n1,2\n"))
        let rows = try parse(json)
        #expect(rows[0] == ["a": "1", "b": "2", "c": ""])
    }

    @Test func emptyInputReturnsNil() {
        #expect(TextTransforms.csvToJSON("") == nil)
        #expect(TextTransforms.csvToJSON("\n\n") == nil)
    }
}
