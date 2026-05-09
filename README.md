# testcontainers-swift

A Swift port of [testcontainers-python](https://github.com/testcontainers/testcontainers-python) `core` + `compose` modules.

Testcontainers is a library that supports tests that need throwaway instances of real Docker containers — databases, message brokers, web servers, and more.

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/mridang/testcontainers-swift", from: "0.0.1")
```

Then add the target dependencies:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "TestcontainersCore", package: "testcontainers-swift"),
        // optionally:
        .product(name: "TestcontainersCompose", package: "testcontainers-swift"),
    ]
)
```

## Usage

### Single container

```swift
import TestcontainersCore

try await DockerContainer.use(
    DockerContainer("redis:7")
        .withExposedPorts(6379)
        .waitingFor(PortWaitStrategy(6379))
) { container in
    let port = try await container.exposedPort(6379)
    // connect to redis on localhost:port
}
```

### Docker Compose

```swift
import TestcontainersCompose

try await DockerCompose.use(
    DockerCompose(context: "Tests/fixtures/my_stack")
) { compose in
    let web = try compose.container(serviceName: "web")
    let pub = try web.publisher(byPort: 8080)
    let port = pub.publishedPort!
    // make HTTP requests to localhost:port
}
```

## Wait strategies

| Strategy | Description |
|----------|-------------|
| `LogMessageWaitStrategy` | Wait for a pattern in container logs |
| `HttpWaitStrategy` | Wait for an HTTP endpoint to respond |
| `HealthcheckWaitStrategy` | Wait for Docker healthcheck to report healthy |
| `PortWaitStrategy` | Wait for a TCP port to accept connections |
| `FileExistsWaitStrategy` | Wait for a file to exist in the container |
| `ContainerStatusWaitStrategy` | Wait for the container status to be `running` |
| `CompositeWaitStrategy` | Run multiple strategies in sequence |
| `ExecWaitStrategy` | Wait for a command to exit with a given code |

## License

Apache 2.0 — see [LICENSE](LICENSE).
