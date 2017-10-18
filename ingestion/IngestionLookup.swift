//  IngestionLookup.swift
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

public class IngestionLookup<ManagedObject: NSManagedObject> {
    
    public let identityKey: String
    private let identityTransformation: AttributeValueTransformation
    
    private let lookup: [NSObject: ManagedObject]
    
    public convenience init(ingester: PayloadIngester<ManagedObject>, objects: [ManagedObject]) throws {
        self.init(identityKey: ingester.identityKey, identityTransformation: ingester.identityTransformation, lookup: try objects.indexedBy({ managedObject -> NSObject in
            guard let identity = managedObject.value(forKey: ingester.identityAttributeName) as? NSObject else {
                throw IngestionError.nullIngestedIdentityAttribute(ingesterName: ingester.name, key: ingester.identityKey)
            }
            return identity
        }))
    }
    
    public init(identityKey: String, identityTransformation: AttributeValueTransformation, lookup: [NSObject: ManagedObject]) {
        self.identityKey = identityKey
        self.identityTransformation = identityTransformation
        self.lookup = lookup
    }
    
    public subscript(payload payload: [String: Any]) -> ManagedObject? {
        return self[payload[identityKey]]
    }
    
    public subscript(possibleIdentity: Any?) -> ManagedObject? {
        do {
            guard let identity = try identityTransformation.transformedObject(from: possibleIdentity) else { return nil }
            return lookup[identity]
        }
        catch {
            // The `possibleIdentity` value would have caused an ingester to throw the same
            // error, so it makes little sense to encounter one here, other than in the case
            // of a development-time programmer error.
            assertionFailure("nonsense: subscript value type incompatible with ingested identities, error: \(String(reflecting: error))")
            return nil
        }
    }
    
}
