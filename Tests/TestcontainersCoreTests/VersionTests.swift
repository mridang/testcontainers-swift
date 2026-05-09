import Testing

@testable import TestcontainersCore

@Suite("ComparableVersion")
struct VersionTests {
    @Test func parsesValidVersion() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(v.major == 1)
        #expect(v.minor == 2)
        #expect(v.patch == 3)
    }

    @Test func descriptionIsOriginalString() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(v.description == "1.2.3")
    }

    @Test func throwsOnInvalidFormat() {
        #expect(throws: (any Error).self) { _ = try ComparableVersion("1.2") }
        #expect(throws: (any Error).self) { _ = try ComparableVersion("not.a.version") }
        #expect(throws: (any Error).self) { _ = try ComparableVersion("") }
        #expect(throws: (any Error).self) { _ = try ComparableVersion("1.2.3.4") }
    }

    @Test func equalVersions() throws {
        let a = try ComparableVersion("1.2.3")
        let b = try ComparableVersion("1.2.3")
        #expect(a == b)
    }

    @Test func lessThanMajor() throws {
        let a = try ComparableVersion("1.0.0")
        let b = try ComparableVersion("2.0.0")
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test func lessThanMinor() throws {
        let a = try ComparableVersion("1.1.0")
        let b = try ComparableVersion("1.2.0")
        #expect(a < b)
    }

    @Test func lessThanPatch() throws {
        let a = try ComparableVersion("1.2.3")
        let b = try ComparableVersion("1.2.4")
        #expect(a < b)
    }

    @Test func greaterThan() throws {
        let a = try ComparableVersion("2.0.0")
        let b = try ComparableVersion("1.9.9")
        #expect(a > b)
    }

    @Test func lessThanOrEqual() throws {
        let a = try ComparableVersion("1.2.3")
        let b = try ComparableVersion("1.2.3")
        let c = try ComparableVersion("1.2.4")
        #expect(a <= b)
        #expect(a <= c)
    }

    @Test func greaterThanOrEqual() throws {
        let a = try ComparableVersion("1.2.3")
        let b = try ComparableVersion("1.2.3")
        let c = try ComparableVersion("1.2.2")
        #expect(a >= b)
        #expect(a >= c)
    }

    @Test func notEqual() throws {
        let a = try ComparableVersion("1.2.3")
        let b = try ComparableVersion("1.2.4")
        #expect(a != b)
    }

    @Test func sortable() throws {
        var versions = [
            try ComparableVersion("2.0.0"),
            try ComparableVersion("1.0.0"),
            try ComparableVersion("1.2.3"),
            try ComparableVersion("1.2.1"),
        ]
        versions.sort()
        #expect(versions[0].description == "1.0.0")
        #expect(versions[1].description == "1.2.1")
        #expect(versions[2].description == "1.2.3")
        #expect(versions[3].description == "2.0.0")
    }

    @Test func zeroVersionParsesCorrectly() throws {
        let v = try ComparableVersion("0.0.0")
        #expect(v.major == 0)
        #expect(v.minor == 0)
        #expect(v.patch == 0)
    }

    @Test func largeVersionNumbers() throws {
        let v = try ComparableVersion("100.200.300")
        #expect(v.major == 100)
        #expect(v.minor == 200)
        #expect(v.patch == 300)
    }

    @Test func compareToNegativeForLess() throws {
        let a = try ComparableVersion("1.0.0")
        let b = try ComparableVersion("2.0.0")
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test func compareToZeroForEqual() throws {
        let a = try ComparableVersion("1.2.3")
        let b = try ComparableVersion("1.2.3")
        #expect(!(a < b))
        #expect(!(b < a))
    }

    @Test func compareToPositiveForGreater() throws {
        let a = try ComparableVersion("2.0.0")
        let b = try ComparableVersion("1.9.9")
        #expect(a > b)
    }

    @Test func throwsFormatExceptionWithDoubleDot() {
        #expect(throws: (any Error).self) { _ = try ComparableVersion("1..3") }
    }

    @Test func throwsFormatExceptionForAlphaComponent() {
        #expect(throws: (any Error).self) { _ = try ComparableVersion("a.b.c") }
    }

    @Test func zeroVersionEqualsItself() throws {
        let a = try ComparableVersion("0.0.0")
        let b = try ComparableVersion("0.0.0")
        #expect(a == b)
    }

    @Test func zeroVersionLessThanNonZero() throws {
        let zero = try ComparableVersion("0.0.0")
        let one = try ComparableVersion("0.0.1")
        #expect(zero < one)
    }

    @Test func stringOperatorEqualToMatchingVersion() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(v == "1.2.3")
    }

    @Test func stringOperatorLessThanWithHigherString() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(v < "1.2.4")
    }

    @Test func stringOperatorLessThanOrEqualWithSameString() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(v <= "1.2.3")
    }

    @Test func stringOperatorGreaterThanWithLowerString() throws {
        let v = try ComparableVersion("2.0.0")
        #expect(v > "1.9.9")
    }

    @Test func stringOperatorGreaterThanOrEqualWithSameString() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(v >= "1.2.3")
    }

    @Test func invalidStringInEqualOperatorReturnsFalse() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(!(v == "not-a-version"))
    }

    @Test func invalidStringInLessOperatorReturnsFalse() throws {
        let v = try ComparableVersion("1.2.3")
        #expect(!(v < "not-a-version"))
    }
}
