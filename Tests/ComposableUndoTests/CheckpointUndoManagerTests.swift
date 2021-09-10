import XCTest
import ComposableArchitecture

@testable import ComposableUndo

final class CheckpointUndoManagerTests: XCTestCase {
  struct Value: Equatable {
    var name: String
    var number: Int
  }

  struct State: Equatable {
    @CheckpointState var value: Value

    init(value: Value) {
      self.value = value
    }
  }

  enum Action: SingleCheckpointAction, Equatable {
    case setName(String)
    case setNumber(Int)
    case checkpoint(CheckpointAction)
  }

  struct Environment { }

  let reducer = Reducer<State, Action, Environment> { state, action, environment in
    switch action {
    case let .setName(name):
      state.value.name = name
      return .checkpoint(.register("Change Name to \(name)"))
    case let .setNumber(number):
      state.value.number = number
      return .checkpoint(.register("Change Number to \(number)"))
    case .checkpoint:
      return .none
    }
  }
  .trackCheckpoints(of: \.$value)

  /// Records the current state in test store using `toLocalState` hack
  class StateRecorder {
    private var currentState: State?

    func toLocalState(_ state: State) -> State {
      currentState = state
      return state
    }

    func verifyUndoManagerState() {
      guard let history = currentState?.$value, let manager = history.manager else { return }

      XCTAssertEqual(manager.canUndo, history.canUndo)
      XCTAssertEqual(manager.undoActionName, history.undoLabel ?? "")

      XCTAssertEqual(manager.canRedo, history.canRedo)
      XCTAssertEqual(manager.redoActionName, history.redoLabel ?? "")
    }
  }

  func testUndoManagerOnly() {
    let recorder = StateRecorder()

    let store = TestStore(
      initialState: .init(value: .init(name: "A", number: 1)),
      reducer: reducer,
      environment: .init()
    ).scope(state: recorder.toLocalState)

    let undoManager = UndoManager()
    store.send(.checkpoint(.attachManager(undoManager)))
    defer {
      store.send(.checkpoint(.detachManager))
    }

    // Perform a mutation of store that takes snapshot
    store.send(.setName("B")) {
      $0.value.name = "B"
    }
    store.receiveCheckpoint(.register("Change Name to B"), of: \.$value)
    recorder.verifyUndoManagerState()

    // Undo mutation with manager
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.name = "A"
    }
    recorder.verifyUndoManagerState()

    // Redo same action with manager
    undoManager.redo()
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value.name = "B"
    }
    recorder.verifyUndoManagerState()

    // Add amother mutation
    store.send(.setNumber(2)) {
      $0.value.number = 2
    }
    store.receiveCheckpoint(.register("Change Number to 2"), of: \.$value)
    recorder.verifyUndoManagerState()


    // Undo the second action
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }
    recorder.verifyUndoManagerState()

    // Redo the second action
    undoManager.redo()
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value.number = 2
    }
    recorder.verifyUndoManagerState()

    // Undo the second action for replacement
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }
    recorder.verifyUndoManagerState()

    // Replace the mutation
    store.send(.setNumber(-1)) {
      $0.value.number = -1
    }
    store.receiveCheckpoint(.register("Change Number to -1"), of: \.$value)
    recorder.verifyUndoManagerState()

    // Undo the replacement action
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }
    recorder.verifyUndoManagerState()
  }

  func testRegisterManagerInterleaved() {
    let recorder = StateRecorder()

    let store = TestStore(
      initialState: .init(value: .init(name: "A", number: 1)),
      reducer: reducer,
      environment: .init()
    ).scope(state: recorder.toLocalState)

    let undoManager = UndoManager()
    store.send(.checkpoint(.attachManager(undoManager)))
    defer {
      store.send(.checkpoint(.detachManager))
    }

    // Perform a mutation of store that takes snapshot
    store.send(.setName("B")) {
      $0.value.name = "B"
    }
    store.receiveCheckpoint(.register("Change Name to B"), of: \.$value)
    recorder.verifyUndoManagerState()

    // Undo mutation with manager
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.name = "A"
    }
    recorder.verifyUndoManagerState()

    // Redo same action outside manager
    store.send(.checkpoint(.redo))
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value.name = "B"
    }
    recorder.verifyUndoManagerState()

    // Add amother mutation
    store.send(.setNumber(2)) {
      $0.value.number = 2
    }
    store.receiveCheckpoint(.register("Change Number to 2"), of: \.$value)
    recorder.verifyUndoManagerState()


    // Undo the second action
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }
    recorder.verifyUndoManagerState()

    // Redo the second action
    undoManager.redo()
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value.number = 2
    }
    recorder.verifyUndoManagerState()

    // Undo the second action for replacement
    store.send(.checkpoint(.undo))
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }
    recorder.verifyUndoManagerState()

    // Replace the mutation
    store.send(.setNumber(-1)) {
      $0.value.number = -1
    }
    store.receiveCheckpoint(.register("Change Number to -1"), of: \.$value)
    recorder.verifyUndoManagerState()

    // Undo the replacement action
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }
    recorder.verifyUndoManagerState()
  }

  struct Change {
    let action: Action
    let expectedValue: Value
    let label: String
  }

  func changes(from initialValue: Value) -> [Change] {
    let actions: [Action] = [
      .setName("X"),
      .setName("N"),
      .setName("BA"),
      .setName("Z"),
      .setName("V"),
      .setName("PQR"),
      .setNumber(9),
      .setNumber(5),
      .setNumber(21),
      .setNumber(42),
      .setNumber(7),
      .setNumber(2),
    ]
    .shuffled()

    var changes: [Change] = []
    changes.reserveCapacity(actions.count)

    var v = initialValue
    for action in actions {
      let actionName: String
      switch action {
      case let .setName(name):
        v.name = name
        actionName = "Change Name to \(name)"
      case let .setNumber(number):
        v.number = number
        actionName = "Change Number to \(number)"
      default:
        preconditionFailure("Invalid action")
      }
      changes.append(.init(action: action, expectedValue: v, label: actionName))
    }
    return changes
  }

  func testMultiLevelUndo() {
    let initialValue = Value(name: "AA", number: 1)
    let changes = changes(from: initialValue)

    let store = TestStore(
      initialState: .init(value: initialValue),
      reducer: reducer,
      environment: .init()
    )

    // Record all actions
    for c in changes {
      store.send(c.action) {
        $0.value = c.expectedValue
      }
      store.receiveCheckpoint(.register(c.label), of: \.$value)
    }

    // Undo all actions
    for index in changes.indices.reversed().dropFirst() {
      store.send(.checkpoint(.undo))
      store.receiveCheckpoint(.finishedUndo, of: \.$value) {
        $0.value = changes[index].expectedValue
      }
    }

    // Undo last action
    store.send(.checkpoint(.undo))
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value = initialValue
    }

    // Undo beyond last action should be ignored
    store.send(.checkpoint(.undo))

    // Redo all actions
    for index in changes.indices.dropLast() {
      store.send(.checkpoint(.redo))
      store.receiveCheckpoint(.finishedRedo, of: \.$value) {
        $0.value = changes[index].expectedValue
      }
    }

    // Redo final action
    store.send(.checkpoint(.redo))
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value = changes.last!.expectedValue
    }

    // Redo beyond last action should be ignored
    store.send(.checkpoint(.redo))
  }

  func testMultiLevelUndoWithUndoManager() {
    let initialValue = Value(name: "A", number: 1)
    let changes = changes(from: initialValue)

    let recorder = StateRecorder()
    let store = TestStore(
      initialState: .init(value: initialValue),
      reducer: reducer,
      environment: .init()
    ).scope(state: recorder.toLocalState)

    let undoManager = UndoManager()
    store.send(.checkpoint(.attachManager(undoManager)))
    defer {
      store.send(.checkpoint(.detachManager))
    }

    // Record all actions
    for c in changes {
      store.send(c.action) {
        $0.value = c.expectedValue
      }
      store.receiveCheckpoint(.register(c.label), of: \.$value)
      recorder.verifyUndoManagerState()
    }

    // Undo all actions
    for index in changes.indices.reversed().dropFirst() {
      if Bool.random() {
        undoManager.undo()
      } else {
        store.send(.checkpoint(.undo))
      }
      store.receiveCheckpoint(.finishedUndo, of: \.$value) {
        $0.value = changes[index].expectedValue
      }
      recorder.verifyUndoManagerState()
    }

    // Undo last action
    undoManager.undo()
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value = initialValue
    }
    recorder.verifyUndoManagerState()

    // Undo beyond last action should be ignored
    undoManager.undo()

    // Redo all actions
    for index in changes.indices.dropLast() {
      if Bool.random() {
        undoManager.redo()
      } else {
        store.send(.checkpoint(.redo))
      }
      store.receiveCheckpoint(.finishedRedo, of: \.$value) {
        $0.value = changes[index].expectedValue
      }
      recorder.verifyUndoManagerState()
    }

    // Redo final action
    undoManager.redo()
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value = changes.last!.expectedValue
    }
    recorder.verifyUndoManagerState()

    // Redo beyond last action should be ignored
    undoManager.redo()
  }
}
