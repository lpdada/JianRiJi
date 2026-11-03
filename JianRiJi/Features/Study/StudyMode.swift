import Foundation

/// 学习模式的分类。
enum StudyMode: String, CaseIterable, Identifiable, Hashable {
    /// ClassicReview / QuickReview
    case review
    /// PhoneticScreen + KnowVocabulary（给词形选假名）
    case kanaJudge
    /// SpellScreen02 / SpellBaseWordScreen
    case spell
    /// Lianlianka
    case connect
    /// SuishentingScreenV2（随身听，连播）
    case listen
    /// 手写输入（v0.3.0 新增）：看中文意思，在画布上写词形
    case handwriting
    /// 经典模式（v0.4.0 新增）：大字词卡 + 注音例句，洗脑循环 + 下一词
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "经典复习"
        case .kanaJudge: return "假名判断"
        case .spell: return "拼写"
        case .connect: return "连连看"
        case .listen: return "随身听"
        case .handwriting: return "手写"
        case .classic: return "经典模式"
        }
    }

    var subtitle: String {
        switch self {
        case .review: return "翻面回忆，四档评分"
        case .kanaJudge: return "看汉字，选读音"
        case .spell: return "听音写罗马字"
        case .connect: return "日文配中文"
        case .listen: return "循环听，不动手"
        case .handwriting: return "看意思写词形"
        case .classic: return "大字词卡 + 注音例句"
        }
    }

    var icon: String {
        switch self {
        case .review: return "rectangle.stack.fill"
        case .kanaJudge: return "character.book.closed.fill"
        case .spell: return "keyboard"
        case .connect: return "square.grid.2x2.fill"
        case .listen: return "headphones"
        case .handwriting: return "pencil"
        case .classic: return "book.fill"
        }
    }
}
