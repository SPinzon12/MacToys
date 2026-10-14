import Foundation
import Testing
@testable import MacPowerToys

/// Plain text: strip HTML tags and decode entities, no markdown conversion.
struct PlainTextTests {
    private func strip(_ html: String) -> String {
        TextTransforms.plainText(fromHTML: html)
    }

    @Test func tagsAreRemovedAndTextKept() {
        #expect(strip("<p>Hello <b>world</b></p>") == "Hello world")
        #expect(strip("<div>one</div><div>two</div>") == "one\n\ntwo")
    }

    @Test func breakAndParagraphProduceNewlines() {
        #expect(strip("a<br>b") == "a\nb")
        #expect(strip("<p>a</p><p>b</p>") == "a\n\nb")
    }

    @Test func scriptAndStyleContentIsDropped() {
        let out = strip("<script>var x = 1;</script><style>p { color: red; }</style>visible")
        #expect(!out.contains("var x"))
        #expect(!out.contains("color"))
        #expect(out.contains("visible"))
    }

    @Test func entitiesAreDecoded() {
        #expect(strip("<p>a &amp; b &lt; c &gt; d &quot;e&quot;</p>") == "a & b < c > d \"e\"")
    }

    @Test func malformedInputNeverCrashes() {
        #expect(strip("text with <broken tag").contains("text with"))
        #expect(strip("<p>unclosed").contains("unclosed"))
        #expect(strip("5 < 10").contains("5 < 10"))
    }

    @Test func plainTextFromClipboardContent() {
        let htmlOnly = ClipboardContent(html: "<p>formatted</p>")
        #expect(TextTransforms.plainText(from: htmlOnly) == "formatted")
        let textOnly = ClipboardContent(text: "already plain")
        #expect(TextTransforms.plainText(from: textOnly) == "already plain")
        #expect(TextTransforms.plainText(from: ClipboardContent()) == nil)
    }
}
