import Foundation
import Testing

@testable import TestcontainersCore

@Suite("createLabels")
struct LabelsTests {
    @Test func attachesRequiredLabelKeys() throws {
        let labels = try createLabels(image: "nginx:latest")
        #expect(labels[labelTestcontainers] == "true")
        #expect(labels[labelVersion] == tcVersion)
        #expect(labels[labelLang] == labelLangValue)
        #expect(labels[labelSessionId] != nil)
    }

    @Test func omitsSessionIdLabelForRyukImage() throws {
        let labels = try createLabels(image: testcontainersConfig.ryukImage)
        #expect(labels[labelSessionId] == nil)
        #expect(labels[labelTestcontainers] == "true")
    }

    @Test func mergesUserSuppliedLabels() throws {
        let labels = try createLabels(image: "nginx:latest", labels: ["app": "myapp"])
        #expect(labels["app"] == "myapp")
        #expect(labels[labelTestcontainers] == "true")
    }

    @Test func throwsWhenUserLabelUsesReservedPrefix() {
        #expect(throws: (any Error).self) {
            _ = try createLabels(image: "nginx:latest", labels: ["org.testcontainers.custom": "value"])
        }
    }

    @Test func throwsWhenUserLabelIsExactNamespace() {
        #expect(throws: (any Error).self) {
            _ = try createLabels(image: "nginx:latest", labels: ["org.testcontainers": "value"])
        }
    }

    @Test func throwsWhenUserLabelStartsWithNamespaceNoDot() {
        #expect(throws: (any Error).self) {
            _ = try createLabels(image: "nginx:latest", labels: ["org.testcontainersXYZ": "value"])
        }
    }

    @Test func allowsLabelNotStartingWithReservedPrefix() throws {
        _ = try createLabels(image: "nginx:latest", labels: ["com.mycompany.label": "value"])
    }

    @Test func sessionIdIsNonEmpty() {
        #expect(!sessionId.isEmpty)
    }

    @Test func sessionIdIsValidLowercaseUUID() {
        // UUID v4 pattern (lowercased)
        let uuidPattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
        let regex = try? NSRegularExpression(pattern: uuidPattern)
        let range = NSRange(sessionId.startIndex..., in: sessionId)
        #expect(regex?.firstMatch(in: sessionId, range: range) != nil)
    }

    @Test func labelLangValueIsSwift() {
        #expect(labelLangValue == "swift")
    }

    @Test func sessionIdIsScopedSameValueOnTwoCalls() throws {
        let first = try createLabels(image: "not-ryuk")
        let second = try createLabels(image: "not-ryuk")
        #expect(first[labelSessionId] == second[labelSessionId])
    }

    @Test func doesNotMutateInputMap() throws {
        let input: [String: String] = ["key": "value"]
        let expected = input
        _ = try createLabels(image: "nginx:latest", labels: input)
        #expect(input == expected)
    }

    @Test func withEmptyMapAdds4RequiredKeys() throws {
        let labels = try createLabels(image: "nginx:latest", labels: [:])
        #expect(labels.count == 4)
    }

    @Test func forRyukImageAddsExactly3Keys() throws {
        let labels = try createLabels(image: testcontainersConfig.ryukImage, labels: [:])
        #expect(labels.count == 3)
        #expect(labels[labelSessionId] == nil)
    }

    @Test func throwsWhenAnyOfMultipleLabelsHasReservedPrefix() {
        #expect(throws: (any Error).self) {
            _ = try createLabels(
                image: "nginx:latest",
                labels: [
                    "com.example.ok": "good",
                    "org.testcontainers.bad": "value",
                    "net.app.other": "fine",
                ]
            )
        }
    }

    @Test func errorMessageMentionsReservedNamespace() {
        do {
            _ = try createLabels(image: "nginx:latest", labels: ["org.testcontainers.custom": "value"])
            Issue.record("Expected error")
        } catch {
            let desc = String(describing: error)
            #expect(desc.contains("org.testcontainers"))
        }
    }
}

@Suite("Label constants")
struct LabelConstantsTests {
    @Test func testcontainersNamespaceIsRootNamespace() {
        #expect(testcontainersNamespace == "org.testcontainers")
    }

    @Test func labelTestcontainersEqualsNamespace() {
        #expect(labelTestcontainers == testcontainersNamespace)
    }

    @Test func labelSessionIdHasCorrectValue() {
        #expect(labelSessionId == "org.testcontainers.session-id")
    }

    @Test func labelVersionHasCorrectValue() {
        #expect(labelVersion == "org.testcontainers.version")
    }

    @Test func labelLangHasCorrectValue() {
        #expect(labelLang == "org.testcontainers.lang")
    }
}
