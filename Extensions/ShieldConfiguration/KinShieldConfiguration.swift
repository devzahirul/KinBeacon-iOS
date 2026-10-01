import Foundation
import ManagedSettings
import ManagedSettingsUI
import ScreenTimeShared
import UIKit

/// Renders the system shield ("Instagram is unavailable right now") using the same copy as the in-app preview.
final class KinShieldConfiguration: ShieldConfigurationDataSource {
    private let store = SharedPolicyStore()

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(appName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(appName: webDomain.domain)
    }

    private func make(appName: String?) -> ShieldConfiguration {
        let content = ShieldCopy.content(appName: appName, policy: store.loadPolicy(), now: Date())
        let brand = UIColor(red: 0.32, green: 0.27, blue: 0.9, alpha: 1)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: .systemBackground,
            icon: UIImage(systemName: "graduationcap.circle.fill")?.withTintColor(brand, renderingMode: .alwaysOriginal),
            title: .init(text: content.title, color: .label),
            subtitle: .init(text: content.subtitle, color: .secondaryLabel),
            primaryButtonLabel: content.primaryButton.map { .init(text: $0, color: .white) },
            primaryButtonBackgroundColor: brand,
            secondaryButtonLabel: .init(text: content.secondaryButton, color: brand)
        )
    }
}
