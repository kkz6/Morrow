import Foundation

public struct QueryPattern: Codable, Identifiable, Sendable {
    public var id: String { connection + ":" + sql }
    public let sql: String
    public let connection: String
    public let count: Int
    public let durationMilliseconds: Double
}

public struct DiagnosticInsights: Codable, Sendable {
    public let durationMilliseconds: Double?
    public let status: Int?
    public let queryCount: Int
    public let queryMilliseconds: Double
    public let slowQueryCount: Int
    public let errorCount: Int
    public let repeatedQueries: [QueryPattern]
    public var needsAttention: Bool { slowQueryCount > 0 || errorCount > 0 || !repeatedQueries.isEmpty || (status ?? 0) >= 500 }
    public static let slowQueryMilliseconds: Double = 100

    public init(events: [DiagnosticEvent]) {
        let response = events.last { $0.kind == "response" }
        durationMilliseconds = response?.value.nonnegativeNumber("duration_ms")
        status = response?.value.nonnegativeNumber("status").flatMap { (100...599).contains($0) ? Int($0) : nil }
        let queries = events.filter { $0.kind == "query" }
        queryCount = queries.count
        queryMilliseconds = queries.reduce(0) { $0 + ($1.value.nonnegativeNumber("duration_ms") ?? 0) }
        slowQueryCount = queries.filter { ($0.value.nonnegativeNumber("duration_ms") ?? 0) >= Self.slowQueryMilliseconds }.count
        errorCount = events.filter { event in
            event.kind == "error" || event.kind == "log" && ["ERROR", "CRITICAL", "ALERT", "EMERGENCY"].contains(String(event.title.prefix { !$0.isWhitespace }).uppercased())
        }.count
        var groups: [String: (sql: String, connection: String, count: Int, duration: Double)] = [:]
        for query in queries {
            let sql = Self.queryShape(query.title), connection = query.value.string("connection") ?? "default"
            guard !sql.isEmpty else { continue }
            let key = connection + "\u{0}" + sql
            let old = groups[key]
            groups[key] = (sql, connection, (old?.count ?? 0) + 1, (old?.duration ?? 0) + (query.value.nonnegativeNumber("duration_ms") ?? 0))
        }
        repeatedQueries = groups.values.filter { $0.count >= 3 }.map { QueryPattern(sql: $0.sql, connection: $0.connection, count: $0.count, durationMilliseconds: $0.duration) }
            .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }

    /// A conservative SQL shape, not a SQL parser. Keep quoted identifiers and
    /// operators intact; normalize literal values to spot repeated work. These
    /// are investigation hints, never proof of an N+1 bug.
    static func queryShape(_ sql: String) -> String {
        let input = Array(sql.prefix(8192)), count = input.count
        var index = 0, tokens: [String] = []
        func word(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
        while index < count {
            let c = input[index]
            if c.isWhitespace { index += 1; continue }
            if c == "-", index + 1 < count, input[index + 1] == "-" {
                while index < count && input[index] != "\n" { index += 1 }; continue
            }
            if c == "/", index + 1 < count, input[index + 1] == "*" {
                index += 2; var depth = 1
                while index < count && depth > 0 {
                    if index + 1 < count && input[index] == "/" && input[index + 1] == "*" { depth += 1; index += 2 }
                    else if index + 1 < count && input[index] == "*" && input[index + 1] == "/" { depth -= 1; index += 2 }
                    else { index += 1 }
                }
                continue
            }
            if c == "'" || c == "\"" || c == "`" {
                let start = index; index += 1
                while index < count {
                    if input[index] == "\\" { index = min(count, index + 2); continue }
                    if input[index] == c {
                        index += 1
                        if index < count && input[index] == c { index += 1; continue }
                        break
                    }
                    index += 1
                }
                tokens.append(c == "'" ? "?" : String(input[start..<index])); continue
            }
            if c == "$" {
                var end = index + 1
                while end < count && (input[end].isLetter || input[end].isNumber || input[end] == "_") { end += 1 }
                if end < count && input[end] == "$", end == index + 1 || !input[index + 1].isNumber {
                    let delimiter = Array(input[index...end]); index = end + 1
                    while index + delimiter.count <= count && Array(input[index..<(index + delimiter.count)]) != delimiter { index += 1 }
                    index = min(count, index + delimiter.count); tokens.append("?"); continue
                }
            }
            if c.isNumber {
                index += 1
                while index < count && (input[index].isNumber || input[index] == ".") { index += 1 }
                if index < count && (input[index] == "e" || input[index] == "E") {
                    index += 1
                    if index < count && (input[index] == "+" || input[index] == "-") { index += 1 }
                    while index < count && input[index].isNumber { index += 1 }
                }
                tokens.append("?"); continue
            }
            if word(c) {
                let start = index; index += 1
                while index < count && word(input[index]) { index += 1 }
                tokens.append(String(input[start..<index]).lowercased()); continue
            }
            tokens.append(String(c)); index += 1
        }
        return tokens.joined(separator: " ")
    }
}

extension DiagnosticValue {
    func nonnegativeNumber(_ key: String) -> Double? {
        guard case .object(let fields) = self, case .number(let value) = fields[key], value.isFinite, (0...1_000_000_000_000).contains(value) else { return nil }; return value
    }
    func string(_ key: String) -> String? {
        guard case .object(let fields) = self, case .string(let value) = fields[key] else { return nil }; return value
    }
    public func contains(_ search: String) -> Bool {
        switch self {
        case .object(let fields): return fields.contains { $0.key.localizedCaseInsensitiveContains(search) || $0.value.contains(search) }
        case .array(let values): return values.contains { $0.contains(search) }
        default: return text.localizedCaseInsensitiveContains(search)
        }
    }
}

extension DiagnosticEvent {
    public var queryMilliseconds: Double? { kind == "query" ? value.nonnegativeNumber("duration_ms") : nil }
    public func matches(_ search: String) -> Bool {
        search.isEmpty || title.localizedCaseInsensitiveContains(search) || (file?.localizedCaseInsensitiveContains(search) ?? false) || value.contains(search)
    }
}

extension DiagnosticRequest {
    public var insights: DiagnosticInsights { DiagnosticInsights(events: events) }
    public func matches(_ search: String, kind: String = "all") -> Bool {
        let candidates = events.filter { kind == "all" || $0.kind == kind }
        guard !candidates.isEmpty else { return false }
        return search.isEmpty || title.localizedCaseInsensitiveContains(search) || project.localizedCaseInsensitiveContains(search) || candidates.contains { $0.matches(search) }
    }
}

public struct DiagnosticRequestReport: Codable, Sendable {
    public let id: String
    public let project: String
    public let title: String
    public let time: Double
    public let insights: DiagnosticInsights
    public init(_ request: DiagnosticRequest) {
        id = request.id; project = request.project; title = request.title; time = request.time; insights = request.insights
    }
}
