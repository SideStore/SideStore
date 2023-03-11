//
//  Operation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import RoxasUIKit

public class ResultOperation<ResultType>: Operation {
    var resultHandler: ((Result<ResultType, Error>) -> Void)?

    @available(*, unavailable)
	public override func finish() {
        super.finish()
    }

    func finish(_ result: Result<ResultType, Error>) {
        guard !isFinished else { return }

        if isCancelled {
            resultHandler?(.failure(OperationError.cancelled))
        } else {
            resultHandler?(result)
        }

        super.finish()
    }
}

public class Operation: RSTOperation, ProgressReporting {
	public let progress = Progress.discreteProgress(totalUnitCount: 1)

    private var backgroundTaskID: UIBackgroundTaskIdentifier?

	public override var isAsynchronous: Bool {
        true
    }

    override init() {
        super.init()

        progress.cancellationHandler = { [weak self] in self?.cancel() }
    }

	public override func cancel() {
        super.cancel()

        if !progress.isCancelled {
            progress.cancel()
        }
    }

	public override func main() {
        super.main()

        let name = "com.altstore." + NSStringFromClass(type(of: self))
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let backgroundTask = self?.backgroundTaskID else { return }

            self?.cancel()

            UIApplication.shared.endBackgroundTask(backgroundTask)
            self?.backgroundTaskID = .invalid
        }
    }

	public override func finish() {
        guard !isFinished else { return }

        super.finish()

        if let backgroundTaskID = backgroundTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
    }
}
