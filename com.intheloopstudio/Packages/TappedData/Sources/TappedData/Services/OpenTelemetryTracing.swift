import Darwin
import Foundation
@preconcurrency import OpenTelemetryApi
@preconcurrency import OpenTelemetryProtocolExporterCommon
@preconcurrency import OpenTelemetryProtocolExporterHttp
@preconcurrency import OpenTelemetrySdk
@preconcurrency import URLSessionInstrumentation

/// Where app spans go. `make` returns `nil`, so telemetry stays a no-op, in mock mode or without a PostHog key.
public struct TelemetrySettings: Sendable, Equatable {
    public static let serviceName = "tapped-ios"

    public var tracesEndpoint: URL
    public var headers: [String: String]
    public var resource: [String: String]
    /// Hosts whose `URLSession` requests get a client span.
    public var spanHosts: Set<String>
    /// Hosts that also get a W3C `traceparent` header, so the request joins the server's trace.
    public var propagationHosts: Set<String>

    public init(
        tracesEndpoint: URL,
        headers: [String: String],
        resource: [String: String],
        spanHosts: Set<String>,
        propagationHosts: Set<String>
    ) {
        self.tracesEndpoint = tracesEndpoint
        self.headers = headers
        self.resource = resource
        self.spanHosts = spanHosts
        self.propagationHosts = propagationHosts
    }

    /// PostHog ingests OTLP/HTTP traces at `<host>/i/v1/traces`, authenticated with the project token
    /// (`https://posthog.com/docs/distributed-tracing/start-here`).
    public static func make(
        config: TappedConfig,
        app: AppInfo,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TelemetrySettings? {
        guard environment["TAPPED_MOCK"] != "1",
              !config.postHogAPIKey.isEmpty,
              let host = URL(string: config.postHogHost), host.host() != nil else { return nil }
        let apiHosts = Set([config.tappedAPIURL.host()].compactMap(\.self))
        return TelemetrySettings(
            tracesEndpoint: host.appending(path: "i/v1/traces"),
            headers: ["Authorization": "Bearer \(config.postHogAPIKey)"],
            resource: [
                "service.name": serviceName,
                "service.version": app.version,
                "app.build": app.build,
                "device.model.identifier": app.deviceModel,
                "os.name": "iOS",
                "os.version": app.osVersion,
            ],
            spanHosts: apiHosts.union([config.typesenseHost]),
            propagationHosts: apiHosts
        )
    }
}

public struct AppInfo: Sendable, Equatable {
    public var version: String
    public var build: String
    public var deviceModel: String
    public var osVersion: String

    public init(version: String, build: String, deviceModel: String, osVersion: String) {
        self.version = version
        self.build = build
        self.deviceModel = deviceModel
        self.osVersion = osVersion
    }

    public static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppInfo {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let os = processInfo.operatingSystemVersion
        return AppInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            deviceModel: processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        )
    }
}

/// OpenTelemetry tracer exporting over OTLP/HTTP, plus `URLSession` instrumentation for the Tapped API and Typesense.
/// The instrumentation swizzles `URLSession`, so `traceparent` is added without touching the repositories' requests.
// The SDK's tracer and provider are thread-safe; every stored property is immutable.
public final class OpenTelemetryTracing: TelemetryRepository, @unchecked Sendable {
    private let provider: TracerProviderSdk
    private let tracer: any Tracer
    private let urlSession: URLSessionInstrumentation

    /// Builds the SDK and installs the instrumentation. Create once per process, off the main thread.
    public init(settings: TelemetrySettings, exporter: (any SpanExporter)? = nil) {
        let exporter = exporter ?? OtlpHttpTraceExporter(
            endpoint: settings.tracesEndpoint,
            config: OtlpConfiguration(headers: settings.headers.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }),
            envVarHeaders: nil
        )
        provider = TracerProviderBuilder()
            .with(resource: Resource(attributes: settings.resource.mapValues { AttributeValue.string($0) }))
            .add(spanProcessor: BatchSpanProcessor(spanExporter: exporter))
            .build()
        OpenTelemetry.registerTracerProvider(tracerProvider: provider)
        tracer = provider.get(instrumentationName: TelemetrySettings.serviceName)

        let spanHosts = settings.spanHosts
        let propagationHosts = settings.propagationHosts
        urlSession = URLSessionInstrumentation(configuration: URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in request.url?.host().map(spanHosts.contains) ?? false },
            nameSpan: { request in "\(request.httpMethod ?? "GET") \(request.url?.host() ?? "")" },
            shouldInjectTracingHeaders: { request in request.url?.host().map(propagationHosts.contains) ?? false },
            tracer: provider.get(instrumentationName: "URLSession"),
            semanticConvention: .stable
        ))
    }

    public func record(_ spans: [TelemetrySpan]) async {
        for span in spans { emit(span, parent: nil) }
    }

    /// Exports everything queued so far (tests, or before the app is suspended).
    public func flush() {
        provider.forceFlush()
    }

    private func emit(_ span: TelemetrySpan, parent: (any Span)?) {
        let builder = tracer.spanBuilder(spanName: span.name).setStartTime(time: span.start)
        if let parent { builder.setParent(parent) } else { builder.setNoParent() }
        let started = builder.startSpan()
        for (key, value) in span.attributes {
            started.setAttribute(key: key, value: value.attributeValue)
        }
        for event in span.events {
            started.addEvent(name: event.name, attributes: event.attributes.mapValues(\.attributeValue), timestamp: event.time)
        }
        for child in span.children {
            emit(child, parent: started)
        }
        started.end(time: span.end)
    }
}

private extension AnalyticsValue {
    var attributeValue: AttributeValue {
        switch self {
        case let .string(value): .string(value)
        case let .int(value): .int(value)
        case let .double(value): .double(value)
        case let .bool(value): .bool(value)
        }
    }
}
