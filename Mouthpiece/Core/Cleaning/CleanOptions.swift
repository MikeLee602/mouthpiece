import Foundation

struct CleanOptions: Codable, Equatable, Sendable {
    var removeFillers: Bool = true
    var removeRepetition: Bool = true
    var normalizeSpaces: Bool = true
    var customFillers: [String] = []

    static let `default` = CleanOptions()

    static let zhFillers = ["嗯", "啊", "呃", "那个", "就是", "然后", "这个", "其实", "比如说"]
    static let enFillers = ["um", "uh", "you know", "like", "i mean", "basically"]
}
