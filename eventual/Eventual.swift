//  Eventual.swift
//
//  ProtoKit
//  Copyright © 2016-2017 Trevor Squires.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

/**
 An Eventual object represents a possibly as yet unknown `Subject` value.
 
 Eventual is intended to replace the increasingly long-in-the-tooth ZDSDeferred/ZDSPromise classes, which
 are cumbersome to use in Swift 2+ and which suffer from significant usage compromises due to the need for
 built-in cancellation support (a facility that's now better left to NSProgress).
 
 The most significant departures from ZDSDeferred/ZDSPromise are:
 
 -  Eventual results are immutable, shared, and strongly-typed. Transformations result in new Eventual 
    instances rather than causing updates to a notional 'current' value.
 -  The resolve and reject functions are now private and only exposed as function references, which are passed
    to the Eventual's initialization closure (this should feel familiar to anyone who's used JavaScript promises).
 -  Arbitrary 'rejected' values are no longer supported. An eventual's result is either the `Subject` value,
    or an `Error` describing a failure.
 -  Cancellation, and all associated semantics, has been removed. Surfacing UI-initiated task cancellation should 
    now be done with NSProgress.
 -  Now that cancellation support has been removed, transformation methods (then/either/trap) are able to guarantee
    to return control to the caller before the supplied processing block executes.
 -  Eventual processing blocks have a stricter guarantee to run on the main queue, rather than just a
    guarantee to run on the main thread.

 Some of those design decisions aren't sitting well with me any more... In particular, I'm starting to think that
 limiting access to the `resolve` and `reject` methods just adds clunkiness in the name of correctness, for no
 real-world benefit. In all the code built on ZDSDeferred and ZDSPromise, nobody ever actually hijacked a resolution.
 */

public final class Eventual<Subject>: ResultProcessor {
    
    /**
     Creates an `Eventual` instance that is waiting for a result, typically from delegate callbacks
     or other sources that don't expose their outcomes as completion blocks.
     - returns: a tuple of three elements: the `Eventual` instance, its private `resolve` function, and 
     its private `reject` function.
     */
    public class func make() -> (eventual: Eventual, resolve: (Subject) -> Void, reject: (Error) -> Void) {
        let eventual = Eventual<Subject>()
        return (eventual, eventual.resolve, eventual.reject)
    }
    
    /**
     Creates an `Eventual` instance that is waiting for a result, typically from completion blocks.
     - parameter prepareWork: a closure which executes immediately on the current thread (before control is returned
     to the caller) and is passed references to the `Eventual` instance's private `resolve` and `reject`
     functions for later use once a result is available.
     
     Example:
     ```
     Eventual<CKRecord?> { (resolve, reject) in
         database.fetchRecordWithID(recordID, completionHandler: { (maybeRecord, maybeError) in
             if let error = maybeError {
                reject(error)
             }
             else {
                resolve(maybeRecord)
             }
         })
     }
     ```
     */
    public convenience init(prepareWork: (_ resolve: @escaping (Subject) -> Void, _ reject: @escaping (Error) -> Void) throws -> Void) {
        self.init()
        do {
            try prepareWork(self.resolve, self.reject)
        } catch {
            reject(error)
        }
    }
    
    /**
     Creates an `Eventual` instance that has an immediately available `.value` result.
     - parameter value: the result's associated value instance
     
     Example:
     ```
     Eventual<String>("something")
     Eventual("something else")
     ```
     */
    public convenience init(value: Subject) {
        self.init()
        result = .value(value)
        isDistributable = true
    }
    
    /**
     Creates an `Eventual` instance that has an immediately available `.error` result.
     - parameter error: the result's associated `Error` instance
     
     Example:
     ```
     Eventual<String>(error: anError)
     ```
     */
    public convenience init(error: Error) {
        self.init()
        result = .error(error)
        isDistributable = true
    }

    /**
     Checks whether the receiver's result is available yet.
     - note: Not recommended for common-case usage. Unless it's critical to avoid starting
     unnecessary work while you wait for the available result to be delivered in a
     callback on the next spin of the runloop, the complexity of manually checking
     for a result is not worth it.
     - precondition: May only be called from the main thread.
     - returns: true iff the receiver has an available value or error
    */
    public var hasResult: Bool {
        precondition(Thread.isMainThread, "Eventual.hasResult is unsafe when called off the main thread")
        return result != nil
    }

    /**
     Retrieves the receiver's result, either as a returned value or a thrown error.
     - note: Not recommended for common-case usage. Unless it's critical to avoid starting
     unnecessary work while you wait for the available result to be delivered in a
     callback on the next spin of the runloop, the complexity of manually checking
     for a result is not worth it.
     - precondition: May only be called from the main thread.
     - precondition: The result must be available. In other words, `hasResult` must be true.
     - throws: The associated error object if the receiver's result is an `.error`
     - returns: The associated value object if the receiver's result is a `.value`
     */
    public func checkedValue() throws -> Subject {
        precondition(Thread.isMainThread, "Eventual.checkedVaue() is unsafe when called off the main thread")
        guard let result = result else {
            preconditionFailure("Eventual.checkedValue() called before result was available")
        }

        return try result.checkedValue()
    }
    
    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available iff that result is a successful `.value`.
     If the receiver's result is an `.error`, then the vended eventual will inherit the `.error` and the supplied closure will be discarded without execution.
     
     The value returned by the closure will be used as the vended Eventual's result `.value`, while any error thrown by the closure will be captured as the vended Eventual's `.error`.
     
     - parameter processValue: A closure which accepts a Subject value and returns another value.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func then<U>(_ processValue: @escaping (Subject) throws -> U) -> Eventual<U> {
        let eventual = Eventual<U>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                switch result {
                case .value(let inputValue):
                    eventual.result = .value(try processValue(inputValue))
                case .error(let error):
                    eventual.result = .error(error)
                }
            }
            catch {
                eventual.result = .error(error)
            }
        }
        
        addProcessor(eventual)
        return eventual
    }
    
    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available iff that result is a successful `.value`.
     If the receiver's result is an `.error`, the vended eventual will inherit the `.error` and the supplied closure will be discarded without execution.
     
     The closure itself returns an Eventual whose result, when available, will be used as the result (whether a `.value` or an `.error`) for the vended Eventual.
     If the closure throws an error, it will be captured as the vended Eventual's `.error`.
     
     - parameter processValue: A closure which accepts a Subject value and returns an Eventual.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func then<U>(_ processValue: @escaping (Subject) throws -> Eventual<U>) -> Eventual<U> {
        let eventual = Eventual<U>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                switch result {
                case .value(let inputValue):
                    let processedEventual = try processValue(inputValue)
                    guard let processedEventualResult = processedEventual.result else {
                        eventual.processWork = { [unowned processedEventual] in
                            guard let result = processedEventual.result else {
                                preconditionFailure("nil result during processWork()")
                            }
                            eventual.result = result
                        }
                        processedEventual.addProcessor(eventual)
                        return
                    }
                    eventual.result = processedEventualResult
                case .error(let error):
                    eventual.result = .error(error)
                }
            }
            catch {
                eventual.result = .error(error)
            }
        }
        
        addProcessor(eventual)
        return eventual
    }

    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available iff that result is a successful `.value`.
     If the receiver's result is an `.error`, then the vended eventual will inherit the `.error` and the supplied closure will be discarded without execution.
     
     After the closure has finished executing, the receiver's `.value` will be used as the vended Eventual's result `.value`. If an error thrown by the closure, 
     it will be captured as the vended Eventual's `.error`.
     
     - parameter processValue: A closure which accepts a Subject value.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func then(_ processValue: @escaping (Subject) throws -> Void) -> Eventual<Subject> {
        let eventual = Eventual<Subject>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                if case .value(let inputValue) = result {
                    try processValue(inputValue)
                }
                
                eventual.result = result
            }
            catch {
                eventual.result = .error(error)
            }
        }
        
        addProcessor(eventual)
        return eventual
    }

    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available iff that result is an `.error`.
     If the receiver's result is a successful `.value`, then the vended eventual will inherit the `.value` and the supplied closure will be discarded without execution.
     
     The closure itself returns an Eventual whose result, when available, will be used as the result (whether a `.value` or an `.error`) for the vended Eventual.
     If the closure throws an error, it will be captured as the vended Eventual's `.error`.
     
     - note: The Subject type for the vended Eventual must be the same type as used by the receiver.
     - parameter processError: A closure which accepts an Error and returns an Eventual.
     - returns: A new Eventual instance.
     */

    @discardableResult
    public func trap(_ processError: @escaping (Error) throws -> Eventual<Subject>) -> Eventual<Subject> {
        let eventual = Eventual<Subject>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                switch result {
                case .value:
                    eventual.result = result
                case .error(let inputError):
                    let processedEventual = try processError(inputError)
                    guard let processedEventualResult = processedEventual.result else {
                        eventual.processWork = { [unowned processedEventual] in
                            guard let innerResult = processedEventual.result else {
                                preconditionFailure("nil result during processWork()")
                            }
                            eventual.result = innerResult
                        }
                        processedEventual.addProcessor(eventual)
                        return
                    }
                    eventual.result = processedEventualResult
                }
            }
            catch {
                eventual.result = .error(error)
            }
        }

        addProcessor(eventual)
        return eventual
    }
    
    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available iff that result is an `.error`.
     If the receiver's result is a successful `.value`, then the vended eventual will inherit the `.value` and the supplied closure will be discarded without execution.
     
     After the closure has finished executing, the receiver's `.error` will be used as the vended Eventual's result `.error`. If an error thrown by the closure,
     it will be captured as the vended Eventual's `.error` instead.
     
     - parameter processError: A closure which accepts an Error value.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func trap(_ processError: @escaping (Error) throws -> Void) -> Eventual<Subject> {
        let eventual = Eventual<Subject>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                if case .error(let inputError) = result {
                    try processError(inputError)
                }
                
                eventual.result = result
            }
            catch {
                eventual.result = .error(error)
            }
        }

        addProcessor(eventual)
        return eventual
    }

    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available.
     
     The value returned by the closure will be used as the vended Eventual's result `.value`, while any error thrown by the closure will be captured as the vended Eventual's `.error`.
     
     - parameter processResult: A closure which accepts an EventualResult<Subject> and returns a value.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func either<U>(_ processResult: @escaping (EventualResult<Subject>) throws -> U) -> Eventual<U> {
        let eventual = Eventual<U>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                eventual.result = .value(try processResult(result))
            }
            catch {
                eventual.result = .error(error)
            }
        }

        addProcessor(eventual)
        return eventual
    }
    
    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available.
     
     The closure itself returns an Eventual whose result, when available, will be used as the result (whether a `.value` or an `.error`) for the vended Eventual.
     If the closure throws an error, it will be captured as the vended Eventual's `.error`.
     
     - parameter processResult: A closure which accepts and EventualResult<Subject> and returns an Eventual.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func either<U>(_ processResult: @escaping (EventualResult<Subject>) throws -> Eventual<U>) -> Eventual<U> {
        let eventual = Eventual<U>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                let processedEventual: Eventual<U> = try processResult(result)
                
                guard let processedEventualResult = processedEventual.result else {
                    eventual.processWork = { [unowned processedEventual] in
                        guard let result = processedEventual.result else {
                            preconditionFailure("nil result during processWork()")
                        }
                        eventual.result = result
                    }
                    processedEventual.addProcessor(eventual)
                    return
                }
                
                eventual.result = processedEventualResult
            }
            catch {
                eventual.result = .error(error)
            }
        }

        addProcessor(eventual)
        return eventual
    }
    
    /**
     Vends a new Eventual instance which executes the supplied closure when the receiver's result becomes available.
     
     After the closure has finished executing, the receiver's result will be used as the vended Eventual's result. If an error thrown by the closure,
     it will be captured as the vended Eventual's `.error`.
     
     - parameter processResult: A closure which accepts an EventualResult<Subject>.
     - returns: A new Eventual instance.
     */
    @discardableResult
    public func either(_ processResult: @escaping (EventualResult<Subject>) throws -> Void) -> Eventual<Subject> {
        let eventual = Eventual<Subject>()
        eventual.processWork = { [unowned self] in
            do {
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                try processResult(result)
                eventual.result = result
            }
            catch {
                eventual.result = .error(error)
            }
        }

        addProcessor(eventual)
        return eventual
    }
    
    /**
     Vends a new Eventual instance with a Void subject type.
     
     - returns: A new Eventual instance.
     */
    public func asVoid() -> Eventual<Void> {
        let eventual = Eventual<Void>()
        
        // asVoid() is often used for erasure when gathering heterogeneous outcomes using Eventual.results(of:),
        // which tries to avoid unnecessary async-waiting when all results are ready immediately, so we should
        // avoid contributing to async-waiting ourselves.
        
        if Thread.isMainThread, let readyResult = result {
            switch readyResult {
            case .value:
                eventual.result = .value(())
            case .error(let error):
                eventual.result = .error(error)
            }
            
            eventual.isDistributable = true
        }
        else {
            eventual.processWork = { [unowned self] in
                guard let result = self.result else {
                    preconditionFailure("nil result during processWork()")
                }
                
                switch result {
                case .value:
                    eventual.result = .value(())
                case .error(let error):
                    eventual.result = .error(error)
                }
            }
            
            addProcessor(eventual)
        }

        return eventual
    }

    // Designated initializer is intentionally private b/c external callers have
    // no way to resolve an Eventual that's been intialized like this.
    private init() {}

    private var processWork: Optional<() -> Void> = nil

    private let processorQueue: DispatchQueue = DispatchQueue(label: "com.protocool.ProtoKit.Eventual.processor")
    private var processors: [ResultProcessor] = []
    private var result: EventualResult<Subject>? = nil
    
    private var isDistributable: Bool = false
    private var isScheduled: Bool = false
    
    private func addProcessor(_ processor: ResultProcessor) {
        processorQueue.sync {
            self.processors.append(processor)
            guard self.isDistributable && self.isScheduled == false else { return }

            self.isScheduled = true
            DispatchQueue.main.async {
                distributeResultToProcessors(of: self)
            }
        }
    }

    private func resolve(_ value: Subject) {
        consume(.value(value))
    }
    
    private func reject(_ error: Error) {
        consume(.error(error))
    }

    private func consume(_ input: EventualResult<Subject>) {
        // Our internal result is only safe to read/write from the main _thread_.
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.consume(input)
            }
            return
        }
        
        guard result == nil else { return }
        
        result = input
        
        // Processor blocks must only be called from the main _queue_.
        if isExecutingOnMainQueue() {
            distributeResultToProcessors(of: self)
        }
        else {
            DispatchQueue.main.async {
                distributeResultToProcessors(of: self)
            }
        }
    }
    
    fileprivate func process() {
        assert(isExecutingOnMainQueue(), "Eventual.process() can only be called on the main queue")
        guard let work = processWork else {
            preconditionFailure("nil processWork block during Eventual.process()")
        }
        
        processWork = nil
        work()
    }

    fileprivate func surrenderProcessors() -> [ResultProcessor] {
        var surrendered: [ResultProcessor]!
        processorQueue.sync {
            surrendered = self.processors
            self.processors = []
            self.isDistributable = true
            self.isScheduled = false
        }
        return surrendered
    }

}

/// A type that represents either the eventual Subject value, or an Error describing a failure.
public enum EventualResult<Subject> {
    case value(Subject)
    case error(Error)
    
    /**
     Retrieves the receiver's Subject `.value`.
     - throws: The associated error object if the receiver is an `.error`.
     - returns: The associated value object if the receiver is a `.value`.
     */
    public func checkedValue() throws -> Subject {
        switch self {
        case .value(let value):
            return value
        case .error(let error):
            throw error
        }
    }
}

public extension DispatchQueue {
    /**
     Vends an eventual instance which will be resolved using the outcome of asynchronously executing the supplied closure on the receiver.
     
     The value returned by the closure will be used as the vended Eventual's result `.value`, while any error thrown by the closure will be captured as the vended Eventual's `.error`.
     
     - parameter work: A closure which returns a value.
     - returns: A new Eventual instance.
     */
    public func eventually<Subject>(execute work: @escaping () throws -> Subject) -> Eventual<Subject> {
        return Eventual<Subject> { (resolve, reject) -> Void in
            async {
                do { resolve(try work()) }
                catch { reject(error) }
            }
        }
    }
    
    /**
     Vends an eventual instance which will be resolved using the outcome of asynchronously executing the supplied closure on the receiver.
     
     The closure itself returns an Eventual whose result, when available, will be used as the result (whether a `.value` or an `.error`) for the vended Eventual.
     If the closure throws an error, it will be captured as the vended Eventual's `.error`.
     
     - parameter work: A closure which returns an Eventual.
     - returns: A new Eventual instance.
     */
    public func eventually<Subject>(execute work: @escaping () throws -> Eventual<Subject>) -> Eventual<Subject> {
        return Eventual<Subject> { (resolve, reject) -> Void in
            async {
                do {
                    try work().either { result in
                        switch result {
                        case .value(let value): resolve(value)
                        case .error(let error): reject(error)
                        }
                    }
                }
                catch { reject(error) }
            }
        }
    }
}

private var mainQueueMarkerKey: DispatchSpecificKey<Bool> = {
    let markerKey = DispatchSpecificKey<Bool>()
    DispatchQueue.main.setSpecific(key: markerKey, value: true)
    return markerKey
}()

private func isExecutingOnMainQueue() -> Bool {
    return DispatchQueue.getSpecific(key: mainQueueMarkerKey) == true
}

private func distributeResultToProcessors(of initial: ResultProcessor) {
    assert(isExecutingOnMainQueue(), "distributeResultToProcessors(of:) can only be called on the main queue")
    
    var processor: ResultProcessor? = initial
    while let current = processor, current.hasResult {
        let surrenderedProcessors = current.surrenderProcessors()

        guard surrenderedProcessors.count == 1, let single = surrenderedProcessors.first else {
            // More than one processor. Requires backtracking, but we're lazy, so we distribute recursively.
            for processor in surrenderedProcessors {
                processor.process()
                distributeResultToProcessors(of:processor)
            }
            return
        }

        // A single processor means no backtracking, so we iterate.
        single.process()
        processor = single
    }
}

private protocol ResultProcessor {
    var hasResult: Bool { get }
    func process()
    func surrenderProcessors() -> [ResultProcessor]
}
