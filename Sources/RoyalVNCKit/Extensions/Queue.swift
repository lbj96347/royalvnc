import Foundation

/// Thread-safe FIFO. Only adjacent moves explicitly marked as replaceable may be coalesced.
final class Queue<T> {
    private struct Entry { let value: T; let replaceable: Bool }
    private let lock = NSLock()
    private var list: [Entry] = []
    func enqueue(_ element: T, replaceable: Bool = false) {
        lock.withLock {
            if replaceable, list.last?.replaceable == true { list.removeLast() }
            list.append(Entry(value: element, replaceable: replaceable))
        }
    }
    func dequeue() -> T? { lock.withLock { list.isEmpty ? nil : list.removeFirst().value } }
    func clear() { lock.withLock { list.removeAll() } }
    func peek() -> T? { lock.withLock { list.first?.value } }
    var isEmpty: Bool { lock.withLock { list.isEmpty } }
}
