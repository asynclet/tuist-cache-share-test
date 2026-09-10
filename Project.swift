import ProjectDescription

// Три кэшируемых фреймворка и приложение над ними: достаточно, чтобы в кэше
// оказалось несколько записей и промах одной был виден отдельно от остальных.
private func framework(_ name: String, dependencies: [TargetDependency] = []) -> Target {
    .target(
        name: name,
        destinations: [.iPhone],
        product: .framework,
        bundleId: "io.cacheshare.\(name.lowercased())",
        deploymentTargets: .iOS("17.0"),
        sources: ["Sources/\(name)/**"],
        dependencies: dependencies
    )
}

let project = Project(
    name: "CacheShare",
    targets: [
        framework("Core"),
        framework("Feature", dependencies: [.target(name: "Core")]),
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.cacheshare.app",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/App/**"],
            dependencies: [.target(name: "Feature")]
        ),
    ]
)
