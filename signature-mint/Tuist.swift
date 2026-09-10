import ProjectDescription

let config = Config(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(default: .allPossible),
            storages: [.local]
        )
    )
)
