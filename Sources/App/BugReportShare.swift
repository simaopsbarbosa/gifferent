import AppKit
import Foundation
import Security
import SwiftUI

struct BugReportFields: Encodable, Equatable {
  var repository = ""
  var repositoryID: Int64 = 0
  var title = ""
  var steps = ""
  var expected = ""
  var actual = ""

  var isComplete: Bool {
    repositoryID > 0
      && [title, steps, expected, actual].allSatisfy {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  func encoded() throws -> Data {
    let values = [title, steps, expected, actual]
    let limits = [120, 1_000, 1_000, 1_000]
    guard isComplete,
      zip(values, limits).allSatisfy({ $0.unicodeScalars.count <= $1 }),
      title.rangeOfCharacter(from: .controlCharacters) == nil
    else { throw BugReportError.fields }
    let data = try JSONEncoder().encode(self)
    guard data.count <= 6_000 else { throw BugReportError.fields }
    return data
  }
}

enum BugReportError: LocalizedError {
  case fields
  case size
  case previewBusy
  case response
  case keychain
  case unauthorized
  case missing
  case server(String)

  var errorDescription: String? {
    switch self {
    case .fields: "use a single-line title up to 120 characters and up to 1,000 per other field"
    case .size: "the GIF is over 9 MB. compress it before sharing"
    case .previewBusy: "wait for the current preview action to finish"
    case .response: "the report service returned an unexpected response"
    case .keychain: "could not access the GitHub connection in Keychain"
    case .unauthorized: "reconnect GitHub to continue"
    case .missing: "the report service has no record of this upload"
    case .server(let message): message
    }
  }
}

struct BugReportRepository: Codable, Identifiable {
  let id: Int64
  let name: String
}

struct BugReportConnection: Decodable {
  let key: String
  let code: String
  let interval: Int
  let expiresIn: Int
}

struct BugReportProfile: Decodable {
  let id: Int64
  let username: String
}

struct BugReportClient {
  let origin: URL

  static func configured(environment: [String: String]) -> Self? {
    #if DEBUG
      let raw =
        environment["GIFFERENT_REPORT_ORIGIN"]
        ?? Bundle.main.object(forInfoDictionaryKey: "GifferentReportOrigin") as? String
    #else
      let raw = Bundle.main.object(forInfoDictionaryKey: "GifferentReportOrigin") as? String
    #endif
    guard let raw, var parts = URLComponents(string: raw),
      let host = parts.host, !host.isEmpty,
      parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/"
    else { return nil }
    #if DEBUG
      guard parts.scheme == "https" || (parts.scheme == "http" && host == "127.0.0.1")
      else { return nil }
    #else
      guard parts.scheme == "https" else { return nil }
    #endif
    parts.path = ""
    return parts.url.map(Self.init)
  }

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 90
    return URLSession(configuration: configuration)
  }()

  struct ConnectionStatus: Decodable {
    let profile: BugReportProfile?
    let interval: Int?
  }

  struct RepositoryList: Decodable {
    let profile: BugReportProfile
    let repositories: [BugReportRepository]
    let grantURL: URL
  }

  struct ReportStatus: Decodable {
    let state: String
    let issueUrl: URL?
    let needsReconciliation: Bool?
    let reconnect: Bool?
  }

  private struct Failure: Decodable { let error: String }
  private struct Empty: Decodable {}

  func beginConnection() async throws -> BugReportConnection {
    try await send("connect", method: "POST")
  }

  func checkConnection(_ key: String) async throws -> ConnectionStatus {
    try await send("connect", key: key)
  }

  func disconnect(_ key: String) async throws {
    let _: Empty = try await send("connect", method: "DELETE", key: key)
  }

  func repositories(_ key: String) async throws -> RepositoryList {
    try await send("repositories", key: key)
  }

  func status(_ id: UUID, key: String) async throws -> ReportStatus {
    try await send(reportPath(id), key: key)
  }

  func submit(id: UUID, fields: BugReportFields, gif: EncodedGIF, key: String) async throws
    -> ReportStatus
  {
    guard gif.fileBytes <= 9_000_000 else { throw BugReportError.size }
    var request = request(reportPath(id), method: "PUT", key: key)
    request.setValue("image/gif", forHTTPHeaderField: "Content-Type")
    request.setValue(
      try fields.encoded().base64EncodedString(), forHTTPHeaderField: "X-Gifferent-Report")
    let (data, response) = try await Self.session.upload(
      for: request, fromFile: gif.url, delegate: BugReportRedirectDelegate()
    )
    return try decode(data, response: response)
  }

  private func reportPath(_ id: UUID) -> String { "reports/\(id.uuidString.lowercased())" }

  private func request(_ path: String, method: String, key: String?) -> URLRequest {
    var request = URLRequest(url: origin.appendingPathComponent("api/\(path)"), timeoutInterval: 30)
    request.httpMethod = method
    if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    return request
  }

  private func send<Value: Decodable>(
    _ path: String, method: String = "GET", key: String? = nil
  ) async throws -> Value {
    let (data, response) = try await Self.session.data(
      for: request(path, method: method, key: key), delegate: BugReportRedirectDelegate()
    )
    return try decode(data, response: response)
  }

  private func decode<Value: Decodable>(_ data: Data, response: URLResponse) throws -> Value {
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw BugReportError.response }
    switch http.statusCode {
    case 200...299: return try JSONDecoder().decode(Value.self, from: data)
    case 401: throw BugReportError.unauthorized
    case 404: throw BugReportError.missing
    default:
      let failure = try? JSONDecoder().decode(Failure.self, from: data)
      throw failure.map { BugReportError.server($0.error) } ?? .response
    }
  }

  func acceptsIssueURL(_ url: URL) -> Bool {
    let trustedHost = url.scheme == "https" && url.host == "github.com" && url.port == nil
    let fixture =
      origin.scheme == "http" && origin.host == "127.0.0.1"
      && url.scheme == "http" && url.host == origin.host
    return (trustedHost || fixture) && url.user == nil && url.password == nil
      && url.path.range(of: "^/[^/]+/[^/]+/issues/[1-9][0-9]*$", options: .regularExpression) != nil
  }
}

private final class BugReportRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private struct BugReportKeychain {
  let origin: URL

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "gifferent.github",
      kSecAttrAccount as String: origin.absoluteString,
    ]
  }

  func load() throws -> String? {
    var value: CFTypeRef?
    let status = SecItemCopyMatching(
      query.merging([kSecReturnData as String: true]) { _, new in new } as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data,
      let key = String(data: data, encoding: .utf8)
    else { throw BugReportError.keychain }
    return key
  }

  func save(_ key: String) throws {
    let data = [kSecValueData as String: Data(key.utf8)]
    let status = SecItemUpdate(query as CFDictionary, data as CFDictionary)
    if status == errSecSuccess { return }
    if status == errSecItemNotFound,
      SecItemAdd(query.merging(data) { _, new in new } as CFDictionary, nil) == errSecSuccess
    {
      return
    }
    throw BugReportError.keychain
  }

  func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw BugReportError.keychain
    }
  }
}

struct BugReportSubmission {
  let fields: BugReportFields
  let gifURL: URL
  let owner: Int64
  let id = UUID()
}

@MainActor
struct BugReportSheet: View {
  let client: BugReportClient
  let coordinator: RecordingCoordinator
  @Binding var fields: BugReportFields
  @Binding var previous: BugReportSubmission?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var key: String?
  @State private var account: BugReportClient.RepositoryList?
  @State private var connection: BugReportConnection?
  @State private var search = ""
  @State private var recent: [Int64] = []
  @State private var work: Task<Void, Never>?
  @State private var uploading = false
  @State private var error: String?
  @State private var reportID: UUID?
  @State private var resultURL: URL?
  @State private var publishingCheck = false
  @State private var publicationFailed = false

  private var keychain: BugReportKeychain { BugReportKeychain(origin: client.origin) }

  private func preference(_ kind: String, for profile: BugReportProfile) -> String {
    "bug-report.\(kind).\(client.origin.absoluteString).\(profile.id)"
  }

  private var visibleRepos: [BugReportRepository] {
    guard let account else { return [] }
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches =
      if let url = URL(string: query), url.host?.lowercased() == "github.com" {
        url.path.split(separator: "/").prefix(2).joined(separator: "/")
      } else {
        query
      }
    return account.repositories.filter {
      matches.isEmpty || $0.id == fields.repositoryID
        || $0.name.localizedCaseInsensitiveContains(matches)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("share as bug report")
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
      if let resultURL {
        Text("issue published")
        Link("open GitHub issue", destination: resultURL)
        Button("new report") { clearTrackedReport() }
      } else if publicationFailed {
        Button("back to report") { clearTrackedReport() }
      } else if reportID != nil {
        Text("publishing continues if you close this window.")
        if publishingCheck {
          ProgressView("publishing to GitHub").controlSize(.small)
        } else {
          Button("check status again") { publishingCheck = true }
        }
      } else {
        reportForm
      }
      if let error {
        Text(error).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("bug-report-error")
          .accessibilityAddTraits(.updatesFrequently)
      }
      HStack {
        Spacer()
        if uploading {
          ProgressView("uploading GIF").controlSize(.small)
        }
        Button(uploading ? "cancel upload" : "close") {
          if uploading { work?.cancel() } else { dismiss() }
        }
        .keyboardShortcut(.cancelAction)
        if reportID == nil, account != nil {
          Button("publish to GitHub", action: submit)
            .keyboardShortcut(.defaultAction)
            .disabled(work != nil || !fields.isComplete)
        }
      }
    }
    .padding(20)
    .frame(width: 500)
    .interactiveDismissDisabled(uploading)
    .onDisappear { work?.cancel() }
    .task {
      do {
        if let stored = try keychain.load() { try await load(stored, restore: true) }
      } catch { show(error) }
    }
    .task(id: publishingCheck) {
      if publishingCheck, let reportID, let key { await watch(reportID, key: key) }
    }
  }

  private var reportForm: some View {
    Form {
      if let connection {
        LabeledContent("GitHub sign-in code", value: connection.code)
          .monospaced()
        Button("copy code and open GitHub") { openDeviceLogin(connection.code) }
      } else if let account {
        LabeledContent("connected as", value: account.profile.username)
        HStack {
          Button("disconnect GitHub", action: disconnect)
          Button("refresh repositories") {
            if let key { run { try await load(key, restore: false) } }
          }
        }
        if fields.repositoryID == 0 || !search.isEmpty {
          Link("grant repository access on GitHub", destination: account.grantURL)
        }
        TextField("search or paste a GitHub repository link", text: $search)
          .onChange(of: search) { _, _ in selectPastedRepo() }
        Picker("repository", selection: $fields.repositoryID) {
          Text("choose a repository").tag(Int64(0))
          let matches = visibleRepos
          let recentMatches = recent.compactMap { id in matches.first { $0.id == id } }
          if !recentMatches.isEmpty {
            Section("recent") {
              ForEach(recentMatches) { Text($0.name).tag($0.id) }
            }
          }
          Section("available repositories") {
            ForEach(matches.filter { !recent.contains($0.id) }) { Text($0.name).tag($0.id) }
          }
        }
        if account.repositories.isEmpty {
          Text("grant access to a public repository with GitHub Issues enabled, then refresh.")
        }
      } else {
        Button("connect GitHub", action: connect)
      }
      TextField("issue title", text: $fields.title).accessibilityIdentifier("bug-report-title")
      TextField("steps to reproduce", text: $fields.steps, axis: .vertical).lineLimit(2...3)
      TextField("expected behavior", text: $fields.expected, axis: .vertical).lineLimit(2...3)
      TextField("actual behavior", text: $fields.actual, axis: .vertical).lineLimit(2...3)
      Text("publishing uploads this GIF and report and makes both public.")
        .foregroundStyle(.secondary)
    }
    .disabled(uploading)
  }

  private func selectPastedRepo() {
    guard let url = URL(string: search.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.host?.lowercased() == "github.com"
    else { return }
    let name = url.path.split(separator: "/").prefix(2).joined(separator: "/")
    fields.repositoryID =
      account?.repositories.first {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      }?.id ?? 0
  }

  private func openDeviceLogin(_ code: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
    if let url = URL(string: "https://github.com/login/device") { openURL(url) }
  }

  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    guard work == nil else { return }
    error = nil
    work = Task {
      defer { work = nil }
      do { try await action() } catch { show(error) }
    }
  }

  private func connect() {
    run {
      let login = try await client.beginConnection()
      connection = login
      defer { connection = nil }
      var interval = login.interval
      let deadline = ContinuousClock.now + .seconds(login.expiresIn)
      while ContinuousClock.now < deadline {
        try await Task.sleep(for: .seconds(max(1, interval)))
        let status = try await client.checkConnection(login.key)
        if status.profile != nil {
          try keychain.save(login.key)
          try await load(login.key, restore: true)
          return
        }
        interval = status.interval ?? interval
      }
      throw BugReportError.server("GitHub sign-in expired. try again")
    }
  }

  private func load(_ credential: String, restore: Bool) async throws {
    let list = try await client.repositories(credential)
    guard list.grantURL.scheme == "https", list.grantURL.host == "github.com" else {
      throw BugReportError.response
    }
    key = credential
    account = list
    recent =
      UserDefaults.standard.array(forKey: preference("recent", for: list.profile)) as? [Int64] ?? []
    if !list.repositories.contains(where: { $0.id == fields.repositoryID }) {
      fields.repositoryID = 0
    }
    selectPastedRepo()
    if restore,
      let saved = UserDefaults.standard.string(forKey: preference("pending", for: list.profile)),
      let id = UUID(uuidString: saved)
    {
      reportID = id
      appStartCheck()
    }
  }

  private func disconnect() {
    guard let key else { return }
    run {
      try await client.disconnect(key)
      try keychain.remove()
      self.key = nil
      account = nil
      fields.repositoryID = 0
    }
  }

  private func submit() {
    guard let key, let account,
      let repo = account.repositories.first(where: { $0.id == fields.repositoryID })
    else { return }
    var submitted = fields
    submitted.repository = repo.name
    run {
      uploading = true
      defer { uploading = false }
      let pending = preference("pending", for: account.profile)
      guard
        let id = try await coordinator.sharePreview({ gif in
          let submission: BugReportSubmission
          if let previous, previous.fields == submitted, previous.gifURL == gif.url,
            previous.owner == account.profile.id
          {
            submission = previous
          } else {
            submission = BugReportSubmission(
              fields: submitted, gifURL: gif.url, owner: account.profile.id)
            previous = submission
          }
          UserDefaults.standard.set(submission.id.uuidString, forKey: pending)
          _ = try await client.submit(id: submission.id, fields: submitted, gif: gif, key: key)
          return submission.id
        })
      else { throw BugReportError.previewBusy }
      recent = Array(([repo.id] + recent.filter { $0 != repo.id }).prefix(8))
      UserDefaults.standard.set(recent, forKey: preference("recent", for: account.profile))
      reportID = id
      appStartCheck()
    }
  }

  private func appStartCheck() {
    error = nil
    publishingCheck = true
  }

  private func watch(_ id: UUID, key: String) async {
    defer { publishingCheck = false }
    do {
      let deadline = ContinuousClock.now + .seconds(120)
      while ContinuousClock.now < deadline {
        let status = try await client.status(id, key: key)
        switch status.state {
        case "publishing":
          try await Task.sleep(for: .seconds(2))
        case "published":
          guard let url = status.issueUrl, client.acceptsIssueURL(url) else {
            throw BugReportError.response
          }
          resultURL = url
          openURL(url)
          return
        default:
          publicationFailed = true
          error =
            status.needsReconciliation == true
            ? "GitHub may have created the issue. check the repository before sending again."
            : status.reconnect == true
              ? "reconnect GitHub before sending again." : "the report could not be published."
          return
        }
      }
    } catch BugReportError.missing {
      clearTrackedReport()
      error = BugReportError.missing.localizedDescription
    } catch { show(error) }
  }

  private func clearTrackedReport() {
    if let profile = account?.profile {
      UserDefaults.standard.removeObject(forKey: preference("pending", for: profile))
    }
    if publicationFailed || resultURL != nil { previous = nil }
    reportID = nil
    resultURL = nil
    publicationFailed = false
    error = nil
  }

  private func show(_ cause: Error) {
    switch cause {
    case BugReportError.unauthorized:
      // a subsequent connection can recover the same account's pending report.
      key = nil
      account = nil
      reportID = nil
      error = cause.localizedDescription
    case is CancellationError:
      break
    case let failure as BugReportError:
      error = failure.localizedDescription
    default:
      if !Task.isCancelled {
        error = "could not reach the report service. check the connection and retry."
      }
    }
  }
}
