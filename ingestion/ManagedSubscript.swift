//
//  ManagedSubscript.swift
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
 The ManagedSubscript protocol extends `NSManagedObject` instances to expose a
 subscript that performs an inequality check before actually setting the value,
 avoiding needlessly dirtying the receiver when the value is unchanged.
 
 Example:
 ```
 let track = methodFetchingTrack()
 
 // The track will be considered 'changed'
 // even if no actual change too place:
 
 track.album = track.album
 
 // You avoid the database write and cross-context
 // change propagation by first checking for
 // inequality, but it gets tiresome if you're doing
 // a few assignments.
 
 if track.album != album {
   track.album = album
 }

 // Instead, you can use the `managed` subscript,
 // which does the inequality check for you.
 
 track[managed: \.album] = album
 ```
 
 ***
 
 There isn't much point to using the `managed` subscript as a getter because it
 is limited to `ReferenceWritableKeyPath`, which is pointlessly restrictive for
 a getter.
 
 If a callsite using the `managed` subscript is giving you strange errors, rewrite
 it as `[keyPath: \FullTypeName.accessor]` and recompile.
 
 - If the code builds without error, then the accessor's type may not be Equatable.
 
   Types which can be modelled by CoreData are all equatable, so if this happens,
   it's likely because you're using a custom accessor. Either make the offending
   type Equatable, or move the inequality check to your accessor's setter, where it
   is calling the modelled property setter.

 - If the code still has errors when using the `keyPath` subscript, it's probable
   that you've either mistyped the keypath, or you're trying to assign properties
   across members (especially where part of the keypath is optional).
 
   Don't do this. Call the accessors directly (with optional chaining) and append
   the `managed` subscript at the end of the chain where you want to actually perform
   the inequality check.
 */
public protocol ManagedSubscript: class {}

public extension ManagedSubscript where Self: NSManagedObject {
    subscript<T>(managed path: ReferenceWritableKeyPath<Self, T>) -> T where T: Equatable {
        get { return self[keyPath: path] }
        set {
            if self[keyPath: path] != newValue {
                self[keyPath: path] = newValue
            }
        }
    }
    
    #if swift(>=4.2)
    #else
    subscript<T>(managed path: ReferenceWritableKeyPath<Self, T?>) ->T? where T: Equatable {
        get { return self[keyPath: path] }
        set {
            if self[keyPath: path] != newValue {
                self[keyPath: path] = newValue
            }
        }
    }
    subscript<T>(managed path: ReferenceWritableKeyPath<Self, ImplicitlyUnwrappedOptional<T>>) -> T! where T: Equatable {
        get { return self[keyPath: path] }
        set {
            if self[keyPath: path] != newValue {
                self[keyPath: path] = newValue ?? nil
            }
        }
    }
    #endif
}
