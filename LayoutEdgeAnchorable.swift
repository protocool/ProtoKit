//  LayoutEdgeAnchorable.swift
//
//  ProtoKit
//  Copyright © 2016 Trevor Squires.
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

public enum LayoutEdgeAnchor {
    case leading
    case trailing
    case left
    case right
    case top
    case bottom
}

public protocol LayoutEdgeAnchorable {
    var leadingAnchor: NSLayoutXAxisAnchor { get }
    var trailingAnchor: NSLayoutXAxisAnchor { get }
    var leftAnchor: NSLayoutXAxisAnchor { get }
    var rightAnchor: NSLayoutXAxisAnchor { get }
    var topAnchor: NSLayoutYAxisAnchor { get }
    var bottomAnchor: NSLayoutYAxisAnchor { get }
    
    func makeEdgeConstraints(equalToAnchorsOf anchorable: LayoutEdgeAnchorable, forEdges edges: [LayoutEdgeAnchor], insetBy insets: EdgeInsets) -> [NSLayoutConstraint]
}

public extension LayoutEdgeAnchorable {
    
    public func makeEdgeConstraints(equalToAnchorsOf anchorable: LayoutEdgeAnchorable, forEdges edges: [LayoutEdgeAnchor] = [.top, .leading, .bottom, .trailing], insetBy insets: EdgeInsets = NSEdgeInsetsZero) -> [NSLayoutConstraint] {
        return edges.map { edge in
            switch edge {
            case .top:
                return topAnchor.constraint(equalTo: anchorable.topAnchor, constant: insets.top)
            case .left:
                return leftAnchor.constraint(equalTo: anchorable.leftAnchor, constant: insets.left)
            case .leading:
                return leadingAnchor.constraint(equalTo: anchorable.leadingAnchor, constant: insets.left)
            case .bottom:
                return anchorable.bottomAnchor.constraint(equalTo: bottomAnchor, constant: insets.bottom)
            case .right:
                return anchorable.rightAnchor.constraint(equalTo: rightAnchor, constant: insets.right)
            case .trailing:
                return anchorable.trailingAnchor.constraint(equalTo: trailingAnchor, constant: insets.right)
            }
        }
    }
    
}

#if os(iOS)
    extension UIView: LayoutEdgeAnchorable {}
    extension UILayoutGuide: LayoutEdgeAnchorable {}
#endif

#if os(macOS)
    extension NSView: LayoutEdgeAnchorable {}
    extension NSLayoutGuide: LayoutEdgeAnchorable {}
#endif

