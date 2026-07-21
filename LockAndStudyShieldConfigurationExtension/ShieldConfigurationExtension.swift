import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration { makeConfiguration() }
  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { makeConfiguration() }
  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { makeConfiguration() }
  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { makeConfiguration() }

  private func makeConfiguration() -> ShieldConfiguration {
    ShieldConfiguration(
      backgroundBlurStyle: .systemThinMaterialDark,
      backgroundColor: UIColor(red: 0.04, green: 0.12, blue: 0.17, alpha: 1),
      icon: UIImage(systemName: "lock.open.rotation"),
      title: .init(text: "ロックンスタディ", color: .white),
      subtitle: .init(text: "学習すると、一時的に利用できます。", color: UIColor(white: 0.9, alpha: 1)),
      primaryButtonLabel: .init(text: "学習して開く", color: UIColor(red: 0.03, green: 0.15, blue: 0.18, alpha: 1)),
      primaryButtonBackgroundColor: UIColor(red: 0.50, green: 0.88, blue: 0.78, alpha: 1),
      secondaryButtonLabel: .init(text: "閉じる", color: UIColor(white: 0.92, alpha: 1))
    )
  }
}

