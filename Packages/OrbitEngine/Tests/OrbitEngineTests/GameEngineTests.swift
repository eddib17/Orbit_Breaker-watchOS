import Foundation
import Testing
@testable import OrbitEngine

@Suite struct GameEngineTests {
    /// No bricks, so nothing but the paddle gets in the ball's way.
    let open = level(rings: [])

    // MARK: Math

    @Test func wrapAngleStaysInRange() {
        #expect(abs(wrapAngle(3 * .pi) - -.pi) < 1e-5)
        #expect(abs(wrapAngle(-3 * .pi / 2) - .pi / 2) < 1e-5)
        #expect(abs(wrapAngle(0.5)) - 0.5 < 1e-6)
        for a in stride(from: Float(-20), through: 20, by: 0.37) {
            let w = wrapAngle(a)
            #expect(w >= -.pi && w < .pi)
        }
    }

    @Test func angleDeltaTakesTheShortWay() {
        #expect(abs(degrees(angleDelta(10 * deg, 350 * deg)) - -20) < 1e-3)
        #expect(abs(degrees(angleDelta(350 * deg, 10 * deg)) - 20) < 1e-3)
    }

    @Test func predictedExitAngleFollowsAStraightLine() {
        let ball = Ball(x: 0, y: 0, vx: 1, vy: 1, stuck: false)
        #expect(abs(degrees(predictedExitAngle(ball)) - 45) < 1e-3)
    }

    // MARK: Countdown & launch

    @Test func countdownTicksThenLaunches() {
        let game = engine(open)
        #expect(game.state.phase == .countdown)
        #expect(game.state.balls[0].stuck)
        let events = game.run(seconds: 3.1)
        let ticks = events.compactMap { if case .countdownTick(let n) = $0 { n } else { nil } }
        #expect(ticks == [3, 2, 1])
        #expect(events.count { $0 == .launched } == 1)
        #expect(game.state.phase == .playing)
        #expect(!game.state.balls[0].stuck)
    }

    @Test func launchSkipsTheCountdownAndAimsInward() {
        let game = engine(open)
        game.launch()
        #expect(game.state.phase == .playing)
        let ball = game.state.balls[0]
        #expect(abs(norm(ball.vx, ball.vy) - game.state.ballSpeed) < 1e-4)
        // The paddle is at the bottom, so the ball leaves upward within ±10°.
        let heading = degrees(atan2(ball.vy, ball.vx))
        #expect(abs(heading - -90) <= 10.01)
    }

    @Test func stuckBallFollowsThePaddleDuringCountdown() {
        let game = engine(open)
        game.aimPaddle(0)
        game.run(seconds: 0.5)
        let ball = game.state.balls[0]
        #expect(abs(degrees(atan2(ball.y, ball.x))) < 1)
    }

    // MARK: Paddle

    @Test func aimPaddleTakesTheShortestWay() {
        let game = engine(open)
        game.aimPaddle(90 * deg + 350 * deg)
        #expect(abs(degrees(game.state.paddle.target) - 80) < 1e-3)
        game.nudgePaddle(-10 * deg)
        #expect(abs(degrees(game.state.paddle.target) - 70) < 1e-3)
    }

    @Test func paddleEasesTowardTarget() {
        let game = engine(open)
        game.aimPaddle(0)
        game.run(seconds: 0.25)
        #expect(abs(degrees(game.state.paddle.angle)) < 0.5)
    }

    @Test func centerHitBouncesStraightBack() throws {
        let game = engine(open)
        let speed = game.state.ballSpeed
        game.place(x: 0, y: 0.7, vx: 0, vy: speed)
        let events = game.run(seconds: 0.3)
        let offset = try #require(events.compactMap { if case .paddleHit(let o) = $0 { o } else { nil } }.first)
        #expect(abs(offset) < 0.01)
        let ball = game.state.balls[0]
        #expect(ball.vy < 0)
        #expect(abs(ball.vx) < 0.01)
    }

    @Test(arguments: [Float(-0.8), -0.4, 0.4, 0.8])
    func edgeHitAddsEnglish(offset: Float) throws {
        let game = engine(open)
        let p = game.state.paddle
        let a = p.angle + offset * p.halfArc
        let speed = game.state.ballSpeed
        game.place(x: cos(a) * 0.75, y: sin(a) * 0.75, vx: cos(a) * speed, vy: sin(a) * speed)
        let events = game.run(seconds: 0.25)
        let hit = try #require(events.compactMap { if case .paddleHit(let o) = $0 { o } else { nil } }.first)
        #expect(abs(hit - offset) < 0.02)

        let ball = game.state.balls[0]
        let inward = (x: -cos(a), y: -sin(a))
        let tangent = (x: -sin(a), y: cos(a))
        let v = (x: ball.vx / norm(ball.vx, ball.vy), y: ball.vy / norm(ball.vx, ball.vy))
        let deflection = degrees(acos((v.x * inward.x + v.y * inward.y).clamped(-1, 1)))
        #expect(abs(deflection - abs(offset) * Arena.maxDeflectDeg) < 1.5)
        // Hitting one side sends the ball toward that side.
        #expect((v.x * tangent.x + v.y * tangent.y > 0) == (offset > 0))
    }

    @Test func deflectionNeverExceedsTheAbsoluteCap() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<200 {
            let game = engine(open)
            let p = game.state.paddle
            let a = p.angle + (rng.nextFloat() * 2.4 - 1.2) * p.halfArc
            // A fast-moving paddle adds spin on top of the edge english.
            game.nudgePaddle((rng.nextFloat() - 0.5) * 2)
            let speed = game.state.ballSpeed
            game.place(x: cos(a) * 0.8, y: sin(a) * 0.8, vx: cos(a) * speed, vy: sin(a) * speed)
            for _ in 0..<30 {
                let events = game.update(frameSeconds: 1 / 60)
                guard events.contains(where: { if case .paddleHit = $0 { true } else { false } }) else { continue }
                let ball = game.state.balls[0]
                let d = norm(ball.x, ball.y)
                let cosine = -(ball.x * ball.vx + ball.y * ball.vy) / (d * norm(ball.vx, ball.vy))
                #expect(degrees(acos(cosine.clamped(-1, 1))) <= Arena.absoluteMaxDeflectDeg + 0.1)
                break
            }
        }
    }

    @Test func paddleHitsRampSpeedUpToTheCap() {
        let game = engine(open)
        game.state.speed = game.state.baseSpeed * 1.59
        game.place(x: 0, y: 0.7, vx: 0, vy: 1)
        game.run(seconds: 0.3)
        #expect(abs(game.state.speed - game.state.baseSpeed * Arena.maxSpeedFactor) < 1e-5)
        #expect(abs(norm(game.state.balls[0].vx, game.state.balls[0].vy) - game.state.ballSpeed) < 1e-4)
    }

    // MARK: Losing balls

    @Test func missingTheBallCostsALifeAndRestartsTheCountdown() {
        let game = engine(open)
        game.snapPaddle(to: -90 * deg)
        game.place(x: 0, y: 0.8, vx: 0, vy: 1)
        let events = game.run(seconds: 0.4)
        #expect(events.contains(.ballLost(livesLeft: 2)))
        #expect(game.state.lives == 2)
        #expect(game.state.livesLost == 1)
        #expect(game.state.phase == .countdown)
        #expect(game.state.balls.count == 1 && game.state.balls[0].stuck)
    }

    @Test func losingTheLastLifeEndsTheGame() {
        let game = engine(open)
        var events: [GameEvent] = []
        for _ in 0..<Arena.startingLives {
            game.snapPaddle(to: -90 * deg)
            game.place(x: 0, y: 0.8, vx: 0, vy: 1)
            events += game.run(seconds: 0.4)
        }
        #expect(events.last == .gameOver)
        #expect(game.state.phase == .gameOver)
        #expect(game.run(seconds: 1).isEmpty)
    }

    @Test func droppingOneOfSeveralBallsIsFree() {
        let game = engine(open)
        game.snapPaddle(to: -90 * deg)
        game.place(x: 0, y: 0.8, vx: 0, vy: 1)
        game.state.balls.append(Ball(x: 0, y: 0, vx: 0, vy: 0, stuck: false))
        let events = game.run(seconds: 0.4)
        #expect(events.contains(.ballDropped))
        #expect(!events.contains { if case .ballLost = $0 { true } else { false } })
        #expect(game.state.lives == Arena.startingLives)
        #expect(game.state.balls.count == 1)
    }

    @Test func missWarningFiresWhenThePaddleIsElsewhere() {
        let game = engine(open)
        game.snapPaddle(to: -90 * deg)
        game.place(x: 0, y: 0.3, vx: 0, vy: game.state.ballSpeed)
        let events = game.run(seconds: 1)
        #expect(events.count { $0 == .missWarning } == 1)

        let covered = engine(open)
        covered.place(x: 0, y: 0.3, vx: 0, vy: covered.state.ballSpeed)
        #expect(!covered.run(seconds: 0.6).contains(.missWarning))
    }

    // MARK: Tunneling & stalls

    /// A ball inside a closed ring of unbreakable bricks must never escape, even at top speed and
    /// with long, uneven frames.
    @Test func ballCannotTunnelThroughBricksAtMaxSpeed() {
        let cage = level(rings: [RingDef(radius: 0.3, sectors: 10, bricks: "XXXXXXXXXX")]) { $0.ballSpeed = 2 }
        for seed in UInt64(1)...5 {
            let game = engine(cage, seed: seed)
            game.state.speed = game.state.baseSpeed * Arena.maxSpeedFactor
            var rng = SplitMix64(seed: seed)
            let a = rng.nextFloat() * 2 * .pi
            game.place(x: 0, y: 0, vx: cos(a), vy: sin(a))
            for frame in 0..<600 {
                _ = game.update(frameSeconds: frame % 7 == 0 ? 0.1 : 1 / 30)
                let ball = game.state.balls[0]
                #expect(norm(ball.x, ball.y) < game.state.rings[0].inner)
            }
        }
    }

    @Test func stallNudgeFiresAfterEightSecondsWithoutABrick() {
        let cage = level(rings: [RingDef(radius: 0.3, sectors: 10, bricks: "XXXXXXXXXX")])
        let game = engine(cage)
        game.place(x: 0, y: 0, vx: 0.6, vy: 0.2)
        #expect(!game.run(seconds: 7.9).contains(.stallNudge))
        #expect(game.run(seconds: 0.2).contains(.stallNudge))
        #expect(game.state.stallNudgePending)
    }

    // MARK: Scoring & stars

    @Test func clearingTheLastBrickClearsTheLevel() {
        let single = level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "A...")]) { $0.parSeconds = 60 }
        let game = engine(single)
        let events = game.hitBrick(ring: 0, index: 0)
        #expect(game.state.phase == .cleared)
        #expect(game.state.stars == 3)
        // 10 for the brick, 100 per remaining life.
        #expect(game.state.score == 10 + 3 * 100)
        #expect(events.contains(.levelCleared(stars: 3, score: 310)))
    }

    @Test func starsDropForLostLivesAndSlowClears() {
        let single = level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "A...")]) { $0.parSeconds = 10 }
        let game = engine(single)
        game.state.livesLost = 1
        game.state.elapsed = 11
        game.hitBrick(ring: 0, index: 0)
        #expect(game.state.stars == 1)
    }

    @Test func comboMultipliesScoreAndHitsMilestones() {
        let game = engine(level())
        game.state.combo = 4
        let events = game.hitBrick(ring: 0, index: 0)
        #expect(events.contains(.comboMilestone(tier: 1, combo: 5)))
        // 10 × (1 + 5 / 5)
        #expect(game.state.score == 20)
    }

    @Test func paddleHitResetsCombo() {
        let game = engine(open)
        game.state.combo = 7
        game.place(x: 0, y: 0.7, vx: 0, vy: 1)
        game.run(seconds: 0.3)
        #expect(game.state.combo == 0)
    }

    // MARK: Determinism

    @Test func sameSeedSameGame() throws {
        let def = try #require(try LevelLoader.load(36))
        func play() -> ([GameEvent], Int) {
            let game = engine(def, seed: 9)
            let bot = Autopilot(rng: SplitMix64(seed: 10))
            var all: [GameEvent] = []
            for _ in 0..<(60 * 40) {
                bot.steer(game)
                let events = game.update(frameSeconds: 1 / 60)
                bot.onEvents(game, events)
                all += events
            }
            return (all, game.state.score)
        }
        let first = play()
        let second = play()
        #expect(first.0 == second.0)
        #expect(first.1 == second.1)
    }
}
