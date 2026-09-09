import AppKit
import CryptoKit
import Darwin
import Foundation
import ServiceManagement

@discardableResult
private func runTool(_ path: String, arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    } catch {
        print("IdentityMigration: failed to run \(path): \(error)")
        return false
    }
}

final class DesktopRenamerBridgeMigrationManager: NSObject {
    static let shared = DesktopRenamerBridgeMigrationManager()

    private var hasPresentedPrompt = false
    private var completion: (() -> Void)?
    private var stageMonitor: Timer?
    private var stageMonitorDeadline: Date?
    private var stageLaunchStarted = false
    private var manifestURL: URL?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadProgressTimer: Timer?
    private var downloadProgressWindow: NSWindow?
    private var downloadProgressIndicator: NSProgressIndicator?
    private var downloadProgressMessage: NSTextField?

    private override init() {
        super.init()
    }

    /// Returns true when the caller must pause normal application startup while
    /// the legacy bridge offers or performs the migration.
    func beginIfNeeded(completion: @escaping () -> Void) -> Bool {
        guard DesktopRenamerIdentity.isLegacyBridge,
              DesktopRenamerMigrationConfiguration.isConfigured else {
            return false
        }

        self.completion = completion
        guard !hasPresentedPrompt else { return true }
        hasPresentedPrompt = true

        if resumePendingMigrationIfNeeded() {
            return true
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentMigrationPrompt()
        }
        return true
    }

    /// Starts migration from the settings button after the user previously
    /// chose to defer the one-time bridge prompt.
    func startMigrationFromUserAction() {
        guard DesktopRenamerIdentity.isLegacyBridge,
              DesktopRenamerMigrationConfiguration.isConfigured,
              downloadTask == nil,
              stageMonitor == nil,
              !stageLaunchStarted else {
            return
        }

        stageLaunchStarted = false
        if resumePendingMigrationIfNeeded() {
            return
        }

        startMigration()
    }

    private func presentMigrationPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "DesktopRenamer needs a one-time update"
        alert.informativeText = "This update changes DesktopRenamer's application identity. Your settings will be preserved, and the previous application will be removed only after the new one starts successfully."
        alert.addButton(withTitle: "Migrate Now")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            startMigration()
        } else {
            continueNormalApplication()
        }
    }

    private func resumePendingMigrationIfNeeded() -> Bool {
        let manifestURL = DesktopRenamerMigrationStorage.manifestURL
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let manifest = try? DesktopRenamerMigrationStorage.readManifest(from: manifestURL),
              let expectedVersion = DesktopRenamerMigrationConfiguration.packageVersion else {
            return false
        }

        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let stagingURL = DesktopRenamerMigrationConfiguration.stagingApplicationURL
        guard manifest.schemaVersion == DesktopRenamerMigrationManifest.currentSchemaVersion,
              manifest.sourceApplicationPath == sourceURL.path,
              manifest.targetBundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
              manifest.stagingApplicationPath == stagingURL.path,
              DesktopRenamerMigrationVersion.isAtLeast(expectedVersion, manifest.expectedVersion),
              let stagedBundle = Bundle(url: stagingURL),
              stagedBundle.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
              let stagedVersion = stagedBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return false
        }

        self.manifestURL = manifestURL

        if stagedVersion == expectedVersion {
            print("IdentityMigration: resuming the installed staged application")
            DispatchQueue.main.async { [weak self] in
                self?.launchInstalledStagingApplication()
            }
        } else if DesktopRenamerMigrationVersion.isAtLeast(expectedVersion, stagedVersion) {
            // A previous bridge may have left a newer staged app behind with
            // an older manifest. Replace it with this bridge's verified
            // package so the staged executable contains the current recovery
            // logic before it is launched.
            print(
                "IdentityMigration: refreshing stale staged build \(stagedVersion) "
                    + "with build \(expectedVersion)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.startMigration(launchAtLoginEnabled: manifest.launchAtLoginEnabled)
            }
        } else {
            return false
        }

        return true
    }

    private func startMigration(launchAtLoginEnabled: Bool? = nil) {
        guard let packageURL = DesktopRenamerMigrationConfiguration.packageURL,
              let expectedHash = DesktopRenamerMigrationConfiguration.packageSHA256,
              let expectedVersion = DesktopRenamerMigrationConfiguration.packageVersion else {
            showFailure(DesktopRenamerMigrationError.invalidConfiguration)
            return
        }

        stageLaunchStarted = false
        guard terminateRunningStagingApplicationsIfNeeded() else {
            showFailure(DesktopRenamerMigrationError.stagingApplicationDidNotTerminate)
            return
        }

        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let manifest = DesktopRenamerMigrationManifest(
            schemaVersion: DesktopRenamerMigrationManifest.currentSchemaVersion,
            sourceApplicationPath: sourceURL.path,
            sourceProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            targetBundleIdentifier: DesktopRenamerIdentity.currentBundleIdentifier,
            stagingApplicationPath: DesktopRenamerMigrationConfiguration.stagingApplicationURL.path,
            launchAtLoginEnabled: launchAtLoginEnabled
                ?? (SMAppService.mainApp.status == .enabled
                    || SMAppService.mainApp.status == .requiresApproval),
            expectedVersion: expectedVersion,
            createdAt: Date()
        )

        do {
            try DesktopRenamerMigrationStorage.writeManifest(manifest)
            manifestURL = DesktopRenamerMigrationStorage.manifestURL
        } catch {
            showFailure(error)
            return
        }

        downloadMigrationPackage(at: packageURL, expectedSHA256: expectedHash)
    }

    private func downloadMigrationPackage(at packageURL: URL, expectedSHA256: String) {
        let task = URLSession.shared.downloadTask(with: packageURL) { [weak self] temporaryURL, response, error in
            guard let self else { return }

            if let error {
                self.completeDownload(.failure(error))
                return
            }

            guard let temporaryURL,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                self.completeDownload(
                    .failure(DesktopRenamerMigrationError.invalidDownloadResponse)
                )
                return
            }

            do {
                let packageURL = try self.cacheDownloadedPackage(
                    at: temporaryURL
                )
                try self.validatePackage(
                    at: packageURL,
                    expectedSHA256: expectedSHA256
                )
                self.completeDownload(.success(packageURL))
            } catch {
                self.completeDownload(.failure(error))
            }
        }
        downloadTask = task
        task.resume()
        presentDownloadProgress()
    }

    private func presentDownloadProgress() {
        guard downloadProgressWindow == nil else { return }

        let titleLabel = NSTextField(labelWithString: "Downloading DesktopRenamer migration")
        titleLabel.font = .boldSystemFont(ofSize: 16)

        let messageLabel = NSTextField(
            labelWithString: "Downloading the migration package. Please keep DesktopRenamer open."
        )
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping

        let progressIndicator = NSProgressIndicator(
            frame: NSRect(x: 0, y: 0, width: 280, height: 20)
        )
        progressIndicator.style = .bar
        progressIndicator.controlSize = .regular
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelDownload))
        cancelButton.bezelStyle = .rounded
        cancelButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let stackView = NSStackView(views: [titleLabel, messageLabel, progressIndicator, cancelButton])
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "DesktopRenamer Migration"
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.center()

        downloadProgressWindow = window
        downloadProgressIndicator = progressIndicator
        downloadProgressMessage = messageLabel
        let progressTimer = Timer(
            timeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            self?.updateDownloadProgress()
        }
        downloadProgressTimer = progressTimer
        RunLoop.main.add(progressTimer, forMode: .common)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateDownloadProgress() {
        guard let downloadTask,
              let progressIndicator = downloadProgressIndicator else {
            return
        }

        let progress = downloadTask.progress
        guard progress.totalUnitCount > 0 else {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
            return
        }

        progressIndicator.isIndeterminate = false
        progressIndicator.stopAnimation(nil)
        let fractionCompleted = min(max(progress.fractionCompleted, 0), 1)
        let isDownloadComplete = fractionCompleted >= 1
        let percentage = Int(fractionCompleted * 100)
        progressIndicator.doubleValue = isDownloadComplete ? 99 : fractionCompleted * 100
        downloadProgressMessage?.stringValue =
            isDownloadComplete
                ? "Finalizing the downloaded migration package…"
                : "Downloading the migration package… \(percentage)% complete."
    }

    private func completeDownload(_ result: Result<URL, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.downloadTask != nil else { return }
            if case .success = result {
                self.downloadProgressIndicator?.isIndeterminate = false
                self.downloadProgressIndicator?.doubleValue = 100
                self.downloadProgressMessage?.stringValue =
                    "Download complete. Preparing the installer…"
            }
            self.downloadTask = nil
            self.stopDownloadProgress()

            switch result {
            case .success(let packageURL):
                self.installPackage(at: packageURL)
            case .failure(let error):
                self.showFailure(error)
            }
        }
    }

    private func stopDownloadProgress() {
        downloadProgressTimer?.invalidate()
        downloadProgressTimer = nil
        downloadProgressWindow?.close()
        downloadProgressWindow = nil
        downloadProgressIndicator = nil
        downloadProgressMessage = nil
    }

    @objc private func cancelDownload() {
        guard downloadTask != nil else { return }

        downloadTask?.cancel()
        downloadTask = nil
        stopDownloadProgress()
        continueNormalApplication()
    }

    private func cacheDownloadedPackage(at temporaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = DesktopRenamerMigrationStorage.cacheDirectoryURL
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let packageURL = directoryURL.appendingPathComponent("DesktopRenamer-Migration.pkg")
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: packageURL)
        return packageURL
    }

    private func validatePackage(at packageURL: URL, expectedSHA256: String) throws {
        let packageData = try Data(contentsOf: packageURL)
        let actualHash = SHA256.hash(data: packageData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == expectedSHA256 else {
            throw DesktopRenamerMigrationError.invalidPackageHash
        }

        if !DesktopRenamerMigrationConfiguration.allowsManualApproval {
            guard runTool(
                "/usr/sbin/pkgutil",
                arguments: ["--check-signature", packageURL.path]
            ), runTool(
                "/usr/sbin/spctl",
                arguments: ["--assess", "--type", "install", packageURL.path]
            ) else {
                throw DesktopRenamerMigrationError.packageVerificationFailed
            }
        }
    }

    private func installPackage(at packageURL: URL) {
        guard NSWorkspace.shared.open(packageURL) else {
            showFailure(DesktopRenamerMigrationError.packageVerificationFailed)
            return
        }

        stageMonitorDeadline = Date().addingTimeInterval(10 * 60)
        stageMonitor?.invalidate()
        stageMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkForInstalledStagingApplication()
        }
    }

    private func checkForInstalledStagingApplication() {
        guard !stageLaunchStarted else { return }

        if let deadline = stageMonitorDeadline, Date() > deadline {
            stopStageMonitoring()
            showFailure(DesktopRenamerMigrationError.stagingApplicationNotFound)
            return
        }

        let stagingURL = DesktopRenamerMigrationConfiguration.stagingApplicationURL
        guard let bundle = Bundle(url: stagingURL),
              bundle.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                == DesktopRenamerMigrationConfiguration.packageVersion else {
            return
        }

        launchInstalledStagingApplication()
    }

    private func launchInstalledStagingApplication() {
        guard !stageLaunchStarted else { return }
        stageLaunchStarted = true
        stopStageMonitoring()

        guard let manifestURL else {
            showFailure(DesktopRenamerMigrationError.manifestInvalid)
            return
        }

        let stagingURL = DesktopRenamerMigrationConfiguration.stagingApplicationURL
        waitForStagingApplicationsToTerminate(
            at: stagingURL,
            manifestURL: manifestURL,
            attemptsRemaining: 20,
            didForceTerminate: false
        )
    }

    private func waitForStagingApplicationsToTerminate(
        at stagingURL: URL,
        manifestURL: URL,
        attemptsRemaining: Int,
        didForceTerminate: Bool
    ) {
        let runningApplications = runningStagingApplications(at: stagingURL)
        guard !runningApplications.isEmpty else {
            openStagingApplication(at: stagingURL, manifestURL: manifestURL)
            return
        }

        guard attemptsRemaining > 0 else {
            guard !didForceTerminate else {
                showFailure(DesktopRenamerMigrationError.stagingApplicationDidNotTerminate)
                return
            }

            let forceTerminationSucceeded = runningApplications.allSatisfy {
                forciblyTerminateStagingApplication($0, at: stagingURL)
            }
            guard forceTerminationSucceeded else {
                showFailure(DesktopRenamerMigrationError.stagingApplicationDidNotTerminate)
                return
            }

            waitForStagingApplicationsToTerminate(
                at: stagingURL,
                manifestURL: manifestURL,
                attemptsRemaining: 20,
                didForceTerminate: true
            )
            return
        }

        runningApplications.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForStagingApplicationsToTerminate(
                at: stagingURL,
                manifestURL: manifestURL,
                attemptsRemaining: attemptsRemaining - 1,
                didForceTerminate: didForceTerminate
            )
        }
    }

    private func openStagingApplication(at stagingURL: URL, manifestURL: URL) {

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--desktoprenamer-migration",
            "--desktoprenamer-migration-manifest",
            manifestURL.path
        ]

        NSWorkspace.shared.openApplication(at: stagingURL, configuration: configuration) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.showFailure(error) }
            }
        }
    }

    private func terminateRunningStagingApplicationsIfNeeded() -> Bool {
        let stagingURL = DesktopRenamerMigrationConfiguration.stagingApplicationURL
        let runningApplications = runningStagingApplications(at: stagingURL)
        guard !runningApplications.isEmpty else { return true }

        print(
            "IdentityMigration: stopping stale staged process(es): "
                + runningApplications.map { String($0.processIdentifier) }.joined(separator: ", ")
        )
        runningApplications.forEach { $0.terminate() }
        return runningApplications.allSatisfy {
            forciblyTerminateStagingApplication($0, at: stagingURL)
        }
    }

    private func runningStagingApplications(at stagingURL: URL) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard application.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
                  application.bundleURL?.standardizedFileURL == stagingURL.standardizedFileURL else {
                return false
            }

            let processIdentifier = application.processIdentifier
            guard processIdentifier > 0 else { return false }
            return Darwin.kill(processIdentifier, 0) == 0 || errno == EPERM
        }
    }

    private func forciblyTerminateStagingApplication(
        _ application: NSRunningApplication,
        at stagingURL: URL
    ) -> Bool {
        guard runningStagingApplications(at: stagingURL).contains(where: {
            $0.processIdentifier == application.processIdentifier
        }) else {
            return true
        }

        if application.forceTerminate() {
            return true
        }

        guard application.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
              application.bundleURL?.standardizedFileURL == stagingURL.standardizedFileURL else {
            return false
        }

        return Darwin.kill(application.processIdentifier, SIGKILL) == 0 || errno == ESRCH
    }

    private func stopStageMonitoring() {
        stageMonitor?.invalidate()
        stageMonitor = nil
        stageMonitorDeadline = nil
    }

    private func continueNormalApplication() {
        stopStageMonitoring()
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    private func showFailure(_ error: Error) {
        stopStageMonitoring()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "DesktopRenamer migration was not completed"
        alert.informativeText = "\(error.localizedDescription) The current application was left available so you can retry the migration later."
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            stageLaunchStarted = false
            startMigration()
        } else {
            continueNormalApplication()
        }
    }
}
