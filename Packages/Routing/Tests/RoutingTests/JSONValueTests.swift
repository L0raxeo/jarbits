import Foundation
import Testing
@testable import Routing

@Suite struct JSONValueTests {
    @Test func whatJSONSerializationReadsComesBackWhole() throws {
        let text = #"{"a":true,"b":1,"c":"x","d":null,"e":[1,2.5],"f":{"g":false,"h":"y"}}"#
        let any = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let value = try JSONValue(any: any)
        #expect(value == ["a": true, "b": 1, "c": "x", "d": nil, "e": [1, 2.5], "f": ["g": false, "h": "y"]])
        #expect(value["a"]?.boolValue == true, "a bool stays a bool")
        #expect(value["b"]?.doubleValue == 1, "a number stays a number")
        #expect(value["b"]?.intValue == 1)
        #expect(value["e"]?.arrayValue?[1].intValue == nil, "2.5 is no whole number")
        #expect(value["d"]?.isNull == true)
        #expect(value["f"]?["h"]?.stringValue == "y")
        #expect(value["missing"] == nil)
        let back = try JSONValue(any: value.any)
        #expect(back == value, "back through JSONSerialization's shapes")
    }

    @Test func bytesAreSortedAndStable() throws {
        let value: JSONValue = ["b": "y", "a": ["d": true, "c": nil]]
        #expect(String(decoding: try value.data(), as: UTF8.self) == #"{"a":{"c":null,"d":true},"b":"y"}"#)
        #expect(try value.data() == JSONValue.object(["a": .object(["c": .null, "d": .bool(true)]), "b": .string("y")]).data())
    }

    @Test func aFieldOfThisTypeSynthesises() throws {
        struct Holder: Codable, Equatable {
            var schema: JSONValue
            var note: JSONValue?
        }
        let holder = Holder(schema: ["type": "object", "required": ["temperature"]], note: nil)
        let data = try JSONEncoder().encode(holder)
        #expect(try JSONDecoder().decode(Holder.self, from: data) == holder)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(#"[1, "two", null, {"three": 3.5}]"#.utf8)) == [1, "two", nil, ["three": 3.5]])
    }

    @Test func somethingThatIsNotJSONIsRefused() {
        #expect(throws: DecodingError.self) { try JSONValue(any: Date()) }
    }
}
