//  ContextOperationPerformer.swift
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
import CoreData

/**
 ContextOperationPerformer and the Eventual extension below present a suggestion for making
 the task of intesting something into CoreData more composable when using ContextOperations.
 */

public protocol ContextOperationPerformer {
    func performContextOperation<Subject>(file: StaticString, function: StaticString, line: UInt, work: @escaping (_ context: NSManagedObjectContext) throws -> Subject) -> Eventual<Subject>
    func performContextOperation<T, Subject>(withInput input: T, file: StaticString, function: StaticString, line: UInt, work: @escaping (_ input: T, _ context: NSManagedObjectContext) throws -> Subject) -> Eventual<Subject>
}

public extension Eventual {
    
    @discardableResult
    public func ingestedBy<U>(_ performer: ContextOperationPerformer,
                                file: StaticString = #file, function: StaticString = #function, line: UInt = #line,
                                using work: @escaping (Subject, NSManagedObjectContext) throws -> U) -> Eventual<U> {
        return then { value in
            return performer.performContextOperation(file: file, function: function, line: line) { (context) -> U in
                return try work(value, context)
            }
        }
    }
    
    @discardableResult
    public func ingestedBy<T, U>(_ performer: ContextOperationPerformer, withInput input: T,
                                   file: StaticString = #file, function: StaticString = #function, line: UInt = #line,
                                   using work: @escaping (Subject, T, NSManagedObjectContext) throws -> U) -> Eventual<U> {
        return then { value in
            return performer.performContextOperation(withInput: input, file: file, function: function, line: line) { (localInput, context) -> U in
                return try work(value, localInput, context)
            }
        }
    }
    
}
