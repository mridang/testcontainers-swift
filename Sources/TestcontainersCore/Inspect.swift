/// Strongly-typed data types for the Docker `GET /containers/{id}/json` response.
///
/// Each struct is `Codable` with `CodingKeys` mapping Docker's PascalCase JSON keys
/// to Swift camelCase properties. All fields are optional so that unknown or
/// missing keys in the Docker API response are silently tolerated.
///
/// The top-level type is `ContainerInspectInfo`. The other types model the nested
/// sub-objects of the inspect response.
import Foundation

/// A single health-check execution record.
public struct ContainerLog: Codable {
    public let start: String?
    public let end: String?
    public let exitCode: Int?
    public let output: String?

    enum CodingKeys: String, CodingKey {
        case start = "Start"
        case end = "End"
        case exitCode = "ExitCode"
        case output = "Output"
    }
}

/// Aggregated health-check state for a container.
public struct ContainerHealth: Codable {
    public let status: String?
    public let failingStreak: Int?
    public let log: [ContainerLog]?

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case failingStreak = "FailingStreak"
        case log = "Log"
    }
}

/// Container lifecycle state.
public struct ContainerState: Codable {
    public let status: String?
    public let running: Bool?
    public let paused: Bool?
    public let restarting: Bool?
    public let oomKilled: Bool?
    public let dead: Bool?
    public let pid: Int?
    public let exitCode: Int?
    public let error: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let health: ContainerHealth?

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case running = "Running"
        case paused = "Paused"
        case restarting = "Restarting"
        case oomKilled = "OOMKilled"
        case dead = "Dead"
        case pid = "Pid"
        case exitCode = "ExitCode"
        case error = "Error"
        case startedAt = "StartedAt"
        case finishedAt = "FinishedAt"
        case health = "Health"
    }
}

/// Container OS/architecture platform.
public struct ContainerPlatform: Codable {
    public let os: String?
    public let architecture: String?
    public let variant: String?

    enum CodingKeys: String, CodingKey {
        case os = "os"
        case architecture = "architecture"
        case variant = "variant"
    }
}

/// Image manifest descriptor (multi-platform images).
public struct ContainerImageManifestDescriptor: Codable {
    public let mediaType: String?
    public let digest: String?
    public let size: Int?
    public let urls: [String]?
    public let annotations: [String: String]?
    public let data: String?
    public let platform: ContainerPlatform?
    public let artifactType: String?

    enum CodingKeys: String, CodingKey {
        case mediaType = "mediaType"
        case digest = "digest"
        case size = "size"
        case urls = "urls"
        case annotations = "annotations"
        case data = "data"
        case platform = "platform"
        case artifactType = "artifactType"
    }
}

/// Block I/O weight device setting.
public struct ContainerBlkioWeightDevice: Codable {
    public let path: String?
    public let weight: Int?

    enum CodingKeys: String, CodingKey {
        case path = "Path"
        case weight = "Weight"
    }
}

/// Block I/O device rate (bytes/ops per second).
public struct ContainerBlkioDeviceRate: Codable {
    public let path: String?
    public let rate: Int?

    enum CodingKeys: String, CodingKey {
        case path = "Path"
        case rate = "Rate"
    }
}

/// Device mapping (device file pass-through).
public struct ContainerDeviceMapping: Codable {
    public let pathOnHost: String?
    public let pathInContainer: String?
    public let cgroupPermissions: String?

    enum CodingKeys: String, CodingKey {
        case pathOnHost = "PathOnHost"
        case pathInContainer = "PathInContainer"
        case cgroupPermissions = "CgroupPermissions"
    }
}

/// GPU / device request.
public struct ContainerDeviceRequest: Codable {
    public let driver: String?
    public let count: Int?
    public let deviceIDs: [String]?
    public let capabilities: [[String]]?
    public let options: [String: String]?

    enum CodingKeys: String, CodingKey {
        case driver = "Driver"
        case count = "Count"
        case deviceIDs = "DeviceIDs"
        case capabilities = "Capabilities"
        case options = "Options"
    }
}

/// Resource ulimit specification.
public struct ContainerUlimit: Codable {
    public let name: String?
    public let soft: Int?
    public let hard: Int?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case soft = "Soft"
        case hard = "Hard"
    }
}

/// Container log driver configuration.
public struct ContainerLogConfig: Codable {
    public let type: String?
    public let config: [String: String]?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case config = "Config"
    }
}

/// A single host-port binding for a container port.
public struct ContainerPortBinding: Codable {
    public let hostIp: String?
    public let hostPort: String?

    enum CodingKeys: String, CodingKey {
        case hostIp = "HostIp"
        case hostPort = "HostPort"
    }
}

/// Container restart policy.
public struct ContainerRestartPolicy: Codable {
    public let name: String?
    public let maximumRetryCount: Int?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maximumRetryCount = "MaximumRetryCount"
    }
}

/// Bind mount options.
public struct ContainerBindOptions: Codable {
    public let propagation: String?
    public let nonRecursive: Bool?
    public let createMountpoint: Bool?
    public let readOnlyNonRecursive: Bool?
    public let readOnlyForceRecursive: Bool?

    enum CodingKeys: String, CodingKey {
        case propagation = "Propagation"
        case nonRecursive = "NonRecursive"
        case createMountpoint = "CreateMountpoint"
        case readOnlyNonRecursive = "ReadOnlyNonRecursive"
        case readOnlyForceRecursive = "ReadOnlyForceRecursive"
    }
}

/// Volume driver configuration for a mount.
public struct ContainerVolumeDriverConfig: Codable {
    public let name: String?
    public let options: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case options = "Options"
    }
}

/// Volume mount options.
public struct ContainerVolumeOptions: Codable {
    public let noCopy: Bool?
    public let labels: [String: String]?
    public let driverConfig: ContainerVolumeDriverConfig?
    public let subpath: String?

    enum CodingKeys: String, CodingKey {
        case noCopy = "NoCopy"
        case labels = "Labels"
        case driverConfig = "DriverConfig"
        case subpath = "Subpath"
    }
}

/// Image pull options for a mount.
public struct ContainerImageOptions: Codable {
    public let subpath: String?

    enum CodingKeys: String, CodingKey {
        case subpath = "Subpath"
    }
}

/// Tmpfs mount options.
public struct ContainerTmpfsOptions: Codable {
    public let sizeBytes: Int?
    public let mode: Int?
    public let options: [[String]]?

    enum CodingKeys: String, CodingKey {
        case sizeBytes = "SizeBytes"
        case mode = "Mode"
        case options = "Options"
    }
}

/// A mount point as described in the container's host config.
public struct ContainerMountPoint: Codable {
    public let type: String?
    public let source: String?
    public let target: String?
    public let readOnly: Bool?
    public let consistency: String?
    public let bindOptions: ContainerBindOptions?
    public let volumeOptions: ContainerVolumeOptions?
    public let tmpfsOptions: ContainerTmpfsOptions?
    public let imageOptions: ContainerImageOptions?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case source = "Source"
        case target = "Target"
        case readOnly = "ReadOnly"
        case consistency = "Consistency"
        case bindOptions = "BindOptions"
        case volumeOptions = "VolumeOptions"
        case tmpfsOptions = "TmpfsOptions"
        case imageOptions = "ImageOptions"
    }
}

/// Host configuration passed to the Docker daemon at container creation.
public struct ContainerHostConfig: Codable {
    public let binds: [String]?
    public let containerIDFile: String?
    public let logConfig: ContainerLogConfig?
    public let networkMode: String?
    public let portBindings: [String: [ContainerPortBinding]?]?
    public let restartPolicy: ContainerRestartPolicy?
    public let autoRemove: Bool?
    public let volumeDriver: String?
    public let volumesFrom: [String]?
    public let mounts: [ContainerMountPoint]?
    public let consoleSize: [Int]?
    public let annotations: [String: String]?
    public let capAdd: [String]?
    public let capDrop: [String]?
    public let cgroupnsMode: String?
    public let dns: [String]?
    public let dnsOptions: [String]?
    public let dnsSearch: [String]?
    public let extraHosts: [String]?
    public let groupAdd: [String]?
    public let ipcMode: String?
    public let cgroup: String?
    public let links: [String]?
    public let oomScoreAdj: Int?
    public let pidMode: String?
    public let privileged: Bool?
    public let publishAllPorts: Bool?
    public let readonlyRootfs: Bool?
    public let securityOpt: [String]?
    public let storageOpt: [String: String]?
    public let tmpfs: [String: String]?
    public let utsMode: String?
    public let usernsMode: String?
    public let shmSize: Int?
    public let sysctls: [String: String]?
    public let runtime: String?
    public let isolation: String?
    public let cpuShares: Int?
    public let memory: Int?
    public let nanoCpus: Int?
    public let cgroupParent: String?
    public let blkioWeight: Int?
    public let blkioWeightDevice: [ContainerBlkioWeightDevice]?
    public let blkioDeviceReadBps: [ContainerBlkioDeviceRate]?
    public let blkioDeviceWriteBps: [ContainerBlkioDeviceRate]?
    public let blkioDeviceReadIOps: [ContainerBlkioDeviceRate]?
    public let blkioDeviceWriteIOps: [ContainerBlkioDeviceRate]?
    public let cpuPeriod: Int?
    public let cpuQuota: Int?
    public let cpuRealtimePeriod: Int?
    public let cpuRealtimeRuntime: Int?
    public let cpusetCpus: String?
    public let cpusetMems: String?
    public let devices: [ContainerDeviceMapping]?
    public let deviceCgroupRules: [String]?
    public let deviceRequests: [ContainerDeviceRequest]?
    public let kernelMemoryTCP: Int?
    public let memoryReservation: Int?
    public let memorySwap: Int?
    public let memorySwappiness: Int?
    public let oomKillDisable: Bool?
    public let `init`: Bool?
    public let pidsLimit: Int?
    public let ulimits: [ContainerUlimit]?
    public let cpuCount: Int?
    public let cpuPercent: Int?
    public let ioMaximumIOps: Int?
    public let ioMaximumBandwidth: Int?
    public let maskedPaths: [String]?
    public let readonlyPaths: [String]?

    enum CodingKeys: String, CodingKey {
        case binds = "Binds"
        case containerIDFile = "ContainerIDFile"
        case logConfig = "LogConfig"
        case networkMode = "NetworkMode"
        case portBindings = "PortBindings"
        case restartPolicy = "RestartPolicy"
        case autoRemove = "AutoRemove"
        case volumeDriver = "VolumeDriver"
        case volumesFrom = "VolumesFrom"
        case mounts = "Mounts"
        case consoleSize = "ConsoleSize"
        case annotations = "Annotations"
        case capAdd = "CapAdd"
        case capDrop = "CapDrop"
        case cgroupnsMode = "CgroupnsMode"
        case dns = "Dns"
        case dnsOptions = "DnsOptions"
        case dnsSearch = "DnsSearch"
        case extraHosts = "ExtraHosts"
        case groupAdd = "GroupAdd"
        case ipcMode = "IpcMode"
        case cgroup = "Cgroup"
        case links = "Links"
        case oomScoreAdj = "OomScoreAdj"
        case pidMode = "PidMode"
        case privileged = "Privileged"
        case publishAllPorts = "PublishAllPorts"
        case readonlyRootfs = "ReadonlyRootfs"
        case securityOpt = "SecurityOpt"
        case storageOpt = "StorageOpt"
        case tmpfs = "Tmpfs"
        case utsMode = "UTSMode"
        case usernsMode = "UsernsMode"
        case shmSize = "ShmSize"
        case sysctls = "Sysctls"
        case runtime = "Runtime"
        case isolation = "Isolation"
        case cpuShares = "CpuShares"
        case memory = "Memory"
        case nanoCpus = "NanoCpus"
        case cgroupParent = "CgroupParent"
        case blkioWeight = "BlkioWeight"
        case blkioWeightDevice = "BlkioWeightDevice"
        case blkioDeviceReadBps = "BlkioDeviceReadBps"
        case blkioDeviceWriteBps = "BlkioDeviceWriteBps"
        case blkioDeviceReadIOps = "BlkioDeviceReadIOps"
        case blkioDeviceWriteIOps = "BlkioDeviceWriteIOps"
        case cpuPeriod = "CpuPeriod"
        case cpuQuota = "CpuQuota"
        case cpuRealtimePeriod = "CpuRealtimePeriod"
        case cpuRealtimeRuntime = "CpuRealtimeRuntime"
        case cpusetCpus = "CpusetCpus"
        case cpusetMems = "CpusetMems"
        case devices = "Devices"
        case deviceCgroupRules = "DeviceCgroupRules"
        case deviceRequests = "DeviceRequests"
        case kernelMemoryTCP = "KernelMemoryTCP"
        case memoryReservation = "MemoryReservation"
        case memorySwap = "MemorySwap"
        case memorySwappiness = "MemorySwappiness"
        case oomKillDisable = "OomKillDisable"
        case `init` = "Init"
        case pidsLimit = "PidsLimit"
        case ulimits = "Ulimits"
        case cpuCount = "CpuCount"
        case cpuPercent = "CpuPercent"
        case ioMaximumIOps = "IOMaximumIOps"
        case ioMaximumBandwidth = "IOMaximumBandwidth"
        case maskedPaths = "MaskedPaths"
        case readonlyPaths = "ReadonlyPaths"
    }
}

/// Graph driver info for the container's root filesystem.
public struct ContainerGraphDriver: Codable {
    public let name: String?
    public let data: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case data = "Data"
    }
}

/// A volume or bind mount attached to the container (from inspect output).
public struct ContainerMount: Codable {
    public let type: String?
    public let name: String?
    public let source: String?
    public let destination: String?
    public let driver: String?
    public let mode: String?
    public let rw: Bool?
    public let propagation: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case name = "Name"
        case source = "Source"
        case destination = "Destination"
        case driver = "Driver"
        case mode = "Mode"
        case rw = "RW"
        case propagation = "Propagation"
    }
}

/// Health-check configuration baked into the image or container.
public struct ContainerHealthcheck: Codable {
    public let test: [String]?
    public let interval: Int?
    public let timeout: Int?
    public let retries: Int?
    public let startPeriod: Int?
    public let startInterval: Int?

    enum CodingKeys: String, CodingKey {
        case test = "Test"
        case interval = "Interval"
        case timeout = "Timeout"
        case retries = "Retries"
        case startPeriod = "StartPeriod"
        case startInterval = "StartInterval"
    }
}

/// Container configuration (image metadata + user overrides).
public struct ContainerConfig: Codable {
    public let hostname: String?
    public let domainname: String?
    public let user: String?
    public let attachStdin: Bool?
    public let attachStdout: Bool?
    public let attachStderr: Bool?
    public let exposedPorts: [String: [String: String]?]?
    public let tty: Bool?
    public let openStdin: Bool?
    public let stdinOnce: Bool?
    public let env: [String]?
    public let cmd: [String]?
    public let healthcheck: ContainerHealthcheck?
    public let argsEscaped: Bool?
    public let image: String?
    public let volumes: [String: [String: String]?]?
    public let workingDir: String?
    public let entrypoint: [String]?
    public let networkDisabled: Bool?
    public let macAddress: String?
    public let onBuild: [String]?
    public let labels: [String: String]?
    public let stopSignal: String?
    public let stopTimeout: Int?
    public let shell: [String]?

    enum CodingKeys: String, CodingKey {
        case hostname = "Hostname"
        case domainname = "Domainname"
        case user = "User"
        case attachStdin = "AttachStdin"
        case attachStdout = "AttachStdout"
        case attachStderr = "AttachStderr"
        case exposedPorts = "ExposedPorts"
        case tty = "Tty"
        case openStdin = "OpenStdin"
        case stdinOnce = "StdinOnce"
        case env = "Env"
        case cmd = "Cmd"
        case healthcheck = "Healthcheck"
        case argsEscaped = "ArgsEscaped"
        case image = "Image"
        case volumes = "Volumes"
        case workingDir = "WorkingDir"
        case entrypoint = "Entrypoint"
        case networkDisabled = "NetworkDisabled"
        case macAddress = "MacAddress"
        case onBuild = "OnBuild"
        case labels = "Labels"
        case stopSignal = "StopSignal"
        case stopTimeout = "StopTimeout"
        case shell = "Shell"
    }
}

/// IPAM configuration for a network endpoint.
public struct ContainerIPAMConfig: Codable {
    public let ipv4Address: String?
    public let ipv6Address: String?
    public let linkLocalIPs: [String]?

    enum CodingKeys: String, CodingKey {
        case ipv4Address = "IPv4Address"
        case ipv6Address = "IPv6Address"
        case linkLocalIPs = "LinkLocalIPs"
    }
}

/// A container's attachment to a specific network.
public struct ContainerNetworkEndpoint: Codable {
    public let ipamConfig: ContainerIPAMConfig?
    public let links: [String]?
    public let aliases: [String]?
    public let macAddress: String?
    public let driverOpts: [String: String]?
    public let gwPriority: Int?
    public let networkID: String?
    public let endpointID: String?
    public let gateway: String?
    public let ipAddress: String?
    public let ipPrefixLen: Int?
    public let ipv6Gateway: String?
    public let globalIPv6Address: String?
    public let globalIPv6PrefixLen: Int?
    public let dnsNames: [String]?

    enum CodingKeys: String, CodingKey {
        case ipamConfig = "IPAMConfig"
        case links = "Links"
        case aliases = "Aliases"
        case macAddress = "MacAddress"
        case driverOpts = "DriverOpts"
        case gwPriority = "GwPriority"
        case networkID = "NetworkID"
        case endpointID = "EndpointID"
        case gateway = "Gateway"
        case ipAddress = "IPAddress"
        case ipPrefixLen = "IPPrefixLen"
        case ipv6Gateway = "IPv6Gateway"
        case globalIPv6Address = "GlobalIPv6Address"
        case globalIPv6PrefixLen = "GlobalIPv6PrefixLen"
        case dnsNames = "DNSNames"
    }
}

/// An IP address assigned to a container on a network interface.
public struct ContainerAddress: Codable {
    public let addr: String?
    public let prefixLen: Int?

    enum CodingKeys: String, CodingKey {
        case addr = "Addr"
        case prefixLen = "PrefixLen"
    }
}

/// Network settings for the container (from inspect output).
public struct ContainerNetworkSettings: Codable {
    public let bridge: String?
    public let sandboxID: String?
    public let hairpinMode: Bool?
    public let linkLocalIPv6Address: String?
    public let linkLocalIPv6PrefixLen: Int?
    public let ports: [String: [ContainerPortBinding]?]?
    public let sandboxKey: String?
    public let secondaryIPAddresses: [ContainerAddress]?
    public let secondaryIPv6Addresses: [ContainerAddress]?
    public let endpointID: String?
    public let gateway: String?
    public let globalIPv6Address: String?
    public let globalIPv6PrefixLen: Int?
    public let ipAddress: String?
    public let ipPrefixLen: Int?
    public let ipv6Gateway: String?
    public let macAddress: String?
    public let networks: [String: ContainerNetworkEndpoint]?

    enum CodingKeys: String, CodingKey {
        case bridge = "Bridge"
        case sandboxID = "SandboxID"
        case hairpinMode = "HairpinMode"
        case linkLocalIPv6Address = "LinkLocalIPv6Address"
        case linkLocalIPv6PrefixLen = "LinkLocalIPv6PrefixLen"
        case ports = "Ports"
        case sandboxKey = "SandboxKey"
        case secondaryIPAddresses = "SecondaryIPAddresses"
        case secondaryIPv6Addresses = "SecondaryIPv6Addresses"
        case endpointID = "EndpointID"
        case gateway = "Gateway"
        case globalIPv6Address = "GlobalIPv6Address"
        case globalIPv6PrefixLen = "GlobalIPv6PrefixLen"
        case ipAddress = "IPAddress"
        case ipPrefixLen = "IPPrefixLen"
        case ipv6Gateway = "IPv6Gateway"
        case macAddress = "MacAddress"
        case networks = "Networks"
    }

    /// Returns the networks map, or `nil` if absent.
    public func getNetworks() -> [String: ContainerNetworkEndpoint]? { networks }
}

/// Top-level container inspect response (`GET /containers/{id}/json`).
public struct ContainerInspectInfo: Codable {
    public let id: String?
    public let created: String?
    public let path: String?
    public let args: [String]?
    public let state: ContainerState?
    public let image: String?
    public let resolvConfPath: String?
    public let hostnamePath: String?
    public let hostsPath: String?
    public let logPath: String?
    public let name: String?
    public let restartCount: Int?
    public let driver: String?
    public let platform: String?
    public let imageManifestDescriptor: ContainerImageManifestDescriptor?
    public let mountLabel: String?
    public let processLabel: String?
    public let appArmorProfile: String?
    public let execIDs: [String]?
    public let hostConfig: ContainerHostConfig?
    public let graphDriver: ContainerGraphDriver?
    public let sizeRw: Int?
    public let sizeRootFs: Int?
    public let mounts: [ContainerMount]?
    public let config: ContainerConfig?
    public let networkSettings: ContainerNetworkSettings?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case created = "Created"
        case path = "Path"
        case args = "Args"
        case state = "State"
        case image = "Image"
        case resolvConfPath = "ResolvConfPath"
        case hostnamePath = "HostnamePath"
        case hostsPath = "HostsPath"
        case logPath = "LogPath"
        case name = "Name"
        case restartCount = "RestartCount"
        case driver = "Driver"
        case platform = "Platform"
        case imageManifestDescriptor = "ImageManifestDescriptor"
        case mountLabel = "MountLabel"
        case processLabel = "ProcessLabel"
        case appArmorProfile = "AppArmorProfile"
        case execIDs = "ExecIDs"
        case hostConfig = "HostConfig"
        case graphDriver = "GraphDriver"
        case sizeRw = "SizeRw"
        case sizeRootFs = "SizeRootFs"
        case mounts = "Mounts"
        case config = "Config"
        case networkSettings = "NetworkSettings"
    }

    /// Returns the network settings, or `nil` if absent.
    public func getNetworkSettings() -> ContainerNetworkSettings? { networkSettings }
}
