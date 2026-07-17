import Foundation

private struct SceneSignature: Equatable {
    let seed: Float
    let symmetry: Int
    let motif: Int
    let direction: Float
    let twist: Float
    let tunnelRate: Float
    let breathRate: Float
    let duration: Double

    init(_ scene: MandalaScene) {
        seed = scene.seed
        symmetry = scene.symmetry
        motif = scene.motif.rawValue
        direction = scene.rotationDirection
        twist = scene.twist
        tunnelRate = scene.tunnelRate
        breathRate = scene.breathRate
        duration = scene.duration
    }
}

@main
private enum SceneTests {
    static func main() {
        var first = MandalaSceneGenerator(seed: 0x12345678)
        var second = MandalaSceneGenerator(seed: 0x12345678)
        var firstSequence: [SceneSignature] = []
        var secondSequence: [SceneSignature] = []
        for _ in 0..<64 {
            firstSequence.append(SceneSignature(first.next(forcedSymmetry: nil)))
            secondSequence.append(SceneSignature(second.next(forcedSymmetry: nil)))
        }
        precondition(firstSequence == secondSequence, "scene generation must be deterministic")

        let validSymmetries: Set<Int> = [6, 7, 8, 10, 12]
        var motifs: Set<Int> = []
        for (index, scene) in firstSequence.enumerated() {
            precondition(validSymmetries.contains(scene.symmetry), "invalid automatic symmetry")
            precondition((0..<MandalaMotif.allCases.count).contains(scene.motif), "invalid motif")
            precondition((52.0...78.0).contains(scene.duration), "invalid duration")
            precondition((0.55...1.25).contains(scene.twist), "invalid twist")
            precondition((0.75...1.35).contains(scene.tunnelRate), "invalid tunnel rate")
            precondition((0.78...1.22).contains(scene.breathRate), "invalid breath rate")
            precondition(scene.direction == -1.0 || scene.direction == 1.0, "invalid direction")
            motifs.insert(scene.motif)
            if index > 0 {
                precondition(scene.symmetry != firstSequence[index - 1].symmetry, "automatic symmetry repeated")
                precondition(scene.motif != firstSequence[index - 1].motif, "motif repeated")
            }
        }
        precondition(motifs.count == MandalaMotif.allCases.count, "not all motifs were generated")

        var forced = MandalaSceneGenerator(seed: 99)
        for _ in 0..<32 {
            precondition(forced.next(forcedSymmetry: 10).symmetry == 10, "forced symmetry was ignored")
        }

        print("Scene tests passed (determinism, ranges, diversity, forced symmetry).")
    }
}
