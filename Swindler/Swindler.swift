/// The state represents the entire state of the OS, including all known windows, applications, and
/// spaces.
public class State {
  let delegate: StateDelegate
  init(delegate: StateDelegate) {
    self.delegate = delegate
  }

  /// The currently running applications.
  public var runningApplications: [Application] { return delegate.runningApplications.map({ Application(delegate: $0) }) }

  /// All windows that we know about. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { return delegate.knownWindows.flatMap({ Window(delegate: $0) }) }

  /// Calls `handler` when the specified `Event` occurs.
  public func on<Event: EventType>(handler: (Event) -> ()) { delegate.on(handler) }
}

// All public classes in Swindler are implemented with an internal delegate. This decoupling aids in
// testing and hides implementation details from the API.
//
// Our delegates differ from most Apple API delegates in that they are internal and are critical to
// the functioning of the class, so they are not held with weak references.
protocol StateDelegate {
  var runningApplications: [ApplicationDelegate] { get }
  var knownWindows: [WindowDelegate] { get }
  func on<Event: EventType>(handler: (Event) -> ())
}

/// A running application.
public class Application: Equatable {
  let delegate: ApplicationDelegate
  init(delegate: ApplicationDelegate) {
    self.delegate = delegate
  }

  /// The known windows of the application. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { return delegate.knownWindows.flatMap({ Window(delegate: $0) }) }

  /// The main window of the application.
  public var mainWindow: Property<OfOptionalType<Window>> { return delegate.mainWindow }
  /// Whether the application is the frontmost application.
  public var isFrontmost: WriteableProperty<OfType<Bool>> { return delegate.isFrontmost }
}
public func ==(lhs: Application, rhs: Application) -> Bool {
  return lhs.delegate.equalTo(rhs.delegate)
}

protocol ApplicationDelegate: class {
  var knownWindows: [WindowDelegate] { get }

  var mainWindow: Property<OfOptionalType<Window>>! { get }
  var isFrontmost: WriteableProperty<OfType<Bool>>! { get }

  func equalTo(other: ApplicationDelegate) -> Bool
}

/// A window.
public class Window: Equatable {
  internal let delegate: WindowDelegate

  // A Window holds a strong reference to the Application and therefore the ApplicationDelegate.
  // It should not be held internally by delegates, or it could create a reference cycle.
  private var application_: Application!

  internal init(delegate: WindowDelegate, appDelegate: ApplicationDelegate) {
    self.delegate = delegate
    self.application_ = Application(delegate: appDelegate)
  }

  /// This initializer fails only if the ApplicationDelegate is no longer reachable (because the
  /// application terminated, which means this window no longer exists).
  internal convenience init?(delegate: WindowDelegate) {
    guard let appDelegate = delegate.appDelegate else {
      // The application terminated.
      log.debug("Window for delegate \(delegate) failed to initialize because of unreachable ApplicationDelegate")
      return nil
    }
    self.init(delegate: delegate, appDelegate: appDelegate)
  }

  /// The application the window belongs to.
  public var application: Application { return application_ }

  /// Whether or not the window referred to by this type remains valid. Windows usually become
  /// invalid because they are destroyed (in which case a WindowDestroyedEvent will be emitted).
  /// They can also become invalid because they do not have all the required properties, or because
  /// the application that owns them is otherwise not giving a well-behaved response.
  public var isValid: Bool { return delegate.isValid }

  /// The position of the top-left corner of the window in screen coordinates.
  public var position: WriteableProperty<OfType<CGPoint>> { return delegate.position }
  /// The size of the window in screen coordinates.
  public var size: WriteableProperty<OfType<CGSize>> { return delegate.size }

  /// The window title.
  public var title: Property<OfType<String>> { return delegate.title }

  /// Whether the window is minimized.
  public var isMinimized: WriteableProperty<OfType<Bool>> { return delegate.isMinimized }

  /// TODO: main, fullScreen, focused, screen, space
}
public func ==(lhs: Window, rhs: Window) -> Bool {
  return lhs.delegate.equalTo(rhs.delegate)
}

protocol WindowDelegate: class {
  var isValid: Bool { get }

  // Optional because a WindowDelegate shouldn't hold a strong reference to its parent ApplicationDelegate.
  var appDelegate: ApplicationDelegate? { get }

  var position: WriteableProperty<OfType<CGPoint>>! { get }
  var size: WriteableProperty<OfType<CGSize>>! { get }
  var title: Property<OfType<String>>! { get }
  var isMinimized: WriteableProperty<OfType<Bool>>! { get }

  func equalTo(other: WindowDelegate) -> Bool
}

// (oldSpace, newSpace, windowsArrived, windowsDeparted)
// case SpaceChanged
// (oldLayout?, newLayout)
// case ScreenLayoutChanged

/// The basic protocol for an event struct.
public protocol EventType {
  /// All events are marked as internal or external. Internal events were caused via Swindler,
  /// external events were not.
  var external: Bool { get }
}

extension EventType {
  // In a later version of Swift, this can be stored (lazily).. store as hashValue for more speed.
  // Instead of using this, we _could_ use an enum of all notifications and require each event to
  // declare a static var of its notification. That's error prone, though, and this is fast enough.
  static var typeName: String {
    return Mirror(reflecting: Self.self).description
  }
}

/// An event on a window.
public protocol WindowEventType: EventType {
  var external: Bool { get }  // TODO: remove
  /// The window corresponding to the event.
  var window: Window { get }
}

public struct WindowCreatedEvent: WindowEventType {
  public var external: Bool
  public var window: Window
}

public struct WindowDestroyedEvent: WindowEventType {
  public var external: Bool
  public var window: Window
}

/// An event describing a property change.
public protocol PropertyEventType: EventType {
  typealias PropertyType

  var external: Bool { get }
  /// The old value of the property.
  var oldValue: PropertyType { get }
  /// The new value of the property.
  var newValue: PropertyType { get }
  // TODO: requestedVal?
}

protocol PropertyEventTypeInternal: PropertyEventType {
  typealias Object
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType)
}

public protocol WindowPropertyEventType: WindowEventType, PropertyEventType {}

protocol WindowPropertyEventTypeInternal: WindowPropertyEventType, PropertyEventTypeInternal {
  typealias Object = Window
  init(external: Bool, window: Object, oldValue: PropertyType, newValue: PropertyType)
}
extension WindowPropertyEventTypeInternal {
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType) {
    self.init(external: external, window: object, oldValue: oldValue, newValue: newValue)
  }
}

public struct WindowPosChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = CGPoint
  public var external: Bool
  public var window: Window
  public var oldValue: PropertyType
  public var newValue: PropertyType
}

public struct WindowSizeChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = CGSize
  public var external: Bool
  public var window: Window
  public var oldValue: PropertyType
  public var newValue: PropertyType
}

public struct WindowTitleChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = String
  public var external: Bool
  public var window: Window
  public var oldValue: PropertyType
  public var newValue: PropertyType
}

public struct WindowMinimizedChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = Bool
  public var external: Bool
  public var window: Window
  public var oldValue: PropertyType
  public var newValue: PropertyType
}

public protocol ApplicationEventType: EventType {
  var application: Application { get }
}

public protocol ApplicationPropertyEventType: ApplicationEventType, PropertyEventType {}

protocol ApplicationPropertyEventTypeInternal: ApplicationPropertyEventType, PropertyEventTypeInternal {
  typealias Object = Application
  init(external: Bool, application: Object, oldValue: PropertyType, newValue: PropertyType)
}
extension ApplicationPropertyEventTypeInternal {
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType) {
    self.init(external: external, application: object, oldValue: oldValue, newValue: newValue)
  }
}

public struct ApplicationFrontmostChangedEvent: ApplicationPropertyEventTypeInternal {
  public typealias PropertyType = Bool
  public var external: Bool
  public var application: Application
  public var oldValue: PropertyType
  public var newValue: PropertyType
}

public struct ApplicationMainWindowChangedEvent: ApplicationPropertyEventTypeInternal {
  public typealias PropertyType = Window?
  public var external: Bool
  public var application: Application
  public var oldValue: PropertyType
  public var newValue: PropertyType
}
