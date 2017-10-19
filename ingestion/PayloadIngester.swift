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
    public typealias PayloadApplication = (ManagedObject, Dictionary<String, Any>, PayloadApplicator<ManagedObject>) throws -> Void
    
    public let name: String
    public let identityKey: String
    public let identityTransformers: [ValueTransformer]
    public let identityAttributeName: String
    public let identityTransformation: AttributeValueTransformation
    
    private let applicator: PayloadApplicator<ManagedObject>
    
    public init<T>(payloadMap: PayloadMap<T>, name: String? = nil) where T.ManagedObject == ManagedObject {
        guard let identityKey = payloadMap.identityKey, let identityMap = payloadMap.identityMap else {
            preconditionFailure("ingester requires a PayloadMap that has been initialized with an identity mapping")
        }
        
        self.identityKey = identityKey
        self.identityTransformers = identityMap.transformers
        self.identityAttributeName = identityMap.attribute.name
        self.identityTransformation = identityMap
        
        self.name = name.map({"\($0) (\(ManagedObject.self))"}) ?? "Unnamed PayloadIngester (\(ManagedObject.self))"
        self.applicator = PayloadApplicator(payloadMap: payloadMap)
    }
    
    public convenience init<T>(identityKey: String, transformers: [ValueTransformer] = [], attribute: T, name: String? = nil, withMapping preparation: (inout PayloadMap<T>) -> Void) where T.ManagedObject == ManagedObject {
        var attributeMap = PayloadMap(identityKey: identityKey, transformers: transformers, attribute: attribute)
        preparation(&attributeMap)
        
        self.init(payloadMap: attributeMap, name: name)
    }

    @discardableResult
    public func upsert(with dictionary: Dictionary<String, Any>, scope: Dictionary<String, Any>? = nil, prefetch keyPaths: [String]? = nil, context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> ManagedObject {
        guard let updated = try upsert(with: [dictionary], scope: scope, prefetch: keyPaths, context: context, appliedBy: application).first else {
            preconditionFailure("unexpected nil result of upsert with known dictionary")
        }
        return updated
    }
    
    @discardableResult
    public func upsert(with dictionaries: [Dictionary<String, Any>], scope: Dictionary<String, Any>? = nil, prefetch keyPaths: [String]? = nil, ordered: Bool = false, context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> [ManagedObject] {
        let updateResult = try update(with: dictionaries, scope: scope, prefetch: keyPaths, context: context, appliedBy: application)
        let inserted = try insert(with: updateResult.remainder, scope: scope, context: context, appliedBy: application)
        let upserted = updateResult.updated + inserted
        
        return ordered ? try reorder(upserted, accordingTo: dictionaries) : upserted
    }

    @discardableResult
    public func upsertExisting(_ existing: [ManagedObject], with dictionaries: [Dictionary<String, Any>], ordered: Bool = false, context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> [ManagedObject] {
        let updateResult = try updateExisting(existing, with: dictionaries, context: context, appliedBy: application)
        let inserted = try insert(with: updateResult.remainder, scope: nil, context: context, appliedBy: application)
        let upserted = updateResult.updated + inserted
        
        return ordered ? try reorder(upserted, accordingTo: dictionaries) : upserted
    }

    @discardableResult
    public func update(with dictionaries: [Dictionary<String, Any>], scope: Dictionary<String, Any>? = nil, prefetch keyPaths: [String]? = nil, context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> PayloadIngesterResult<ManagedObject> {
        let byIdentity = try dictionaries.indexedBy { dictionary -> NSObject in
            guard let identity = identityObject(from: dictionary) else {
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
        
        return try update(existing: existing, using: byIdentity, context: context, appliedBy: application)
    }

    @discardableResult
    public func updateExisting(_ existing: [ManagedObject], with dictionaries: [Dictionary<String, Any>], context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> PayloadIngesterResult<ManagedObject> {
        let byIdentity = try dictionaries.indexedBy { dictionary -> NSObject in
            guard let identity = identityObject(from: dictionary) else {
                throw IngestionError.nullPayloadIdentityValue(ingesterName: name, key: identityKey)
            }
            return identity
        }

        return try update(existing: existing, using: byIdentity, context: context, appliedBy: application)
    }

    private func update(existing: [ManagedObject], using lookup: [NSObject: [String: Any]], context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> PayloadIngesterResult<ManagedObject> {
        var lookup = lookup
        
        for object in existing {
            let identity = object.value(forKey: identityAttributeName) as! NSObject
            let dictionary = lookup.removeValue(forKey: identity)!
            
            do {
                if let application = application {
                    try application(object, dictionary, applicator)
                }
                else {
                    try applicator.applyValuesForKeys(from: dictionary, to: object)
                }
            }
            catch {
                throw IngestionError.payloadMappingFailed(ingesterName: name, underlyingError: error)
            }
        }
        
        return PayloadIngesterResult(updated: existing, remainder: Array(lookup.values))
    }

    private func insert(with dictionaries: [Dictionary<String, Any>], scope: Dictionary<String, Any>? = nil, context: NSManagedObjectContext, appliedBy application: PayloadApplication? = nil) throws -> [ManagedObject] {
        let entity = ManagedObject.entity()
        
        var result: [ManagedObject] = []
        result.reserveCapacity(dictionaries.count)
        
        for dictionary in dictionaries {
            let inserted = ManagedObject(entity: entity, insertInto: context)
            
            do {
                if let scope = scope {
                    inserted.setValuesForKeys(scope)
                }
                
                if let application = application {
                    try application(inserted, dictionary, applicator)
                }
                else {
                    try applicator.applyValuesForKeys(from: dictionary, to: inserted)
                }
            }
            catch {
                throw IngestionError.payloadMappingFailed(ingesterName: name, underlyingError: error)
            }
            
            result.append(inserted)
        }
        
        return result
    }

    public func identityObject(from dictionary: [String: Any]) -> NSObject? {
        do { return try identityTransformation.transformedObject(from: dictionary[identityKey]) }
        catch { return nil }
    }
    
    public func reorder(_ objects: [ManagedObject], accordingTo dictionaries: [Dictionary<String, Any>]) throws -> [ManagedObject] {
        let byIdentity = try objects.indexedBy { managedObject -> NSObject in
            guard let identity = managedObject.value(forKey: identityAttributeName) as? NSObject else {
                throw IngestionError.nullIngestedIdentityAttribute(ingesterName: name, key: identityKey)
            }
            return identity
        }
        
        return try dictionaries.map { dictionary -> ManagedObject in
            guard let identity = identityObject(from: dictionary) else {
                throw IngestionError.nullPayloadIdentityValue(ingesterName: name, key: identityKey)
            }
            
            guard let managedObject = byIdentity[identity] else {
                throw IngestionError.orderingFailed(ingesterName: name, identity: identity)
            }
            
            return managedObject
        }
    }
}
