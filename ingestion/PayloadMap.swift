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

enum InternalError: Error {
    case attributeMappingFailed(name: String)
}

private let transformersPrefix: [ValueTransformer] = [ValueTransformer(forName: NSValueTransformerName.payloadNullToNil)!]

public struct PayloadMap<T: AttributeInfo>: DictionaryApplication {

    private var scalarMaps: Dictionary<String, ScalarApplication> = [:]
    private var nestedMaps: Dictionary<String, PayloadMap> = [:]

    public let identityMap: AttributeMap<T>?
    
    public init(identityKey: String, transformers: [ValueTransformer] = [], attribute: T) {
        let attributeMap = AttributeMap<T>(key: identityKey, transformers: transformersPrefix + transformers, attribute: attribute)
        identityMap = attributeMap
        addMapping(forPathComponents: [identityKey], to: attributeMap)
    }
    
    public init() {
        identityMap = nil
    }
    
    mutating
    public func addDefaultMappings(forAttributes attributes: [T]) {
        attributes.forEach { attribute in
            addMapping(where: attribute.name, updates: attribute)
        }
    }
    
    mutating
    public func addMapping(where keyPath: String, transformedBy transformers: [ValueTransformer] = [], updates attribute: T) {
        let scalarMap = AttributeMap<T>(key: keyPath, transformers: transformersPrefix + transformers, attribute: attribute)
        addMapping(forPathComponents: keyPath.characters.split(separator: ".").map({String($0)}), to: scalarMap)
    }

    mutating
    public func addMapping(where keyPath: String, transformedBy transformers: [ValueTransformer] = [], performs work: @escaping (_ receiver: T.ManagedObject, _ value: Any?) throws -> Void) {
        let customMap = CustomMap<T>(key: keyPath, transformers: transformersPrefix + transformers) { (receiver, value) in
            try work(receiver, value)
        }
        addMapping(forPathComponents: keyPath.characters.split(separator: ".").map({String($0)}), to: customMap)
    }

    mutating
    private func addMapping(forPathComponents components: [String], to scalarMap: ScalarApplication) {
        var remainingComponents = components
        let firstComponent = remainingComponents.removeFirst()
        
        if remainingComponents.isEmpty {
            scalarMaps[firstComponent] = scalarMap
        }
        else {
            var nested = nestedMaps[firstComponent] ?? PayloadMap()
            nested.addMapping(forPathComponents: remainingComponents, to: scalarMap)
            nestedMaps[firstComponent] = nested
        }
    }
    
    mutating
    public func addMapping(where keyPath: String, isAppliedBy otherMap: PayloadMap<T>) {
        addMapping(where: keyPath.characters.split(separator: ".").map({String($0)}), isAppliedBy: otherMap)
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

    public func applyValuesForKeys(from dictionary: Dictionary<String, Any>, to managedObject: NSManagedObject) throws -> Void {
        for (key, value) in dictionary {
            do {
                if let subDict = value as? Dictionary<String, Any>, let mapper = nestedMaps[key] {
                    try mapper.applyValuesForKeys(from: subDict, to: managedObject)
                }
                else if let mapper = scalarMaps[key] {
                    try mapper.applyValue(value, to: managedObject)
                }
            }
            catch InternalError.attributeMappingFailed(let attributeName) {
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

}

public struct CustomMap<T: AttributeInfo>: ScalarApplication {
    public let key: String
    public let transformers: [ValueTransformer]
    public let work: (_ receiver: T.ManagedObject, _ value: Any?) throws -> Void
    
    func applyValue(_ value: Any?, to managedObject: NSManagedObject) throws -> Void {
        let transformed = transformers.applyTransfomations(to: value)
        return try work(managedObject as! T.ManagedObject, transformed)
    }
}

public struct AttributeMap<T: AttributeInfo>: ScalarApplication {
    public let key: String
    public let transformers: [ValueTransformer]
    public let attribute: T
    
    func applyValue(_ value: Any?, to managedObject: NSManagedObject) throws -> Void {
        let attributeName = attribute.name
        let attributeType = attribute.type
        var transformed = transformers.applyTransfomations(to: value)
        
        // Attempt to fallback to the model's default value
        if transformed == nil && attribute.isOptional == false {
            assertionFailure("nil value not permitted by model, production would fallback to default")
            transformed = managedObject.entity.attributesByName[attributeName]?.defaultValue
        }
        
        guard let applicable = transformed else {
            guard attribute.isOptional == true else {
                assertionFailure("nil value not permitted by model")
                throw InternalError.attributeMappingFailed(name: attributeName)
            }
            
            if managedObject.value(forKey: attributeName) != nil {
                managedObject.setValue(nil, forKey: attributeName)
            }
            return
        }
        
        let existing = try existingValue(forAttributeName: attributeName, of: managedObject)
        let sanitized: Any
        
        switch attributeType {
        case .stringAttributeType:
            switch applicable {
            case let stringValue as NSString:
                sanitized = stringValue
            case let numberValue as NSNumber:
                sanitized = numberValue.stringValue
            default:
                assertionFailure("can't infer coercion to NSString")
                throw InternalError.attributeMappingFailed(name: attributeName)
            }
            
        case .dateAttributeType:
            sanitized = applicable
            
        case .integer16AttributeType: fallthrough
        case .integer32AttributeType: fallthrough
        case .integer64AttributeType: fallthrough
        case .doubleAttributeType: fallthrough
        case .floatAttributeType: fallthrough
        case .booleanAttributeType: fallthrough
        case .decimalAttributeType:
            switch applicable {
            case let numberValue as NSNumber:
                sanitized = numberValue
            case let stringValue as NSString:
                sanitized = try sanitizedNumber(fromString: stringValue, asType: attributeType)
            default:
                assertionFailure("can't infer coercion to NSNumber")
                throw InternalError.attributeMappingFailed(name: attributeName)
            }
            
        case .UUIDAttributeType:
            sanitized = try sanitizedUUID(from: applicable, for: attributeName)
            
        case .URIAttributeType:
            sanitized = try sanitizedURL(from: applicable, for: attributeName)

        case .objectIDAttributeType: fallthrough
        case .binaryDataAttributeType: fallthrough
        case .transformableAttributeType: fallthrough
        case .undefinedAttributeType:
            sanitized = applicable
        }
        
        if existing?.isEqual(sanitized) != true {
            managedObject.setValue(sanitized, forKey: attributeName)
        }
    }
    
    func sanitizedNumber(fromString input: NSString, asType type: NSAttributeType) throws -> NSNumber {
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
    
    func sanitizedUUID(from input: Any, for attributeName: String) throws -> UUID {
        if let uuid = input as? UUID {
            return uuid
        }
        else if let stringInput = input as? String, let uuid = UUID(uuidString: stringInput) {
            return uuid
        }
        
        assertionFailure("can't coerce to UUID")
        throw InternalError.attributeMappingFailed(name: attributeName)
    }
    
    func sanitizedURL(from input: Any, for attributeName: String) throws -> URL {
        if let url = input as? URL {
            return url
        }
        else if let stringInput = input as? String, let url = URL(string: stringInput) {
            return url
        }
        
        assertionFailure("can't coerce to URL")
        throw InternalError.attributeMappingFailed(name: attributeName)
    }
    
    func existingValue(forAttributeName attributeName: String, of managedObject: NSManagedObject) throws -> NSObjectProtocol? {
        return managedObject.value(forKey: attributeName).map { value -> NSObjectProtocol in
            guard let conformingValue = value as? NSObjectProtocol else {
                preconditionFailure("the non-nil value for \(attributeName) does not conform to NSObjectProtocol")
            }
            
            return conformingValue
        }
    }
}

internal protocol DictionaryApplication {
    func applyValuesForKeys(from dictionary: Dictionary<String, Any>, to managedObject: NSManagedObject) throws -> Void
}

private protocol ScalarApplication {
    func applyValue(_ value: Any?, to managedObject: NSManagedObject) throws -> Void
}
