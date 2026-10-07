import XCTest
import MorrowCore
@testable import MorrowApp

final class CreationFlowTests: XCTestCase {
    @MainActor func testInstalledVersionsAppearBeforeAnInstanceExists() {
        let model = AppModel(preview: true)
        model.instances = []
        model.statuses = [:]
        XCTAssertEqual(model.unconfiguredInstallations, model.installations)
        XCTAssertEqual(model.runningCount, 0)
    }
    @MainActor func testCreateActionPreservesChosenEngineAndExactVersion() {
        let model = AppModel(preview: true)
        let chosen = model.installations.first { $0.engine == .mongodb }!
        model.selection = .general
        model.requestCreation(installation: chosen)
        XCTAssertEqual(model.creationRequest?.installation, chosen)
        XCTAssertEqual(model.selection, .instances)
    }
    @MainActor func testConfiguredVersionsAreNotListedAsUnconfigured() {
        let model = AppModel(preview: true)
        XCTAssertTrue(model.unconfiguredInstallations.isEmpty)
        let removed = model.instances.removeLast()
        XCTAssertEqual(model.unconfiguredInstallations, [removed.installation])
    }
    @MainActor func testNewInstanceWithoutAnyInstalledVersionOpensCreation() {
        let model = AppModel(preview: true)
        model.installations = []
        model.requestCreation()
        XCTAssertNotNil(model.creationRequest)
        XCTAssertNil(model.creationRequest?.installation)
        XCTAssertEqual(model.selection, .instances)
    }
    @MainActor func testCreationCanRequestAVersionThatIsNotInstalled() {
        let model = AppModel(preview: true)
        model.requestCreation(engine: .mongodb, version: "mongodb/brew/mongodb-community@8.0")
        XCTAssertEqual(model.creationRequest?.engine, .mongodb)
        XCTAssertEqual(model.creationRequest?.version, "mongodb/brew/mongodb-community@8.0")
        XCTAssertNil(model.creationRequest?.installation)
    }
}
