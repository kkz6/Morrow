import XCTest
@testable import MorrowCore

final class DiagnosticInsightsTests: XCTestCase {
    private func event(_ kind: String, _ title: String, _ fields: [String: DiagnosticValue] = [:]) -> DiagnosticEvent {
        DiagnosticEvent(id: UUID().uuidString, kind: kind, time: 1, title: title, value: .object(fields), file: nil, line: nil)
    }
    func testQueryPatternsArePerConnectionAndFlagOnlyRepeatedWork() {
        let queries = (1...3).map { event("query", "select * from users where id = \($0)", ["duration_ms": .number(Double($0) * 50), "connection": .string("main")]) }
        let other = event("query", "select * from users where id = 4", ["connection": .string("analytics"), "duration_ms": .number(1)])
        let response = event("response", "Finished", ["duration_ms": .number(400), "status": .number(200)])
        let insights = DiagnosticInsights(events: queries + [other, response])
        XCTAssertEqual(insights.queryCount, 4); XCTAssertEqual(insights.queryMilliseconds, 301)
        XCTAssertEqual(insights.slowQueryCount, 2); XCTAssertEqual(insights.repeatedQueries.count, 1)
        XCTAssertEqual(insights.repeatedQueries.first?.count, 3)
        XCTAssertEqual(insights.repeatedQueries.first?.connection, "main")
        XCTAssertEqual(insights.durationMilliseconds, 400); XCTAssertEqual(insights.status, 200)
        XCTAssertTrue(insights.needsAttention)
    }
    func testQueryNormalizationPreservesIdentifiersAndOperators() {
        let shape = DiagnosticInsights.queryShape
        XCTAssertEqual(shape("SELECT * FROM t2 WHERE id=42 AND name='O''Neil' /* detail */"), shape("select * from t2 where id = 99 and name = 'other'"))
        XCTAssertEqual(shape("select * from t where body=$tag$hello 'world'$tag$"), shape("select * from t where body='different'"))
        XCTAssertEqual(shape("select 1.5e-4 -- comment\n from t"), shape("select 2 from t"))
        XCTAssertNotEqual(shape("select `value1` from t1"), shape("select `value2` from t2"))
        XCTAssertNotEqual(shape("select * from t where a >= 1"), shape("select * from t where a > 1"))
        XCTAssertEqual(shape("select /* outer /* inner */ end */ 3"), "select ?")
    }
    func testIncompleteCapturesAndErrorsDoNotInventTiming() {
        let values = [event("error", "Exception"), event("log", "ERROR Failed"), event("log", "WARNING Retrying"), event("query", "select 1", ["duration_ms": .number(-1)])]
        let insights = DiagnosticInsights(events: values)
        XCTAssertNil(insights.durationMilliseconds); XCTAssertNil(insights.status)
        XCTAssertEqual(insights.queryMilliseconds, 0); XCTAssertEqual(insights.errorCount, 2)
        XCTAssertTrue(insights.needsAttention)
        XCTAssertTrue(DiagnosticInsights(events: [event("response", "Finished", ["status": .number(503)])]).needsAttention)
        XCTAssertFalse(DiagnosticInsights(events: [event("response", "Finished", ["status": .number(302)])]).needsAttention)
    }
    func testSearchFindsNestedValuesAndTypeFilterAppliesToTheSameEvent() {
        let request = DiagnosticRequest(id: "one", project: "/project", events: [
            event("request", "GET /users"), event("dump", "dump()", ["profile": .array([.object(["name": .string("Ada")])])]),
            event("query", "select users", ["bindings": .array([.number(12)])])
        ])
        XCTAssertTrue(request.matches("ada")); XCTAssertTrue(request.matches("12", kind: "query"))
        XCTAssertFalse(request.matches("Ada", kind: "query")); XCTAssertFalse(request.matches("", kind: "error"))
        XCTAssertTrue(request.matches("/users", kind: "query"))
    }
}
