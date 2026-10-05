package com.orbitbreaker.engine

import kotlinx.serialization.json.Json
import kotlin.math.hypot

/** Loads level definitions bundled as resources at `levels/NNN.json`. */
object LevelLoader {
    private val json = Json { ignoreUnknownKeys = false }

    fun parse(text: String): LevelDef = json.decodeFromString(LevelDef.serializer(), text).also(::validate)

    fun load(id: Int): LevelDef? {
        val stream = LevelLoader::class.java.classLoader
            ?.getResourceAsStream("levels/%03d.json".format(id)) ?: return null
        return stream.bufferedReader().use { parse(it.readText()) }
    }

    /** Loads levels 1, 2, 3… until the first missing file. */
    fun loadAll(): List<LevelDef> = generateSequence(1) { it + 1 }
        .map { load(it) }
        .takeWhile { it != null }
        .filterNotNull()
        .toList()

    fun validate(level: LevelDef) {
        require(level.rings.isNotEmpty() || level.isBoss) { "Level ${level.id} has no rings or core" }
        level.rings.forEachIndexed { i, ring ->
            require(ring.bricks.length == ring.sectors) {
                "Level ${level.id} ring $i: ${ring.bricks.length} brick codes for ${ring.sectors} sectors"
            }
            ring.bricks.forEach { BrickType.fromCode(it) }
            val inner = ring.radius - Arena.BRICK_THICKNESS / 2
            val outer = ring.radius + Arena.BRICK_THICKNESS / 2
            require(inner >= 0.1f && outer <= Arena.PADDLE_INNER - 0.12f) {
                "Level ${level.id} ring $i radius ${ring.radius} is outside the brick field"
            }
        }
        val sorted = level.rings.map { it.radius }.sorted()
        sorted.zipWithNext().forEach { (a, b) ->
            require(b - a >= Arena.BRICK_THICKNESS) { "Level ${level.id} has overlapping rings at $a and $b" }
        }
        val codes = level.rings.flatMap { r -> r.bricks.mapNotNull(BrickType::fromCode) }
        require(level.isBoss || codes.any { it.breakable }) { "Level ${level.id} has no breakable bricks" }
        require(codes.count { it == BrickType.WARP } % 2 == 0) { "Level ${level.id} has an unpaired warp brick" }
        val innermost = level.rings.minOfOrNull { it.radius - Arena.BRICK_THICKNESS / 2 } ?: 1f
        level.cores.forEach { core ->
            require(core.hp > 0) { "Level ${level.id} core needs HP" }
            require(hypot(core.x, core.y) + core.radius + 2 * Arena.BALL_RADIUS + 0.01f < innermost) {
                "Level ${level.id} core is too close to the innermost ring for the ball to fit"
            }
        }
        level.cores.forEachIndexed { i, a ->
            level.cores.drop(i + 1).forEach { b ->
                require(hypot(a.x - b.x, a.y - b.y) > a.radius + b.radius + 2 * Arena.BALL_RADIUS) {
                    "Level ${level.id} has overlapping cores"
                }
            }
        }
        require(level.darkness in 0f..1f)
        require(level.paddleShrinkDps >= 0f)
        level.gravityWells.forEach { require(it.x * it.x + it.y * it.y < 0.7f * 0.7f) { "Well outside field" } }
        require(level.dropChance in 0f..1f)
    }
}
