import Foundation

extension Array {
    /// Foundation-only equivalent of SwiftUI's `move(fromOffsets:toOffset:)`, so models stay UI-free.
    /// `destination` is an index in the array before the move, as delivered by `onMove`.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let validSource = source.filter { $0 >= 0 && $0 < count }
        guard !validSource.isEmpty else { return }
        let moving = validSource.map { self[$0] }
        let removedBeforeDestination = validSource.filter { $0 < destination }.count
        for index in validSource.sorted(by: >) {
            remove(at: index)
        }
        let insertionIndex = Swift.max(0, Swift.min(count, destination - removedBeforeDestination))
        insert(contentsOf: moving, at: insertionIndex)
    }
}
