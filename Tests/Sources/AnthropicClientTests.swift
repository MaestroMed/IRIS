import Testing
@testable import IRIS
import Foundation

struct AnthropicClientTests {

    @Test func costEstimationOpus() {
        let usage = MessageResponse.Usage(
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil
        )
        let cost = usage.estimatedCostUSD(model: .opus47)
        // 1M input × $15 + 100k output × $75 = $15 + $7.5 = $22.5
        #expect(abs(cost - 22.5) < 0.01)
    }

    @Test func costEstimationWithPromptCache() {
        let usage = MessageResponse.Usage(
            inputTokens: 1_000_000,
            outputTokens: 50_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 900_000  // 90% des inputs sont en cache hit
        )
        let cost = usage.estimatedCostUSD(model: .opus47)
        // regularInput = 100k, cacheRead = 900k
        // = (100k × $15 + 900k × $1.5 + 50k × $75) / 1M
        // = $1.5 + $1.35 + $3.75 = $6.6
        #expect(abs(cost - 6.6) < 0.05)
    }

    @Test func missingAPIKeyThrows() async {
        // Clean keychain pour s'assurer qu'il n'y a pas de clé
        _ = IRISKeychain.shared.deleteAnthropicAPIKey()

        await #expect(throws: AnthropicError.self) {
            _ = try await AnthropicClient.shared.ask("hello", model: .haiku45)
        }
    }

    @Test func keychainRoundtrip() {
        let testKey = "sk-ant-test-\(UUID().uuidString)"
        let ok = IRISKeychain.shared.setAnthropicAPIKey(testKey)
        #expect(ok)
        let retrieved = IRISKeychain.shared.getAnthropicAPIKey()
        #expect(retrieved == testKey)
        _ = IRISKeychain.shared.deleteAnthropicAPIKey()
        #expect(IRISKeychain.shared.getAnthropicAPIKey() == nil)
    }
}
