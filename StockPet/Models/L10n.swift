import Foundation

func tr(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

var stockPetLocale: Locale {
#if ENGLISH_BUILD
    Locale(identifier: "en_US")
#else
    Locale(identifier: "zh_CN")
#endif
}

func localizedStockName(_ sourceName: String, code: String) -> String {
#if ENGLISH_BUILD
    let knownNames = [
        "600519": "Kweichow Moutai",
        "00700": "Tencent Holdings",
        "AAPL": "Apple",
        "300308": "Zhongji Innolight",
        "07200": "CSOP HSI 2x Daily Long"
    ]
    if let knownName = knownNames[code.uppercased()] {
        return knownName
    }
    if sourceName.range(
        of: #"\p{Script=Han}"#,
        options: .regularExpression
    ) != nil {
        return code.uppercased()
    }
#endif
    return sourceName
}
