import ProjectDescription

// Отдельный проект ровно для одной цели: получить на машине хоть один артефакт кэша,
// подписанный её значением. Таргет под macOS, потому что рантайм симулятора iOS может
// быть не установлен, а подпись от платформы и от содержимого артефакта не зависит.
// Проект намеренно отдельный: добавь этот таргет к основному — изменятся его хэши,
// и сравнение с машиной A развалится.
let project = Project(
    name: "SignatureMint",
    targets: [
        .target(
            name: "Mint",
            destinations: [.mac],
            product: .framework,
            bundleId: "io.cacheshare.mint",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/Mint/**"]
        ),
    ]
)
