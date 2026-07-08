import SwiftUI

/// Edit the opportunity's delivery & collection dates (admin). A pure editor —
/// it hands the edited dates back to the caller via `onSaved` and dismisses
/// immediately; the caller owns the PATCH (see `JobDetailView.saveDates`), since
/// dates aren't optimistic (Job has no local-edit helper for them).
struct DateEditSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let job: Job
    let onSaved: (_ deliverDate: String, _ collectDate: String) -> Void

    @State private var deliver = Date()
    @State private var collect = Date()

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
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Hire dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
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

    private func save() {
        onSaved(DateUtil.apiString(from: deliver), DateUtil.apiString(from: collect))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
