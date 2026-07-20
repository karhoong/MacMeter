import XCTest
@testable import MacMeter

final class LocalizationTests: XCTestCase {
    func testSystemLanguageResolutionCoversChineseScriptsAndFallback() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-Hant-HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["ms-MY"]), .malay)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["de-DE"]), .german)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["unsupported"]), .english)
    }

    func testEverySupportedLanguageHasLocalizedPrimaryNavigationAndSettingsCopy() {
        XCTAssertEqual(AppLanguage.allCases.count, 18)
        for language in AppLanguage.allCases where language != .system {
            let localizer = Localizer(selection: language)
            let values = [
                localizer.text(.settingsWindowTitle),
                localizer.text(.metrics),
                localizer.text(.appearance),
                localizer.text(.general),
                localizer.text(.visibleMetrics),
                localizer.text(.language),
                localizer.text(.settings),
                localizer.text(.quit)
            ]
            XCTAssertTrue(values.allSatisfy { !$0.isEmpty }, "Missing primary localization for \(language.rawValue)")
        }
    }

    func testLanguageNamesStayNativeAndRateFormattingUsesSelection() {
        let malay = Localizer(selection: .malay)
        XCTAssertEqual(malay.languageTitle(.malay), "Bahasa Melayu")
        XCTAssertEqual(malay.updateRate(1), "1 saat")
        XCTAssertEqual(malay.updateRate(10), "10 saat")

        let japanese = Localizer(selection: .japanese)
        XCTAssertEqual(japanese.languageTitle(.japanese), "日本語")
        XCTAssertEqual(japanese.version(AppVersionInfo(version: "1.0.3", build: "1")), "バージョン 1.0.3 (1)")
    }
}
