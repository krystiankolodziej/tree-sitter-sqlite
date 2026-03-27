import XCTest
import SwiftTreeSitter
import TreeSitterSqlite

final class TreeSitterSqliteTests: XCTestCase {
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

        // AUTOINCREMENT
        let tree1 = parser.parse("CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT)")
        XCTAssertFalse(tree1?.rootNode?.hasError ?? true, "AUTOINCREMENT should parse without error")

        // INSERT OR REPLACE
        let tree2 = parser.parse("INSERT OR REPLACE INTO t VALUES (1)")
        XCTAssertFalse(tree2?.rootNode?.hasError ?? true, "INSERT OR REPLACE should parse without error")

        // PRAGMA
        let tree3 = parser.parse("PRAGMA foreign_keys = ON")
        XCTAssertFalse(tree3?.rootNode?.hasError ?? true, "PRAGMA should parse without error")

        // CREATE VIRTUAL TABLE
        let tree4 = parser.parse("CREATE VIRTUAL TABLE docs USING fts5(title, body)")
        XCTAssertFalse(tree4?.rootNode?.hasError ?? true, "CREATE VIRTUAL TABLE should parse without error")
    }
}
