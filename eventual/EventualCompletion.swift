//  EventualCompletion.swift
//
//  ProtoKit
//  Copyright © 2016 Trevor Squires.
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
 receive the result of the `Eventual`. It is designed to make it easy to expose a more trational "trailing completion
 block" API to callers, hiding any underlying `Eventual` objects as an implementation detail.
 
 If you wish to expose a cancellation facility to callers, you should vend an `NSProgress` object configured with a
 `cancellationHandler` that cancels the underlying unit of work (which would typically generate an NSUserCancelledError
 for propagation to downstream consumers).
 
 If your preference is to simply not execute the EventualCompletion's completion block on cancellation (similar to the
 behavior of `NSURLConnection.cancel()`), then your `cancellationHandler` block may call the `EventualCompletion`
 `disposeHandler()` prior cancelling any outstanding work. However, you are strongly discouraged from using `disposeHandler()` 
 if your completion block exposes the eventual `Error?` to callers: developers who are familiar with modern system APIs
 (such as NSURLSession) will expect cancellations to be reported as an NSUserCancelledError.
 
 There is no need to directly retain a reference to an `EventualCompletion` once it has been constructed, unless you intend
 to call `disposeHandler()`.
 */

public final class EventualCompletion<Subject> {

    private typealias ResultHandler = (EventualResult<Subject>) -> Void
    
    private let lockQueue: DispatchQueue = DispatchQueue(label: "com.protocool.ProtoKit.EventualCompletion.lock")
    private var resultHandler: ResultHandler?
    
    /**
     Creates an EventualCompletion instance which will, unless cancelled, pass the eventual result to the supplied result handler when it is ready.
    
     You do not need to maintain a reference to the EventualCompletion except to (optionally) call `disposeHandler()` at a later time.
    
     - important: The `resultHandler` closure executes on the main queue some time after control has returned to the caller.
     - parameter with: The underlying `Eventual` generating the result.
     - parameter resultHandler: A closure which accepts an `EventualResult`.
     - seealso: `Eventual`
     - seealso: `EventualResult`
     */
    public init(with eventual: Eventual<Subject>, resultHandler: @escaping (EventualResult<Subject>) -> Void) {
        self.resultHandler = resultHandler
        
        eventual.either { result -> Void in
            var handler: ResultHandler?
            self.lockQueue.sync {
                handler = self.resultHandler
                self.resultHandler = nil
            }

            handler?(result)
        }
    }
    
    /**
     Creates an EventualCompletion instance which will, unless cancelled, pass the eventual result to the supplied completion handler when it is ready.
     
     You do not need to maintain a reference to the EventualCompletion except to (optionally) call `disposeHandler()` at a later time.
     
     - important: The `completionHandler` closure executes on the main queue some time after control has returned to the caller.
     - parameter with: The underlying `Eventual` generating the result.
     - parameter resultHandler: A closure which accepts an optional generic `Subject` value and an optional `Error`.
     - seealso: `Eventual`
     - seealso: `EventualResult`
     */
    public convenience init(with eventual: Eventual<Subject>, completionHandler: @escaping (Subject?, Error?) -> Void) {
        self.init(with: eventual, resultHandler: { result in
            switch result {
            case .value(let value):
                completionHandler(value, nil)
            case .error(let error):
                completionHandler(nil, error)
            }
        })
    }
    
    
    /**
     Releases the result handler closure so that it will not be executed if the Eventual resolves after control is returned to the caller.

     - important: Although this method is safe to call from any queue, non-main-queue callers cannot safely make inferences about whether
                  the result handler closure is currently executing or has finished executing. On the main queue, callers can infer that,
                  once control has been returned, either the handler closure will not execute, or it has already finished executing.
     */
    public func disposeHandler() {
        lockQueue.sync {
            self.resultHandler = nil
        }
    }
}

