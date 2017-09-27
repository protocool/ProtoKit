//  ContextOperation.swift
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

public final class ContextOperation<Subject> : Operation, ProgressReporting {

    public let callerInfo: CallerInfo
    public var sourceContext: NSManagedObjectContext?
    
    public let progress: Progress
    public let eventual: Eventual<Subject>
    private let mergePolicy: NSMergePolicy
    
    private var work: Optional<(_ context: NSManagedObjectContext) throws -> Subject>
    private var workCompleted: Bool = false
    private var saveNotification: Notification?
    
    private let resolve: (_ value: Subject) -> Void
    private let reject: (_ error: Error) -> Void

    public init(mergePolicy: NSMergePolicy = NSMergePolicy.error, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, work: @escaping (_ context: NSManagedObjectContext) throws -> Subject) {
        let (eventual, resolve, reject) = Eventual<Subject>.make()
        self.eventual = eventual
        self.resolve = resolve
        self.reject = reject

        self.work = work
        self.callerInfo = CallerInfo(file, function, line)
        self.progress =  Progress.discreteProgress(totalUnitCount: 10)
        self.mergePolicy = mergePolicy
        
        super.init()
        
        self.progress.cancellationHandler = { [weak self] in
            self?.handleProgressCancellation()
        }
    }

    public convenience init<T>(withInput input: T, mergePolicy: NSMergePolicy = NSMergePolicy.error, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, work: @escaping (_ input: T, _ context: NSManagedObjectContext) throws -> Subject) {
        self.init(mergePolicy: mergePolicy, file: file, function: function, line: line) { context in
            let realizedInput: T
            do {
                realizedInput = try context.realize(input)
            }
            catch {
                throw ContextOperationError.inputRealizationFailed(callerInfo: CallerInfo(file, function, line), underlyingError: error)
            }
            
            return try work(realizedInput, context)
        }
    }

    deinit {
        if work != nil {
            // Looks like neither start() nor main() have run. Make sure our eventual doesn't sit waiting forever.
            let error = isCancelled ? ContextOperationError.operationCancelled(callerInfo: callerInfo) : ContextOperationError.operationDiscarded(callerInfo: callerInfo)
            reject(error)
        }
    }
    
    public override func start() {
        if isCancelled {
            work = nil
            reject(ContextOperationError.operationCancelled(callerInfo: callerInfo))
        }
        super.start()
    }
    
    public override func main() {
        autoreleasepool {

            guard let operationWork = work else {
                preconditionFailure("ContextOperation block unexpectedly nil at start of operation")
            }
            
            work = nil

            let operationProgress = progress
            let operationCallerInfo = callerInfo
            let resolveEventual = resolve
            let rejectEventual = reject
            
            guard isCancelled == false else {
                rejectEventual(ContextOperationError.operationCancelled(callerInfo: operationCallerInfo))
                return
            }
            
            guard let sourceContext = sourceContext, let sourceCoordinator = sourceContext.persistentStoreCoordinator else {
                rejectEventual(ContextOperationError.contextSetupFailed(callerInfo: operationCallerInfo))
                return
            }
            
            let operationContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            operationContext.mergePolicy = mergePolicy
            operationContext.undoManager = nil
            operationContext.persistentStoreCoordinator = sourceCoordinator
            
            NotificationCenter.default.addObserver(self, selector: #selector(ContextOperation.operationContextSaved(_:)), name: NSNotification.Name.NSManagedObjectContextDidSave, object: operationContext)
            defer { NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSManagedObjectContextDidSave, object: operationContext) }
        
            operationContext.performAndWait {
                do {
                    operationProgress.becomeCurrent(withPendingUnitCount: 9)
                    defer {
                        if Progress.current() === operationProgress {
                            operationProgress.resignCurrent()
                        }
                    }

                    let subject = try operationWork(operationContext)
                    operationProgress.resignCurrent()
                    self.workCompleted = true
                    
                    do {
                        let saveProgress = Progress(totalUnitCount: 1, parent: operationProgress, pendingUnitCount: 1)

                        try operationContext.save()
                        saveProgress.completedUnitCount = 1
                        
                        let lastSaveNotification = self.saveNotification
                        self.saveNotification = nil
                        
                        sourceContext.perform {
                            if let notification = lastSaveNotification {
                                sourceContext.mergeContextOperationChanges(withContextDidSaveNotification: notification)
                            }
                            
                            autoreleasepool {
                                do {
                                    let realizedSubject = try sourceContext.realize(subject)
                                    resolveEventual(realizedSubject)
                                }
                                catch {
                                    rejectEventual(ContextOperationError.outputRealizationFailed(callerInfo: operationCallerInfo, underlyingError: error))
                                }
                            }
                        }
                    }
                    catch {
                        throw ContextOperationError.contextSaveFailed(callerInfo: operationCallerInfo, underlyingError: error)
                    }
                }
                catch let error as ContextOperationError {
                    rejectEventual(error)
                }
                catch {
                    let wrapped = ContextOperationError.workFailed(callerInfo: operationCallerInfo, underlyingError: error)
                    rejectEventual(wrapped)
                }
            }
            
        }
    }

    public override func cancel() {
        super.cancel()
        handleOperationCancellation()
    }
    
    // When the progress is cancelled, make sure the operation is too.
    private func handleProgressCancellation() {
        guard isCancelled == false else { return }
        cancel()
    }
    
    // When the operation is cancelled, make sure the progress is too.
    private func handleOperationCancellation() {
        guard progress.isCancelled == false else { return }
        progress.cancel()
    }
    
    @objc private func operationContextSaved(_ notification: Notification) {
        guard workCompleted else {
            // The closure must have called save(), so we merge those changes right away.
            if let sourceContext = sourceContext {
                sourceContext.perform {
                    sourceContext.mergeContextOperationChanges(withContextDidSaveNotification: notification)
                }
            }
            return
        }

        // Hang on to the notification for delivery by main() cleanup, which ensures
        // that the final change notification and the resolution of our Eventual
        // both occur within the same spin of the runloop.
        saveNotification = notification
    }
    
}

public enum ContextOperationError: Error {

    case operationDiscarded(callerInfo: CallerInfo)
    case operationCancelled(callerInfo: CallerInfo)
    
    case contextSetupFailed(callerInfo: CallerInfo)
    case inputRealizationFailed(callerInfo: CallerInfo, underlyingError: Error)
    case workFailed(callerInfo: CallerInfo, underlyingError: Error)
    case contextSaveFailed(callerInfo: CallerInfo, underlyingError: Error)
    case outputRealizationFailed(callerInfo: CallerInfo, underlyingError: Error)

}

private extension NSManagedObjectContext {
    func mergeContextOperationChanges(withContextDidSaveNotification notification: Notification) {
        // When merging changes, the receiver only generates NSManagedObjectContextObjectsDidChange info
        // for changed objects in a merge notification if those changed objects are registered with the
        // receiver and if they are not a fault. This is a problem for NSFetchedResultsController if
        // any of those unregistered or faulted objects now satisfy the controller's predicate.

        if #available(iOS 10.0, macOS 10.12, *) {
            // Nothing required here because private notifications inform NSFetchedResultsController of
            // all changed objects that were merged.
        }
        else {
            // On older platforms, we must make sure all updated objects are unfaulted by the receiver
            // before merging changes
            if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                for updated in updatedObjects {
                    object(with: updated.objectID).willAccessValue(forKey: nil)
                }
            }
        }

        mergeChanges(fromContextDidSave: notification)
        processPendingChanges()
    }
}
