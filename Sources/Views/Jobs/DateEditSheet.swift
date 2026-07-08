import SwiftUI

/// Edit the opportunity's delivery & collection dates (admin). Saving pushes the
/// change to Current-RMS server-side and updates both linked jobs.
struct DateEditSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let job: Job
    let onSaved: () -> Void

    @State private var deliver = Date()
    @State private var collect = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Delivery", selection: $deliver, displayedComponents: .date)
                    DatePicker("Collection", selection: $collect, in: deliver..., displayedComponents: .date)
                } footer: {
                    Text("Changing dates updates Current-RMS and both the delivery and collection jobs.")
                }
                .listRowBackground(Theme.card)

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                        .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Hire dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() }
                    else { Button("Save") { Task { await save() } }.fontWeight(.semibold) }
                }
            }
            .onAppear(perform: seed)
        }
    }

    private func seed() {
        if let d = DateUtil.date(from: job.deliverDate) { deliver = d }
        if let c = DateUtil.date(from: job.collectDate) { collect = c }
        if collect < deliver { collect = deliver }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        if session.isDemo {
            onSaved()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            return
        }

        guard let client = session.client else { isSaving = false; return }
        do {
            try await client.updateDates(
                jobId: job.id,
                deliverDate: DateUtil.apiString(from: deliver),
                collectDate: DateUtil.apiString(from: collect)
            )
            onSaved()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isSaving = false
        }
    }
}
