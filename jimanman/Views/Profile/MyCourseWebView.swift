import UIKit

enum MyCourseOpener {
    static let courseURL = "https://appejkiwpkt6085.h5.xet.citv.cn/p/t/v1/ecommerce/pay_record/record"

    @discardableResult
    static func openInExternalBrowser() -> Bool {
        guard let url = URL(string: courseURL) else { return false }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
}
