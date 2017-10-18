//  PayloadApplicator.swift
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

/// `PayloadApplicator` is a type erased wrapper around `PayloadMap<T>`, used by
/// a `PayloadIngester` for applying a given payload's values to a managed object.
public final class PayloadApplicator<ManagedObject: NSManagedObject> {
    private let apply: (Dictionary<String, Any>, ManagedObject) throws -> Void
    
    public init<T>(payloadMap: PayloadMap<T>) where T.ManagedObject == ManagedObject {
        apply = payloadMap.applyValuesForKeys(from:to:)
    }
    
    public func applyValuesForKeys(from dictionary: Dictionary<String, Any>, to managedObject: ManagedObject) throws {
        try apply(dictionary, managedObject)
    }
}
