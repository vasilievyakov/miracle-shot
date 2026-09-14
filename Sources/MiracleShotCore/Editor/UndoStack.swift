/// A simple two-stack undo/redo history over any `Equatable` state snapshot.
public struct UndoStack<State: Equatable & Sendable>: Sendable {
    public private(set) var undoStates: [State]
    public private(set) var redoStates: [State]
    public let limit: Int

    public init(limit: Int = 100) {
        self.undoStates = []
        self.redoStates = []
        self.limit = limit
    }

    public var canUndo: Bool { !undoStates.isEmpty }
    public var canRedo: Bool { !redoStates.isEmpty }

    /// Records `state` as the state to return to; clears redo. Drops the oldest entry past `limit`.
    public mutating func push(_ state: State) {
        undoStates.append(state)
        redoStates.removeAll()
        if undoStates.count > limit {
            undoStates.removeFirst()
        }
    }

    /// Returns the state to restore, moving `current` onto the redo stack. nil if nothing to undo.
    public mutating func undo(current: State) -> State? {
        guard let state = undoStates.popLast() else { return nil }
        redoStates.append(current)
        return state
    }

    /// Returns the state to restore, moving `current` onto the undo stack. nil if nothing to redo.
    public mutating func redo(current: State) -> State? {
        guard let state = redoStates.popLast() else { return nil }
        undoStates.append(current)
        return state
    }
}
