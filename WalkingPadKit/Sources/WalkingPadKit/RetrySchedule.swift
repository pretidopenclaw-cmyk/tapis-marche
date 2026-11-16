/// How long to wait before retrying a failed Notion sync: grows, then stays at 15 minutes.
public enum RetrySchedule {
    private static let delays = [60, 120, 300, 900]

    public static func delaySeconds(afterFailures failures: Int) -> Int {
        guard failures > 0 else { return 0 }
        return delays[min(failures, delays.count) - 1]
    }
}
