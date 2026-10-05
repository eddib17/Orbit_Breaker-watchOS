package com.orbitbreaker.engine

data class WorldInfo(val number: Int, val name: String, val tagline: String)

/** The six worlds of the campaign; each has 10 levels and ends with a boss. */
object Worlds {
    const val LEVELS_PER_WORLD = 10

    val all = listOf(
        WorldInfo(1, "First Light", "Learn the ropes"),
        WorldInfo(2, "Orbit", "Spinning rings"),
        WorldInfo(3, "Iron", "Armor and explosives"),
        WorldInfo(4, "Flux", "Warps and gravity"),
        WorldInfo(5, "Eclipse", "Feel what you can't see"),
        WorldInfo(6, "Singularity", "Everything at once"),
    )

    fun of(levelId: Int): WorldInfo = all[((levelId - 1) / LEVELS_PER_WORLD).coerceIn(0, all.lastIndex)]
}
