import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        if controller.loadError == nil {
            DemoDataWriter.seedIfNeeded(into: controller.container.viewContext)
        }
        return controller
    }()

    let container: NSPersistentContainer
    let loadError: Error?

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "LoonyBear")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        }

        var persistentStoreLoadError: Error?
        container.loadPersistentStores { _, error in
            if let error {
                persistentStoreLoadError = error
            }
        }
        loadError = persistentStoreLoadError

        if loadError == nil {
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }

    func makeBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}
