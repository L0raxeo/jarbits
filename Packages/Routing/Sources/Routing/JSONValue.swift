import Foundation

/// A JSON value kept whole: a schema, a tool's arguments, a model's step
/// before and after the wire. Codable through a single value, so a field
/// of this type synthesises; `data()` writes it with sorted keys, so the
/// same value is always the same bytes. Numbers are doubles: an exact
/// large quantity, an id, goes as a string.
public indirect enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// From what `JSONSerialization` reads: a bool stays a bool, a number a number.
    public init(any: Any) throws {
        switch any {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(try array.map(JSONValue.init(any:)))
        case let object as [String: Any]:
            self = .object(try object.mapValues(JSONValue.init(any:)))
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "not a JSON value: \(type(of: any))"))
        }
    }

    /// Back to what `JSONSerialization` writes.
    public var any: Any {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case .null: NSNull()
        case let .array(value): value.map(\.any)
        case let .object(value): value.mapValues(\.any)
        }
    }

    /// The value as bytes, keys sorted.
    public func data() throws -> Data {
        try OrderedJSON.encode(self)
    }

    public var stringValue: String? { if case let .string(value) = self { value } else { nil } }
    public var doubleValue: Double? { if case let .number(value) = self { value } else { nil } }
    /// A whole number, within an Int.
    public var intValue: Int? {
        guard case let .number(value) = self, value.rounded() == value, value.magnitude < 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }
    public var boolValue: Bool? { if case let .bool(value) = self { value } else { nil } }
    public var arrayValue: [JSONValue]? { if case let .array(value) = self { value } else { nil } }
    public var objectValue: [String: JSONValue]? { if case let .object(value) = self { value } else { nil } }
    public var isNull: Bool { if case .null = self { true } else { false } }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last })) }
    public init(nilLiteral: ()) { self = .null }
}
