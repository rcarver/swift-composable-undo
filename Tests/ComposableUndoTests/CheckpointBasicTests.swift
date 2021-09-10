import XCTest
import ComposableArchitecture

@testable import ComposableUndo

final class CheckpointBasicTests: XCTestCase {
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

  enum Action: Equatable {
    case setName(String)
    case setNumber(Int)
    case checkpoint(CheckpointAction)
  }

  struct Environment { }

  let reducer = Reducer<State, Action, Environment> { state, action, environment in
    switch action {
    case let .setName(name):
      state.value.name = name
      return .init(value: .checkpoint(.register("Change Name to \(name)")))
    case let .setNumber(number):
      state.value.number = number
      return .init(value: .checkpoint(.register("Change Number to \(number)")))
    case .checkpoint:
      return .none
    }
  }
 .trackCheckpoints(of: \.$value, in: /Action.checkpoint)

  func testCheckpointChanges() {
    let store = TestStore(
      initialState: .init(value: .init(name: "A", number: 1)),
      reducer: reducer,
      environment: .init()
    )

    // Perform a mutation of store that takes snapshot
    store.send(.setName("B")) {
      $0.value.name = "B"
    }
    store.receive(.checkpoint(.register("Change Name to B"))) {
      $0.$value.setExpected(undoLabel: "Change Name to B", redoLabel: nil)
    }

    // Undo mutation
    store.send(.checkpoint(.undo))
    store.receive(.checkpoint(.finishedUndo)) {
      $0.value.name = "A"
      $0.$value.setExpected(undoLabel: nil, redoLabel: "Change Name to B")
    }

    // Redo same action
    store.send(.checkpoint(.redo))
    store.receive(.checkpoint(.finishedRedo)) {
      $0.value.name = "B"
      $0.$value.setExpected(undoLabel: "Change Name to B", redoLabel: nil)
    }

    // Add another mutation
    store.send(.setNumber(2)) {
      $0.value.number = 2
    }
    store.receive(.checkpoint(.register("Change Number to 2"))) {
      $0.$value.setExpected(undoLabel: "Change Number to 2", redoLabel: nil)
    }

    // Undo the second action
    store.send(.checkpoint(.undo))
    store.receive(.checkpoint(.finishedUndo)) {
      $0.value.number = 1
      $0.$value.setExpected(undoLabel: "Change Name to B", redoLabel: "Change Number to 2")
    }

    // Replace the mutation
    store.send(.setNumber(-1)) {
      $0.value.number = -1
    }
    store.receive(.checkpoint(.register("Change Number to -1"))) {
      $0.$value.setExpected(undoLabel: "Change Number to -1", redoLabel: nil)
    }
  }
}

extension CheckpointState {
  fileprivate mutating func setExpected(undoLabel: String?, redoLabel: String?) {
      switch (undoLabel, redoLabel) {
      case (.none, .none):
        currentIndex = stack.startIndex
        stack.removeSubrange(stack.index(after: currentIndex)...)
      case let (.none, .some(redoAction)):
        if stack.count < 2 {
          stack.append(stack[0])
        }
        currentIndex = stack.startIndex
        stack[stack.index(after: currentIndex)].label = redoAction
      case let (.some(undoAction), .none):
        if stack.count < 2 {
          stack.append(stack[0])
        }
        currentIndex = stack.index(before: stack.endIndex)
        stack[currentIndex].label = undoAction
      case let (.some(undoAction), .some(redoAction)):
        while stack.count < 3 {
          stack.append(stack[0])
        }
        currentIndex = stack.index(stack.endIndex, offsetBy: -2)
        stack[currentIndex].label = undoAction
        stack[stack.index(after: currentIndex)].label = redoAction
      }
    }
}
