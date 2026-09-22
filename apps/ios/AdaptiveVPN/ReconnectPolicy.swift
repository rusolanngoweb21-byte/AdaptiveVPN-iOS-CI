import Foundation

struct ReconnectPolicy: Equatable {
    let initialDelayMs: Double
    let maxDelayMs: Double
    let multiplier: Double
    let jitterRatio: Double

    init(
        initialDelayMs: Double = 500,
        maxDelayMs: Double = 30_000,
        multiplier: Double = 2,
        jitterRatio: Double = 0.2
    ) {
        precondition(initialDelayMs > 0)
        precondition(maxDelayMs >= initialDelayMs)
        precondition(multiplier >= 1)
        precondition((0...1).contains(jitterRatio))
        self.initialDelayMs = initialDelayMs
        self.maxDelayMs = maxDelayMs
        self.multiplier = multiplier
        self.jitterRatio = jitterRatio
    }

    func delayForAttempt(_ attempt: Int, randomUnit: Double = Double.random(in: 0...1)) -> TimeInterval {
        precondition(attempt >= 0)
        precondition((0...1).contains(randomUnit))
        let exponential = initialDelayMs * pow(multiplier, Double(attempt))
        let capped = min(exponential, maxDelayMs)
        let jitter = capped * jitterRatio
        let factor = randomUnit * 2 - 1
        return max(0, capped + jitter * factor) / 1_000
    }
}
