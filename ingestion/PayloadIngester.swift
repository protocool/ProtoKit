//  PayloadIngester.swift
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

public struct PayloadIngesterResult<ManagedObject: NSManagedObject> {
    public let updated: [ManagedObject]
    public let remainder: [Dictionary<String, Any>]
}

public class PayloadIngester<ManagedObject: NSManagedObject> {
    
    public let name: String
    public let identityKey: String
    public let identityTransformers: [ValueTransformer]
    public let identityAttributeName: String
    
    private let mapper: PayloadApplicator
    
    public init<T>(payloadMap: PayloadMap<T>, name: String? = nil) where T.ManagedObject == ManagedObject {
        guard let identityMap = payloadMap.identityMap else {
            preconditionFailure("PayloadMap.identityMap cannot be nil")
        }
        
        identityKey = identityMap.key
        identityTransformers = identityMap.transformers
        identityAttributeName = identityMap.attribute.name
        
        self.name = name.map({"\($0) (\(ManagedObject.self))"}) ?? "Unnamed PayloadIngester (\(ManagedObject.self))"
        self.mapper = PayloadApplicator(payloadMap: payloadMap)
    }

    @discardableResult
    public func upsert(with dictionary: Dictionary<String, Any>, scope: Dictionary<String, Any>? = nil, prefetch keyPaths: [String]? = nil, context: NSManagedObjectContext) throws -> ManagedObject {
        guard let updated = try upsert(with: [dictionary], scope: scope, prefetch: keyPaths, context: context).first else {
            preconditionFailure("unexpected nil result of upsert with known dictionary")
        }
        return updated
    }
    
    @discardableResult
    public func upsert(with dictionaries: [Dictionary<String, Any>], scope: Dictionary<String, Any>? = nil, prefetch keyPaths: [String]? = nil, ordered: Bool = false, context: NSManagedObjectContext) throws -> [ManagedObject] {
        let result = try update(with: dictionaries, scope: scope, prefetch: keyPaths, context: context)
        
        guard result.remainder.isEmpty == false else {
            return ordered ? try reorder(result.updated, accordingTo: dictionaries) : result.updated
        }
        
        let entity = ManagedObject.entity()
        var upserted = result.updated
        
        for dictionary in result.remainder {
            let inserted = ManagedObject(entity: entity, insertInto: context)
            
            do {
                if let scope = scope {
                    inserted.setValuesForKeys(scope)
                }
                try inserted.setValuesForKeys(with: dictionary, using: mapper)
            }
            catch {
                throw IngestionError.payloadMappingFailed(ingesterName: name, underlyingError: error)
            }
            
            upserted.append(inserted)
        }
        
        return ordered ? try reorder(upserted, accordingTo: dictionaries) : upserted
    }
    
    @discardableResult
    public func update(with dictionaries: [Dictionary<String, Any>], scope: Dictionary<String, Any>? = nil, prefetch keyPaths: [String]? = nil, context: NSManagedObjectContext) throws -> PayloadIngesterResult<ManagedObject> {
        var byIdentity = try dictionaries.indexedBy { dictionary -> AnyHashable in
            guard let identity = identityTransformers.applyTransfomations(to: dictionary[identityKey]) as? AnyHashable else {
                throw IngestionError.nullPayloadIdentityValue(ingesterName: name, key: identityKey)
            }
            return identity
        }
        
        let identityPredicate = NSPredicate(format: "%K in (%@)", identityAttributeName, Array(byIdentity.keys))
        let scopePredicates = scope?.map { NSPredicate(format: "%K == %@", argumentArray: [$0, $1]) }
        let compoundScope = scopePredicates.map { NSCompoundPredicate(andPredicateWithSubpredicates: $0) }
        
        let request = NSFetchRequest<ManagedObject>()
        request.entity = ManagedObject.entity()
        request.predicate = compoundScope.map({NSCompoundPredicate(andPredicateWithSubpredicates: [$0, identityPredicate])}) ?? identityPredicate
        request.relationshipKeyPathsForPrefetching = keyPaths
        
        let existing = try context.fetch(request)
        for case let object as NSManagedObject in existing {
            let identity = object.value(forKey: identityAttributeName) as! AnyHashable
            let dictionary = byIdentity.removeValue(forKey: identity)!
            
            do {
                try object.setValuesForKeys(with: dictionary, using: mapper)
            }
            catch {
                throw IngestionError.payloadMappingFailed(ingesterName: name, underlyingError: error)
            }
        }
        
        return PayloadIngesterResult(updated: existing, remainder: Array(byIdentity.values))
    }
    
    public func reorder(_ objects: [ManagedObject], accordingTo dictionaries: [Dictionary<String, Any>]) throws -> [ManagedObject] {
        let byIdentity = try objects.indexedBy { managedObject -> AnyHashable in
            guard let identity = managedObject.value(forKey: identityAttributeName) as? AnyHashable else {
                throw IngestionError.nullIngestedIdentityAttribute(ingesterName: name, key: identityKey)
            }
            return identity
        }
        
        return try dictionaries.map { dictionary -> ManagedObject in
            guard let identity = identityTransformers.applyTransfomations(to: dictionary[identityKey]) as? AnyHashable else {
                throw IngestionError.nullPayloadIdentityValue(ingesterName: name, key: identityKey)
            }
            
            guard let managedObject = byIdentity[identity] else {
                throw IngestionError.orderingFailed(ingesterName: name, identity: identity)
            }
            
            return managedObject
        }
    }
}
