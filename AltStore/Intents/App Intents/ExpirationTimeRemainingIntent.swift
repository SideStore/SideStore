import AppIntents
import AltStoreCore

@available(iOS 17.0, *)
struct ExpirationTimeRemainingIntent: AppIntent
{
    static var title: LocalizedStringResource { "Get Time Until Expiration" }
    static var description: IntentDescription {
            IntentDescription("Returns the number of seconds until the main app's signing certificate expires. Returns 0 if the app has already expired.")
    }
    static var parameterSummary: some ParameterSummary {
        Summary("Get seconds until app expires")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double>
    {
        do
        {
            let secondsRemaining = try await self.secondsUntilExpiration()
            return .result(value: secondsRemaining)
        }
        catch
        {
            throw IntentError(error)
        }
    }
}

@available(iOS 17.0, *)
private extension ExpirationTimeRemainingIntent
{
    func secondsUntilExpiration() async throws -> Double
    {
        if !DatabaseManager.shared.isStarted
        {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DatabaseManager.shared.start { error in
                    if let error
                    {
                        continuation.resume(throwing: error)
                    }
                    else
                    {
                        continuation.resume()
                    }
                }
            }
        }

        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let expirationDate = await context.perform { () -> Date? in
            guard let sideStoreApp = InstalledApp.fetchAltStore(in: context) else { return nil }
            return sideStoreApp.expirationDate
        }

        guard let expirationDate else { throw OperationError.appNotFound(name: nil) }

        let secondsRemaining = max(0, expirationDate.timeIntervalSinceNow)
        return secondsRemaining
    }
}
