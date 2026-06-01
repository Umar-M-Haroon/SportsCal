import Foundation

extension Array {
    /// Splits the array into consecutive sub-arrays of at most `size` elements.
    /// Used to bound Redis MGET argument counts (a single 10k-arg MGET is a
    /// latency spike) and to feed bounded-concurrency processing.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
