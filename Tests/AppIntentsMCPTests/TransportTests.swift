import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Transport Tests")
struct TransportTests {

    @Test("Can frame message with Content-Length header")
    func frameMessage() {
        let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\"}"
        let framed = StdioTransport.frame(body)

        #expect(framed.hasPrefix("Content-Length: \(body.utf8.count)\r\n\r\n"))
        #expect(framed.hasSuffix(body))
    }
}
