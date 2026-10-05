import Foundation
import Testing
@testable import OrbitEngine

@Suite struct MechanicsTests {

    // MARK: Brick types

    @Test func toughAndArmoredTakeSeveralHits() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "BCAA")]))
        #expect(game.hitBrick(ring: 0, index: 0).contains(.brickDamaged(ring: 0, index: 0, hpLeft: 1)))
        #expect(game.hitBrick(ring: 0, index: 0).contains { if case .brickDestroyed(0, 0, .tough, _, _) = $0 { true } else { false } })
        game.hitBrick(ring: 0, index: 1)
        game.hitBrick(ring: 0, index: 1)
        #expect(game.state.rings[0].bricks[1]!.hp == 1)
        game.hitBrick(ring: 0, index: 1)
        #expect(!game.state.rings[0].bricks[1]!.alive)
    }

    @Test func unbreakableBricksBounceTheBall() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "XAAA")]))
        let events = game.hitBrick(ring: 0, index: 0)
        #expect(events.contains(.unbreakableHit))
        #expect(game.state.rings[0].bricks[0]!.alive)
    }

    @Test func explosionsChainThroughExplosiveNeighbours() {
        let rings = [
            RingDef(radius: 0.3, sectors: 12, bricks: "AEEAXAAAAAAA"),
            RingDef(radius: 0.6, sectors: 12, bricks: "AAAAAAAAAAAA"),
        ]
        let game = engine(level(rings: rings))
        let events = game.hitBrick(ring: 0, index: 1)
        let inner = game.state.rings[0].bricks.map { $0!.alive }
        #expect(inner == [false, false, false, false, true, true, true, true, true, true, true, true])
        #expect(events.count { if case .explosion = $0 { true } else { false } } == 2)
        // The outer ring is too far away to be caught in the blast.
        #expect(game.state.rings[1].bricks.allSatisfy { $0!.alive })
    }

    @Test func explosionsReachTheNextRing() {
        let rings = [
            RingDef(radius: 0.3, sectors: 12, bricks: "E..........."),
            RingDef(radius: 0.4, sectors: 12, bricks: "AAAAAAAAAAAA"),
        ]
        let game = engine(level(rings: rings))
        game.hitBrick(ring: 0, index: 0)
        #expect(!game.state.rings[1].bricks[0]!.alive)
        #expect(game.state.rings[1].bricks[6]!.alive)
    }

    @Test func carriersAlwaysDropAPowerUp() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "PAAA")]) { $0.powerUps = [.laser] })
        let events = game.hitBrick(ring: 0, index: 0)
        #expect(events.contains(.powerUpSpawned(.laser)))
        #expect(game.state.powerUps.count == 1)
    }

    @Test func regenBricksGrowBack() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "RAAA")]) { $0.regenSeconds = 1 })
        game.hitBrick(ring: 0, index: 0)
        #expect(!game.state.rings[0].bricks[0]!.alive)
        #expect(game.run(seconds: 1.1).contains(.brickRegenerated(ring: 0, index: 0)))
        #expect(game.state.rings[0].bricks[0]!.alive)
    }

    @Test func regenBricksStayDownOnceTheirRingIsClear() {
        let rings = [
            RingDef(radius: 0.3, sectors: 4, bricks: "R..."),
            RingDef(radius: 0.6, sectors: 4, bricks: "AAAA"),
        ]
        let game = engine(level(rings: rings) { $0.regenSeconds = 1 })
        game.hitBrick(ring: 0, index: 0)
        #expect(!game.run(seconds: 1.5).contains { if case .brickRegenerated = $0 { true } else { false } })
        #expect(!game.state.rings[0].bricks[0]!.alive)
    }

    @Test func ghostsRevealThenBreak() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "GAAA")]))
        #expect(!game.state.rings[0].bricks[0]!.revealed)
        #expect(game.hitBrick(ring: 0, index: 0).contains(.ghostRevealed(ring: 0, index: 0)))
        #expect(game.state.rings[0].bricks[0]!.revealed)
        #expect(game.state.rings[0].bricks[0]!.alive)
        game.hitBrick(ring: 0, index: 0)
        #expect(!game.state.rings[0].bricks[0]!.alive)
    }

    @Test func hiddenGhostsPingSonarWhenTheBallIsNear() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "GAAA")]))
        let ring = game.state.rings[0]
        let a = ring.midAngle(0)
        let r = ring.inner - Arena.ballRadius - 0.05
        game.place(x: cos(a) * r, y: sin(a) * r, vx: 0, vy: 0)
        let events = game.run(seconds: 1)
        // Once, then again after each cooldown.
        #expect(events.count { $0 == .ghostNear } == 2)
    }

    @Test func darkLevelsPingSonarForEveryBrick() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "AAAA")]) { $0.darkness = 0.6 })
        let ring = game.state.rings[0]
        let a = ring.midAngle(0)
        let r = ring.inner - Arena.ballRadius - 0.05
        game.place(x: cos(a) * r, y: sin(a) * r, vx: 0, vy: 0)
        #expect(game.run(seconds: 0.1).contains(.ghostNear))
    }

    @Test func phasingBricksAlternate() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "FFAA")]) { $0.phaseSeconds = 1 })
        #expect(game.state.isTangible(ring: 0, index: 0))
        #expect(!game.state.isTangible(ring: 0, index: 1))
        game.state.clock = 1.5
        #expect(!game.state.isTangible(ring: 0, index: 0))
        #expect(game.state.isTangible(ring: 0, index: 1))
        #expect(game.state.isTangible(ring: 0, index: 2))
    }

    @Test func intangibleBricksLetTheBallThrough() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "FFAA")]) { $0.phaseSeconds = 100 })
        let events = game.hitBrick(ring: 0, index: 1)
        #expect(!events.contains { $0.touchesBrick })
        #expect(game.state.rings[0].bricks[1]!.alive)
    }

    // MARK: Warps

    @Test func warpsLinkInConsecutivePairs() {
        let rings = [
            RingDef(radius: 0.3, sectors: 4, bricks: "W.W."),
            RingDef(radius: 0.5, sectors: 4, bricks: "WAWA"),
        ]
        let game = engine(level(rings: rings))
        let b = game.state.rings.map(\.bricks)
        #expect(b[0][0]!.warpPartner == BrickRef(ring: 0, index: 2))
        #expect(b[0][2]!.warpPartner == BrickRef(ring: 0, index: 0))
        #expect(b[1][0]!.warpPartner == BrickRef(ring: 1, index: 2))
        #expect(b[0][0]!.warpPair == 0)
        #expect(b[1][2]!.warpPair == 1)
    }

    @Test func warpTeleportsToThePartnerKeepingTheHeading() throws {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 12, bricks: "W.....W....A")]))
        let ring = game.state.rings[0]
        let a = ring.midAngle(0)
        let r = ring.inner - Arena.ballRadius - 0.03
        game.place(x: cos(a) * r, y: sin(a) * r, vx: cos(a), vy: sin(a))
        var warped = false
        for _ in 0..<30 where !warped {
            warped = game.update(frameSeconds: 1 / 60).contains { if case .warped = $0 { true } else { false } }
        }
        #expect(warped)
        let ball = game.state.balls[0]
        // Rotated 180° to the partner portal, still heading outward.
        #expect(abs(degrees(angleDelta(atan2(ball.y, ball.x), ring.midAngle(6)))) < 3)
        #expect(ball.x * ball.vx + ball.y * ball.vy > 0)
        #expect(ball.warpCooldown > 0)
    }

    // MARK: Ring motion & gravity

    @Test func ringsRotateAndTidalRingsReverse() {
        let rings = [
            RingDef(radius: 0.3, sectors: 4, bricks: "AAAA", rotationDps: 90),
            RingDef(radius: 0.5, sectors: 4, bricks: "AAAA", rotationDps: 90, offsetDeg: 10, rotationPeriod: 2),
        ]
        let game = engine(level(rings: rings))
        #expect(abs(degrees(game.state.rings[1].rotation) - 10) < 1e-4)
        game.run(seconds: 1)
        #expect(abs(degrees(game.state.rings[0].rotation) - 90) < 0.5)
        // Half a tide period: swung forward, then the tide turns.
        let peak = game.state.rings[1].rotation
        #expect(peak > 10 * deg)
        game.run(seconds: 1)
        #expect(game.state.rings[1].rotation < peak)
    }

    @Test func gravityBendsTheBallButKeepsItsSpeed() {
        let game = engine(level(rings: []) { $0.gravityWells = [GravityWellDef(x: 0, y: 0.3, strength: 0.2)] })
        let speed = game.state.ballSpeed
        game.place(x: -0.4, y: 0, vx: speed, vy: 0)
        game.run(seconds: 0.3)
        let ball = game.state.balls[0]
        #expect(ball.vy > 0.05)
        #expect(abs(norm(ball.vx, ball.vy) - speed) < 1e-4)
    }

    @Test func paddleShrinksOverTimeDownToTheMinimum() {
        let game = engine(level(rings: []) { $0.paddleArcDeg = 40; $0.paddleShrinkDps = 2 })
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.run(seconds: 5)
        #expect(abs(degrees(game.state.paddle.halfArc * 2) - 30) < 0.5)
        game.run(seconds: 10)
        #expect(abs(degrees(game.state.paddle.halfArc * 2) - Arena.minPaddleArcDeg) < 0.5)
    }

    // MARK: Boss cores

    private func boss(hp: Int = 3, phases: [CorePhaseDef] = []) -> GameEngine {
        let rings = [RingDef(radius: 0.4, sectors: 4, bricks: "AAAA", rotationDps: 10, shield: true)]
        return engine(level(rings: rings, cores: [CoreDef(hp: hp, phases: phases)]))
    }

    private func shootCore(_ game: GameEngine, charged: Bool = true) -> [GameEvent] {
        game.place(x: 0.25, y: 0, vx: -game.state.ballSpeed, vy: 0)
        game.state.balls[0].charged = charged
        var all: [GameEvent] = []
        for _ in 0..<30 {
            let events = game.update(frameSeconds: 1 / 60)
            all += events
            if events.contains(where: { $0 == .coreDeflected || { if case .bossHit = $0 { true } else { false } }($0) }) {
                break
            }
        }
        game.park()
        return all
    }

    @Test func chargedBallDamagesTheCoreAndSpendsTheCharge() {
        let game = boss()
        #expect(shootCore(game).contains(.bossHit(hpLeft: 2)))
        #expect(game.state.cores[0].hp == 2)
        #expect(game.state.score == Arena.coreHitScore)
    }

    @Test func unchargedBallIsDeflected() {
        let game = boss()
        let events = shootCore(game, charged: false)
        #expect(events.contains(.coreDeflected))
        #expect(game.state.cores[0].hp == 3)
    }

    @Test func paddleHitRechargesTheBall() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0.7, vx: 0, vy: 1)
        game.state.balls[0].charged = false
        game.run(seconds: 0.3)
        #expect(game.state.balls[0].charged)
    }

    @Test func bossPhasesApplyOnce() {
        let phase = CorePhaseDef(atHp: 2, ringSpeedMultiplier: 2, gravity: 0.1, restoreShields: true, phaseShields: true)
        let game = boss(hp: 4, phases: [phase])
        game.state.rings[0].bricks[1]!.hp = 0
        #expect(!shootCore(game).contains { if case .bossPhase = $0 { true } else { false } })
        let events = shootCore(game)
        #expect(events.contains(.bossPhase(1)))
        #expect(game.state.rings[0].speedMultiplier == 2)
        #expect(game.state.cores[0].gravity == 0.1)
        #expect(game.state.rings[0].bricks[1]!.alive)
        #expect(game.state.rings[0].bricks.allSatisfy { $0!.phasing })
        #expect(!shootCore(game).contains { if case .bossPhase = $0 { true } else { false } })
    }

    @Test func defeatingTheCoreClearsTheLevel() {
        let game = boss(hp: 1)
        let events = shootCore(game)
        #expect(events.contains(.bossDefeated))
        #expect(game.state.phase == .cleared)
        #expect(game.state.score == Arena.coreHitScore + Arena.coreDefeatScore + 3 * 100)
    }

    @Test func breakingEveryBrickDoesNotClearABossLevel() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "A...")], cores: [CoreDef(hp: 2)]))
        game.hitBrick(ring: 0, index: 0)
        #expect(game.state.phase == .playing)
    }

    // MARK: Power-ups

    @Test func widePaddleGrowsAndCancelsNarrow() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.state.effects[.shrink] = 5
        #expect(game.give(.wide).contains { if case .powerUpCollected(.wide, _, _) = $0 { true } else { false } })
        #expect(game.state.isActive(.wide))
        #expect(!game.state.isActive(.shrink))
        game.run(seconds: 1.5)
        #expect(abs(game.state.paddle.halfArc - game.state.paddle.baseHalfArc * Arena.wideFactor) < 0.01)
    }

    @Test func powerUpsMissedByThePaddleAreLost() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.state.powerUps.append(FallingPowerUp(type: .life, x: 0, y: -0.8))
        game.run(seconds: 1)
        #expect(game.state.powerUps.isEmpty)
        #expect(game.state.lives == Arena.startingLives)
    }

    @Test func timedPowerUpsWarnThenExpire() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.state.effects[.slow] = 2.5
        #expect(game.run(seconds: 0.6).contains(.powerUpEnding(.slow)))
        #expect(game.run(seconds: 2).contains(.powerUpExpired(.slow)))
        #expect(!game.state.isActive(.slow))
    }

    @Test func slowMoSlowsTheBall() {
        let game = engine(level(rings: []))
        let normal = game.state.ballSpeed
        game.state.effects[.slow] = 5
        #expect(abs(game.state.ballSpeed - normal * Arena.slowFactor) < 1e-6)
    }

    @Test func multiBallSplitsUpToTheMaximum() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.give(.multi)
        #expect(game.state.balls.count == 3)
        for _ in 0..<3 { game.give(.multi) }
        #expect(game.state.balls.count == Arena.maxBalls)
    }

    @Test func shieldSavesOneMissedBall() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.give(.shield)
        #expect(game.state.shield)
        game.snapPaddle(to: -90 * deg)
        game.place(x: 0, y: 0.8, vx: 0, vy: 1)
        let events = game.run(seconds: 0.3)
        #expect(events.contains(.shieldSaved))
        #expect(!game.state.shield)
        #expect(game.state.lives == Arena.startingLives)
        #expect(game.state.balls[0].vy < 0)
    }

    @Test func extraLivesAreCapped() {
        let game = engine(level(rings: []))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.give(.life)
        #expect(game.state.lives == Arena.startingLives + 1)
        game.state.lives = Arena.maxLives
        game.give(.life)
        #expect(game.state.lives == Arena.maxLives)
    }

    @Test func stickyPaddleCatchesThenAutoReleases() {
        let game = engine(level(rings: []))
        game.state.effects[.sticky] = 10
        game.place(x: 0, y: 0.7, vx: 0, vy: 1)
        #expect(game.run(seconds: 0.3).contains(.ballCaught))
        #expect(game.state.balls[0].stuck)
        #expect(game.run(seconds: Arena.stickyHoldSeconds).contains(.launched))
        #expect(!game.state.balls[0].stuck)
    }

    @Test func launchReleasesAStickyBall() {
        let game = engine(level(rings: []))
        game.state.effects[.sticky] = 10
        game.place(x: 0, y: 0.7, vx: 0, vy: 1)
        game.run(seconds: 0.3)
        game.launch()
        #expect(!game.state.balls[0].stuck)
        #expect(game.state.balls[0].vy < 0)
    }

    @Test func fireballPiercesArmor() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 4, bricks: "CAAA")]))
        game.state.effects[.fire] = 5
        let ring = game.state.rings[0]
        let a = ring.midAngle(0)
        game.place(x: cos(a) * 0.3, y: sin(a) * 0.3, vx: cos(a), vy: sin(a))
        game.run(seconds: 0.1)
        #expect(!game.state.rings[0].bricks[0]!.alive)
        let ball = game.state.balls[0]
        // Straight through, no bounce.
        #expect(ball.x * ball.vx + ball.y * ball.vy > 0)
    }

    @Test func laserFiresBoltsThatBreakBricks() {
        let game = engine(level(rings: [RingDef(radius: 0.4, sectors: 1, bricks: "B")]))
        game.place(x: 0, y: 0, vx: 0, vy: 0)
        game.state.effects[.laser] = 5
        let events = game.run(seconds: 0.05)
        #expect(events.contains(.laserFired))
        #expect(game.state.bolts.count == 2)
        game.run(seconds: 0.5)
        // Both bolts hit the one brick that wraps the whole ring.
        #expect(game.state.phase == .cleared)
    }

    @Test func losingABallClearsPowerUps() {
        let game = engine(level(rings: []))
        game.state.effects[.wide] = 10
        game.state.powerUps.append(FallingPowerUp(type: .multi, x: 0, y: -0.2))
        game.snapPaddle(to: -90 * deg)
        game.place(x: 0, y: 0.8, vx: 0, vy: 1)
        game.run(seconds: 0.3)
        #expect(game.state.effects.isEmpty)
        #expect(game.state.powerUps.isEmpty)
        #expect(game.state.speed == game.state.baseSpeed)
    }
}
