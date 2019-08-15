//  PayloadMap.swift
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

public enum PayloadMapError: Error {
    case attributeMappingFailed(keyPath: String, name: String, value: Any?)
    case customMappingFailed(keyPath: String, value: Any?, underlyingError: Error)

    fileprivate func rewrite(withKeyPathPrefix prefix: String) -> PayloadMapError {
        switch self {
        case .attributeMappingFailed(let trailing, let name, let value):
            return PayloadMapError.attributeMappingFailed(keyPath: prefix + "." + trailing, name: name, value: value)
        case .customMappingFailed(let trailing, let value, let underlyingError):
            return PayloadMapError.customMappingFailed(keyPath: prefix + "." + trailing, value: value, underlyingError: underlyingError)
        }
    }
}

public enum AttributeMapError: Error {
    case mappingFailed(name: String)
}

public protocol AttributeValueTransformation {
    func transformedObject(from value: Any?) throws -> NSObject?
}

private let transformersPrefix: [ValueTransformer] = [ValueTransformer(forName: NSValueTransformerName.payloadNullToNil)!]

public struct PayloadMap<T: AttributeInfo> {
    public typealias ManagedObject = T.ManagedObject
    public typealias PreparationBlock = (inout PayloadMap) -> Void

    private var scalarMaps: Dictionary<String, ScalarApplication> = [:]
    private var nestedMaps: Dictionary<String, PayloadMap> = [:]

    public let identityKey: String?
    public let identityMap: AttributeMap<T>?
    
    public init(identityKey: String, transformers: [ValueTransformer] = [], attribute: T, preparedBy preparation: PreparationBlock? = nil) {
        let attributeMap = AttributeMap<T>(transformers: transformers, attribute: attribute)
        
        self.identityKey = identityKey
        self.identityMap = attributeMap
        
        addMapping(forPathComponents: [identityKey], appliedBy: attributeMap)
        preparation?(&self)
    }

    public init(identity attribute: T, transformers: [ValueTransformer] = [], preparedBy preparation: PreparationBlock? = nil) {
        let attributeMap = AttributeMap<T>(transformers: transformers, attribute: attribute)
        
        self.identityKey = attribute.name
        self.identityMap = attributeMap
        
        addMapping(forPathComponents: [attribute.name], appliedBy: attributeMap)
        preparation?(&self)
    }

    public init(preparedBy preparation: PreparationBlock? = nil) {
        identityKey = nil
        identityMap = nil
        preparation?(&self)
    }
    
    mutating
    public func addDefaultMappings(forAttributes attributes: [T]) {
        attributes.forEach { attribute in
            guard identityKey != attribute.name else { return }
            addMapping(where: attribute.name, updates: attribute)
        }
    }
    
    mutating
    public func addMapping(where keyPath: String, transformedBy transformers: [ValueTransformer] = [], updates attribute: T) {
        guard identityKey != keyPath else {
            assertionFailure("added mapping conflicts with identity mapping")
            return
        }

        let scalarMap = AttributeMap<T>(transformers: transformers, attribute: attribute)
        addMapping(forPathComponents: keyPath.split(separator: ".").map({String($0)}), appliedBy: scalarMap)
    }

    mutating
    public func addMapping(for attribute: T, transformedBy transformers: [ValueTransformer] = []) {
        guard identityKey != attribute.name else {
            assertionFailure("added mapping conflicts with identity mapping")
            return
        }
        
        addMapping(where: attribute.name, transformedBy: transformers, updates: attribute)
    }

    mutating
    public func addMapping(where keyPath: String, transformedBy transformers: [ValueTransformer] = [], performs work: @escaping (_ receiver: T.ManagedObject, _ value: Any?) throws -> Void) {
        guard identityKey != keyPath else {
            assertionFailure("added mapping conflicts with identity mapping")
            return
        }
        
        let customMap = CustomMap<T>(transformers: transformers) { (receiver, value) in
            try work(receiver, value)
        }
        addMapping(forPathComponents: keyPath.split(separator: ".").map({String($0)}), appliedBy: customMap)
    }

    mutating
    private func addMapping(forPathComponents components: [String], appliedBy scalarMap: ScalarApplication) {
        var remainingComponents = components
        let firstComponent = remainingComponents.removeFirst()
        
        if remainingComponents.isEmpty {
            scalarMaps[firstComponent] = scalarMap
        }
        else {
            var nested = nestedMaps[firstComponent] ?? PayloadMap()
            nested.addMapping(forPathComponents: remainingComponents, appliedBy: scalarMap)
            nestedMaps[firstComponent] = nested
        }
    }
    
    mutating
    public func addMapping(where keyPath: String, isAppliedBy otherMap: PayloadMap<T>) {
        guard identityKey != keyPath else {
            assertionFailure("added mapping conflicts with identity mapping")
            return
        }
        
        addMapping(where: keyPath.split(separator: ".").map({String($0)}), isAppliedBy: otherMap)
    }

    mutating
    private func addMapping(where components: [String], isAppliedBy otherMap: PayloadMap<T>) {
        var remainingComponents = components
        let firstComponent = remainingComponents.removeFirst()
        
        if remainingComponents.isEmpty {
            nestedMaps[firstComponent] = otherMap
        }
        else {
            var nested = nestedMaps[firstComponent] ?? PayloadMap()
            nested.addMapping(where: remainingComponents, isAppliedBy: otherMap)
            nestedMaps[firstComponent] = nested
        }
    }

    public func applyValuesForKeys(from dictionary: Dictionary<String, Any>, to managedObject: ManagedObject) throws -> Void {
        for (key, value) in dictionary {
            try apply(value, forKey: key, to: managedObject)
        }
    }

    public func applyValues(forKeys keys: [String], from dictionary: Dictionary<String, Any>, to managedObject: ManagedObject) throws -> Void {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            try apply(value, forKey: key, to: managedObject)
        }
    }

    public func applyValue(forKey key: String, from dictionary: Dictionary<String, Any>, to managedObject: ManagedObject) throws -> Void {
        guard let value = dictionary[key] else { return }
        try apply(value, forKey: key, to: managedObject)
    }

    private func apply(_ value: Any, forKey key:String, to managedObject: ManagedObject) throws -> Void {
        do {
            if let subDict = value as? Dictionary<String, Any>, let mapper = nestedMaps[key] {
                try mapper.applyValuesForKeys(from: subDict, to: managedObject)
            }
            else if let mapper = scalarMaps[key] {
                try mapper.applyValue(value, to: managedObject)
            }
        }
        catch AttributeMapError.mappingFailed(let attributeName) {
            throw PayloadMapError.attributeMappingFailed(keyPath: key, name: attributeName, value: value)
        }
        catch let error as PayloadMapError {
            throw error.rewrite(withKeyPathPrefix: key)
        }
        catch {
            assertionFailure("error raised by custom mapping block")
            throw PayloadMapError.customMappingFailed(keyPath: key, value: value, underlyingError: error)
        }
    }

}

public struct CustomMap<T: AttributeInfo>: ScalarApplication {
    public let transformers: [ValueTransformer]
    public let work: (_ receiver: T.ManagedObject, _ value: Any?) throws -> Void
    
    public init(transformers: [ValueTransformer], work: @escaping (_ receiver: T.ManagedObject, _ value: Any?) throws -> Void) {
        self.transformers = transformersPrefix + transformers
        self.work = work
    }
    
    public func applyValue(_ value: Any?, to managedObject: NSManagedObject) throws -> Void {
        let transformed = transformers.applyTransfomations(to: value)
        return try work(managedObject as! T.ManagedObject, transformed)
    }
}

public struct AttributeMap<T: AttributeInfo>: ScalarApplication, AttributeValueTransformation {
    public let transformers: [ValueTransformer]
    public let attribute: T

    public init(transformers: [ValueTransformer], attribute: T) {
        self.transformers = transformersPrefix + transformers
        self.attribute = attribute
    }

    public func applyValue(_ value: Any?, to managedObject: NSManagedObject) throws -> Void {
        let attributeName = attribute.name
        var transformed = try transformedObject(from: value)
        
        // When nil but required, attempt fallback to the model's default value
        if transformed == nil && attribute.isOptional == false {
            transformed = managedObject.entity.attributesByName[attributeName]?.defaultValue as? NSObject
            assert(transformed != nil, "nil value not permitted by model: no default value available for production-build fallback")

            // Even though production builds will attempt fallback to assigning the default
            // value defined in the model, it may not be what you intended.
            // Either make the property nullable, or define a value transformer to sanitize
            // payload nulls, or use a custom mapper with a `performs:` block to conditinally
            // accept the payload null.
            assertionFailure("nil value not permitted by model: production build will assign model default value")
        }
        
        guard let applicable = transformed else {
            guard attribute.isOptional == true else {
                throw AttributeMapError.mappingFailed(name: attributeName)
            }
            
            if managedObject.value(forKey: attributeName) != nil {
                managedObject.setValue(nil, forKey: attributeName)
            }
            return
        }
        
        let existing = try existingValue(forAttributeName: attributeName, of: managedObject)
        
        if existing?.isEqual(applicable) != true {
            managedObject.setValue(applicable, forKey: attributeName)
        }
    }
    
    public func transformedObject(from value: Any?) throws -> NSObject? {
        // A nil result from the ValueTransformers doesn't (on its own) indicate an error.
        guard let transformedValue = transformers.applyTransfomations(to: value) else { return nil }

        let attributeName = attribute.name
        let attributeType = attribute.type

        // HOWEVER, a non-nil transformed value which cannot be downcast to NSObject
        // most certainly is an error: CoreData is built upon the obj-c runtime, and this
        // value is going to be applied using KVC.
        guard let valueObject = transformedValue as? NSObject else {
            assertionFailure("input value is expected to be downcastable to NSObject")
            throw AttributeMapError.mappingFailed(name: attributeName)
        }

        // It's not uncommon for server payloads to be a bit inconsistent WRT string and number
        // representations, so we silently apply the appropriate type coercion to avoid having
        // to declare value transformers all over the place when setting up our PayloadMaps.
        //
        // Additionally, UUID and URL both have initializers that accept string representations,
        // so we silently attempt that coercion as well.
        //
        switch attributeType {
        case .stringAttributeType:
            switch valueObject {
            case let stringValue as NSString:
                return stringValue
            case let numberValue as NSNumber:
                return numberValue.stringValue as NSObject
            default:
                assertionFailure("can't infer coercion to NSString")
                throw AttributeMapError.mappingFailed(name: attributeName)
            }
            
        case .dateAttributeType:
            return valueObject
            
        case .integer16AttributeType: fallthrough
        case .integer32AttributeType: fallthrough
        case .integer64AttributeType: fallthrough
        case .doubleAttributeType: fallthrough
        case .floatAttributeType: fallthrough
        case .booleanAttributeType: fallthrough
        case .decimalAttributeType:
            switch valueObject {
            case let numberValue as NSNumber:
                return numberValue
            case let stringValue as NSString:
                return try coercedNumber(fromString: stringValue, asType: attributeType)
            default:
                assertionFailure("can't infer coercion to NSNumber")
                throw AttributeMapError.mappingFailed(name: attributeName)
            }
            
        case .UUIDAttributeType:
            return try coercedUUID(from: valueObject, for: attributeName)
            
        case .URIAttributeType:
            return try coercedURL(from: valueObject, for: attributeName)
            
        case .objectIDAttributeType: fallthrough
        case .binaryDataAttributeType: fallthrough
        case .transformableAttributeType: fallthrough
        case .undefinedAttributeType:
            return valueObject
                        
        @unknown default:
            preconditionFailure("unexpected attribute type for transformed object: \(attributeType)")
        }
    }
    
    func coercedNumber(fromString input: NSString, asType type: NSAttributeType) throws -> NSNumber {
        switch type {
        case .integer16AttributeType: fallthrough
        case .integer32AttributeType:
            return NSNumber(value: input.integerValue)
        case .integer64AttributeType:
            return NSNumber(value: input.longLongValue)
        case .doubleAttributeType:
            return NSNumber(value: input.doubleValue)
        case .floatAttributeType:
            return NSNumber(value: input.floatValue)
        case .booleanAttributeType:
            return NSNumber(value: input.boolValue)
        case .decimalAttributeType:
            return NSDecimalNumber(string: input as String)
        default:
            preconditionFailure("unexpected attribute type for string to number coercion: \(type)")
        }
    }
    
    func coercedUUID(from input: Any, for attributeName: String) throws -> NSUUID {
        if let uuid = input as? NSUUID {
            return uuid
        }
        else if let stringInput = input as? String, let uuid = NSUUID(uuidString: stringInput) {
            return uuid
        }
        
        assertionFailure("can't coerce to UUID")
        throw AttributeMapError.mappingFailed(name: attributeName)
    }
    
    func coercedURL(from input: Any, for attributeName: String) throws -> NSURL {
        if let url = input as? NSURL {
            return url
        }
        else if let stringInput = input as? String, let url = NSURL(string: stringInput) {
            return url
        }
        
        assertionFailure("can't coerce to URL")
        throw AttributeMapError.mappingFailed(name: attributeName)
    }
    
    func existingValue(forAttributeName attributeName: String, of managedObject: NSManagedObject) throws -> NSObject? {
        return managedObject.value(forKey: attributeName).map { value -> NSObject in
            guard let conformingValue = value as? NSObject else {
                preconditionFailure("the non-nil value for \(attributeName) does not conform to NSObject")
            }
            
            return conformingValue
        }
    }
}

internal protocol ScalarApplication {
    func applyValue(_ value: Any?, to managedObject: NSManagedObject) throws -> Void
}

