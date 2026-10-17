import Foundation
import Testing
@testable import MacToys

/// HTML → Markdown: the supported subset only; everything else is stripped
/// to its text. Malformed input must never crash.
struct HTMLToMarkdownTests {
    private func md(_ html: String) -> String {
        TextTransforms.htmlToMarkdown(html)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Block tags

    @Test func headings() {
        #expect(md("<h1>Title</h1>") == "# Title")
        #expect(md("<h2>Sub</h2>") == "## Sub")
        #expect(md("<h3>Deep</h3>") == "### Deep")
        #expect(md("<h6>Deepest</h6>") == "###### Deepest")
    }

    @Test func paragraphAndBreak() {
        #expect(md("<p>Hello</p>") == "Hello")
        #expect(md("<p>a<br>b</p>") == "a\nb")
        #expect(md("<p>one</p><p>two</p>") == "one\n\ntwo")
    }

    @Test func blockquote() {
        #expect(md("<blockquote>quoted</blockquote>") == "> quoted")
    }

    @Test func preFencedCodeBlock() {
        #expect(md("<pre>let x = 1</pre>") == "```\nlet x = 1\n```")
    }

    // MARK: - Inline tags

    @Test func strongAndEmphasis() {
        #expect(md("<p><strong>x</strong></p>") == "**x**")
        #expect(md("<p><b>x</b></p>") == "**x**")
        #expect(md("<p><em>x</em></p>") == "*x*")
        #expect(md("<p><i>x</i></p>") == "*x*")
    }

    @Test func link() {
        #expect(
            md(#"<p><a href="https://example.com">link</a></p>"#)
                == "[link](https://example.com)"
        )
    }

    @Test func inlineCode() {
        #expect(md("<p><code>x = 1</code></p>") == "`x = 1`")
    }

    // MARK: - Lists

    @Test func unorderedList() {
        #expect(md("<ul><li>a</li><li>b</li></ul>") == "- a\n- b")
    }

    @Test func orderedList() {
        #expect(md("<ol><li>a</li><li>b</li></ol>") == "1. a\n2. b")
    }

    @Test func nestedListIsIndented() {
        #expect(md("<ul><li>a<ul><li>b</li></ul></li></ul>") == "- a\n  - b")
    }

    // MARK: - Nesting across contexts

    @Test func listInsideBlockquote() {
        #expect(md("<blockquote><ul><li>x</li></ul></blockquote>") == "> - x")
    }

    @Test func inlineNestedInsideLink() {
        #expect(
            md(#"<p><a href="https://x.test"><strong>bold link</strong></a></p>"#)
                == "[**bold link**](https://x.test)"
        )
    }

    // MARK: - Stripping and robustness

    @Test func unsupportedTagsKeepTheirText() {
        #expect(md("<section data-x=\"1\">keep me</section>") == "keep me")
        #expect(md("<table><tr><td>cell</td></tr></table>") == "cell")
    }

    @Test func scriptAndStyleContentIsDropped() {
        let out = md("<p>ok</p><script>alert('evil')</script><style>p{}</style>")
        #expect(out.contains("ok"))
        #expect(!out.contains("evil"))
        #expect(!out.contains("p{}"))
    }

    @Test func malformedInputNeverCrashes() {
        // Unclosed tags: text survives, markdown markers may be unbalanced.
        let unclosed = md("<p>unclosed <strong>bold")
        #expect(unclosed.contains("unclosed"))
        #expect(unclosed.contains("bold"))
        // Stray `<` without a closing `>` stays literal text.
        #expect(md("a < b and <p>tail").contains("tail"))
        #expect(md("<div").contains("div"))
        // Truncated attribute quote.
        #expect(md(#"<a href="https://broken.link>text</a>"#).contains("text"))
    }

    @Test func entitiesAreDecoded() {
        #expect(md("<p>a &amp; b &lt; c</p>") == "a & b < c")
    }

    @Test func whitespaceRunsCollapseInParagraphs() {
        #expect(md("<p>  spaced   out\n\n  text  </p>") == "spaced out text")
    }
}
