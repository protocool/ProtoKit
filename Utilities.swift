//  Utilities.swift
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

extension Optional {

    public func forSome(_ work: (Wrapped) throws -> Void) rethrows {
        guard case .some(let value) = self else { return }
        try work(value)
    }
    
}

public extension DispatchQueue {
    /**
     Enqueue a closure for execution, roughly `interval` seconds from now, on a given queue.
     
     - parameter interval: The amount of time, meastured as an NSTimeInterval, to wait before executing the block
     - parameter on: A dispatch_queue on which to execute the block. Defaults to `dispatch_get_main_queue()`.
     - parameter work: The closure to execute.
     */
    public func asyncAfter(interval: TimeInterval, execute work: @escaping @convention(block) () -> Void) {
        asyncAfter(deadline: DispatchTime.now() + interval, execute: work)
    }
}

public extension Array {
    
    public mutating func remove(at indexes: IndexSet) -> [Element] {
        var removed: [Element] = []
        removed.reserveCapacity(indexes.count)
        
        for index in indexes.reversed() {
            removed.append(remove(at: index))
        }
        
        return removed.reversed()
    }
    
    public subscript (indexes: IndexSet) -> [Element] {
        get { return indexes.map { self[$0] } }
    }
    
}

public extension MutableCollection where Self : RandomAccessCollection, Iterator.Element : NSObject {
    
    public mutating func sort(using descriptors: [NSSortDescriptor]) {
        self.sort {
            for descriptor in descriptors {
                switch descriptor.compare($0, to: $1) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }
    
}

public extension Sequence where Iterator.Element : NSObject {
    
    public func sorted(using descriptors: [NSSortDescriptor]) -> [Self.Iterator.Element] {
        return sorted {
            for descriptor in descriptors {
                switch descriptor.compare($0, to: $1) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }
    
}
