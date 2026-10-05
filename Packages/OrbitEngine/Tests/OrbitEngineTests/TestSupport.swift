import Foundation
@testable import OrbitEngine

func level(
    rings: [RingDef] = [RingDef(radius: 0.4, sectors: 12, bricks: "AAAAAAAAAAAA")],
    cores: [CoreDef] = [],
    configure: (inout LevelDef) -> Void = { _ in }
) -> LevelDef {
    var def = LevelDef(id: 999, name: "Test", world: 1, rings: rings, cores: cores)
    configure(&def)
    return def
}

func engine(_ level: LevelDef, seed: UInt64 = 1) -> GameEngine {
    GameEngine(level: level, rng: SplitMix64(seed: seed))
}

extension GameEngine {
    /// Skips the countdown and puts the first ball at a given spot and velocity.
    func place(x: Float, y: Float, vx: Float, vy: Float) {
        state.phase = .playing
        let ball = state.balls[0]
        ball.stuck = false
        ball.x = x
        ball.y = y
        ball.vx = vx
        ball.vy = vy
    }

    /// Runs `seconds` of game time at 60 fps and returns every event.
    @discardableResult
    func run(seconds: Float, fps: Float = 60, steer: (() -> Void)? = nil) -> [GameEvent] {
        var all: [GameEvent] = []
        for _ in 0..<Int(seconds * fps) {
            steer?()
            all += update(frameSeconds: 1 / fps)
        }
        return all
    }

    /// Points the paddle at an angle and lets it settle there immediately.
    func snapPaddle(to angle: Float) {
        state.paddle.target = angle
        state.paddle.angle = angle
    }
}

extension Array where Element == GameEvent {
    func count(where predicate: (GameEvent) -> Bool) -> Int { filter(predicate).count }
}

extension GameEngine {
    /// Fires the ball straight outward at a brick from just inside its ring, runs until something
    /// happens to the brick, then parks the ball motionless at the center.
    @discardableResult
    func hitBrick(ring ri: Int, index bi: Int) -> [GameEvent] {
        let ring = state.rings[ri]
        let a = ring.midAngle(bi)
        let r = ring.inner - Arena.ballRadius - 0.03
        let speed = state.ballSpeed
        place(x: cos(a) * r, y: sin(a) * r, vx: cos(a) * speed, vy: sin(a) * speed)
        var all: [GameEvent] = []
        for _ in 0..<60 {
            let events = update(frameSeconds: 1 / 60)
            all += events
            if events.contains(where: \.touchesBrick) { break }
        }
        park()
        return all
    }

    /// Stops the first ball at the center so it can't touch anything.
    func park() {
        let ball = state.balls[0]
        ball.x = 0
        ball.y = 0
        ball.vx = 0
        ball.vy = 0
    }

    /// Drops a power-up just inside the paddle so it is caught on the next frames.
    @discardableResult
    func give(_ type: PowerUpType) -> [GameEvent] {
        let a = state.paddle.angle
        state.powerUps.append(FallingPowerUp(type: type, x: cos(a) * 0.8, y: sin(a) * 0.8))
        return run(seconds: 0.3)
    }
}

extension GameEvent {
    var touchesBrick: Bool {
        switch self {
        case .brickDamaged, .brickDestroyed, .unbreakableHit, .ghostRevealed, .warped: true
        default: false
        }
    }
}

func degrees(_ radians: Float) -> Float { radians * 180 / .pi }
