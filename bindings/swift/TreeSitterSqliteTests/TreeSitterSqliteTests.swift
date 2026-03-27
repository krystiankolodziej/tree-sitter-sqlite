import XCTest
import SwiftTreeSitter
import TreeSitterSqlite

final class TreeSitterSqliteTests: XCTestCase {

    // MARK: - Parser Tests

    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(tree_sitter_sqlite())
        XCTAssertNoThrow(try parser.setLanguage(language))
    }

    func testCanParseSimpleSelect() throws {
        let parser = Parser()
        let language = Language(tree_sitter_sqlite())
        try parser.setLanguage(language)

        let tree = parser.parse("SELECT * FROM users WHERE id = 1")
        XCTAssertNotNil(tree)
        XCTAssertNotNil(tree?.rootNode)
        XCTAssertEqual(tree?.rootNode?.nodeType, "sql_stmt_list")
        XCTAssertFalse(tree?.rootNode?.hasError ?? true)
    }

    func testCanParseSQLiteSpecific() throws {
        let parser = Parser()
        let language = Language(tree_sitter_sqlite())
        try parser.setLanguage(language)

        let tree1 = parser.parse("CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT)")
        XCTAssertFalse(tree1?.rootNode?.hasError ?? true, "AUTOINCREMENT should parse without error")

        let tree2 = parser.parse("INSERT OR REPLACE INTO t VALUES (1)")
        XCTAssertFalse(tree2?.rootNode?.hasError ?? true, "INSERT OR REPLACE should parse without error")

        let tree3 = parser.parse("PRAGMA foreign_keys = ON")
        XCTAssertFalse(tree3?.rootNode?.hasError ?? true, "PRAGMA should parse without error")

        let tree4 = parser.parse("CREATE VIRTUAL TABLE docs USING fts5(title, body)")
        XCTAssertFalse(tree4?.rootNode?.hasError ?? true, "CREATE VIRTUAL TABLE should parse without error")
    }

    // MARK: - Highlights Tests

    /// Loads highlights.scm directly from the repo source (not from bundle).
    private func loadHighlightsQuery() throws -> Query {
        let language = Language(tree_sitter_sqlite())

        // Find the queries/highlights.scm file relative to the test file location.
        // SPM test working directory is the package root.
        let candidates = [
            "queries/highlights.scm",
            "../../../queries/highlights.scm",  // from bindings/swift/TreeSitterSqliteTests/
        ]

        var scmContent: String?
        for candidate in candidates {
            if let content = try? String(contentsOfFile: candidate, encoding: .utf8) {
                scmContent = content
                break
            }
        }

        // Fallback: search from current working directory upwards
        if scmContent == nil {
            let fm = FileManager.default
            var dir = fm.currentDirectoryPath
            for _ in 0..<5 {
                let path = (dir as NSString).appendingPathComponent("queries/highlights.scm")
                if fm.fileExists(atPath: path) {
                    scmContent = try String(contentsOfFile: path, encoding: .utf8)
                    break
                }
                dir = (dir as NSString).deletingLastPathComponent
            }
        }

        guard let content = scmContent else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "highlights.scm not found"])
        }

        return try Query(language: language, data: content.data(using: .utf8)!)
    }

    /// Returns all (captureName, matchedText) pairs from highlights query.
    private func highlights(for sql: String) throws -> [(capture: String, text: String)] {
        let language = Language(tree_sitter_sqlite())
        let parser = Parser()
        try parser.setLanguage(language)

        guard let tree = parser.parse(sql) else {
            XCTFail("Failed to parse SQL")
            return []
        }

        let query = try loadHighlightsQuery()
        let cursor = query.execute(in: tree)
        let nsString = sql as NSString
        var results: [(capture: String, text: String)] = []

        for match in cursor {
            for capture in match.captures {
                guard let name = capture.name else { continue }
                let range = capture.range
                guard range.location + range.length <= nsString.length else { continue }
                let text = nsString.substring(with: range)
                results.append((capture: name, text: text))
            }
        }

        return results
    }

    /// Finds the capture name for a specific text.
    /// When multiple captures match the same text, prefer more specific ones
    /// (function.call > variable, field > variable, etc.)
    private func captureFor(_ text: String, in highlights: [(capture: String, text: String)]) -> String? {
        let matches = highlights.filter { $0.text == text }
        if matches.isEmpty { return nil }
        // Prefer more specific captures over generic ones
        let priority = ["function.call", "field", "type", "string.special",
                        "variable.parameter", "keyword", "string", "number",
                        "comment", "operator", "punctuation.delimiter",
                        "punctuation.bracket", "variable"]
        for p in priority {
            if matches.contains(where: { $0.capture == p }) { return p }
        }
        return matches.last?.capture
    }

    // MARK: - Keyword Highlighting

    func testKeywordsAreHighlighted() throws {
        let h = try highlights(for: "SELECT * FROM users WHERE id = 1")
        XCTAssertEqual(captureFor("SELECT", in: h), "keyword")
        XCTAssertEqual(captureFor("FROM", in: h), "keyword")
        XCTAssertEqual(captureFor("WHERE", in: h), "keyword")
    }

    func testSQLiteSpecificKeywords() throws {
        let h1 = try highlights(for: "PRAGMA foreign_keys = ON")
        XCTAssertEqual(captureFor("PRAGMA", in: h1), "keyword")

        let h2 = try highlights(for: "CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT)")
        XCTAssertEqual(captureFor("AUTOINCREMENT", in: h2), "keyword")

        let h3 = try highlights(for: "INSERT OR REPLACE INTO t VALUES (1)")
        XCTAssertEqual(captureFor("REPLACE", in: h3), "keyword")
        XCTAssertEqual(captureFor("OR", in: h3), "keyword")
    }

    func testJoinKeywords() throws {
        let h = try highlights(for: "SELECT * FROM a LEFT OUTER JOIN b ON a.id = b.id")
        XCTAssertEqual(captureFor("LEFT", in: h), "keyword")
        XCTAssertEqual(captureFor("OUTER", in: h), "keyword")
        XCTAssertEqual(captureFor("JOIN", in: h), "keyword")
        XCTAssertEqual(captureFor("ON", in: h), "keyword")
    }

    // MARK: - Function Highlighting

    func testFunctionsAreHighlighted() throws {
        let h = try highlights(for: "SELECT COUNT(*), MAX(id), MIN(id) FROM users")
        XCTAssertEqual(captureFor("COUNT", in: h), "function.call",
                       "COUNT should be function.call, not \(captureFor("COUNT", in: h) ?? "nil")")
        XCTAssertEqual(captureFor("MAX", in: h), "function.call",
                       "MAX should be function.call, not \(captureFor("MAX", in: h) ?? "nil")")
        XCTAssertEqual(captureFor("MIN", in: h), "function.call",
                       "MIN should be function.call, not \(captureFor("MIN", in: h) ?? "nil")")
    }

    func testFunctionNotOverriddenByVariable() throws {
        let h = try highlights(for: "SELECT SUM(total) FROM orders")
        XCTAssertEqual(captureFor("SUM", in: h), "function.call",
                       "SUM should be function.call (not variable)")
        XCTAssertEqual(captureFor("total", in: h), "variable")
        XCTAssertEqual(captureFor("orders", in: h), "variable")
    }

    // MARK: - Literal Highlighting

    func testStringLiterals() throws {
        let h = try highlights(for: "SELECT * FROM users WHERE name = 'test'")
        XCTAssertEqual(captureFor("'test'", in: h), "string")
    }

    func testNumericLiterals() throws {
        let h = try highlights(for: "SELECT * FROM users WHERE id = 42")
        XCTAssertEqual(captureFor("42", in: h), "number")
    }

    func testBlobLiterals() throws {
        let h = try highlights(for: "SELECT X'48656C6C6F'")
        XCTAssertEqual(captureFor("X'48656C6C6F'", in: h), "string.special")
    }

    // MARK: - Comment Highlighting

    func testLineComment() throws {
        let h = try highlights(for: "-- this is a comment\nSELECT 1")
        XCTAssertEqual(captureFor("-- this is a comment", in: h), "comment")
    }

    func testBlockComment() throws {
        let h = try highlights(for: "/* block */\nSELECT 1")
        XCTAssertEqual(captureFor("/* block */", in: h), "comment")
    }

    // MARK: - Identifier and Operator Highlighting

    func testIdentifiersAreVariables() throws {
        let h = try highlights(for: "SELECT name FROM users")
        XCTAssertEqual(captureFor("name", in: h), "variable")
        XCTAssertEqual(captureFor("users", in: h), "variable")
    }

    func testOperators() throws {
        let h = try highlights(for: "SELECT 1 + 2, 3 * 4, a || b")
        XCTAssertEqual(captureFor("+", in: h), "operator")
        XCTAssertEqual(captureFor("||", in: h), "operator")
    }

    func testPunctuation() throws {
        let h = try highlights(for: "SELECT a, b FROM t")
        XCTAssertEqual(captureFor(",", in: h), "punctuation.delimiter")
    }

    // MARK: - Type Highlighting

    func testTypeNames() throws {
        let h = try highlights(for: "CREATE TABLE t (id INTEGER, name TEXT, age REAL)")
        XCTAssertEqual(captureFor("INTEGER", in: h), "type")
        XCTAssertEqual(captureFor("TEXT", in: h), "type")
        XCTAssertEqual(captureFor("REAL", in: h), "type")
    }

    // MARK: - Bind Parameters

    func testBindParameters() throws {
        let h = try highlights(for: "SELECT * FROM users WHERE id = ?1")
        XCTAssertEqual(captureFor("?1", in: h), "variable.parameter")
    }

    // MARK: - Alias Highlighting

    func testTableAliasHighlighted() throws {
        let h = try highlights(for: "SELECT * FROM users u")
        XCTAssertEqual(captureFor("u", in: h), "variable")
    }

    func testColumnAliasHighlighted() throws {
        let h = try highlights(for: "SELECT name AS username FROM users")
        XCTAssertEqual(captureFor("username", in: h), "variable")
    }
}
