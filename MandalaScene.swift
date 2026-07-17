import Foundation

enum MandalaMotif: Int, CaseIterable {
    case bloom
    case temple
    case weave
    case oracle
}

struct MandalaScene {
    let seed: Float
    let symmetry: Int
    let motif: MandalaMotif
    let rotationDirection: Float
    let twist: Float
    let tunnelRate: Float
    let breathRate: Float
    let duration: CFAbsoluteTime

    static let initial = MandalaScene(
        seed: 173.0,
        symmetry: 8,
        motif: .bloom,
        rotationDirection: 1.0,
        twist: 0.85,
        tunnelRate: 1.0,
        breathRate: 1.0,
        duration: 64.0
    )
}

/// Small deterministic generator. Every scene can be replayed from the seed,
/// while each saver instance starts at a different point in the sequence.
struct MandalaSceneGenerator {
    private var state: UInt64
    private var previousSymmetry = 0
    private var previousMotif: MandalaMotif?

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next(forcedSymmetry: Int?) -> MandalaScene {
        let symmetry: Int
        if let forcedSymmetry {
            symmetry = forcedSymmetry
        } else {
            let choices = [6, 7, 8, 10, 12]
            var candidate = choices[nextInt(upperBound: choices.count)]
            if candidate == previousSymmetry {
                candidate = choices[(choices.firstIndex(of: candidate)! + 1 + nextInt(upperBound: choices.count - 1)) % choices.count]
            }
            symmetry = candidate
        }

        var motif = MandalaMotif.allCases[nextInt(upperBound: MandalaMotif.allCases.count)]
        if motif == previousMotif {
            motif = MandalaMotif(rawValue: (motif.rawValue + 1 + nextInt(upperBound: 3)) % MandalaMotif.allCases.count)!
        }

        previousSymmetry = symmetry
        previousMotif = motif

        return MandalaScene(
            seed: nextFloat(in: 0.0...4096.0),
            symmetry: symmetry,
            motif: motif,
            rotationDirection: nextBool() ? 1.0 : -1.0,
            twist: nextFloat(in: 0.55...1.25),
            tunnelRate: nextFloat(in: 0.75...1.35),
            breathRate: nextFloat(in: 0.78...1.22),
            duration: CFAbsoluteTime(nextFloat(in: 52.0...78.0))
        )
    }

    private mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    private mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(nextUInt64() % UInt64(upperBound))
    }

    private mutating func nextBool() -> Bool {
        return (nextUInt64() & 1) == 0
    }

    private mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        let unit = Float(nextUInt64() >> 40) / Float(1 << 24)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
