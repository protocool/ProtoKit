//  ContextRealizable.swift
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
import CoreData

public extension NSManagedObjectContext {

    public final func realize<T>(_ object: T) throws -> T {
        switch object {
        case let realizable as ContextRealizable:
            return try realizable.realized(by: self) as! T
        case let managed as NSManagedObject:
            return try existingObject(with: managed.objectID) as! T
        default:
            return object
        }
    }
    
}

public protocol ContextRealizable {
    func realized(by context: NSManagedObjectContext) throws -> Self
}

extension Array: ContextRealizable {
    public func realized(by context: NSManagedObjectContext) throws -> Array<Element> {
        return try map { try context.realize($0) }
    }
}

extension Dictionary: ContextRealizable {
    public func realized(by context: NSManagedObjectContext) throws -> Dictionary<Key, Value> {
        var result = Dictionary<Key, Value>(minimumCapacity: count)
        for (key, value) in self {
            result[key] = (try context.realize(value))
        }
        return result
    }
}

extension Set: ContextRealizable {
    public func realized(by context: NSManagedObjectContext) throws -> Set<Element> {
        var result = Set<Element>(minimumCapacity: count)
        for element in self {
            result.insert(try context.realize(element))
        }
        return result
    }
}
