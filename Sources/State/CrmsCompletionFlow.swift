import Foundation
import Observation

/// Drives the Current-RMS side of marking a job or movement completed,
/// mirroring the web app's `handleCrmsCompletion`/`promptToCloseOrder`
/// (`public/js/crms.js`): book-out on delivery, check-in on collection, then —
/// when the paired delivery is also done — an offer to close the order.
///
/// `JobDetailView` calls `begin(…)` after every successful status PATCH and
/// renders `step` as alerts/progress; all transitions happen here. Declining
/// any prompt leaves the local status change intact and touches nothing in
/// CRMS, exactly like the web.
@MainActor
@Observable
final class CrmsCompletionFlow {

    enum Step: Equatable {
        case idle
        /// Waiting on "Mark delivery/collection complete?".
        case confirmAction
        /// A network stage is running (asset collection, book-out/check-in, close-order).
        case working(String)
        /// Waiting on "Close this order in Current RMS?".
        case confirmClose
        /// Terminal info alert (success, warning, or failure).
        case result(title: String, message: String)
    }

    private(set) var step: Step = .idle

    private var client: APIClient?
    private var jobId = 0
    private var jobType: JobType = .delivery
    private var opportunityId = 0
    /// Asset ids collected for book-out/check-in, reused by close-order.
    private var itemAssetIds: [Int] = []

    var isWorking: Bool {
        if case .working = step { return true }
        return false
    }

    // MARK: - Entry

    /// Called after a status PATCH succeeds. No-op unless this PATCH is the one
    /// that completed the final movement of a CRMS-sourced job — the same
    /// trigger as the web: status became `completed`, wasn't before, the server
    /// says every movement is now completed, and the job has a `crms_id`
    /// (manual jobs are `nil` and never prompt).
    func begin(job: Job, oldStatus: JobStatus, newStatus: JobStatus,
               allMovementsCompleted: Bool, client: APIClient) {
        guard case .idle = step else { return }
        guard newStatus == .completed, oldStatus != .completed, allMovementsCompleted,
              let crmsId = job.crmsId, crmsId >= 10 else { return }
        self.client = client
        jobId = job.id
        jobType = job.type
        // crms_id = {opportunity_id}{1|2} (1 = delivery, 2 = collection) —
        // drop the type digit to get the opportunity.
        opportunityId = crmsId / 10
        itemAssetIds = []
        step = .confirmAction
    }

    // MARK: - Prompt wording (kept to the web app's)

    var confirmActionTitle: String {
        jobType == .delivery ? "Mark delivery complete?" : "Mark collection complete?"
    }

    var confirmActionMessage: String {
        jobType == .delivery
            ? "This will book out items in Current RMS."
            : "This will check in items in Current RMS."
    }

    static let confirmCloseTitle = "Close this order in Current RMS?"
    static let confirmCloseMessage = """
    Both delivery and collection are now complete.

    This will:
    • Finalise all items (make them available again)
    • Finalise service charges
    • Mark the order as Completed
    """

    // MARK: - Transitions (wired to alert buttons)

    /// "Confirm" on the book-out/check-in prompt.
    func confirmAction() {
        step = .working(jobType == .delivery
                        ? "Booking out items in Current RMS…"
                        : "Checking in items in Current RMS…")
        Task { await runAction() }
    }

    /// "Cancel" on the book-out/check-in prompt — local status stays, CRMS untouched.
    func cancel() {
        reset()
    }

    /// "Close Order" on the close prompt.
    func confirmClose() {
        step = .working("Closing order in Current RMS…")
        Task { await runCloseOrder() }
    }

    /// "Not Now" on the close prompt — check-in already succeeded, so just stop.
    func declineClose() {
        reset()
    }

    func reset() {
        step = .idle
        client = nil
        itemAssetIds = []
    }

    // MARK: - Network stages

    private func runAction() async {
        guard let client else { return reset() }
        do {
            let assetIds = try await collectAssetIds(client: client, servicesOnly: false)
            guard !assetIds.isEmpty else {
                step = .result(
                    title: "Current RMS",
                    message: "No item assets found for this opportunity. Current RMS action skipped."
                )
                return
            }
            itemAssetIds = assetIds
            switch jobType {
            case .delivery:
                try await client.bookOut(opportunityId: opportunityId, itemAssetIds: assetIds)
                step = .result(title: "Delivery complete",
                               message: "Items booked out in Current RMS.")
            case .collection:
                try await client.checkIn(opportunityId: opportunityId, itemAssetIds: assetIds)
                await offerCloseOrderIfReady(client: client)
            }
        } catch {
            let action = jobType == .delivery ? "book-out" : "check-in"
            step = .result(
                title: "Current RMS",
                message: "Current RMS \(action) failed: \(Self.describe(error))\n\nThe local status was still updated."
            )
        }
    }

    /// Only offer to close when the paired delivery is already completed —
    /// checked against the server's related jobs, not local state (which may be
    /// filtered), same as the web's `promptToCloseOrder`.
    private func offerCloseOrderIfReady(client: APIClient) async {
        let related = (try? await client.relatedJob(id: jobId)) ?? []
        let deliveryDone = related.contains { $0.type == .delivery && $0.status == .completed }
        guard deliveryDone else {
            step = .result(title: "Collection complete",
                           message: "Items checked in in Current RMS.")
            return
        }
        step = .confirmClose
    }

    private func runCloseOrder() async {
        guard let client else { return reset() }
        do {
            let serviceAssetIds = try await collectAssetIds(client: client, servicesOnly: true)
            let response = try await client.closeOrder(
                opportunityId: opportunityId,
                itemAssetIds: itemAssetIds,
                serviceAssetIds: serviceAssetIds
            )
            step = .result(title: "Close order", message: Self.closeOrderSummary(response))
        } catch {
            step = .result(title: "Close order",
                           message: "Failed to close order in Current RMS: \(Self.describe(error))")
        }
    }

    /// Walks the opportunity's items and gathers their asset ids — all items
    /// for book-out/check-in, service items only for close-order. Per-item
    /// asset-fetch failures are skipped, matching the web helpers.
    private func collectAssetIds(client: APIClient, servicesOnly: Bool) async throws -> [Int] {
        let items = try await client.opportunityItems(opportunityId: opportunityId).items
        var assetIds: [Int] = []
        for item in items {
            if servicesOnly && !item.isService { continue }
            if let assets = try? await client.opportunityItemAssets(
                opportunityId: opportunityId, itemId: item.id
            ) {
                assetIds.append(contentsOf: assets.assetIds)
            }
        }
        return assetIds
    }

    // MARK: - Messages

    private static func closeOrderSummary(_ response: CrmsCloseOrderResponse) -> String {
        var lines: [String] = []
        if response.results?.finaliseItems == true { lines.append("✓ Items finalised") }
        if response.results?.finaliseServices == true { lines.append("✓ Services finalised") }
        if response.results?.markCompleted == true { lines.append("✓ Order marked Completed") }
        let summary = lines.joined(separator: "\n")

        let errors = response.errors ?? []
        if !errors.isEmpty {
            let detail = errors
                .map { "✗ \($0.step ?? "step"): \($0.error ?? "unknown error")" }
                .joined(separator: "\n")
            return "Order closed with errors:\n\n\(summary)\n\n\(detail)"
        }
        let warnings = (response.warnings ?? []).compactMap(\.message)
        if !warnings.isEmpty {
            let detail = warnings.map { "⚠ \($0)" }.joined(separator: "\n")
            return "Order closed in Current RMS.\n\n\(summary)\n\nNote:\n\(detail)"
        }
        return "Order successfully closed in Current RMS.\n\n\(summary)"
    }

    private static func describe(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
