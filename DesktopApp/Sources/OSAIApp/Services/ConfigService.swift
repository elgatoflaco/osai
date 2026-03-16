import Foundation

class ConfigService {
    private let configDir = NSString("~/.desktop-agent").expandingTildeInPath
    private var configPath: String { "\(configDir)/config.json" }

    func saveActiveModel(_ model: String) {
        updateConfig { json in
            json["activeModel"] = model
        }
    }

    func saveSpendingLimits(_ limits: SpendingLimits) {
        updateConfig { json in
            json["spending_limits"] = [
                "daily_usd": limits.dailyUSD,
                "monthly_usd": limits.monthlyUSD,
                "per_session_usd": limits.perSessionUSD,
                "warn_at_percent": limits.warnAtPercent
            ] as [String: Any]
        }
    }

    func toggleGateway(_ name: String, enabled: Bool) {
        updateConfig { json in
            if var gateways = json["gateways"] as? [String: [String: Any]],
               var gw = gateways[name] {
                gw["enabled"] = enabled
                gateways[name] = gw
                json["gateways"] = gateways
            }
        }
    }

    private func updateConfig(_ transform: (inout [String: Any]) -> Void) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        transform(&json)

        if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? newData.write(to: URL(fileURLWithPath: configPath))
        }
    }
}
