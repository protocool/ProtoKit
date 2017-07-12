//  EventualIterator.swift
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
 An EventualIterator encapsulates the task of repeatedly generating an Eventual until some condition is met,
 similar to AnyIterator.
 */

public struct EventualIterator {
    
    /**
     The overall generation progress. It is initially created as indeterminate, with a
     total unit count of -1.
     -  note: It is up to the creator of the EventualIterator to ensure that this progress
        object accurately reflects the state of the generator. If the generator is cancellable,
        the creator of the EventualIterator should ensure that the generation block checks
        the cancellation state of the progress periodically.
     */
    public let progress: Progress

    /**
     A Void Eventual which will be resolved either when the generation block returns nil or
     it throws an error.
     */
    public let eventual: Eventual<Void>
    
    /**
     Creates an `EventualIterator` instance that repeatedly executes the supplied closure,
     waiting for the returned Eventual to become resolved before executing the closure again,
     until the closure either returns nil or throws an error.
     - parameter work: A closure which accepts a Progress and an Optional previous EventualResult, returning an Optional Eventual
     */
    public init<Subject>(work: @escaping (_ progress: Progress, _ previousResult: EventualResult<Subject>?) throws -> Eventual<Subject>?) {
        let generatorProgress = Progress.discreteProgress(totalUnitCount: -1)
        self.progress = generatorProgress
        
        var previousResult: EventualResult<Subject>? = nil
        
        let (eventual, resolve, reject) = Eventual<Void>.make()
        self.eventual = eventual

        DispatchQueue.main.async {
            // Ahoy! A recursive nested function
            func performWorkCycle() {
                do {
                    // that passes the progress and any previous result to the work closure
                    if let workEventual = try work(generatorProgress, previousResult) {
                        // which immediately returns an Eventual
                        workEventual.either { result -> Void in
                            // whose result will arrive some time later
                            previousResult = result
                            // allowing us to repeat the cycle
                            performWorkCycle()
                        }
                    }
                    else {
                        // until the work closure returns nil, signalling that we're done
                        resolve()
                    }
                }
                catch {
                    // or until the work closure throws an error, which also signals that we're done
                    reject(error)
                }
            }
            
            performWorkCycle()
        }
    }
}

public extension Eventual {
    
    public static func results<T: Collection>(of collection: T) -> Eventual<[EventualResult<Subject>]> where T.Iterator.Element: Eventual<Subject> {
        var input = collection.makeIterator()
        var results: [EventualResult<Subject>] = []
        
        // If possible, we consume the elements of the collection's iterator,
        // immediately gathering results until we encounter one that isn't yet
        // available, handing over to EventualIterator as appropriate.
        
        var nextElement: Eventual<Subject>? = input.next()
        
        if Thread.isMainThread {
            while let current = nextElement, current.hasResult {
                do { results.append(.value(try current.checkedValue())) }
                catch { results.append(.error(error)) }
                
                nextElement = input.next()
            }
        }
        
        // If there is no nextElement waiting for a result, then we're done.
        if nextElement == nil {
            return Eventual<[EventualResult<Subject>]>(value: results)
        }
        
        // Otherwise, use an EventualIterator to wait for the remaining elements.
        let iterator = EventualIterator { _ -> Eventual<Subject>? in
            return nextElement?.either { result -> Void in
                results.append(result)
                nextElement = input.next()
            }
        }
        
        return iterator.eventual.either { _ in return results }
    }

    public static func resultValues<T: Collection>(of collection: T) -> Eventual<[Subject]> where T.Iterator.Element: Eventual<Subject> {
        let pending = results(of: collection)
        
        guard pending.hasResult else {
            return pending.then { try $0.map { try $0.checkedValue() } }
        }
        
        do {
            return Eventual<[Subject]>(value: try pending.checkedValue().map({ try $0.checkedValue() }))
        }
        catch {
            return Eventual<[Subject]>(error: error)
        }
    }
}
