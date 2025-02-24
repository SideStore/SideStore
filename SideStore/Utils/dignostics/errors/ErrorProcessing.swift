//
//  ErrorProcessing.swift
//  AltStore
//
//  Created by Magesh K on 20/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

class ErrorProcessing {
    
    enum InfoMode: String {
        case fullError
        case localizedDescription
    }
    
    let info: InfoMode
    let unique: Bool
    let recur: Bool
    
    
    var errors: Set<String> = []
    
    // by default we will process only the localDesc on first level errors
    init(_ mode: InfoMode = .localizedDescription, unique: Bool = false, recur: Bool = false){
        self.info = mode
        self.unique = unique
        self.recur = recur
    }
    
    private func processError(_ error: NSError, ignoreTitle: Bool = false, getMoreErrors: (_ error: NSError)->String) -> String{
        // if unique was requested and if this error is duplicate, ignore processing it
        let serializedError = "\(error)"
        if unique && errors.contains(serializedError) {
            return ""
        }
        errors.insert(serializedError)    // mark this as processed
        
        var title = ""
        var desc = ""
        switch (info){
            case .localizedDescription:
                title = !ignoreTitle ? (error.localizedTitle.map{$0+"\n"} ?? "") : ""
                desc = error.localizedDescription
            case .fullError:
                desc = serializedError
        }
        var moreErrors = getMoreErrors(error)
        moreErrors = moreErrors == "" ? "" : "\n" + moreErrors
        return title + desc + moreErrors
    }

    func getDescription(error: NSError) -> String{
        errors = []  // reinit for each request
        return getDescriptionText(error: error)
    }
    
    
    func getDescriptionText(error: NSError,_ depth: Int = 0) -> String{
        // closure
        let recurseErrors = { error in
            self.getDescriptionText(error: error, depth+1)        // recursively process underlying error(s) if any
        }
        
        var description = ""
        // process current error only if recur was not requested
        let processMoreErrors = recur ? recurseErrors : {_ in ""}
        
        let underlyingErrors = error.underlyingErrors
        if !underlyingErrors.isEmpty {
            description += underlyingErrors.map{ error in
                let error = error as NSError
                return processError(error, getMoreErrors: processMoreErrors)
            }.joined(separator: "\n")
        } else if let underlyingError = error.underlyingError as? NSError {
            let error = underlyingError as NSError
            description += processError(error, getMoreErrors: processMoreErrors)
        } else {
            // ignore the title for the base error since we wanted this to be description
            let isBaseError = (depth == 0)
            description += processError(error, ignoreTitle: isBaseError, getMoreErrors: processMoreErrors)
        }
        return description
    }
}
