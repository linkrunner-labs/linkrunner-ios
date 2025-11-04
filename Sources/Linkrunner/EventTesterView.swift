import SwiftUI

struct EventTesterView: View {
    @State private var eventName: String = "purchase"
    
    // Editable event data fields
    @State private var productId: String = "1"
    @State private var category: String = "electronics"
    @State private var amountString: String = "249.99"
    @State private var currency: String = "USD"
    @State private var isFeatured: Bool = true
    
    // Stable UUID for eventId (regenerated only if user taps regenerate)
    @State private var eventId: String = UUID().uuidString
    
    // Logs
    @State private var logs: [String] = []
    @State private var isSubmitting: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Name")) {
                    TextField("Enter event name", text: $eventName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section(header: Text("Event Data")) {
                    TextField("product_id", text: $productId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("category", text: $category)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    
                    TextField("currency", text: $currency)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    Toggle("is_featured", isOn: $isFeatured)
                }
                
                Section(header: Text("Event ID")) {
                    HStack {
                        Text(eventId)
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Regenerate") {
                            eventId = UUID().uuidString
                            appendLog("Regenerated eventId: \(eventId)")
                        }
                    }
                }
                
                Section {
                    Button(action: submit) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text("Submit Event")
                        }
                    }
                    .disabled(isSubmitting || eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                Section(header: Text("Logs")) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(logs.indices, id: \.self) { idx in
                                Text(logs[idx])
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 120)
                }
            }
            .navigationTitle("Linkrunner Event Tester")
        }
        .task {
            // Optional: initialize SDK here if not already initialized in App
            // Replace "YOUR_TOKEN" with a valid token if needed.
            if isProbablyNotInitialized() {
                appendLog("Initializing SDK...")
                await LinkrunnerSDK.shared.initialize(token: "YOUR_TOKEN", disableIdfa: true, debug: true)
                appendLog("SDK initialized")
            }
        }
    }
    
    private func submit() {
        isSubmitting = true
        appendLog("Preparing to submit event...")
        
        // Validate and parse amount
        let parsedAmount: Double? = Double(amountString.trimmingCharacters(in: .whitespacesAndNewlines))
        if parsedAmount == nil {
            appendLog("Invalid amount. Please enter a valid number.")
        }
        
        // Build event data dictionary
        var eventData: SendableDictionary = [:]
        eventData["product_id"] = productId
        eventData["category"] = category
        if let amt = parsedAmount {
            eventData["amount"] = amt
        }
        eventData["currency"] = currency
        eventData["is_featured"] = isFeatured
        
        let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = eventId
        
        appendLog("Submitting trackEvent with payload:")
        appendLog("eventName: \(name)")
        appendLog("eventId: \(id)")
        appendLog("eventData: \(eventData)")
        
        Task {
            await LinkrunnerSDK.shared.trackEvent(
                eventName: name,
                eventData: eventData,
                eventId: id
            )
            // The SDK prints debug logs itself; we add a local success log here.
            await MainActor.run {
                self.appendLog("Submitted trackEvent. Check console for SDK logs.")
                self.isSubmitting = false
            }
        }
    }
    
    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.append("[\(timestamp)] \(message)")
    }
    
    private func isProbablyNotInitialized() -> Bool {
        // Heuristic: We cannot read SDK state directly; we assume not initialized on first run.
        // If you already initialize in App, you can return false here.
        return true
    }
}

#Preview {
    EventTesterView()
}
