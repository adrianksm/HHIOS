import SwiftUI

/// The edited fields from a `MovementEditSheet` save, handed to the parent
/// (`JobDetailView`) to apply optimistically and PATCH in the background. The
/// sheet itself never touches the network — see `JobDetailView.saveMovement`.
struct MovementEdit {
    let status: JobStatus
    let notes: String
    let haulier: APIClient.HaulierChange
    let date: APIClient.DateChange
}

/// Edit a single load: status + notes (all roles), haulier + per-movement date
/// (admins). A pure editor — it hands the edited values back to the caller via
/// `onSaved` and dismisses immediately; the caller owns the PATCH so a dismissed
/// sheet can't strand an in-flight save.
struct MovementEditSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let movement: Movement
    let load: [LineItem]
    let onSaved: (MovementEdit) -> Void

    @State private var status: JobStatus = .pending
    @State private var notes: String = ""
    @State private var haulierId: Int?
    @State private var overrideDate = false
    @State private var date = Date()

    private var isAdmin: Bool { session.isAdmin }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Transport", value: movement.transportLabel)
                    LabeledContent("Load", value: "\(movement.loadPosition) of \(movement.totalMovements)")
                }
                .listRowBackground(Theme.card)

                Section {
                    if load.isEmpty {
                        Text("Empty load").foregroundStyle(Theme.tertiary)
                    } else {
                        ForEach(load) { item in
                            HStack {
                                Text(item.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("× \(item.quantity)").fontWeight(.semibold).foregroundStyle(Theme.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("On this load")
                } footer: {
                    Text("Auto-allocated by vehicle capacity unless set manually in the web app.")
                }
                .listRowBackground(Theme.card)

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Theme.card)

                if isAdmin {
                    Section("Haulier") {
                        Picker("Haulier", selection: $haulierId) {
                            Text("Unassigned").tag(Int?.none)
                            ForEach(session.hauliers) { h in
                                HStack {
                                    Circle().fill(Color(hex: h.color, fallback: .gray)).frame(width: 10, height: 10)
                                    Text(h.name)
                                }
                                .tag(Int?.some(h.id))
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Toggle("Override date", isOn: $overrideDate.animation())
                        if overrideDate {
                            DatePicker("Load date", selection: $date, displayedComponents: .date)
                        }
                    } footer: {
                        Text(overrideDate
                             ? "This load runs on a different day from the job."
                             : "This load uses the job's date.")
                    }
                    .listRowBackground(Theme.card)
                }

                whatsAppSection

                Section("Notes") {
                    TextField("Add a note…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle(movement.loadLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: seed)
        }
    }

    @ViewBuilder
    private var whatsAppSection: some View {
        if let haulier = session.haulier(id: haulierId) {
            let digits = WhatsApp.formatUKPhone(haulier.phone)
            Section {
                Button {
                    if let digits { sendWhatsApp(to: haulier, phoneDigits: digits) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "message.fill")
                            .foregroundStyle(digits == nil ? Color.gray : Theme.whatsApp)
                        Text("Send load to \(haulier.name)")
                            .foregroundStyle(digits == nil ? Theme.tertiary : Color(hex: "#1E9E4C", fallback: .green))
                    }
                }
                .disabled(digits == nil)
            } header: {
                Text("WhatsApp")
            } footer: {
                Text(digits == nil
                     ? "No phone number for \(haulier.name) — add one in the web app."
                     : "Opens WhatsApp with the event, address, items and notes prefilled.")
            }
            .listRowBackground(Theme.card)
        }
    }

    private func sendWhatsApp(to haulier: Haulier, phoneDigits: String) {
        let dateString = overrideDate ? DateUtil.apiString(from: date) : movement.effectiveDate
        let message = WhatsApp.message(
            jobType: movement.job.type,
            eventName: movement.job.eventName,
            dateString: dateString,
            transportName: movement.transportName,
            loadPosition: movement.loadPosition,
            totalMovements: movement.totalMovements,
            contactName: movement.job.contactName,
            contactPhone: movement.job.contactPhone,
            destination: movement.job.destination,
            postcode: movement.job.destinationPostcode,
            items: load,
            notes: notes
        )
        if let url = WhatsApp.url(phoneDigits: phoneDigits, message: message) {
            openURL(url)
        }
    }

    private func seed() {
        status = movement.status
        notes = movement.notes
        haulierId = movement.haulierId
        if let override = movement.dateOverride, let d = DateUtil.date(from: override) {
            overrideDate = true
            date = d
        } else if let d = DateUtil.date(from: movement.effectiveDate) {
            date = d
        }
    }

    /// Hands the edited fields to the parent, fires the success haptic, and
    /// dismisses immediately — the parent applies them optimistically and owns
    /// the PATCH (see `JobDetailView.saveMovement`), so this never awaits the
    /// network.
    private func save() {
        guard movement.transportName != nil else { dismiss(); return }

        let newDateString = overrideDate ? DateUtil.apiString(from: date) : nil
        let haulierChange: APIClient.HaulierChange =
            (isAdmin && haulierId != movement.haulierId) ? .set(haulierId) : .unchanged
        let dateChange: APIClient.DateChange =
            (isAdmin && newDateString != movement.dateOverride) ? .set(newDateString) : .unchanged

        onSaved(MovementEdit(status: status, notes: notes, haulier: haulierChange, date: dateChange))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
