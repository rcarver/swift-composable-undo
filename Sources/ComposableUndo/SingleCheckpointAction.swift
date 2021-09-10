import ComposableArchitecture

public protocol SingleCheckpointAction {
  static func checkpoint(_: CheckpointAction) -> Self
}

extension Reducer {
  public func trackCheckpoints<Value>(
    of toHistory: WritableKeyPath<State, CheckpointState<Value>>
  ) -> Self where Action: SingleCheckpointAction {
    trackCheckpoints(of: toHistory, in: /Action.checkpoint)
  }
}

extension Effect where Output: SingleCheckpointAction {
  public static func checkpoint(_ action: CheckpointAction) -> Self {
    .init(value: (/Output.checkpoint).embed(action))
  }
}

extension TestStore where LocalState: Equatable, Action: (Equatable & SingleCheckpointAction) {
  public func receiveCheckpoint<Value>(
    _ expectedAction: CheckpointAction,
    of toState: WritableKeyPath<LocalState, CheckpointState<Value>>,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout LocalState) throws -> Void = { _ in }
  ) {
    receiveCheckpoint(expectedAction, in: /Action.checkpoint, of: toState, file: file, line: line, update)
  }
}

extension TestStore where LocalState: Equatable, LocalAction: SingleCheckpointAction {
  public func sendCheckpoint<Value>(
    _ action: CheckpointAction,
    of toState: WritableKeyPath<LocalState, CheckpointState<Value>>,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout LocalState) throws -> Void = { _ in }
  ) {
    sendCheckpoint(action, in: /LocalAction.checkpoint, of: toState, file: file, line: line, update)
  }
}

extension TestStore.Step where Action: SingleCheckpointAction {
  public static func receiveCheckpoint<Value>(
    _ action: CheckpointAction,
    of toState: WritableKeyPath<LocalState, CheckpointState<Value>>,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout LocalState) throws -> Void = { _ in }
  ) -> Self {
    .receiveCheckpoint(action, in: /Action.checkpoint, of: toState, file: file, line: line, update)
  }
}

extension TestStore.Step where LocalAction: SingleCheckpointAction {
  public static func sendCheckpoint<Value>(
    _ action: CheckpointAction,
    of toState: WritableKeyPath<LocalState, CheckpointState<Value>>,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout LocalState) throws -> Void = { _ in }
  ) -> Self {
    .sendCheckpoint(action, in: /LocalAction.checkpoint, of: toState, file: file, line: line, update)
  }
}
