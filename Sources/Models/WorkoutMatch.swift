import Foundation

/// What closes a block automatically: a Health workout of a kind, or a study session.
/// Shared with the widget, so no Health types here.
enum WorkoutMatch: String, Codable, Sendable {
    case run
    case strength
    case study

    /// Minutes of study on the day needed to close a `.study` block.
    static let studyMinutesToClose = 20
}
