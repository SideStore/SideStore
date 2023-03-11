//
//  Collection-Extensions.swift
//  swift-create-xcframework
//
//  Created by Rob Amos on 9/5/20.
//

extension Collection {
    var nonEmpty: Self? {
        isEmpty ? nil : self
    }
}
