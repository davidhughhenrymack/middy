struct SongHarmony: Equatable {
    let build: [Int]
    let verse: [Int]
    let breakdown: [Int]
    let padVoicing: [Int]
    let droneVoicing: [Int]
    let answerShift: Int

    /// Zero-based scale degrees in the song's natural minor key.
    static let plans = [
        // Descending bass-pedal harmony with paired chords and open voicings.
        SongHarmony(build: [0, 0, 5, 6], verse: [0, 0, 6, 6, 5, 5, 4, 4],
                    breakdown: [5, 5, 3, 3, 0, 0, 6, 6],
                    padVoicing: [0, 4, 9], droneVoicing: [0, 4, 9], answerShift: -2),
        // Relative-major opening, using inversions to keep the upper voices light.
        SongHarmony(build: [0, 2, 3, 6], verse: [2, 2, 5, 6, 0, 0, 3, 6],
                    breakdown: [2, 2, 3, 3, 5, 5, 6, 6],
                    padVoicing: [2, 4, 7], droneVoicing: [0, 7, 9], answerShift: 2),
        // Tonic pedal and suspensions, with the chords changing less often.
        SongHarmony(build: [0, 0, 3, 0], verse: [0, 0, 0, 3, 0, 0, 5, 3],
                    breakdown: [0, 0, 5, 5, 3, 3, 0, 0],
                    padVoicing: [0, 4, 8], droneVoicing: [0, 4, 8], answerShift: 1),
        // Seventh-chord shells and an iv opening.
        SongHarmony(build: [3, 3, 5, 4], verse: [3, 5, 0, 0, 6, 5, 4, 4],
                    breakdown: [3, 3, 2, 2, 5, 5, 0, 0],
                    padVoicing: [0, 2, 6], droneVoicing: [0, 2, 11], answerShift: -1),
        // Close triads with a VI opening and a staggered return to tonic.
        SongHarmony(build: [0, 5, 3, 4], verse: [5, 5, 0, 6, 3, 3, 4, 0],
                    breakdown: [5, 5, 6, 6, 2, 2, 0, 3],
                    padVoicing: [0, 2, 4], droneVoicing: [0, 4, 7], answerShift: 2)
    ]
}
