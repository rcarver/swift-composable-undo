import XCTest
import ComposableArchitecture

@testable import ComposableUndo

final class CheckpointWithCopierTests: XCTestCase {
  class Value: Equatable {
    var name: String
    var number: Int

    init(name: String, number: Int) {
      self.name = name
      self.number = number
    }

    static func ==(lhs: Value, rhs: Value) -> Bool {
      lhs.name == rhs.name && lhs.number == rhs.number
    }

    static func clone(_ other: Value) -> Value {
      .init(name: other.name, number: other.number)
    }
  }

  struct State: Equatable {
    @CheckpointState var value: Value

    init(value: Value) {
      _value = .init(wrappedValue: value, copier: Value.clone)
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

  func testSimpleUndoRedo() {
    let store = TestStore(
      initialState: .init(value: .init(name: "A", number: 1)),
      reducer: reducer,
      environment: .init()
    )

    // Perform a mutation of store that takes snapshot
    store.send(.setName("B")) {
      $0.value.name = "B"
    }
    store.receiveCheckpoint(.register("Change Name to B"), of: \.$value)

    // Undo mutation
    store.send(.checkpoint(.undo))
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.name = "A"
    }

    // Redo same action
    store.send(.checkpoint(.redo))
    store.receiveCheckpoint(.finishedRedo, of: \.$value) {
      $0.value.name = "B"
    }

    // Add another mutation
    store.send(.setNumber(2)) {
      $0.value.number = 2
    }
    store.receiveCheckpoint(.register("Change Number to 2"), of: \.$value)

    // Undo the second action
    store.sendCheckpoint(.undo, of: \.$value)
    store.receiveCheckpoint(.finishedUndo, of: \.$value) {
      $0.value.number = 1
    }

    // Replace the mutation
    store.send(.setNumber(-1)) {
      $0.value.number = -1
    }
    store.receiveCheckpoint(.register("Change Number to -1"), of: \.$value)
  }
}

