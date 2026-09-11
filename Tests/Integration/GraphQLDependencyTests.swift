import Apollo
import ApolloAPI
import Foundation
import XCTest

/// Test-only dependency smoke checks. No Sauce API, schema, or network request.
/// Compiled only by the three source-consumer test targets, not by the SDK.
final class GraphQLDependencyTests: XCTestCase {
    func testClientClearsPopulatedCacheConcurrently() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://graphql.invalid"))
        let client = ApolloClient(url: endpoint)
        let key = "DependencySmoke:1"
        let records: RecordSet = [
            key: ["__typename": "DependencySmoke", "label": "Cart"]
        ]
        try await client.store.publish(records: records)

        let before = try await client.store.withinReadTransaction { transaction in
            let loaded = try await transaction.readOnlyCache.loadRecords(forKeys: [key])
            return loaded[key]?["label"] as? String
        }
        XCTAssertEqual(before, "Cart")

        async let first: Void = client.clearCache()
        async let second: Void = client.clearCache()
        _ = try await (first, second)

        let isEmpty = try await client.store.withinReadTransaction { transaction in
            let loaded = try await transaction.readOnlyCache.loadRecords(forKeys: [key])
            return loaded.isEmpty
        }
        XCTAssertTrue(isEmpty)
    }

    func testNullableInputDistinguishesOmittedNullAndValue() {
        let omitted: GraphQLNullable<String> = .none
        let explicitNull: GraphQLNullable<String> = .null
        let value: GraphQLNullable<String> = .some("Cart")

        XCTAssertNotEqual(omitted, explicitNull)
        XCTAssertNil(omitted.unwrapped)
        XCTAssertNil(explicitNull.unwrapped)
        XCTAssertEqual(value.unwrapped, "Cart")
        XCTAssertNotEqual(value, omitted)
        XCTAssertNotEqual(value, explicitNull)
    }
}
