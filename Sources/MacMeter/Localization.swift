import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case italian = "it"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case malay = "ms"
    case indonesian = "id"
    case thai = "th"
    case vietnamese = "vi"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .portuguese: return "Português"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .malay: return "Bahasa Melayu"
        case .indonesian: return "Bahasa Indonesia"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        return Self.resolve(preferredLanguages: Locale.preferredLanguages)
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") {
                return .traditionalChinese
            }
            if normalized.hasPrefix("zh") { return .simplifiedChinese }
            if let match = allCases.dropFirst().first(where: {
                normalized == $0.rawValue.lowercased()
                    || normalized.hasPrefix($0.rawValue.lowercased() + "-")
            }) {
                return match
            }
        }
        return .english
    }

    var locale: Locale { Locale(identifier: resolved.rawValue) }
}

enum L10nKey: String {
    case systemDefault
    case settingsWindowTitle
    case metrics
    case appearance
    case general
    case about
    case visibleMetrics
    case cpuUsage
    case socTemperature
    case networkSpeed
    case batteryPower
    case displayValues
    case cpuConvention
    case temperature
    case networkUnit
    case overallConvention
    case allCoresConvention
    case celsius
    case fahrenheit
    case menuBarLayout
    case displayMode
    case compact
    case cycle
    case layoutExplanation
    case sampling
    case updateRate
    case startup
    case launchAtLogin
    case language
    case interfaceLanguage
    case enabled
    case approvalRequired
    case disabled
    case installRequired
    case unknown
    case openLoginSettings
    case privacy
    case platform
    case version
    case cpu
    case network
    case overall
    case allCores
    case hottest
    case sensors
    case inbound
    case outbound
    case interfaces
    case charging
    case draining
    case idle
    case updated
    case lastUpdated
    case waitingForData
    case settings
    case quit
    case unavailable
    case core
    case efficiency
    case performance
    case second
    case seconds
    case openSettingsAccessibility
    case quitAccessibility
    case noMetricsEnabled
}

struct Localizer: Equatable {
    let selection: AppLanguage

    var language: AppLanguage { selection.resolved }
    var locale: Locale { language.locale }

    func text(_ key: L10nKey) -> String {
        Self.translations[language]?[key] ?? Self.english[key] ?? key.rawValue
    }

    func formatted(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    func languageTitle(_ language: AppLanguage) -> String {
        language == .system ? text(.systemDefault) : language.nativeName
    }

    func updateRate(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return "\(value) \(text(value == 1 ? .second : .seconds))"
    }

    func version(_ info: AppVersionInfo) -> String {
        "\(text(.version)) \(info.version) (\(info.build))"
    }

    private static let english: [L10nKey: String] = [
        .systemDefault: "System Default", .settingsWindowTitle: "MacMeter Settings",
        .metrics: "Metrics", .appearance: "Appearance", .general: "General", .about: "About",
        .visibleMetrics: "Visible metrics", .cpuUsage: "CPU usage", .socTemperature: "SoC temperature",
        .networkSpeed: "Network speed", .batteryPower: "Battery power", .displayValues: "Display values",
        .cpuConvention: "CPU convention", .temperature: "Temperature", .networkUnit: "Network unit",
        .overallConvention: "Overall (0–100%)", .allCoresConvention: "All cores (n×100%)",
        .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Menu bar layout",
        .displayMode: "Display mode", .compact: "Compact", .cycle: "Cycle",
        .layoutExplanation: "Compact keeps selected metrics in two balanced rows. Network stays on top; Cycle rotates one metric every five seconds.",
        .sampling: "Sampling", .updateRate: "Update rate", .startup: "Startup",
        .launchAtLogin: "Launch at Login", .language: "Language", .interfaceLanguage: "Interface language",
        .enabled: "Enabled", .approvalRequired: "Approval required in System Settings", .disabled: "Disabled",
        .installRequired: "App must be installed before enabling", .unknown: "Unknown",
        .openLoginSettings: "Open Login Items Settings", .privacy: "Private by design: MacMeter reads local system counters and makes no network requests.",
        .platform: "Apple Silicon · macOS 13+", .version: "Version", .cpu: "CPU", .network: "Network",
        .overall: "Overall", .allCores: "All cores", .hottest: "Hottest", .sensors: "Sensors",
        .inbound: "Inbound", .outbound: "Outbound", .interfaces: "Interfaces", .charging: "Charging",
        .draining: "Draining", .idle: "Idle", .updated: "Updated %@", .lastUpdated: "Last updated %@",
        .waitingForData: "Waiting for data", .settings: "Settings…", .quit: "Quit", .unavailable: "Unavailable",
        .core: "Core", .efficiency: "Efficiency", .performance: "Performance", .second: "second",
        .seconds: "seconds", .openSettingsAccessibility: "Open MacMeter Settings",
        .quitAccessibility: "Quit MacMeter", .noMetricsEnabled: "MacMeter. No metrics enabled"
    ]

    private static let translations: [AppLanguage: [L10nKey: String]] = [
        .simplifiedChinese: [
            .systemDefault: "跟随系统", .settingsWindowTitle: "MacMeter 设置", .metrics: "指标", .appearance: "外观", .general: "通用", .about: "关于",
            .visibleMetrics: "显示的指标", .cpuUsage: "CPU 使用率", .socTemperature: "SoC 温度", .networkSpeed: "网络速度", .batteryPower: "电池功率",
            .displayValues: "显示数值", .cpuConvention: "CPU 计算方式", .temperature: "温度", .networkUnit: "网络单位", .overallConvention: "总体 (0–100%)",
            .allCoresConvention: "所有核心 (n×100%)", .celsius: "摄氏", .fahrenheit: "华氏", .menuBarLayout: "菜单栏布局", .displayMode: "显示模式",
            .compact: "紧凑", .cycle: "轮播", .layoutExplanation: "紧凑模式会将所选指标平衡排列为两行。网络始终位于上方；轮播模式每五秒切换一个指标。",
            .sampling: "采样", .updateRate: "更新频率", .startup: "启动", .launchAtLogin: "登录时启动", .language: "语言", .interfaceLanguage: "界面语言",
            .enabled: "已启用", .approvalRequired: "需要在系统设置中批准", .disabled: "已停用", .installRequired: "请先安装应用再启用", .unknown: "未知",
            .openLoginSettings: "打开登录项设置", .privacy: "隐私优先：MacMeter 仅读取本机系统计数器，不会发出网络请求。", .version: "版本",
            .cpu: "CPU", .network: "网络", .overall: "总体", .allCores: "所有核心", .hottest: "最高温度", .sensors: "传感器", .inbound: "下载",
            .outbound: "上传", .interfaces: "接口", .charging: "充电", .draining: "耗电", .idle: "空闲", .updated: "更新于 %@", .lastUpdated: "最后更新 %@",
            .waitingForData: "正在等待数据", .settings: "设置…", .quit: "退出", .unavailable: "不可用", .core: "核心", .efficiency: "能效核",
            .performance: "性能核", .second: "秒", .seconds: "秒", .openSettingsAccessibility: "打开 MacMeter 设置", .quitAccessibility: "退出 MacMeter",
            .noMetricsEnabled: "MacMeter。未启用任何指标"
        ],
        .traditionalChinese: [
            .systemDefault: "跟隨系統", .settingsWindowTitle: "MacMeter 設定", .metrics: "指標", .appearance: "外觀", .general: "一般", .about: "關於",
            .visibleMetrics: "顯示的指標", .cpuUsage: "CPU 使用率", .socTemperature: "SoC 溫度", .networkSpeed: "網路速度", .batteryPower: "電池功率",
            .displayValues: "顯示數值", .cpuConvention: "CPU 計算方式", .temperature: "溫度", .networkUnit: "網路單位", .overallConvention: "總體 (0–100%)",
            .allCoresConvention: "所有核心 (n×100%)", .celsius: "攝氏", .fahrenheit: "華氏", .menuBarLayout: "選單列佈局", .displayMode: "顯示模式",
            .compact: "精簡", .cycle: "輪播", .layoutExplanation: "精簡模式會將所選指標平衡排列為兩行。網路固定在上方；輪播模式每五秒切換一個指標。",
            .sampling: "取樣", .updateRate: "更新頻率", .startup: "啟動", .launchAtLogin: "登入時啟動", .language: "語言", .interfaceLanguage: "介面語言",
            .enabled: "已啟用", .approvalRequired: "需要在系統設定中核准", .disabled: "已停用", .installRequired: "請先安裝 App 再啟用", .unknown: "未知",
            .openLoginSettings: "打開登入項目設定", .privacy: "隱私優先：MacMeter 僅讀取本機系統計數器，不會發出網路要求。", .version: "版本",
            .cpu: "CPU", .network: "網路", .overall: "總體", .allCores: "所有核心", .hottest: "最高溫度", .sensors: "感測器", .inbound: "下載",
            .outbound: "上傳", .interfaces: "介面", .charging: "充電", .draining: "耗電", .idle: "閒置", .updated: "更新於 %@", .lastUpdated: "最後更新 %@",
            .waitingForData: "正在等待資料", .settings: "設定…", .quit: "結束", .unavailable: "無法使用", .core: "核心", .efficiency: "節能核心",
            .performance: "效能核心", .second: "秒", .seconds: "秒", .openSettingsAccessibility: "打開 MacMeter 設定", .quitAccessibility: "結束 MacMeter",
            .noMetricsEnabled: "MacMeter。未啟用任何指標"
        ],
        .japanese: [
            .systemDefault: "システム設定", .settingsWindowTitle: "MacMeter 設定", .metrics: "メトリクス", .appearance: "外観", .general: "一般", .about: "情報",
            .visibleMetrics: "表示する項目", .cpuUsage: "CPU 使用率", .socTemperature: "SoC 温度", .networkSpeed: "ネットワーク速度", .batteryPower: "バッテリー電力",
            .displayValues: "表示値", .cpuConvention: "CPU 表示方式", .temperature: "温度", .networkUnit: "ネットワーク単位", .overallConvention: "全体 (0–100%)",
            .allCoresConvention: "全コア (n×100%)", .celsius: "摂氏", .fahrenheit: "華氏", .menuBarLayout: "メニューバーの配置", .displayMode: "表示モード",
            .compact: "コンパクト", .cycle: "サイクル", .layoutExplanation: "コンパクトでは選択項目を2行に配置し、ネットワークを上段に固定します。サイクルは5秒ごとに項目を切り替えます。",
            .sampling: "サンプリング", .updateRate: "更新間隔", .startup: "起動", .launchAtLogin: "ログイン時に起動", .language: "言語", .interfaceLanguage: "表示言語",
            .enabled: "有効", .approvalRequired: "システム設定で承認が必要です", .disabled: "無効", .installRequired: "有効にする前にアプリをインストールしてください", .unknown: "不明",
            .openLoginSettings: "ログイン項目設定を開く", .privacy: "プライバシー重視：MacMeter はローカルのシステム情報のみを読み取り、ネットワーク通信を行いません。", .version: "バージョン",
            .cpu: "CPU", .network: "ネットワーク", .overall: "全体", .allCores: "全コア", .hottest: "最高", .sensors: "センサー", .inbound: "受信", .outbound: "送信",
            .interfaces: "インターフェイス", .charging: "充電中", .draining: "放電中", .idle: "待機", .updated: "更新 %@", .lastUpdated: "最終更新 %@",
            .waitingForData: "データを待機中", .settings: "設定…", .quit: "終了", .unavailable: "利用不可", .core: "コア", .efficiency: "高効率",
            .performance: "高性能", .second: "秒", .seconds: "秒", .openSettingsAccessibility: "MacMeter 設定を開く", .quitAccessibility: "MacMeter を終了",
            .noMetricsEnabled: "MacMeter。項目が有効になっていません"
        ],
        .korean: [
            .systemDefault: "시스템 기본값", .settingsWindowTitle: "MacMeter 설정", .metrics: "지표", .appearance: "모양", .general: "일반", .about: "정보",
            .visibleMetrics: "표시할 지표", .cpuUsage: "CPU 사용률", .socTemperature: "SoC 온도", .networkSpeed: "네트워크 속도", .batteryPower: "배터리 전력",
            .displayValues: "표시 값", .cpuConvention: "CPU 표시 방식", .temperature: "온도", .networkUnit: "네트워크 단위", .overallConvention: "전체 (0–100%)",
            .allCoresConvention: "모든 코어 (n×100%)", .celsius: "섭씨", .fahrenheit: "화씨", .menuBarLayout: "메뉴 막대 레이아웃", .displayMode: "표시 모드",
            .compact: "컴팩트", .cycle: "순환", .layoutExplanation: "컴팩트는 선택한 지표를 두 줄로 배치하고 네트워크를 위에 둡니다. 순환은 5초마다 한 지표를 표시합니다.",
            .sampling: "샘플링", .updateRate: "업데이트 주기", .startup: "시작", .launchAtLogin: "로그인 시 실행", .language: "언어", .interfaceLanguage: "인터페이스 언어",
            .enabled: "활성화됨", .approvalRequired: "시스템 설정에서 승인이 필요합니다", .disabled: "비활성화됨", .installRequired: "먼저 앱을 설치해야 합니다", .unknown: "알 수 없음",
            .openLoginSettings: "로그인 항목 설정 열기", .privacy: "개인정보 보호: MacMeter는 로컬 시스템 카운터만 읽고 네트워크 요청을 하지 않습니다.", .version: "버전",
            .cpu: "CPU", .network: "네트워크", .overall: "전체", .allCores: "모든 코어", .hottest: "최고", .sensors: "센서", .inbound: "수신", .outbound: "송신",
            .interfaces: "인터페이스", .charging: "충전 중", .draining: "방전 중", .idle: "대기", .updated: "업데이트 %@", .lastUpdated: "마지막 업데이트 %@",
            .waitingForData: "데이터 대기 중", .settings: "설정…", .quit: "종료", .unavailable: "사용할 수 없음", .core: "코어", .efficiency: "효율",
            .performance: "성능", .second: "초", .seconds: "초", .openSettingsAccessibility: "MacMeter 설정 열기", .quitAccessibility: "MacMeter 종료",
            .noMetricsEnabled: "MacMeter. 활성화된 지표 없음"
        ],
        .spanish: [
            .systemDefault: "Predeterminado del sistema", .settingsWindowTitle: "Ajustes de MacMeter", .metrics: "Métricas", .appearance: "Apariencia", .general: "General", .about: "Acerca de",
            .visibleMetrics: "Métricas visibles", .cpuUsage: "Uso de CPU", .socTemperature: "Temperatura del SoC", .networkSpeed: "Velocidad de red", .batteryPower: "Potencia de batería",
            .displayValues: "Valores mostrados", .cpuConvention: "Escala de CPU", .temperature: "Temperatura", .networkUnit: "Unidad de red", .overallConvention: "Total (0–100%)",
            .allCoresConvention: "Todos los núcleos (n×100%)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Diseño de la barra de menús", .displayMode: "Modo de visualización",
            .compact: "Compacto", .cycle: "Ciclo", .layoutExplanation: "Compacto distribuye las métricas seleccionadas en dos filas y mantiene la red arriba. Ciclo cambia de métrica cada cinco segundos.",
            .sampling: "Muestreo", .updateRate: "Frecuencia de actualización", .startup: "Inicio", .launchAtLogin: "Abrir al iniciar sesión", .language: "Idioma", .interfaceLanguage: "Idioma de la interfaz",
            .enabled: "Activado", .approvalRequired: "Se requiere aprobación en Ajustes del Sistema", .disabled: "Desactivado", .installRequired: "Instala la app antes de activarlo", .unknown: "Desconocido",
            .openLoginSettings: "Abrir ajustes de ítems de inicio", .privacy: "Privado por diseño: MacMeter lee contadores locales y no realiza solicitudes de red.", .version: "Versión",
            .cpu: "CPU", .network: "Red", .overall: "Total", .allCores: "Todos los núcleos", .hottest: "Máxima", .sensors: "Sensores", .inbound: "Entrada", .outbound: "Salida",
            .interfaces: "Interfaces", .charging: "Cargando", .draining: "Descargando", .idle: "Inactivo", .updated: "Actualizado %@", .lastUpdated: "Última actualización %@",
            .waitingForData: "Esperando datos", .settings: "Ajustes…", .quit: "Salir", .unavailable: "No disponible", .core: "Núcleo", .efficiency: "Eficiencia",
            .performance: "Rendimiento", .second: "segundo", .seconds: "segundos", .openSettingsAccessibility: "Abrir ajustes de MacMeter", .quitAccessibility: "Salir de MacMeter",
            .noMetricsEnabled: "MacMeter. No hay métricas activadas"
        ],
        .french: [
            .systemDefault: "Réglage du système", .settingsWindowTitle: "Réglages de MacMeter", .metrics: "Mesures", .appearance: "Apparence", .general: "Général", .about: "À propos",
            .visibleMetrics: "Mesures visibles", .cpuUsage: "Utilisation du processeur", .socTemperature: "Température du SoC", .networkSpeed: "Débit réseau", .batteryPower: "Puissance de la batterie",
            .displayValues: "Valeurs affichées", .cpuConvention: "Échelle du processeur", .temperature: "Température", .networkUnit: "Unité réseau", .overallConvention: "Global (0–100 %) ",
            .allCoresConvention: "Tous les cœurs (n×100 %)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Disposition de la barre des menus", .displayMode: "Mode d’affichage",
            .compact: "Compact", .cycle: "Cycle", .layoutExplanation: "Compact place les mesures choisies sur deux lignes et garde le réseau en haut. Cycle change de mesure toutes les cinq secondes.",
            .sampling: "Échantillonnage", .updateRate: "Fréquence d’actualisation", .startup: "Démarrage", .launchAtLogin: "Ouvrir à la connexion", .language: "Langue", .interfaceLanguage: "Langue de l’interface",
            .enabled: "Activé", .approvalRequired: "Autorisation requise dans Réglages Système", .disabled: "Désactivé", .installRequired: "Installez l’app avant l’activation", .unknown: "Inconnu",
            .openLoginSettings: "Ouvrir les réglages d’ouverture", .privacy: "Confidentiel par conception : MacMeter lit les compteurs locaux et n’effectue aucune requête réseau.", .version: "Version",
            .cpu: "Processeur", .network: "Réseau", .overall: "Global", .allCores: "Tous les cœurs", .hottest: "Maximale", .sensors: "Capteurs", .inbound: "Entrant", .outbound: "Sortant",
            .interfaces: "Interfaces", .charging: "En charge", .draining: "Décharge", .idle: "Inactif", .updated: "Actualisé %@", .lastUpdated: "Dernière actualisation %@",
            .waitingForData: "En attente de données", .settings: "Réglages…", .quit: "Quitter", .unavailable: "Indisponible", .core: "Cœur", .efficiency: "Efficacité",
            .performance: "Performance", .second: "seconde", .seconds: "secondes", .openSettingsAccessibility: "Ouvrir les réglages de MacMeter", .quitAccessibility: "Quitter MacMeter",
            .noMetricsEnabled: "MacMeter. Aucune mesure activée"
        ],
        .german: [
            .systemDefault: "Systemstandard", .settingsWindowTitle: "MacMeter-Einstellungen", .metrics: "Messwerte", .appearance: "Darstellung", .general: "Allgemein", .about: "Info",
            .visibleMetrics: "Sichtbare Messwerte", .cpuUsage: "CPU-Auslastung", .socTemperature: "SoC-Temperatur", .networkSpeed: "Netzwerkgeschwindigkeit", .batteryPower: "Batterieleistung",
            .displayValues: "Anzeigewerte", .cpuConvention: "CPU-Skalierung", .temperature: "Temperatur", .networkUnit: "Netzwerkeinheit", .overallConvention: "Gesamt (0–100 %)",
            .allCoresConvention: "Alle Kerne (n×100 %)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Menüleistenlayout", .displayMode: "Anzeigemodus",
            .compact: "Kompakt", .cycle: "Wechsel", .layoutExplanation: "Kompakt verteilt die ausgewählten Messwerte auf zwei Zeilen und hält das Netzwerk oben. Wechsel zeigt alle fünf Sekunden einen anderen Wert.",
            .sampling: "Abtastung", .updateRate: "Aktualisierungsrate", .startup: "Start", .launchAtLogin: "Bei Anmeldung öffnen", .language: "Sprache", .interfaceLanguage: "Oberflächensprache",
            .enabled: "Aktiviert", .approvalRequired: "Genehmigung in den Systemeinstellungen erforderlich", .disabled: "Deaktiviert", .installRequired: "App muss zuerst installiert werden", .unknown: "Unbekannt",
            .openLoginSettings: "Anmeldeobjekte öffnen", .privacy: "Privat konzipiert: MacMeter liest lokale Systemzähler und sendet keine Netzwerkanfragen.", .version: "Version",
            .cpu: "CPU", .network: "Netzwerk", .overall: "Gesamt", .allCores: "Alle Kerne", .hottest: "Höchste", .sensors: "Sensoren", .inbound: "Eingang", .outbound: "Ausgang",
            .interfaces: "Schnittstellen", .charging: "Laden", .draining: "Entladen", .idle: "Leerlauf", .updated: "Aktualisiert %@", .lastUpdated: "Zuletzt aktualisiert %@",
            .waitingForData: "Warte auf Daten", .settings: "Einstellungen…", .quit: "Beenden", .unavailable: "Nicht verfügbar", .core: "Kern", .efficiency: "Effizienz",
            .performance: "Leistung", .second: "Sekunde", .seconds: "Sekunden", .openSettingsAccessibility: "MacMeter-Einstellungen öffnen", .quitAccessibility: "MacMeter beenden",
            .noMetricsEnabled: "MacMeter. Keine Messwerte aktiviert"
        ],
        .portuguese: [
            .systemDefault: "Padrão do sistema", .settingsWindowTitle: "Definições do MacMeter", .metrics: "Métricas", .appearance: "Aparência", .general: "Geral", .about: "Sobre",
            .visibleMetrics: "Métricas visíveis", .cpuUsage: "Uso da CPU", .socTemperature: "Temperatura do SoC", .networkSpeed: "Velocidade da rede", .batteryPower: "Potência da bateria",
            .displayValues: "Valores apresentados", .cpuConvention: "Escala da CPU", .temperature: "Temperatura", .networkUnit: "Unidade de rede", .overallConvention: "Global (0–100%)",
            .allCoresConvention: "Todos os núcleos (n×100%)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Layout da barra de menus", .displayMode: "Modo de visualização",
            .compact: "Compacto", .cycle: "Ciclo", .layoutExplanation: "Compacto organiza as métricas em duas linhas e mantém a rede no topo. Ciclo alterna uma métrica a cada cinco segundos.",
            .sampling: "Amostragem", .updateRate: "Taxa de atualização", .startup: "Arranque", .launchAtLogin: "Abrir ao iniciar sessão", .language: "Idioma", .interfaceLanguage: "Idioma da interface",
            .enabled: "Ativado", .approvalRequired: "É necessária aprovação nas Definições do Sistema", .disabled: "Desativado", .installRequired: "Instale a app antes de ativar", .unknown: "Desconhecido",
            .openLoginSettings: "Abrir itens de início de sessão", .privacy: "Privado por conceção: o MacMeter lê contadores locais e não faz pedidos de rede.", .version: "Versão",
            .cpu: "CPU", .network: "Rede", .overall: "Global", .allCores: "Todos os núcleos", .hottest: "Máxima", .sensors: "Sensores", .inbound: "Entrada", .outbound: "Saída",
            .interfaces: "Interfaces", .charging: "A carregar", .draining: "A descarregar", .idle: "Inativo", .updated: "Atualizado %@", .lastUpdated: "Última atualização %@",
            .waitingForData: "A aguardar dados", .settings: "Definições…", .quit: "Sair", .unavailable: "Indisponível", .core: "Núcleo", .efficiency: "Eficiência",
            .performance: "Desempenho", .second: "segundo", .seconds: "segundos", .openSettingsAccessibility: "Abrir definições do MacMeter", .quitAccessibility: "Sair do MacMeter",
            .noMetricsEnabled: "MacMeter. Nenhuma métrica ativada"
        ],
        .italian: [
            .systemDefault: "Predefinito di sistema", .settingsWindowTitle: "Impostazioni MacMeter", .metrics: "Metriche", .appearance: "Aspetto", .general: "Generali", .about: "Informazioni",
            .visibleMetrics: "Metriche visibili", .cpuUsage: "Utilizzo CPU", .socTemperature: "Temperatura SoC", .networkSpeed: "Velocità di rete", .batteryPower: "Potenza batteria",
            .displayValues: "Valori visualizzati", .cpuConvention: "Scala CPU", .temperature: "Temperatura", .networkUnit: "Unità di rete", .overallConvention: "Complessivo (0–100%)",
            .allCoresConvention: "Tutti i core (n×100%)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Layout barra dei menu", .displayMode: "Modalità di visualizzazione",
            .compact: "Compatta", .cycle: "Ciclo", .layoutExplanation: "Compatta dispone le metriche su due righe e mantiene la rete in alto. Ciclo cambia metrica ogni cinque secondi.",
            .sampling: "Campionamento", .updateRate: "Frequenza aggiornamento", .startup: "Avvio", .launchAtLogin: "Apri al login", .language: "Lingua", .interfaceLanguage: "Lingua interfaccia",
            .enabled: "Attivo", .approvalRequired: "È richiesta l’approvazione in Impostazioni di Sistema", .disabled: "Disattivo", .installRequired: "Installa l’app prima di abilitarla", .unknown: "Sconosciuto",
            .openLoginSettings: "Apri impostazioni elementi login", .privacy: "Privato per design: MacMeter legge contatori locali e non effettua richieste di rete.", .version: "Versione",
            .cpu: "CPU", .network: "Rete", .overall: "Complessivo", .allCores: "Tutti i core", .hottest: "Massima", .sensors: "Sensori", .inbound: "Entrata", .outbound: "Uscita",
            .interfaces: "Interfacce", .charging: "In carica", .draining: "In scarica", .idle: "Inattivo", .updated: "Aggiornato %@", .lastUpdated: "Ultimo aggiornamento %@",
            .waitingForData: "In attesa di dati", .settings: "Impostazioni…", .quit: "Esci", .unavailable: "Non disponibile", .core: "Core", .efficiency: "Efficienza",
            .performance: "Prestazioni", .second: "secondo", .seconds: "secondi", .openSettingsAccessibility: "Apri impostazioni MacMeter", .quitAccessibility: "Esci da MacMeter",
            .noMetricsEnabled: "MacMeter. Nessuna metrica attiva"
        ],
        .russian: [
            .systemDefault: "Системный язык", .settingsWindowTitle: "Настройки MacMeter", .metrics: "Показатели", .appearance: "Вид", .general: "Основные", .about: "О программе",
            .visibleMetrics: "Видимые показатели", .cpuUsage: "Загрузка CPU", .socTemperature: "Температура SoC", .networkSpeed: "Скорость сети", .batteryPower: "Мощность батареи",
            .displayValues: "Отображение значений", .cpuConvention: "Шкала CPU", .temperature: "Температура", .networkUnit: "Единица сети", .overallConvention: "Общая (0–100%)",
            .allCoresConvention: "Все ядра (n×100%)", .celsius: "Цельсий", .fahrenheit: "Фаренгейт", .menuBarLayout: "Макет строки меню", .displayMode: "Режим отображения",
            .compact: "Компактный", .cycle: "Цикл", .layoutExplanation: "Компактный режим размещает показатели в две строки, сеть — сверху. Цикл меняет показатель каждые пять секунд.",
            .sampling: "Опрос", .updateRate: "Частота обновления", .startup: "Запуск", .launchAtLogin: "Запускать при входе", .language: "Язык", .interfaceLanguage: "Язык интерфейса",
            .enabled: "Включено", .approvalRequired: "Требуется разрешение в Системных настройках", .disabled: "Выключено", .installRequired: "Сначала установите приложение", .unknown: "Неизвестно",
            .openLoginSettings: "Открыть объекты входа", .privacy: "Конфиденциальность: MacMeter читает локальные счётчики и не выполняет сетевых запросов.", .version: "Версия",
            .cpu: "CPU", .network: "Сеть", .overall: "Общая", .allCores: "Все ядра", .hottest: "Максимум", .sensors: "Датчики", .inbound: "Вход", .outbound: "Выход",
            .interfaces: "Интерфейсы", .charging: "Зарядка", .draining: "Разрядка", .idle: "Ожидание", .updated: "Обновлено %@", .lastUpdated: "Последнее обновление %@",
            .waitingForData: "Ожидание данных", .settings: "Настройки…", .quit: "Выйти", .unavailable: "Недоступно", .core: "Ядро", .efficiency: "Эффективное",
            .performance: "Производительное", .second: "секунда", .seconds: "секунд", .openSettingsAccessibility: "Открыть настройки MacMeter", .quitAccessibility: "Выйти из MacMeter",
            .noMetricsEnabled: "MacMeter. Нет включённых показателей"
        ],
        .arabic: [
            .systemDefault: "إعداد النظام", .settingsWindowTitle: "إعدادات MacMeter", .metrics: "المقاييس", .appearance: "المظهر", .general: "عام", .about: "حول",
            .visibleMetrics: "المقاييس الظاهرة", .cpuUsage: "استخدام CPU", .socTemperature: "حرارة SoC", .networkSpeed: "سرعة الشبكة", .batteryPower: "طاقة البطارية",
            .displayValues: "قيم العرض", .cpuConvention: "مقياس CPU", .temperature: "الحرارة", .networkUnit: "وحدة الشبكة", .overallConvention: "الإجمالي (0–100%)",
            .allCoresConvention: "كل الأنوية (n×100%)", .celsius: "مئوية", .fahrenheit: "فهرنهايت", .menuBarLayout: "تخطيط شريط القوائم", .displayMode: "وضع العرض",
            .compact: "مضغوط", .cycle: "تدوير", .layoutExplanation: "يرتب الوضع المضغوط المقاييس في صفين ويُبقي الشبكة في الأعلى. يبدّل التدوير المقياس كل خمس ثوانٍ.",
            .sampling: "أخذ العينات", .updateRate: "معدل التحديث", .startup: "بدء التشغيل", .launchAtLogin: "التشغيل عند الدخول", .language: "اللغة", .interfaceLanguage: "لغة الواجهة",
            .enabled: "مفعّل", .approvalRequired: "يلزم الاعتماد في إعدادات النظام", .disabled: "معطّل", .installRequired: "يجب تثبيت التطبيق أولاً", .unknown: "غير معروف",
            .openLoginSettings: "فتح إعدادات عناصر الدخول", .privacy: "خاص بطبيعته: يقرأ MacMeter عدادات النظام المحلية ولا يرسل طلبات شبكة.", .version: "الإصدار",
            .cpu: "CPU", .network: "الشبكة", .overall: "الإجمالي", .allCores: "كل الأنوية", .hottest: "الأعلى", .sensors: "المستشعرات", .inbound: "الوارد", .outbound: "الصادر",
            .interfaces: "الواجهات", .charging: "شحن", .draining: "استهلاك", .idle: "خامل", .updated: "حُدّث %@", .lastUpdated: "آخر تحديث %@",
            .waitingForData: "بانتظار البيانات", .settings: "الإعدادات…", .quit: "إنهاء", .unavailable: "غير متاح", .core: "النواة", .efficiency: "كفاءة",
            .performance: "أداء", .second: "ثانية", .seconds: "ثوانٍ", .openSettingsAccessibility: "فتح إعدادات MacMeter", .quitAccessibility: "إنهاء MacMeter",
            .noMetricsEnabled: "MacMeter. لا توجد مقاييس مفعّلة"
        ],
        .hindi: [
            .systemDefault: "सिस्टम डिफ़ॉल्ट", .settingsWindowTitle: "MacMeter सेटिंग्स", .metrics: "मेट्रिक्स", .appearance: "रूप", .general: "सामान्य", .about: "परिचय",
            .visibleMetrics: "दिखने वाले मेट्रिक्स", .cpuUsage: "CPU उपयोग", .socTemperature: "SoC तापमान", .networkSpeed: "नेटवर्क गति", .batteryPower: "बैटरी पावर",
            .displayValues: "प्रदर्शन मान", .cpuConvention: "CPU पैमाना", .temperature: "तापमान", .networkUnit: "नेटवर्क इकाई", .overallConvention: "कुल (0–100%)",
            .allCoresConvention: "सभी कोर (n×100%)", .celsius: "सेल्सियस", .fahrenheit: "फ़ारेनहाइट", .menuBarLayout: "मेनू बार लेआउट", .displayMode: "प्रदर्शन मोड",
            .compact: "कॉम्पैक्ट", .cycle: "चक्र", .layoutExplanation: "कॉम्पैक्ट मेट्रिक्स को दो पंक्तियों में रखता है और नेटवर्क ऊपर रहता है। चक्र हर पाँच सेकंड में मेट्रिक बदलता है।",
            .sampling: "सैंपलिंग", .updateRate: "अपडेट दर", .startup: "स्टार्टअप", .launchAtLogin: "लॉगिन पर खोलें", .language: "भाषा", .interfaceLanguage: "इंटरफ़ेस भाषा",
            .enabled: "सक्षम", .approvalRequired: "सिस्टम सेटिंग्स में अनुमति आवश्यक", .disabled: "अक्षम", .installRequired: "पहले ऐप इंस्टॉल करें", .unknown: "अज्ञात",
            .openLoginSettings: "लॉगिन आइटम सेटिंग्स खोलें", .privacy: "गोपनीयता के लिए बनाया गया: MacMeter केवल स्थानीय सिस्टम काउंटर पढ़ता है और नेटवर्क अनुरोध नहीं करता।", .version: "संस्करण",
            .cpu: "CPU", .network: "नेटवर्क", .overall: "कुल", .allCores: "सभी कोर", .hottest: "अधिकतम", .sensors: "सेंसर", .inbound: "आवक", .outbound: "जावक",
            .interfaces: "इंटरफ़ेस", .charging: "चार्ज हो रहा", .draining: "डिस्चार्ज", .idle: "निष्क्रिय", .updated: "अपडेट %@", .lastUpdated: "अंतिम अपडेट %@",
            .waitingForData: "डेटा की प्रतीक्षा", .settings: "सेटिंग्स…", .quit: "बंद करें", .unavailable: "अनुपलब्ध", .core: "कोर", .efficiency: "दक्षता",
            .performance: "प्रदर्शन", .second: "सेकंड", .seconds: "सेकंड", .openSettingsAccessibility: "MacMeter सेटिंग्स खोलें", .quitAccessibility: "MacMeter बंद करें",
            .noMetricsEnabled: "MacMeter. कोई मेट्रिक सक्षम नहीं"
        ],
        .malay: [
            .systemDefault: "Lalai Sistem", .settingsWindowTitle: "Tetapan MacMeter", .metrics: "Metrik", .appearance: "Penampilan", .general: "Umum", .about: "Perihal",
            .visibleMetrics: "Metrik kelihatan", .cpuUsage: "Penggunaan CPU", .socTemperature: "Suhu SoC", .networkSpeed: "Kelajuan rangkaian", .batteryPower: "Kuasa bateri",
            .displayValues: "Nilai paparan", .cpuConvention: "Skala CPU", .temperature: "Suhu", .networkUnit: "Unit rangkaian", .overallConvention: "Keseluruhan (0–100%)",
            .allCoresConvention: "Semua teras (n×100%)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Susun atur bar menu", .displayMode: "Mod paparan",
            .compact: "Padat", .cycle: "Kitar", .layoutExplanation: "Padat menyusun metrik dalam dua baris dan mengekalkan rangkaian di atas. Kitar menukar metrik setiap lima saat.",
            .sampling: "Pensampelan", .updateRate: "Kadar kemas kini", .startup: "Permulaan", .launchAtLogin: "Buka semasa log masuk", .language: "Bahasa", .interfaceLanguage: "Bahasa antara muka",
            .enabled: "Didayakan", .approvalRequired: "Kelulusan diperlukan dalam Tetapan Sistem", .disabled: "Dilumpuhkan", .installRequired: "Pasang aplikasi sebelum mendayakan", .unknown: "Tidak diketahui",
            .openLoginSettings: "Buka Tetapan Item Log Masuk", .privacy: "Privasi terbina: MacMeter membaca kaunter sistem setempat dan tidak membuat permintaan rangkaian.", .version: "Versi",
            .cpu: "CPU", .network: "Rangkaian", .overall: "Keseluruhan", .allCores: "Semua teras", .hottest: "Tertinggi", .sensors: "Penderia", .inbound: "Masuk", .outbound: "Keluar",
            .interfaces: "Antara muka", .charging: "Mengecas", .draining: "Menggunakan", .idle: "Melahu", .updated: "Dikemas kini %@", .lastUpdated: "Kemas kini terakhir %@",
            .waitingForData: "Menunggu data", .settings: "Tetapan…", .quit: "Keluar", .unavailable: "Tidak tersedia", .core: "Teras", .efficiency: "Kecekapan",
            .performance: "Prestasi", .second: "saat", .seconds: "saat", .openSettingsAccessibility: "Buka Tetapan MacMeter", .quitAccessibility: "Keluar MacMeter",
            .noMetricsEnabled: "MacMeter. Tiada metrik didayakan"
        ],
        .indonesian: [
            .systemDefault: "Bawaan Sistem", .settingsWindowTitle: "Pengaturan MacMeter", .metrics: "Metrik", .appearance: "Tampilan", .general: "Umum", .about: "Tentang",
            .visibleMetrics: "Metrik terlihat", .cpuUsage: "Penggunaan CPU", .socTemperature: "Suhu SoC", .networkSpeed: "Kecepatan jaringan", .batteryPower: "Daya baterai",
            .displayValues: "Nilai tampilan", .cpuConvention: "Skala CPU", .temperature: "Suhu", .networkUnit: "Unit jaringan", .overallConvention: "Keseluruhan (0–100%)",
            .allCoresConvention: "Semua inti (n×100%)", .celsius: "Celsius", .fahrenheit: "Fahrenheit", .menuBarLayout: "Tata letak bar menu", .displayMode: "Mode tampilan",
            .compact: "Ringkas", .cycle: "Siklus", .layoutExplanation: "Ringkas menata metrik dalam dua baris dan menempatkan jaringan di atas. Siklus mengganti metrik setiap lima detik.",
            .sampling: "Pengambilan sampel", .updateRate: "Laju pembaruan", .startup: "Mulai", .launchAtLogin: "Buka saat masuk", .language: "Bahasa", .interfaceLanguage: "Bahasa antarmuka",
            .enabled: "Aktif", .approvalRequired: "Persetujuan diperlukan di Pengaturan Sistem", .disabled: "Nonaktif", .installRequired: "Instal app sebelum mengaktifkan", .unknown: "Tidak diketahui",
            .openLoginSettings: "Buka Pengaturan Item Masuk", .privacy: "Privat sejak awal: MacMeter hanya membaca penghitung lokal dan tidak membuat permintaan jaringan.", .version: "Versi",
            .cpu: "CPU", .network: "Jaringan", .overall: "Keseluruhan", .allCores: "Semua inti", .hottest: "Tertinggi", .sensors: "Sensor", .inbound: "Masuk", .outbound: "Keluar",
            .interfaces: "Antarmuka", .charging: "Mengisi", .draining: "Menguras", .idle: "Diam", .updated: "Diperbarui %@", .lastUpdated: "Terakhir diperbarui %@",
            .waitingForData: "Menunggu data", .settings: "Pengaturan…", .quit: "Keluar", .unavailable: "Tidak tersedia", .core: "Inti", .efficiency: "Efisiensi",
            .performance: "Performa", .second: "detik", .seconds: "detik", .openSettingsAccessibility: "Buka Pengaturan MacMeter", .quitAccessibility: "Keluar dari MacMeter",
            .noMetricsEnabled: "MacMeter. Tidak ada metrik aktif"
        ],
        .thai: [
            .systemDefault: "ค่าเริ่มต้นของระบบ", .settingsWindowTitle: "การตั้งค่า MacMeter", .metrics: "ตัวชี้วัด", .appearance: "ลักษณะ", .general: "ทั่วไป", .about: "เกี่ยวกับ",
            .visibleMetrics: "ตัวชี้วัดที่แสดง", .cpuUsage: "การใช้ CPU", .socTemperature: "อุณหภูมิ SoC", .networkSpeed: "ความเร็วเครือข่าย", .batteryPower: "พลังงานแบตเตอรี่",
            .displayValues: "ค่าที่แสดง", .cpuConvention: "มาตราส่วน CPU", .temperature: "อุณหภูมิ", .networkUnit: "หน่วยเครือข่าย", .overallConvention: "รวม (0–100%)",
            .allCoresConvention: "ทุกคอร์ (n×100%)", .celsius: "เซลเซียส", .fahrenheit: "ฟาเรนไฮต์", .menuBarLayout: "เค้าโครงแถบเมนู", .displayMode: "โหมดแสดงผล",
            .compact: "กะทัดรัด", .cycle: "วน", .layoutExplanation: "โหมดกะทัดรัดจัดตัวชี้วัดเป็นสองแถวและวางเครือข่ายไว้ด้านบน โหมดวนจะเปลี่ยนทุกห้าวินาที",
            .sampling: "การเก็บตัวอย่าง", .updateRate: "อัตราการอัปเดต", .startup: "เริ่มต้น", .launchAtLogin: "เปิดเมื่อเข้าสู่ระบบ", .language: "ภาษา", .interfaceLanguage: "ภาษาของอินเทอร์เฟซ",
            .enabled: "เปิดใช้", .approvalRequired: "ต้องอนุมัติในการตั้งค่าระบบ", .disabled: "ปิดใช้", .installRequired: "ต้องติดตั้งแอปก่อน", .unknown: "ไม่ทราบ",
            .openLoginSettings: "เปิดการตั้งค่ารายการเข้าสู่ระบบ", .privacy: "ออกแบบเพื่อความเป็นส่วนตัว: MacMeter อ่านเฉพาะข้อมูลในเครื่องและไม่ส่งคำขอเครือข่าย", .version: "เวอร์ชัน",
            .cpu: "CPU", .network: "เครือข่าย", .overall: "รวม", .allCores: "ทุกคอร์", .hottest: "สูงสุด", .sensors: "เซ็นเซอร์", .inbound: "ขาเข้า", .outbound: "ขาออก",
            .interfaces: "อินเทอร์เฟซ", .charging: "กำลังชาร์จ", .draining: "กำลังใช้ไฟ", .idle: "ว่าง", .updated: "อัปเดต %@", .lastUpdated: "อัปเดตล่าสุด %@",
            .waitingForData: "กำลังรอข้อมูล", .settings: "การตั้งค่า…", .quit: "ออก", .unavailable: "ไม่พร้อมใช้", .core: "คอร์", .efficiency: "ประหยัดพลังงาน",
            .performance: "ประสิทธิภาพ", .second: "วินาที", .seconds: "วินาที", .openSettingsAccessibility: "เปิดการตั้งค่า MacMeter", .quitAccessibility: "ออกจาก MacMeter",
            .noMetricsEnabled: "MacMeter ไม่มีตัวชี้วัดที่เปิดใช้"
        ],
        .vietnamese: [
            .systemDefault: "Mặc định hệ thống", .settingsWindowTitle: "Cài đặt MacMeter", .metrics: "Chỉ số", .appearance: "Giao diện", .general: "Chung", .about: "Giới thiệu",
            .visibleMetrics: "Chỉ số hiển thị", .cpuUsage: "Mức dùng CPU", .socTemperature: "Nhiệt độ SoC", .networkSpeed: "Tốc độ mạng", .batteryPower: "Công suất pin",
            .displayValues: "Giá trị hiển thị", .cpuConvention: "Thang CPU", .temperature: "Nhiệt độ", .networkUnit: "Đơn vị mạng", .overallConvention: "Tổng (0–100%)",
            .allCoresConvention: "Tất cả lõi (n×100%)", .celsius: "Độ C", .fahrenheit: "Độ F", .menuBarLayout: "Bố cục thanh menu", .displayMode: "Chế độ hiển thị",
            .compact: "Gọn", .cycle: "Luân phiên", .layoutExplanation: "Chế độ Gọn xếp chỉ số thành hai hàng và giữ mạng ở trên. Luân phiên đổi chỉ số mỗi năm giây.",
            .sampling: "Lấy mẫu", .updateRate: "Tần suất cập nhật", .startup: "Khởi động", .launchAtLogin: "Mở khi đăng nhập", .language: "Ngôn ngữ", .interfaceLanguage: "Ngôn ngữ giao diện",
            .enabled: "Đã bật", .approvalRequired: "Cần phê duyệt trong Cài đặt hệ thống", .disabled: "Đã tắt", .installRequired: "Cần cài ứng dụng trước", .unknown: "Không rõ",
            .openLoginSettings: "Mở cài đặt mục đăng nhập", .privacy: "Riêng tư theo thiết kế: MacMeter chỉ đọc bộ đếm cục bộ và không gửi yêu cầu mạng.", .version: "Phiên bản",
            .cpu: "CPU", .network: "Mạng", .overall: "Tổng", .allCores: "Tất cả lõi", .hottest: "Cao nhất", .sensors: "Cảm biến", .inbound: "Vào", .outbound: "Ra",
            .interfaces: "Giao diện", .charging: "Đang sạc", .draining: "Đang xả", .idle: "Không đổi", .updated: "Đã cập nhật %@", .lastUpdated: "Cập nhật lần cuối %@",
            .waitingForData: "Đang chờ dữ liệu", .settings: "Cài đặt…", .quit: "Thoát", .unavailable: "Không khả dụng", .core: "Lõi", .efficiency: "Tiết kiệm",
            .performance: "Hiệu năng", .second: "giây", .seconds: "giây", .openSettingsAccessibility: "Mở cài đặt MacMeter", .quitAccessibility: "Thoát MacMeter",
            .noMetricsEnabled: "MacMeter. Không có chỉ số nào được bật"
        ]
    ]
}
