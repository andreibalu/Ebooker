//
//  ModelContext+ExistingModel.swift
//  Pageless
//

import Foundation
import SwiftData

extension ModelContext {
    /// The live model for `id`, or nil when its row is gone.
    ///
    /// `model(for:)` hands back a model even for a deleted row, and reading any property of it
    /// traps. Share closures run long after the view that built them, so the record may have been
    /// deleted (or deleted by iCloud sync) in between. A registered model covers unsaved inserts;
    /// otherwise the row is fetched, and a model already marked deleted counts as missing.
    func existingModel<T: PersistentModel>(_ type: T.Type, id: PersistentIdentifier) -> T? {
        if let registered: T = registeredModel(for: id) {
            return registered.isDeleted ? nil : registered
        }
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let fetched = try? fetch(descriptor).first, !fetched.isDeleted else { return nil }
        return fetched
    }
}
