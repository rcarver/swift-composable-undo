import Foundation
import DequeModule
import Combine
import ComposableArchitecture

@propertyWrapper public struct CheckpointState<Value> {
  struct Checkpoint {
    var value: Value
    var label: String
  }

  var stack: Deque<Checkpoint>
  var currentIndex: Deque<Checkpoint>.Index
  weak var manager: UndoManager?
  let managerActions: PassthroughSubject<CheckpointAction, Never>
  let copier: ((Value) -> Value)?

  public var wrappedValue: Value
  
  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }

  public init(wrappedValue initial: Value) {
    wrappedValue = initial
    stack = [.init(value: initial, label: "")]
    currentIndex = stack.startIndex
    managerActions = .init()
    copier = nil
  }

  public init(wrappedValue initial: Value, copier: @escaping ((Value) -> Value)) {
    wrappedValue = initial
    stack = [.init(value: copier(initial), label: "")]
    currentIndex = stack.startIndex
    managerActions = .init()
    self.copier = copier
  }
}

public enum CheckpointAction: Equatable {
  case register(String)
  case undo
  case redo
  case removeAll
  case finishedUndo
  case finishedRedo
  case attachManager(UndoManager?)
  case detachManager
}

extension CheckpointState {
  public var initialValue: Value { stack.first!.value }

  public var canUndo: Bool {
    stack.distance(from: stack.startIndex, to: currentIndex) > 0
  }

  public var allUndoLabels: [String] {
    stack[stack.index(after: stack.startIndex)...currentIndex].map(\.label)
  }

  public var undoLabel: String? {
    guard canUndo else { return nil }
    return stack[currentIndex].label
  }

  public var canRedo: Bool {
    stack.distance(from: currentIndex, to: stack.endIndex) > 1
  }

  public var allRedoLabels: [String] {
    stack[stack.index(after: currentIndex)...].map(\.label)
  }

  public var redoLabel: String? {
    guard canRedo else { return nil }
    return stack[stack.index(after: currentIndex)].label
  }
}

extension CheckpointState: Equatable where Value: Equatable {
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.undoLabel == rhs.undoLabel && lhs.redoLabel == rhs.redoLabel && lhs.wrappedValue == rhs.wrappedValue
  }
}

extension CheckpointState: Hashable where Value: Hashable {
  public func hash(into hasher: inout Hasher) {
    undoLabel?.hash(into: &hasher)
    redoLabel?.hash(into: &hasher)
    wrappedValue.hash(into: &hasher)
  }
}

extension CheckpointState: Decodable where Value: Decodable {
  public init(from decoder: Decoder) throws {
    do {
      let container = try decoder.singleValueContainer()
      self.init(wrappedValue: try container.decode(Value.self))
    } catch {
      self.init(wrappedValue: try Value(from: decoder))
    }
  }
}

extension CheckpointState: Encodable where Value: Encodable {
  public func encode(to encoder: Encoder) throws {
    do {
      var container = encoder.singleValueContainer()
      try container.encode(self.wrappedValue)
    } catch {
      try self.wrappedValue.encode(to: encoder)
    }
  }
}

extension CheckpointState: CustomReflectable {
  public var customMirror: Mirror {
    Mirror(reflecting: self.wrappedValue)
  }
}

extension CheckpointState: CustomDumpRepresentable {
  public var customDumpValue: Any {
    self.wrappedValue
  }
}

extension CheckpointState: CustomDebugStringConvertible where Value: CustomDebugStringConvertible {
  public var debugDescription: String {
    self.wrappedValue.debugDescription
  }
}
