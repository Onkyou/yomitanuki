import Flutter
import Foundation
import Translation

/// Japanese to English (UK, US or plain English pack) through Apple's Translation framework. The session API
/// (`init(installedSource:target:)`) is iOS 26; the deployment target is 15.1,
/// so every use of the framework sits behind `#available` and the framework is
/// weak-linked (see the podspec). Languages are never downloaded from here: the
/// reader installs them under Settings > Apps > Translate.
public final class TranslationIosPlugin: NSObject, FlutterPlugin {
  /// A `Translator` on iOS 26+; `Any` because a stored property cannot carry
  /// the availability of its type.
  private var translator: Any?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "yomitanuki/translation", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TranslationIosPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status": status(result)
    case "translate": translate(call, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func status(_ result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else { return result("requiresNewerOs") }
    Task { @MainActor in
      switch await Translator.availability() {
      case .installed: result("installed")
      case .supported: result("supported")
      case .unsupported: result("unsupported")
      @unknown default: result("unsupported")
      }
    }
  }

  private func translate(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else {
      return result(FlutterError(code: "requiresNewerOs", message: "Needs iOS 26.", details: nil))
    }
    guard let args = call.arguments as? [String: Any], let lines = args["lines"] as? [String] else {
      return result(FlutterError(code: "badArguments", message: "Expected {lines: [String]}.", details: nil))
    }
    Task { @MainActor in
      let translator = (self.translator as? Translator) ?? Translator()
      self.translator = translator
      do {
        // nil must reach Dart as null; a bare [String?] bridge is not guaranteed to do that.
        result(try await translator.translate(lines).map { $0 as Any? ?? NSNull() })
      } catch TranslationError.notInstalled {
        self.translator = nil
        result(FlutterError(code: "notInstalled", message: "Japanese or English is not installed.", details: nil))
      } catch {
        // A failed session may be unusable; the next call makes a fresh one.
        self.translator = nil
        result(FlutterError(code: "translationFailed", message: "\(error)", details: nil))
      }
    }
  }
}

@available(iOS 26.0, *)
@MainActor
private final class Translator {
  private static let source = Locale.Language(identifier: "ja")

  /// Apple lists English variants as separate languages, and a pack for one is
  /// not "installed" for another. The reader's pack may be any of these, so the
  /// target is the first installed one in this fixed order.
  private static let targets = ["en-GB", "en-US", "en"].map { Locale.Language(identifier: $0) }

  private var session: TranslationSession?

  /// `installed` if any English variant is, else `supported` if any is, else `unsupported`.
  static func availability() async -> LanguageAvailability.Status {
    var best = LanguageAvailability.Status.unsupported
    for target in targets {
      switch await LanguageAvailability().status(from: source, to: target) {
      case .installed: return .installed
      case .supported: best = .supported
      default: break
      }
    }
    return best
  }

  private static func installedTarget() async -> Locale.Language? {
    for target in targets
    where await LanguageAvailability().status(from: source, to: target) == .installed {
      return target
    }
    return nil
  }

  private func makeSession() async throws -> TranslationSession {
    if let session { return session }
    guard let target = await Self.installedTarget() else { throw TranslationError.notInstalled }
    let made: TranslationSession
    if #available(iOS 26.4, *) {
      made = TranslationSession(
        installedSource: Self.source, target: target, preferredStrategy: .highFidelity)
    } else {
      made = TranslationSession(installedSource: Self.source, target: target)
    }
    session = made
    return made
  }

  /// Calls queue behind each other: one cached session is not documented as
  /// safe for overlapping `translate(batch:)` runs, and a second bubble can be
  /// tapped while the first is still translating.
  private var tail: Task<Void, Never>?

  func translate(_ lines: [String]) async throws -> [String?] {
    let previous = tail
    let task = Task { () throws -> [String?] in
      _ = await previous?.value
      return try await self.run(lines)
    }
    tail = Task { _ = try? await task.value }
    return try await task.value
  }

  /// One entry per line, nil where the framework answered nothing for it.
  private func run(_ lines: [String]) async throws -> [String?] {
    let session = try await makeSession()
    let requests = lines.enumerated().map {
      TranslationSession.Request(sourceText: $1, clientIdentifier: String($0))
    }
    var out = [String?](repeating: nil, count: lines.count)
    for try await response in session.translate(batch: requests) {
      if let id = response.clientIdentifier, let index = Int(id), out.indices.contains(index) {
        out[index] = response.targetText
      }
    }
    return out
  }
}
