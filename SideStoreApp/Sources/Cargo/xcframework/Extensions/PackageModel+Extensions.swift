//
//  PackageDescription+Extensions.swift
//  swift-create-xcframework
//
//  Created by Rob Amos on 7/5/20.
//

import PackageModel

extension ProductType {
    var isLibrary: Bool {
        if case .library = self {
            return true
        }
        return false
    }
}

extension Manifest {
    var libraryProductNames: [String] {
        products
            .compactMap { product in
                guard product.type.isLibrary else { return nil }
                return product.name
            }
    }
}
