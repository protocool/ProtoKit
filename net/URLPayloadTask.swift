//  URLPayloadTask.swift
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

public class URLPayloadTask<Subject>: NSObject {

    public var taskIdentifier: Int { return dataTask.taskIdentifier }
    
    public var taskDescription: String? {
        get { return dataTask.taskDescription }
        set { dataTask.taskDescription = newValue }
    }
    
    public var state: URLSessionTask.State { return dataTask.state }

    public let dataTask: URLSessionDataTask
    public let progress: Progress
    public let eventual: Eventual<Subject>

    public init(dataTask: URLSessionDataTask, progress: Progress, eventual: Eventual<Subject>) {
        self.dataTask = dataTask
        self.progress = progress
        self.eventual = eventual
    }

    public func cancel() { dataTask.cancel() }
    public func suspend() { dataTask.suspend() }
    public func resume() { dataTask.resume() }

}

public extension URLSession {
    
    public func payloadTask<Subject>(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) throws -> Subject) -> URLPayloadTask<Subject> {
        return payloadTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }

    public func payloadTask<Subject>(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) throws -> Subject) -> URLPayloadTask<Subject> {
        let progress = Progress.discreteProgress(totalUnitCount: 1)
        let (eventualData, resolve, reject) = Eventual<Subject>.make()
        let dataTask = self.dataTask(with: request) { (taskData, taskResponse, taskError) -> Void in
            do {
                resolve(try completionHandler(taskData, taskResponse, taskError))
                progress.completedUnitCount = 1
            }
            catch {
                reject(error)
            }
        }
        
        progress.isCancellable = true
        progress.cancellationHandler = { [weak dataTask] in
            dataTask?.cancel()
        }
        
        return URLPayloadTask(dataTask: dataTask, progress: progress, eventual: eventualData)
    }

}
