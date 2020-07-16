//
//  ObservableObject.swift
//  
//
//  Created by Sergej Jaskiewicz on 08/09/2019.
//

// We use type metadata in the implementation of ObservableObject,
// but type metadata is stable only on Darwin. There are no such guarantees
// on non-Apple platforms (yet).
//
// This means that on Linux the layout of type metadata can change in a new Swift release,
// which will cause bugs that are hard to track (basically, undefined behavior).
//
// Whenever a new Swift version is available, we well test OpenCombine against it,
// and if everything works, release an update as soon as possible where the maximum
// supported Swift version is incremented.
#if !canImport(Darwin) && swift(>=5.1.50)
#warning("""
ObservableObject is not guaranteed to work on non-Apple platforms with this version \
of Swift because its implementation relies on ABI stability.

In order to fix this warning, please update to the newest version of OpenCombine, \
or create an issue at https://github.com/broadwaylamb/OpenCombine if there is no \
newer version yet.
""")
#endif

import Runtime

#if swift(>=5.1)
private protocol _ObservableObjectProperty {
    var objectWillChange: ObservableObjectPublisher? { get set }
}

extension _ObservableObjectProperty {

    fileprivate static func installPublisher(
        _ publisher: ObservableObjectPublisher,
        on publishedStorage: UnsafeMutableRawPointer
    ) {
        // It is safe to call assumingMemoryBound here because we know for sure
        // that the actual type of the pointee is Self.
        publishedStorage
            .assumingMemoryBound(to: Self.self)
            .pointee
            .objectWillChange = publisher
    }

    fileprivate static func getPublisher(
        from publishedStorage: UnsafeMutableRawPointer
    ) -> ObservableObjectPublisher? {
        // It is safe to call assumingMemoryBound here because we know for sure
        // that the actual type of the pointee is Self.
        return publishedStorage
            .assumingMemoryBound(to: Self.self)
            .pointee
            .objectWillChange
    }
}

extension Published: _ObservableObjectProperty {}
#endif

/// A type of object with a publisher that emits before the object has changed.
///
/// By default an `ObservableObject` will synthesize an `objectWillChange`
/// publisher that emits before any of its `@Published` properties changes:
///
///     class Contact : ObservableObject {
///         @Published var name: String
///         @Published var age: Int
///
///         init(name: String, age: Int) {
///             self.name = name
///             self.age = age
///         }
///
///         func haveBirthday() -> Int {
///             age += 1
///         }
///     }
///
///     let john = Contact(name: "John Appleseed", age: 24)
///     john.objectWillChange.sink { _ in print("will change") }
///     print(john.haveBirthday)
///     // Prints "will change"
///     // Prints "25"
///
public protocol ObservableObject: AnyObject {

    /// The type of publisher that emits before the object has changed.
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher
        where ObjectWillChangePublisher.Failure == Never

    /// A publisher that emits before the object has changed.
    var objectWillChange: ObjectWillChangePublisher { get }
}

extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {

    /// A publisher that emits before the object has changed.
    public var objectWillChange: ObservableObjectPublisher {
#if swift(>=5.1)
        var installedPublisher: ObservableObjectPublisher?

        let info = try! typeInfo(of: Self.self)
        for property in info.properties {
            let storage = Unmanaged
                .passUnretained(self)
                .toOpaque()
                .advanced(by: property.offset)

            guard let fieldType = property.type as? _ObservableObjectProperty.Type else {
                // Visit other fields until we meet a @Published field
                continue
            }

            // Now we know that the field is @Published.

            if let alreadyInstalledPublisher = fieldType.getPublisher(from: storage) {
                installedPublisher = alreadyInstalledPublisher
                // Don't visit other fields, as all @Published fields
                // already have a publisher installed.
                break
            }

            // Okay, this field doesn't have a publisher installed.
            // This means that other fields don't have it either
            // (because we install it only once and fields can't be added at runtime).

            var lazilyCreatedPublisher: ObjectWillChangePublisher {
                if let publisher = installedPublisher {
                    return publisher
                }
                let publisher = ObservableObjectPublisher()
                installedPublisher = publisher
                return publisher
            }

            fieldType.installPublisher(lazilyCreatedPublisher, on: storage)

            // Continue visiting other fields.
        }

        return installedPublisher ?? ObservableObjectPublisher()
#else
        // There are no @Published in Swift 5.0, so we act the same as in Swift 5.1
        // with classes without @Published properties.
        // We create a new instance every time.
        return ObservableObjectPublisher()
#endif // swift(>=5.1)
    }
}

/// The default publisher of an `ObservableObject`.
public final class ObservableObjectPublisher: Publisher {

    public typealias Output = Void

    public typealias Failure = Never

    private let lock = UnfairLock.allocate()

    private var connections = Set<Conduit>()

    // TODO: Combine needs this for some reason
    private var identifier: ObjectIdentifier?

    public init() {}

    deinit {
        lock.deallocate()
    }

    public func receive<Downstream: Subscriber>(subscriber: Downstream)
        where Downstream.Input == Void, Downstream.Failure == Never
    {
        let inner = Inner(downstream: subscriber, parent: self)
        lock.lock()
        connections.insert(inner)
        lock.unlock()
        subscriber.receive(subscription: inner)
    }

    public func send() {
        lock.lock()
        let connections = self.connections
        lock.unlock()
        for connection in connections {
            connection.send()
        }
    }

    private func remove(_ conduit: Conduit) {
        lock.lock()
        connections.remove(conduit)
        lock.unlock()
    }
}

extension ObservableObjectPublisher {
    private class Conduit: Hashable {

        fileprivate func send() {
            abstractMethod()
        }

        fileprivate static func == (lhs: Conduit, rhs: Conduit) -> Bool {
            return lhs === rhs
        }

        fileprivate func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }

    private final class Inner<Downstream: Subscriber>
        : Conduit,
          Subscription,
          CustomStringConvertible,
          CustomReflectable,
          CustomPlaygroundDisplayConvertible
        where Downstream.Input == Void, Downstream.Failure == Never
    {
        private enum State {
            case initialized
            case active
            case terminal
        }

        private weak var parent: ObservableObjectPublisher?
        private let downstream: Downstream
        private let downstreamLock = UnfairRecursiveLock.allocate()
        private let lock = UnfairLock.allocate()
        private var state = State.initialized

        init(downstream: Downstream, parent: ObservableObjectPublisher) {
            self.parent = parent
            self.downstream = downstream
        }

        deinit {
            downstreamLock.deallocate()
            lock.deallocate()
        }

        override func send() {
            lock.lock()
            let state = self.state
            lock.unlock()
            if state == .active {
                downstreamLock.lock()
                _ = downstream.receive()
                downstreamLock.unlock()
            }
        }

        func request(_ demand: Subscribers.Demand) {
            lock.lock()
            if state == .initialized {
                state = .active
            }
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            state = .terminal
            lock.unlock()
            parent?.remove(self)
        }

        var description: String { return "ObservableObjectPublisher" }

        var customMirror: Mirror {
            let children = CollectionOfOne<Mirror.Child>(("downstream", downstream))
            return Mirror(self, children: children)
        }

        var playgroundDescription: Any {
            return description
        }
    }
}
