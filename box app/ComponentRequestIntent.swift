import AppIntents

@available(iOS 16.0, *)
struct ComponentRequestIntent: AppIntent {
    static var title: LocalizedStringResource = "Request Electronic Components"

    static var description = IntentDescription("Request one or more electronic components from the Box App.")

    @Parameter(title: "Components")
    var components: [ComponentEntity]

    func perform() async throws -> some IntentResult {
        // Process the requested components
        var result: [(String, Int)] = []
        for component in components {
            result.append((component.name, component.quantity))
        }

        // Here you would typically trigger an action in your app,
        // for example, by sending a notification or updating a database.
        // For now, we'll just return a success message.

        let componentsString = result.map { "\($0.1) of \($0.0)" }.joined(separator: ", ")

        // --- Integration with App: Broadcast Notification ---
        NotificationCenter.default.post(name: .componentRequest, object: nil, userInfo: ["components": result])
        // --- End Integration ---

        return .result(dialog: "Your request for \(componentsString) has been sent to the app.")
    }
}

@available(iOS 16.0, *)
struct ComponentEntity: AppEntity {
    @Property(title: "Name")
    var name: String

    @Property(title: "Quantity")
    var quantity: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Component"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(quantity) x \(name)")
    }
}