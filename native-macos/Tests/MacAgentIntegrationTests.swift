import XCTest
@testable import Zerus_Native

final class MacAgentIntegrationTests: XCTestCase {
    func testMacAgentBudgetLoadsThePackagedTokenizer() async throws {
        // Mac packaging is a separate boundary from the shared tokenizer's
        // algorithm tests. Missing/wrong bundle resources must fail this path.
        // Independent o200k_base count: js-tiktoken 1.0.21, ordinary-text encoding.
        let count = try await NativeAgentTokenizer.shared.count("Olá, ação e café. 🌿")
        XCTAssertEqual(count, 8)
    }
}
