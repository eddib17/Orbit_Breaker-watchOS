import Foundation

let twoPi = 2 * Float.pi
let deg = Float.pi / 180

/// Wraps an angle into [-π, π).
public func wrapAngle(_ a: Float) -> Float {
    var x = (a + .pi).truncatingRemainder(dividingBy: twoPi)
    if x < 0 { x += twoPi }
    return x - .pi
}

/// Signed shortest angular distance from `from` to `to`, in [-π, π).
public func angleDelta(_ from: Float, _ to: Float) -> Float { wrapAngle(to - from) }

/// Where a ball will cross the paddle circle if it keeps going straight.
public func predictedExitAngle(_ ball: Ball) -> Float {
    let r = Arena.paddleInner - ball.radius
    let b = ball.x * ball.vx + ball.y * ball.vy
    let v2 = ball.vx * ball.vx + ball.vy * ball.vy
    if v2 < 1e-9 { return atan2(ball.y, ball.x) }
    let c = ball.x * ball.x + ball.y * ball.y - r * r
    let t = (-b + (max(0, b * b - v2 * c)).squareRoot()) / v2
    return atan2(ball.y + ball.vy * t, ball.x + ball.vx * t)
}

extension Comparable {
    /// Kotlin's `coerceIn`.
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

/// Length of the vector (x, y).
func norm(_ x: Float, _ y: Float) -> Float { (x * x + y * y).squareRoot() }
