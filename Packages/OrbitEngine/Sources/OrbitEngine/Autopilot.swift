/// A simple player: steers the paddle to where the ball will cross the paddle ring, with a random
/// aim offset after each hit so it doesn't bounce straight through the center forever.
/// Used by tests to prove levels are winnable and by the How to Play demo.
public final class Autopilot {
    private var rng: any RandomNumberGenerator
    private var aimOffset: Float = 0

    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    /// Call before each `GameEngine.update(frameSeconds:)`.
    public func steer(_ engine: GameEngine) {
        let balls = engine.state.balls
        guard let ball = balls.first(where: { !$0.stuck && $0.x * $0.vx + $0.y * $0.vy > 0 })
            ?? balls.first(where: { !$0.stuck })
        else { return }
        engine.aimPaddle(predictedExitAngle(ball) + aimOffset)
    }

    /// Call with the events from each `GameEngine.update(frameSeconds:)`.
    public func onEvents(_ engine: GameEngine, _ events: [GameEvent]) {
        if events.contains(where: { if case .paddleHit = $0 { true } else { false } }) {
            aimOffset = (rng.nextFloat() - 0.5) * engine.state.paddle.halfArc
        }
    }
}
