import Foundation
import Testing

@testable import TestcontainersCore

@Suite("Network")
struct NetworkTests {
    @Test func nameIsLowercasedUUID() {
        let network = Network()
        let uuidPattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
        let regex = try? NSRegularExpression(pattern: uuidPattern)
        let range = NSRange(network.name.startIndex..., in: network.name)
        #expect(regex?.firstMatch(in: network.name, range: range) != nil)
    }

    @Test func twoNetworksHaveDistinctNames() {
        let a = Network()
        let b = Network()
        #expect(a.name != b.name)
    }

    @Test func idIsNilBeforeCreate() {
        let network = Network()
        #expect(network.id == nil)
    }

    @Test func removeBeforeCreateIsNoOp() async throws {
        let network = Network()
        // guard let id else return — safe before create()
        try await network.remove()
    }

    @Test func connectBeforeCreateThrowsNetworkError() async throws {
        let network = Network()
        await #expect(throws: NetworkError.self) {
            try await network.connect("some-container-id")
        }
    }

    @Test func connectBeforeCreateErrorMentionsCreate() async {
        let network = Network()
        do {
            try await network.connect("some-id")
            Issue.record("Expected NetworkError.notCreated")
        } catch NetworkError.notCreated(let msg) {
            #expect(msg.contains("create()"))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func hundredNetworksHaveDistinctNames() {
        let names = Set((0..<100).map { _ in Network().name })
        #expect(names.count == 100)
    }

    @Test func networkNameIsNonEmpty() {
        let network = Network()
        #expect(!network.name.isEmpty)
    }
}
