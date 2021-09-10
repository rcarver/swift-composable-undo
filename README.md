# Swift Composable Undo

A library that provides undo semantics for [the Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) with optional bridging with [UndoManager](https://developer.apple.com/documentation/foundation/nsundomanager/).

## Motivation

It is hard to use [UndoManager](https://developer.apple.com/documentation/foundation/nsundomanager/) API with state that uses value sematics. Furthermore, the [instance provided by SwiftUI](https://developer.apple.com/documentation/swiftui/environmentvalues/undomanager) may not be available in all contexts. There have been [previous discussions](https://forums.swift.org/t/how-to-interact-with-a-ns-undomanager/40894/4) which resulted in solutions that were not generic. This library provides a way to scope Undo/Redo operations within a View with minimal efforts.

## Example

The workspace ComposableUndo contains the TicTacToe demo from ComposableArchitecture repository. Open the [GameCore.swift](Example/tic-tac-toe/Sources/GameCore/GameCore.swift) file to see how Composable Undo is integrated.


## Basic Usage

To use ComposableUndo in your project, you need to annotate the state fields that needs undo tracking:
```swift
struct Person: Equatable {
  var firstName: String
  var lastName: String
  var phoneNumber: String
}

struct AppState: Equatable {
  @CheckpointState var person: Person
}
```

You also need to add checkpoint action to your domain. It is advisable to confirm the domain action enum to `SingleCheckpointAction` protocol when only one of the states fields is annotated:
```swift
enum AppAction: Equatable, SingleCheckpointAction {
  case checkpoint(CheckpointAction)
  // Your domain's other actions:
  ...
}
```

If you are planning to use `UndoManager`, it must be registered using view lifecycle methods: 

```swift
struct AppView: View {
  @Environment(\.undoManager) var undoManager
  // Store declarations
  ...
  
  var body: some View {
    WithViewStore(store) { viewStore in
      SomeView {
        ...
      }
      .onAppear { viewStore.send(.checkpoint(.attachManager(undoManager))) }
      .onDisappear { viewStore.send(.checkpoint(.detachManager)) }
    }
  }
}
```

If this view's state is computed by a super view, make sure that the detach happens before clearing the state. See NewGameCore.swift in the example on how to do this.

With this initial setup out of the way, each state change that can be undone must be registered by returning effect from the reducer:
```swift
case .updatePerson:
 // ... code to update state
 return .checkpoint(.register("Change person"))
```

Note that the register string is passed on to UndoManager and appears in the menu on macOS.


