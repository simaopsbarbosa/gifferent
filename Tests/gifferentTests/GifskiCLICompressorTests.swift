import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import gifferent

final class GifskiCLICompressorTests: XCTestCase {
  func testArgumentBuilderKeepsOrderedFramesAndMapsQualityScaleAndLoopMode() {
    let frames = [
      URL(fileURLWithPath: "/tmp/frame 1.png"),
      URL(fileURLWithPath: "/tmp/frame 2.png"),
    ]
    XCTAssertEqual(
      GifskiCLICompressor.arguments(
        frameURLs: frames,
        outputToStandardOutput: true,
        fps: "20",
        qualityPercent: 90,
        width: 32,
        height: 24,
        loopsForever: true
      ),
      [
        "--fps", "20", "--quality", "90", "--width", "32", "--height", "24",
        "--repeat", "0", "--no-sort", "--quiet", "--output", "-",
        "/tmp/frame 1.png", "/tmp/frame 2.png",
      ]
    )
    XCTAssertEqual(
      GifskiCLICompressor.arguments(
        frameURLs: frames,
        outputToStandardOutput: true,
        fps: "12.5",
        qualityPercent: 1,
        width: 8,
        height: 6,
        loopsForever: false
      ).prefix(14),
      [
        "--fps", "12.5", "--quality", "1", "--width", "8", "--height", "6",
        "--repeat", "-1", "--no-sort", "--quiet", "--output", "-",
      ]
    )
  }

  func testOnlyConstantCentisecondTimingHasExactSingleFPSRepresentation() {
    XCTAssertEqual(GifskiCLICompressor.constantFrameRate(for: [5, 5, 5]), "20")
    XCTAssertEqual(GifskiCLICompressor.constantFrameRate(for: [8, 8]), "12.5")
    XCTAssertEqual(GifskiCLICompressor.constantFrameRate(for: [4, 4, 5, 4, 4, 4]), "24")
    XCTAssertNil(GifskiCLICompressor.constantFrameRate(for: [5, 6]))
    XCTAssertNil(GifskiCLICompressor.constantFrameRate(for: [2, 3, 4]))
    XCTAssertNil(GifskiCLICompressor.constantFrameRate(for: []))
    XCTAssertNil(GifskiCLICompressor.constantFrameRate(for: [0, 0]))
  }

  func testSizeSearchPlanRespectsSelectedScaleMaximumAndNeverBelowQualityNinety() {
    let settings = GIFCompressionSettings(scale: .fiftyPercent, qualityPercent: 100)
    let plan = GIFSizeSearchPlan(settings: settings)
    XCTAssertEqual(plan.candidates.count, 3)
    XCTAssertEqual(plan.candidates.map(\.qualityPercent), [100, 95, 90])
    XCTAssertEqual(plan.candidates.map(\.scale), [.fiftyPercent, .fiftyPercent, .fiftyPercent])
    XCTAssertTrue(plan.candidates.allSatisfy { $0.frameRate == .fps24 && $0.qualityPercent >= 90 })
  }

  func testSizeSearchPlanUsesOnlyApprovedScaleAndFrameRatePairs() {
    let original = GIFSizeSearchPlan(
      settings: GIFCompressionSettings(scale: .original, qualityPercent: 90))
    XCTAssertEqual(
      Set(original.candidates.map { "\($0.scale.rawValue)-\($0.frameRate.rawValue)" }),
      Set(["100-24", "100-18", "75-24", "50-24"]))
    let seventyFive = GIFSizeSearchPlan(
      settings: GIFCompressionSettings(scale: .seventyFivePercent, qualityPercent: 90))
    XCTAssertEqual(
      Set(seventyFive.candidates.map { "\($0.scale.rawValue)-\($0.frameRate.rawValue)" }),
      Set(["75-24", "50-24"]))
    let fifty = GIFSizeSearchPlan(
      settings: GIFCompressionSettings(scale: .fiftyPercent, qualityPercent: 90))
    XCTAssertEqual(Set(fifty.candidates.map(\.frameRate)), [.fps24])
    let twentyFive = GIFSizeSearchPlan(
      settings: GIFCompressionSettings(scale: .twentyFivePercent, qualityPercent: 90))
    XCTAssertTrue(twentyFive.candidates.isEmpty)
    XCTAssertTrue(original.candidates.allSatisfy { $0.qualityPercent >= 90 })
  }

  func testSizeSearchQualityStepsReachFloorFromNonMultipleOfFive() {
    for (selected, expected) in [(99, [99, 94, 90]), (91, [91, 90]), (1, [90])] {
      let plan = GIFSizeSearchPlan(
        settings: GIFCompressionSettings(qualityPercent: selected),
        frameRates: [.fps24], eligibleScales: [.original])
      XCTAssertEqual(plan.candidates.map(\.qualityPercent), expected)
    }
  }

  func testFrameSamplerUsesCumulativeSourceTimingAndPreservesExactDuration() throws {
    let sample = try GIFFrameSampler.sample(
      delaysCentiseconds: [3, 8, 4], frameRate: .fps24)
    XCTAssertEqual(sample.durationCentiseconds, 15)
    XCTAssertEqual(sample.sourceIndices, [0, 1, 1])
    XCTAssertEqual(sample.expectedDelaysCentiseconds, [4, 4, 7])
    XCTAssertEqual(sample.expectedDelaysCentiseconds.reduce(0, +), 15)

    let eighteenFPS = try GIFFrameSampler.sample(
      delaysCentiseconds: [6, 6, 6], frameRate: .fps18)
    XCTAssertEqual(eighteenFPS.sourceIndices, [0, 0, 1])
    XCTAssertEqual(eighteenFPS.expectedDelaysCentiseconds.reduce(0, +), 18)
  }

  func testFrameScheduleValidatorAcceptsOnlyContiguousCoalescing() {
    let expected = [4, 4, 5, 4, 4]
    XCTAssertTrue(
      GIFFrameScheduleValidator.matches(
        emittedDelaysCentiseconds: [8, 13], expectedDelaysCentiseconds: expected))
    XCTAssertTrue(
      GIFFrameScheduleValidator.matches(
        emittedDelaysCentiseconds: expected, expectedDelaysCentiseconds: expected))
    XCTAssertFalse(
      GIFFrameScheduleValidator.matches(
        emittedDelaysCentiseconds: [9, 12], expectedDelaysCentiseconds: expected))
    XCTAssertNil(
      GIFFrameScheduleValidator.finalFrameDelay(
        emittedDelaysCentiseconds: [9, 12], expectedDelaysCentiseconds: expected))
  }

  func testSamplerRejectsInvalidTimingAndImpossibleDuration() {
    XCTAssertThrowsError(try GIFFrameSampler.sample(delaysCentiseconds: [], frameRate: .fps24))
    XCTAssertThrowsError(try GIFFrameSampler.sample(delaysCentiseconds: [0], frameRate: .fps24))
    XCTAssertThrowsError(
      try GIFFrameSampler.sample(delaysCentiseconds: [65_536], frameRate: .fps24))
    XCTAssertThrowsError(
      try GIFFrameSampler.sample(delaysCentiseconds: [Int.max], frameRate: .fps24))
    XCTAssertThrowsError(
      try GIFFrameSampler.sample(delaysCentiseconds: [Int.max, 1], frameRate: .fps24))
  }

  func testFinalFrameDelayPatchPreservesGIFAndSetsRequestedDuration() throws {
    let fixture = try makeFixture(delaysCentiseconds: [4, 4, 7], loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    try GifskiCLICompressor.setFinalFrameDelay(in: fixture.source, centiseconds: 7)

    let output = try GIFMetadataInspector().inspect(fixture.source)
    XCTAssertEqual(output.delaysCentiseconds, [4, 4, 7])
    XCTAssertEqual(output.durationCentiseconds, 15)
    XCTAssertTrue(output.loopsForever)
  }

  func testSizeSearchKeepsSmallestCandidateUnderTargetAndDeletesOtherAttempts() async throws {
    let settings = GIFCompressionSettings(scale: .original, qualityPercent: 100)
    let plan = GIFSizeSearchPlan(
      settings: settings, frameRates: [.fps24], eligibleScales: [.original])
    let source = EncodedGIF(
      url: URL(fileURLWithPath: "/tmp/source.gif"), width: 32, height: 24,
      frameCount: 1, delaysCentiseconds: [100], durationCentiseconds: 100,
      loopsForever: true, fileBytes: 20_000_000)
    let discarded = SearchDiscardRecorder()
    let outputs = SearchOutputFactory(source: source, sizes: [9_500_000, 8_500_000, 8_000_000])
    let result = try await GIFSizeSearchEngine.search(
      source: source,
      settings: settings,
      plan: plan,
      compress: { candidate in
        await outputs.make(candidate)
      },
      discard: { output in await discarded.append(output.url) }
    )

    XCTAssertEqual(result.gif.fileBytes, 8_000_000)
    XCTAssertTrue(result.reachedTarget)
    XCTAssertEqual(result.attempts, 3)
    let removed = await discarded.urls
    XCTAssertEqual(removed.count, 2)

    let missedOutputs = SearchOutputFactory(
      source: source, sizes: [10_000_000, 9_500_000, 9_300_000])
    let missed = try await GIFSizeSearchEngine.search(
      source: source,
      settings: settings,
      plan: plan,
      compress: { candidate in await missedOutputs.make(candidate) },
      discard: { _ in }
    )
    XCTAssertEqual(missed.gif.fileBytes, 9_300_000)
    XCTAssertFalse(missed.reachedTarget)
  }

  @MainActor
  func testDiscordSearchPreservesDestinationAndUsesItsTarget() async throws {
    let settings = GIFCompressionSettings(destination: .discord, qualityPercent: 90)
    let plan = GIFSizeSearchPlan(
      settings: settings, frameRates: [.fps24], eligibleScales: [.original])
    let source = EncodedGIF(
      url: URL(fileURLWithPath: "/tmp/source.gif"), width: 32, height: 24,
      frameCount: 1, delaysCentiseconds: [100], durationCentiseconds: 100,
      loopsForever: true, fileBytes: 20_000_000)
    let outputs = SearchOutputFactory(source: source, sizes: [17_000_000])
    let result = try await GIFSizeSearchEngine.search(
      source: source, settings: settings, plan: plan,
      compress: { candidate in
        XCTAssertEqual(candidate.destination, .discord)
        return await outputs.make(candidate)
      },
      discard: { _ in },
      onProgress: { _, _, candidate in
        XCTAssertEqual(candidate.destination, .discord)
      })
    XCTAssertEqual(result.settings.destination, .discord)
    XCTAssertTrue(result.reachedTarget)
    XCTAssertEqual(result.gif.fileBytes, 17_000_000)
  }

  func testSizeSearchCancellationDiscardsBestCandidateAndPropagatesCancellation() async throws {
    let settings = GIFCompressionSettings(scale: .original, qualityPercent: 100)
    let plan = GIFSizeSearchPlan(settings: settings)
    let sourceURL = URL(fileURLWithPath: "/tmp/search-source.gif")
    let source = EncodedGIF(
      url: sourceURL, width: 32, height: 24, frameCount: 1,
      delaysCentiseconds: [100], durationCentiseconds: 100,
      loopsForever: true, fileBytes: 20_000_000)
    let bestURL = URL(fileURLWithPath: "/tmp/search-best.gif")
    let best = EncodedGIF(
      url: bestURL, width: 32, height: 24, frameCount: 1,
      delaysCentiseconds: [100], durationCentiseconds: 100,
      loopsForever: true, fileBytes: 12_000_000)
    let secondCandidateStarted = expectation(description: "second candidate starts")
    let discarded = SearchDiscardRecorder()
    let search = Task {
      try await GIFSizeSearchEngine.search(
        source: source,
        settings: settings,
        plan: plan,
        compress: { candidate in
          if candidate.qualityPercent == 100 { return best }
          secondCandidateStarted.fulfill()
          try await Task.sleep(for: .seconds(30))
          return best
        },
        discard: { output in await discarded.append(output.url) }
      )
    }

    await fulfillment(of: [secondCandidateStarted], timeout: 3)
    search.cancel()
    do {
      _ = try await search.value
      XCTFail("expected cancellation")
    } catch is CancellationError {
      // expected
    }
    let discardedURLs = await discarded.urls
    XCTAssertEqual(discardedURLs, [bestURL])
  }

  @MainActor
  func testSizeSearchFailureRemovesPreviouslyRetainedCandidateFromDisk() async throws {
    for invalidMetadata in [false, true] {
      let fixture = try makeFixture(delaysCentiseconds: [4, 4, 7], loopsForever: true)
      defer { try? FileManager.default.removeItem(at: fixture.directory) }
      let settings = GIFCompressionSettings(qualityPercent: 95)
      let plan = GIFSizeSearchPlan(
        settings: settings, frameRates: [.fps24], eligibleScales: [.original])
      var attempt = 0
      var written: [URL] = []
      do {
        _ = try await GIFSizeSearchEngine.search(
          source: fixture.metadata, settings: settings, plan: plan,
          compress: { _ in
            attempt += 1
            if attempt == 2, !invalidMetadata {
              throw GifskiCompressionError.processFailed(7, "fixture failure")
            }
            let url = fixture.directory.appendingPathComponent("candidate-\(attempt).gif")
            try FileManager.default.copyItem(at: fixture.source, to: url)
            written.append(url)
            let output = try GIFMetadataInspector().inspect(url)
            guard attempt == 2 else { return output }
            return EncodedGIF(
              url: output.url, width: output.width, height: output.height,
              frameCount: output.frameCount, delaysCentiseconds: output.delaysCentiseconds,
              durationCentiseconds: output.durationCentiseconds + 1,
              loopsForever: output.loopsForever, fileBytes: output.fileBytes)
          },
          discard: { output in try? FileManager.default.removeItem(at: output.url) })
        XCTFail("expected failed search")
      } catch let error as GifskiCompressionError {
        XCTAssertEqual(
          error, invalidMetadata ? .invalidOutput : .processFailed(7, "fixture failure"))
      }
      XCTAssertEqual(attempt, 2)
      XCTAssertFalse(written.isEmpty)
      XCTAssertTrue(written.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
      XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }
  }

  func testCancellationWhileDiscardingFinalAttemptAlsoDiscardsBest() async throws {
    let settings = GIFCompressionSettings(qualityPercent: 95)
    let plan = GIFSizeSearchPlan(
      settings: settings, frameRates: [.fps24], eligibleScales: [.original])
    let source = EncodedGIF(
      url: URL(fileURLWithPath: "/tmp/search-source.gif"), width: 32, height: 24,
      frameCount: 1, delaysCentiseconds: [100], durationCentiseconds: 100,
      loopsForever: true, fileBytes: 20_000_000)
    let outputs = SearchOutputFactory(source: source, sizes: [8_000_000, 9_000_000])
    let discarded = SearchDiscardRecorder()
    let finalDiscardStarted = expectation(description: "final attempt is being discarded")
    let search = Task {
      try await GIFSizeSearchEngine.search(
        source: source, settings: settings, plan: plan,
        compress: { candidate in await outputs.make(candidate) },
        discard: { output in
          await discarded.append(output.url)
          if output.url.lastPathComponent == "candidate-1.gif" {
            finalDiscardStarted.fulfill()
            try? await Task.sleep(for: .seconds(30))
          }
        })
    }
    await fulfillment(of: [finalDiscardStarted], timeout: 3)
    search.cancel()
    do {
      _ = try await search.value
      XCTFail("expected cancellation")
    } catch is CancellationError {
      // expected
    }
    let discardedURLs = await discarded.urls
    XCTAssertEqual(discardedURLs.map(\.lastPathComponent), ["candidate-1.gif", "candidate-0.gif"])
  }

  func testFakeExecutableReceivesArgumentsAndProducesValidatedOutput() async throws {
    let fixture = try makeFixture(delaysCentiseconds: [4, 4, 7], loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let argumentsFile = fixture.directory.appendingPathComponent("arguments.txt")
    let executable = try fakeExecutable(
      in: fixture.directory,
      body: "printf '%s\\n' \"$@\" > '\(argumentsFile.path)'\ncat '\(fixture.source.path)'"
    )
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let compressor = GifskiCLICompressor(executableURL: executable)
    let compressed = try await compressor.compress(
      source: fixture.metadata,
      settings: GIFCompressionSettings(scale: .original, qualityPercent: 77),
      to: reservation(fixture, destination: destination, maximumBytes: 100_000)
    )

    let args = try String(contentsOf: argumentsFile, encoding: .utf8)
      .components(separatedBy: .newlines).filter { !$0.isEmpty }
    XCTAssertEqual(
      args.prefix(13),
      [
        "--fps", "24", "--quality", "77", "--width", "32", "--height", "24",
        "--repeat", "0", "--no-sort", "--quiet", "--output",
      ])
    XCTAssertEqual(args[13], "-")
    XCTAssertEqual(args.count, 17)
    XCTAssertEqual(compressed.url, destination)
    XCTAssertEqual(compressed.frameCount, 3)
    XCTAssertEqual(compressed.delaysCentiseconds, [4, 4, 7])
    XCTAssertEqual(compressed.loopsForever, fixture.metadata.loopsForever)
    XCTAssertEqual(compressed.width, fixture.metadata.width)
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
  }

  func testQualityOutsideOneThroughOneHundredDoesNotLaunch() async throws {
    let fixture = try makeFixture(delayCentiseconds: 5, loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let marker = fixture.directory.appendingPathComponent("launched")
    let executable = try fakeExecutable(in: fixture.directory, body: ": > '\(marker.path)'\ncat")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    do {
      _ = try await GifskiCLICompressor(executableURL: executable).compress(
        source: fixture.metadata,
        settings: GIFCompressionSettings(qualityPercent: 0),
        to: reservation(fixture, destination: destination, maximumBytes: 100_000)
      )
      XCTFail("expected invalid quality")
    } catch let error as GifskiCompressionError {
      XCTAssertEqual(error, .invalidQuality)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  func testNonuniformFrameTimingIsRejectedWithoutLaunching() async throws {
    let fixture = try makeFixture(delayCentiseconds: 5, loopsForever: false)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let marker = fixture.directory.appendingPathComponent("launched")
    let executable = try fakeExecutable(in: fixture.directory, body: ": > '\(marker.path)'\ncat")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let source = EncodedGIF(
      url: fixture.source, width: fixture.metadata.width, height: fixture.metadata.height,
      frameCount: 3, delaysCentiseconds: [5, 6, 5], durationCentiseconds: 16,
      loopsForever: false, fileBytes: fixture.metadata.fileBytes
    )
    do {
      _ = try await GifskiCLICompressor(executableURL: executable).compress(
        source: source,
        settings: GIFCompressionSettings(),
        to: reservation(fixture, destination: destination, maximumBytes: 100_000)
      )
      XCTFail("expected unrepresentable timing")
    } catch let error as GifskiCompressionError {
      XCTAssertEqual(error, .unrepresentableTiming)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
  }

  func testOneShotLoopMetadataIsValidatedAndOutputIsRetained() async throws {
    let fixture = try makeFixture(delaysCentiseconds: [4, 4, 7], loopsForever: false)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let executable = try fakeExecutable(in: fixture.directory, body: "cat '\(fixture.source.path)'")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let compressed = try await GifskiCLICompressor(executableURL: executable).compress(
      source: fixture.metadata,
      settings: GIFCompressionSettings(),
      to: reservation(fixture, destination: destination, maximumBytes: 100_000)
    )
    XCTAssertFalse(compressed.loopsForever)
    XCTAssertEqual(try GIFMetadataInspector().inspect(destination), compressed)
  }

  func testInvalidEncoderLoopDimensionsAndCadenceAreRejectedAndCleaned() async throws {
    for mismatch in ["loop", "dimensions", "cadence"] {
      let fixture = try makeFixture(delaysCentiseconds: [4, 4, 7], loopsForever: true)
      defer { try? FileManager.default.removeItem(at: fixture.directory) }
      let replacement = try makeFixture(
        delaysCentiseconds: mismatch == "cadence" ? [5, 5, 5] : [4, 4, 7],
        loopsForever: mismatch != "loop")
      defer { try? FileManager.default.removeItem(at: replacement.directory) }
      let executable = try fakeExecutable(
        in: fixture.directory, body: "cat '\(replacement.source.path)'")
      let destination = fixture.directory.appendingPathComponent("compressed.gif")
      do {
        _ = try await GifskiCLICompressor(executableURL: executable).compress(
          source: fixture.metadata,
          settings: GIFCompressionSettings(
            scale: mismatch == "dimensions" ? .fiftyPercent : .original),
          to: reservation(fixture, destination: destination, maximumBytes: 100_000))
        XCTFail("expected invalid \(mismatch)")
      } catch {
        XCTAssertTrue(
          (error as? GifskiCompressionError) == .invalidOutput
            || (error as? OriginalGIFEncodingError) == .invalidOutput,
          "unexpected error: \(error)")
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
      XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
      XCTAssertEqual(try GIFMetadataInspector().inspect(fixture.source), fixture.metadata)
    }
  }

  func testProcessFailureBoundsStderrAndCleansOutputAndFrameWorkspace() async throws {
    let fixture = try makeFixture(delayCentiseconds: 5, loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let executable = try fakeExecutable(
      in: fixture.directory, body: "printf '%100000s' x >&2\nprintf x\nexit 7")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    do {
      _ = try await GifskiCLICompressor(executableURL: executable).compress(
        source: fixture.metadata,
        settings: GIFCompressionSettings(),
        to: reservation(fixture, destination: destination, maximumBytes: 100_000)
      )
      XCTFail("expected child failure")
    } catch let error as GifskiCompressionError {
      guard case .processFailed(let status, let standardError) = error else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(status, 7)
      XCTAssertEqual(standardError.utf8.count, 64 * 1_024)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
  }

  func testOutputCapIsEnforcedWhileReadingStdout() async throws {
    let fixture = try makeFixture(delayCentiseconds: 5, loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let executable = try fakeExecutable(
      in: fixture.directory, body: "while :; do printf '%4096s' x; done")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    do {
      _ = try await GifskiCLICompressor(executableURL: executable).compress(
        source: fixture.metadata,
        settings: GIFCompressionSettings(),
        to: reservation(fixture, destination: destination, maximumBytes: 128)
      )
      XCTFail("expected output cap")
    } catch let error as GifskiCompressionError {
      XCTAssertEqual(error, .outputSizeExceeded)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
  }

  func testCancellationKillsChildAndCleansTemporaryFiles() async throws {
    let fixture = try makeFixture(delayCentiseconds: 5, loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let marker = fixture.directory.appendingPathComponent("started")
    let executable = try fakeExecutable(
      in: fixture.directory, body: ": > '\(marker.path)'\nwhile :; do :; done")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let compressor = GifskiCLICompressor(executableURL: executable)
    let source = fixture.metadata
    let outputReservation = reservation(fixture, destination: destination, maximumBytes: 100_000)
    let work = Task {
      try await compressor.compress(
        source: source,
        settings: GIFCompressionSettings(),
        to: outputReservation
      )
    }
    try await waitUntil { FileManager.default.fileExists(atPath: marker.path) }
    work.cancel()
    do {
      _ = try await work.value
      XCTFail("expected cancellation")
    } catch let error as GifskiCompressionError {
      XCTAssertEqual(error, .cancelled)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
  }

  func testFramePNGWorkspaceCapRejectsBeforeEncoding() throws {
    let fixture = try makeFixture(delayCentiseconds: 5, loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let working = fixture.directory.appendingPathComponent("frames", isDirectory: true)
    try FileManager.default.createDirectory(
      at: working, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    XCTAssertThrowsError(
      try GifskiCLICompressor.decodePNGFrames(
        source: fixture.metadata, scale: .original, in: working, maximumBytes: 1)
    ) { error in
      XCTAssertEqual(error as? GifskiCompressionError, .frameWorkspaceLimitExceeded)
    }
  }

  func testReservedFrameCacheIsUsedBoundedAndCleaned() async throws {
    for maximumCacheBytes in [Int64(4_096), 1] {
      let fixture = try makeFixture(delaysCentiseconds: [4, 4, 7], loopsForever: true)
      defer { try? FileManager.default.removeItem(at: fixture.directory) }
      let cache = fixture.directory.appendingPathComponent("reserved-cache", isDirectory: true)
      try FileManager.default.createDirectory(
        at: cache, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      let arguments = fixture.directory.appendingPathComponent("arguments.txt")
      let executable = try fakeExecutable(
        in: fixture.directory,
        body: "printf '%s\\n' \"$@\" > '\(arguments.path)'\ncat '\(fixture.source.path)'")
      let destination = fixture.directory.appendingPathComponent("compressed.gif")
      let compressor = GifskiCLICompressor(executableURL: executable)
      XCTAssertEqual(compressor.requiredCacheBytes, 128 * 1_024 * 1_024)
      let output = CompressedPreviewOutputReservation(
        url: destination, maximumBytes: 100_000, sourceURL: fixture.source,
        cacheDirectory: cache, maximumCacheBytes: maximumCacheBytes)
      do {
        _ = try await compressor.compress(
          source: fixture.metadata, settings: GIFCompressionSettings(), to: output)
        XCTAssertGreaterThan(maximumCacheBytes, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let received = try String(contentsOf: arguments, encoding: .utf8)
        XCTAssertTrue(received.contains(cache.path + "/.gifferent-gifski-"))
      } catch let error as GifskiCompressionError {
        XCTAssertEqual(maximumCacheBytes, 1)
        XCTAssertEqual(error, .frameWorkspaceLimitExceeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: arguments.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
      }
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path), [])
      XCTAssertEqual(try temporaryDirectories(in: fixture.directory), [])
    }
  }

  func testPinnedRealGifskiCLIWhenPresent() async throws {
    let executable = URL(fileURLWithPath: "/private/tmp/gifski-target-1.34.0/release/gifski")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw XCTSkip("pinned Gifski 1.34.0 fixture executable is unavailable")
    }
    for loopsForever in [true, false] {
      let fixture = try makeFixture(delaysCentiseconds: [7, 7, 7], loopsForever: loopsForever)
      defer { try? FileManager.default.removeItem(at: fixture.directory) }
      let destination = fixture.directory.appendingPathComponent("compressed.gif")
      let result = try await GifskiCLICompressor(executableURL: executable).compress(
        source: fixture.metadata,
        settings: GIFCompressionSettings(qualityPercent: 90),
        to: reservation(fixture, destination: destination, maximumBytes: 5_000_000)
      )
      XCTAssertGreaterThan(result.frameCount, 0)
      XCTAssertEqual(result.durationCentiseconds, fixture.metadata.durationCentiseconds)
      XCTAssertEqual(result.delaysCentiseconds.reduce(0, +), fixture.metadata.durationCentiseconds)
      let sample = try GIFFrameSampler.sample(
        delaysCentiseconds: fixture.metadata.delaysCentiseconds, frameRate: .fps24)
      XCTAssertTrue(
        GIFFrameScheduleValidator.matches(
          emittedDelaysCentiseconds: result.delaysCentiseconds,
          expectedDelaysCentiseconds: sample.expectedDelaysCentiseconds))
      XCTAssertEqual(result.loopsForever, loopsForever)
    }
  }

  func testPinnedRealGifskiPreservesCanonical24FPSCentisecondSchedule() async throws {
    let executable = URL(fileURLWithPath: "/private/tmp/gifski-target-1.34.0/release/gifski")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw XCTSkip("pinned Gifski 1.34.0 fixture executable is unavailable")
    }
    let expectedDelays = try ImageIOOriginalGIFEncoder.frameDelaysCentiseconds(
      for: (0..<24).map { Double($0) / 24 }
    )
    XCTAssertEqual(GifskiCLICompressor.constantFrameRate(for: expectedDelays), "24")
    let fixture = try makeFixture(delaysCentiseconds: expectedDelays, loopsForever: true)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let result = try await GifskiCLICompressor(executableURL: executable).compress(
      source: fixture.metadata,
      settings: GIFCompressionSettings(qualityPercent: 90),
      to: reservation(fixture, destination: destination, maximumBytes: 5_000_000)
    )
    XCTAssertGreaterThan(result.frameCount, 0)
    XCTAssertEqual(result.durationCentiseconds, expectedDelays.reduce(0, +))
    XCTAssertEqual(result.delaysCentiseconds.reduce(0, +), expectedDelays.reduce(0, +))
    let sample = try GIFFrameSampler.sample(delaysCentiseconds: expectedDelays, frameRate: .fps24)
    XCTAssertTrue(
      GIFFrameScheduleValidator.matches(
        emittedDelaysCentiseconds: result.delaysCentiseconds,
        expectedDelaysCentiseconds: sample.expectedDelaysCentiseconds))
    XCTAssertTrue(result.loopsForever)
  }

  private struct Fixture {
    let directory: URL
    let source: URL
    let metadata: EncodedGIF
  }

  private func makeFixture(delayCentiseconds: Int, loopsForever: Bool) throws -> Fixture {
    try makeFixture(
      delaysCentiseconds: Array(repeating: delayCentiseconds, count: 3),
      loopsForever: loopsForever
    )
  }

  private func makeFixture(delaysCentiseconds: [Int], loopsForever: Bool) throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifferent-gifski-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    let source = directory.appendingPathComponent("source.gif")
    guard
      let destination = CGImageDestinationCreateWithURL(
        source as CFURL, UTType.gif.identifier as CFString, delaysCentiseconds.count, nil)
    else { throw GifskiCompressionError.invalidSource }
    if loopsForever {
      let loop: [CFString: Any] = [kCGImagePropertyGIFLoopCount: 0]
      CGImageDestinationSetProperties(
        destination, [kCGImagePropertyGIFDictionary: loop] as CFDictionary)
    }
    for index in delaysCentiseconds.indices {
      let context = CGContext(
        data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )!
      context.setFillColor(
        CGColor(
          red: CGFloat((index * 37) % 251) / 250,
          green: CGFloat((index * 73) % 241) / 240,
          blue: CGFloat((index * 109) % 239) / 238,
          alpha: 1
        ))
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
      let properties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFUnclampedDelayTime: Double(delaysCentiseconds[index]) / 100,
          kCGImagePropertyGIFDelayTime: Double(delaysCentiseconds[index]) / 100,
        ] as [CFString: Any]
      ]
      CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else {
      throw GifskiCompressionError.invalidSource
    }
    return Fixture(
      directory: directory, source: source,
      metadata: try GIFMetadataInspector().inspect(source))
  }

  private func fakeExecutable(in directory: URL, body: String) throws -> URL {
    let url = directory.appendingPathComponent("fake-gifski")
    try Data(("#!/bin/sh\nset -eu\n" + body + "\n").utf8).write(to: url)
    guard chmod(url.path, 0o700) == 0 else { throw GifskiCompressionError.invalidExecutable }
    return url
  }

  private func reservation(
    _ fixture: Fixture,
    destination: URL,
    maximumBytes: Int64
  ) -> CompressedPreviewOutputReservation {
    CompressedPreviewOutputReservation(
      url: destination, maximumBytes: maximumBytes, sourceURL: fixture.source)
  }

  private func temporaryDirectories(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix(".gifferent-gifski-") }
  }

  private func waitUntil(
    timeout: Duration = .seconds(3),
    condition: () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
      if clock.now >= deadline { throw GifskiCompressionError.cancelled }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private actor SearchOutputFactory {
  private let source: EncodedGIF
  private let sizes: [Int64]
  private var index = 0

  init(source: EncodedGIF, sizes: [Int64]) {
    self.source = source
    self.sizes = sizes
  }

  func make(_ settings: GIFCompressionSettings) -> EncodedGIF {
    defer { index += 1 }
    return EncodedGIF(
      url: URL(fileURLWithPath: "/tmp/candidate-\(index).gif"),
      width: settings.scale.expectedDimension(source.width),
      height: settings.scale.expectedDimension(source.height), frameCount: 1,
      delaysCentiseconds: [100], durationCentiseconds: 100, loopsForever: true,
      fileBytes: sizes[index])
  }
}

private actor SearchDiscardRecorder {
  private(set) var urls: [URL] = []

  func append(_ url: URL) { urls.append(url) }
}
