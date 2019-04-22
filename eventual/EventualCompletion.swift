//  EventualCompletion.swift
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
 An EventualCompletion object encapsulates a supplied `Eventual` and a supplied completion block which is waiting to
 receive the result of the `Eventual`. It is intended to make it easy to expose a more trational "trailing completion
 block" API to callers, hiding any underlying `Eventual` objects as an implementation detail.
 
 Trailing completion blocks are an effective API design tool when you're trying to discourage callers from coordinating
 complicated asynchronous flows: the resulting "pyramid of doom" is unpleasant to work with, so the offending coordonation
 logic is (usually) quickly identified as something to be moved to a lower layer.
 
 EventualCompletion conforms to ProgressReporting, so that you may vend the Progress object to your callers.
 
 The progress object is set up with a cancellationHandler, such that, if `progress.cancel()` is called on the main thread,
 the originally-supplied trailing completion block will have been called (passing CocoaError(.userCancelled) as the error)
 by the time `progress.cancel()` has returned.
 
 */

public final class EventualCompletion<Subject>: NSObject, ProgressReporting {
    
    public let progress: Progress
    
    /**
     Creates an EventualCompletion instance which will, unless cancelled, pass the eventual result to the supplied result handler when it is ready.
     
     You do not need to maintain a reference to the EventualCompletion.
     
     - important: The `resultHandler` closure executes on the main queue some time after control has returned to the caller.
     - parameter with: The underlying `Eventual` generating the result.
     - parameter trackedBy: An optional discrete Progress which is tracking the work of the supplied underlying Eventual.
     - parameter resultHandler: A closure which accepts an `EventualResult`.
     - seealso: `Eventual`
     - seealso: `EventualResult`
     */
    @discardableResult
    public init(with eventual: Eventual<Subject>, trackedBy underlyingProgress: Progress? = nil, resultHandler: @escaping (EventualResult<Subject>) -> Void) {
        let singleCompletion = SingleCompletion(resultHandler)
        let progress = CompletionProgress(completion: singleCompletion)
        
        eventual.either { result in
            if underlyingProgress == nil {
                progress.completedUnitCount = progress.totalUnitCount
            }
            
            singleCompletion.complete(with: result)
        }
        
        if let child = underlyingProgress {
            progress.addChild(child, withPendingUnitCount: 1)
        }
        else if Thread.isMainThread, eventual.hasResult {
            // We know the `either` has already been scheduled to run
            // after this spin of the runloop. We can help callers
            // avoid unnecessary work by eagerly indicating that the
            // underlying work is complete.
            progress.completedUnitCount = progress.totalUnitCount
        }
        
        self.progress = progress
    }
    
    /**
     Creates an EventualCompletion instance which will, unless cancelled, pass the eventual result to the supplied completion handler when it is ready.
     
     You do not need to maintain a reference to the EventualCompletion.
     
     - important: The `completionHandler` closure executes on the main queue some time after control has returned to the caller.
     - parameter with: The underlying `Eventual` generating the result.
     - parameter trackedBy: An optional discrete Progress which is tracking the work of the supplied underlying Eventual.
     - parameter completionHandler: A closure which accepts an optional generic `Subject` value and an optional `Error`.
     - seealso: `Eventual`
     - seealso: `EventualResult`
     */
    @discardableResult
    public convenience init(with eventual: Eventual<Subject>, trackedBy childProgress: Progress? = nil, completionHandler: @escaping (Subject?, Error?) -> Void) {
        self.init(with: eventual, trackedBy: childProgress, resultHandler: { result in
            switch result {
            case .value(let value):
                completionHandler(value, nil)
            case .error(let error):
                completionHandler(nil, error)
            }
        })
    }
    
    private class SingleCompletion {
        private var resultHandler: ((EventualResult<Subject>) -> Void)?
        
        init(_ resultHandler: @escaping (EventualResult<Subject>) -> Void) {
            self.resultHandler = resultHandler
        }
        
        func complete(with result: EventualResult<Subject>) {
            precondition(Thread.isMainThread, "Internal consistency violated: complete() should only be called from the main thread.")
            
            guard let handler = resultHandler else { return }
            resultHandler = nil
            
            handler(result)
        }
        
        func cancel() {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self.cancel() }
                return
            }
            
            complete(with: .error(CocoaError(.userCancelled)))
        }
    }
    
    private class CompletionProgress: Progress {
        private let completion: SingleCompletion
        
        init(completion: SingleCompletion) {
            self.completion = completion
            super.init(parent: nil, userInfo: nil)
            
            totalUnitCount = 1
        }
        
        override func cancel() {
            super.cancel()
            completion.cancel()
        }
    }

}

public extension Eventual {
    
    @discardableResult
    func yieldingResult(trackedBy progress: Progress? = nil, toHandler resultHandler: @escaping (EventualResult<Subject>) -> Void) -> Progress {
        return EventualCompletion(with: self, trackedBy: progress, resultHandler: resultHandler)
            .progress
    }
    
    @discardableResult
    func yieldingCompletion(trackedBy progress: Progress? = nil, toHandler completionHandler: @escaping (Subject?, Error?) -> Void) -> Progress {
        return EventualCompletion(with: self, trackedBy: progress, completionHandler: completionHandler)
            .progress
    }
    
    @discardableResult
    func yieldingSuccess(trackedBy progress: Progress? = nil, toHandler successHandler: @escaping (Bool, Error?) -> Void) -> Progress {
        let completion = EventualCompletion(with: self, trackedBy: progress, resultHandler: {
            switch $0 {
            case .value:
                successHandler(true, nil)
            case .error(let error):
                successHandler(false, error)
            }
        })
        
        return completion.progress
    }
    
}
