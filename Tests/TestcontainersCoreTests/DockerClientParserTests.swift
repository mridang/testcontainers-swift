import Foundation
import Testing

@testable import TestcontainersCore

// MARK: - Helpers

/// Build a Docker multiplexed log frame.
/// stream: 1=stdout, 2=stderr, 0=stdin
private func makeLogFrame(stream: UInt8, payload: Data) -> Data {
    var frame = Data(count: 8)
    frame[0] = stream
    frame[1] = 0; frame[2] = 0; frame[3] = 0
    let size = UInt32(payload.count)
    frame[4] = UInt8((size >> 24) & 0xFF)
    frame[5] = UInt8((size >> 16) & 0xFF)
    frame[6] = UInt8((size >> 8) & 0xFF)
    frame[7] = UInt8(size & 0xFF)
    return frame + payload
}

/// Encode data in HTTP chunked-transfer format.
private func chunked(_ chunks: [Data]) -> Data {
    var result = Data()
    for chunk in chunks {
        let sizeLine = String(format: "%X\r\n", chunk.count)
        result.append(Data(sizeLine.utf8))
        result.append(chunk)
        result.append(Data("\r\n".utf8))
    }
    result.append(Data("0\r\n\r\n".utf8))
    return result
}

/// Build a raw HTTP/1.0 response string.
private func httpResponse(
    status: Int = 200,
    headers: [(String, String)] = [],
    body: String = "",
    chunked: Bool = false
) -> Data {
    var lines = ["HTTP/1.0 \(status) \(statusText(status))"]
    if chunked {
        lines.append("Transfer-Encoding: chunked")
    } else if !body.isEmpty {
        lines.append("Content-Length: \(body.utf8.count)")
    }
    for (k, v) in headers { lines.append("\(k): \(v)") }
    lines.append(""); lines.append("")
    let header = lines.joined(separator: "\r\n")
    if chunked {
        let bodyChunked = makeChunkedBody(body)
        return Data(header.utf8) + bodyChunked
    }
    return Data(header.utf8) + Data(body.utf8)
}

private func makeChunkedBody(_ body: String) -> Data {
    let payload = Data(body.utf8)
    var result = Data()
    result.append(Data("\(String(format: "%X", payload.count))\r\n".utf8))
    result.append(payload)
    result.append(Data("\r\n0\r\n\r\n".utf8))
    return result
}

private func statusText(_ code: Int) -> String {
    switch code {
    case 200: return "OK"
    case 201: return "Created"
    case 204: return "No Content"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 500: return "Internal Server Error"
    default: return "Unknown"
    }
}

// MARK: - decodeChunked

@Suite("DockerClient.decodeChunked")
struct DecodeChunkedTests {
    let client = DockerClient.testOnly()

    @Test func decodeSingleChunk() {
        let payload = Data("hello world".utf8)
        let input = chunked([payload])
        let result = client.decodeChunked(input)
        #expect(String(data: result, encoding: .utf8) == "hello world")
    }

    @Test func decodeMultipleChunks() {
        let chunks = [Data("foo".utf8), Data("bar".utf8), Data("baz".utf8)]
        let input = chunked(chunks)
        let result = client.decodeChunked(input)
        #expect(String(data: result, encoding: .utf8) == "foobarbaz")
    }

    @Test func decodeEmptyInput() {
        let result = client.decodeChunked(Data())
        #expect(result.isEmpty)
    }

    @Test func decodeTerminatorOnly() {
        // "0\r\n\r\n" — chunk of size 0
        let input = Data("0\r\n\r\n".utf8)
        let result = client.decodeChunked(input)
        #expect(result.isEmpty)
    }

    @Test func decodeTruncatedInput() {
        // Chunk header says 10 bytes but only 3 available
        let input = Data("A\r\nhel".utf8)  // A hex = 10, but only "hel"
        let result = client.decodeChunked(input)
        // Truncated — should return empty (graceful no-op)
        #expect(result.isEmpty)
    }

    @Test func decodeMalformedSizeLine() {
        // Non-hex size
        let input = Data("xyz\r\nhello world\r\n0\r\n\r\n".utf8)
        let result = client.decodeChunked(input)
        // Int("xyz", radix:16) returns nil → size = 0 → terminates
        #expect(result.isEmpty)
    }

    @Test func decodeLargePayload() {
        let payload = Data(repeating: 0x41, count: 1000)
        let input = chunked([payload])
        let result = client.decodeChunked(input)
        #expect(result.count == 1000)
        #expect(result == payload)
    }
}

// MARK: - stripDockerLogHeaders

@Suite("DockerClient.stripDockerLogHeaders")
struct StripDockerLogHeadersTests {
    let client = DockerClient.testOnly()

    @Test func stripsStdoutFrame() {
        let payload = Data("hello stdout\n".utf8)
        let frame = makeLogFrame(stream: 1, payload: payload)
        let result = client.stripDockerLogHeaders(frame)
        #expect(result == payload)
    }

    @Test func stripsStderrFrame() {
        let payload = Data("error output\n".utf8)
        let frame = makeLogFrame(stream: 2, payload: payload)
        let result = client.stripDockerLogHeaders(frame)
        #expect(result == payload)
    }

    @Test func stripsMultipleFrames() {
        let p1 = Data("first\n".utf8)
        let p2 = Data("second\n".utf8)
        let frames = makeLogFrame(stream: 1, payload: p1) + makeLogFrame(stream: 1, payload: p2)
        let result = client.stripDockerLogHeaders(frames)
        #expect(result == p1 + p2)
    }

    @Test func stripsStdinFrame() {
        let payload = Data("stdin data".utf8)
        let frame = makeLogFrame(stream: 0, payload: payload)
        let result = client.stripDockerLogHeaders(frame)
        #expect(result == payload)
    }

    @Test func emptyInputReturnsEmpty() {
        let result = client.stripDockerLogHeaders(Data())
        #expect(result.isEmpty)
    }

    @Test func truncatedFrameReturnsOriginalAsTtyFallback() {
        // Fewer than 8 bytes — TTY fallback: return data as-is
        let input = Data([0x01, 0x00, 0x00])
        let result = client.stripDockerLogHeaders(input)
        #expect(result == input)
    }

    @Test func zeroBytePayloadFrame() {
        let frame = makeLogFrame(stream: 1, payload: Data())
        let result = client.stripDockerLogHeaders(frame)
        // Zero-payload frame → result is empty, so TTY fallback returns original
        #expect(result == frame || result.isEmpty)
    }

    @Test func mixedStdoutAndStderrFrames() {
        let out = Data("out\n".utf8)
        let err = Data("err\n".utf8)
        let frames = makeLogFrame(stream: 1, payload: out) + makeLogFrame(stream: 2, payload: err)
        let result = client.stripDockerLogHeaders(frames)
        #expect(result == out + err)
    }
}

// MARK: - parseHttpResponse

@Suite("DockerClient.parseHttpResponse")
struct ParseHttpResponseTests {
    let client = DockerClient.testOnly()

    @Test func parses200() {
        let raw = httpResponse(status: 200, body: "ok")
        let (code, _, body) = client.parseHttpResponse(raw)
        #expect(code == 200)
        #expect(String(data: body, encoding: .utf8) == "ok")
    }

    @Test func parses201() {
        let raw = httpResponse(status: 201, body: "{\"Id\":\"abc\"}")
        let (code, _, body) = client.parseHttpResponse(raw)
        #expect(code == 201)
        #expect(!body.isEmpty)
    }

    @Test func parses204NoContent() {
        let raw = httpResponse(status: 204, body: "")
        let (code, _, _) = client.parseHttpResponse(raw)
        #expect(code == 204)
    }

    @Test func parses404() {
        let raw = httpResponse(status: 404, body: "not found")
        let (code, _, _) = client.parseHttpResponse(raw)
        #expect(code == 404)
    }

    @Test func parses500() {
        let raw = httpResponse(status: 500, body: "error")
        let (code, _, _) = client.parseHttpResponse(raw)
        #expect(code == 500)
    }

    @Test func headersAreLowercased() {
        let raw = httpResponse(status: 200, headers: [("Content-Type", "application/json")], body: "x")
        let (_, headers, _) = client.parseHttpResponse(raw)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["Content-Type"] == nil)
    }

    @Test func multipleHeadersParsedCorrectly() {
        let raw = httpResponse(
            status: 200,
            headers: [("X-Foo", "bar"), ("X-Baz", "qux")],
            body: "hello"
        )
        let (_, headers, _) = client.parseHttpResponse(raw)
        #expect(headers["x-foo"] == "bar")
        #expect(headers["x-baz"] == "qux")
    }

    @Test func malformedResponseReturns500() {
        let raw = Data("not http at all".utf8)
        let (code, _, _) = client.parseHttpResponse(raw)
        #expect(code == 500)
    }

    @Test func emptyInputReturns500() {
        let (code, _, _) = client.parseHttpResponse(Data())
        #expect(code == 500)
    }

    @Test func nonChunkedBodyPassedThrough() {
        let raw = httpResponse(status: 200, body: "plain body")
        let (_, _, body) = client.parseHttpResponse(raw)
        #expect(String(data: body, encoding: .utf8) == "plain body")
    }

    @Test func transferEncodingChunkedHeaderIsDetected() {
        // Verify that the "transfer-encoding: chunked" header is parsed correctly —
        // decodeChunked() itself is verified in DecodeChunkedTests.
        let raw = httpResponse(status: 200, body: "x", chunked: true)
        let (code, headers, _) = client.parseHttpResponse(raw)
        #expect(code == 200)
        #expect(headers["transfer-encoding"] == "chunked")
    }

    @Test func colonInHeaderValuePreserved() {
        let raw = httpResponse(
            status: 200,
            headers: [("X-Custom", "value:with:colons")],
            body: "x"
        )
        let (_, headers, _) = client.parseHttpResponse(raw)
        #expect(headers["x-custom"] == "value:with:colons")
    }
}
