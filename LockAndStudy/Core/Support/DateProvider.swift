import Foundation

protocol DateProviding: Sendable {
  func now() -> Date
}

struct SystemDateProvider: DateProviding {
  func now() -> Date { Date() }
}

final class FixedDateProvider: DateProviding, @unchecked Sendable {
  var date: Date
  init(_ date: Date) { self.date = date }
  func now() -> Date { date }
}

enum AppConfiguration {
  static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
  static let subscriptionManagementURL = URL(string: "https://apps.apple.com/account/subscriptions")!
  static let privacyPolicyURL: URL = {
    let value = Bundle.main.object(forInfoDictionaryKey: "LockAndStudyPrivacyPolicyURL") as? String
    return URL(string: value ?? "https://katonobo.com/lockandstudy-privacy-policy/")!
  }()
}

