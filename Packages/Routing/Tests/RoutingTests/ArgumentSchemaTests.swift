import Foundation
import Testing
@testable import Routing

@Suite struct ArgumentSchemaTests {
    private let thermostat = ArgumentSchema(fields: [
        .init(name: "temperature", kind: .integer, description: "the degrees asked for"),
        .init(name: "room", kind: .text, description: "which room", required: false),
        .init(name: "mode", kind: .choice(["heat", "cool"]), description: "heat or cool"),
        .init(name: "fan", kind: .boolean, description: "the fan on", required: false),
    ])

    @Test func theSchemaListsEveryFieldAndRequiresTheRequiredOnes() throws {
        let schema = thermostat.jsonSchema()
        #expect(schema["type"] == "object")
        #expect(schema["additionalProperties"] == false)
        #expect(schema["required"] == ["temperature", "mode"])
        let properties = try #require(schema["properties"]?.objectValue)
        #expect(properties["temperature"]?["type"] == "integer")
        #expect(properties["temperature"]?["description"] == "the degrees asked for")
        #expect(properties["room"]?["type"] == ["string", "null"], "an optional field is nullable")
        #expect(properties["mode"]?["enum"] == ["heat", "cool"])
        #expect(properties["fan"]?["type"] == ["boolean", "null"])
        let only = thermostat.jsonSchema(only: thermostat.freeForm)
        #expect(Set(only["properties"]?.objectValue?.keys.map { $0 } ?? []) == ["temperature", "room"])
        #expect(only["required"] == ["temperature"])
        #expect(try thermostat.jsonSchema().data() == thermostat.jsonSchema().data(), "byte-stable")
        #expect(String(decoding: try ArgumentSchema.none.jsonSchema().data(), as: UTF8.self) == #"{"additionalProperties":false,"properties":{},"required":[],"type":"object"}"#)
    }

    @Test func validationCoercesAndDrops() {
        let read = thermostat.validate(["temperature": "68", "room": nil, "mode": "cool", "fan": "yes", "extra": 1])
        #expect(read == ["temperature": 68, "mode": "cool", "fan": true])
        #expect(thermostat.validate(["temperature": 68.5]) == [:], "an integer field takes no fraction")
        #expect(thermostat.validate(["temperature": 68]) == ["temperature": 68])
        #expect(thermostat.validate(["mode": "warm"]) == [:], "a choice outside its options is dropped")
        #expect(thermostat.validate(["room": 3]) == ["room": "3"], "a number read for a text field is its text")
        #expect(thermostat.validate(["room": "  "]) == [:])
        #expect(thermostat.validate(["fan": false]) == ["fan": false])
        #expect(thermostat.validate(["fan": "off"]) == ["fan": false])
        #expect(thermostat.missingRequired(in: ["temperature": 68]).map(\.name) == ["mode"])
        #expect(thermostat.missingRequired(in: ["temperature": 68, "mode": "heat"]).isEmpty)
        #expect(thermostat.freeForm.map(\.name) == ["temperature", "room"])
        #expect(thermostat.closedSet.map(\.name) == ["mode", "fan"])
    }
}
