import KinCore
import MetricKit

/// Field performance: MetricKit delivers daily launch-time histograms, hang rates, CPU/disk exceptions and
/// crash diagnostics from real devices. In production these payloads are forwarded to the analytics backend;
/// here they are logged so they show up in Console / sysdiagnose.
final class MetricsReporter: NSObject, MXMetricManagerSubscriber {
    @MainActor static let shared = MetricsReporter()

    @MainActor
    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let launch = payload.applicationLaunchMetrics {
                Log.launch.info("MetricKit launch histogram: \(launch.histogrammedTimeToFirstDraw.totalBucketCount) buckets")
            }
            if let hangs = payload.applicationResponsivenessMetrics {
                Log.app.info("MetricKit hang histogram: \(hangs.histogrammedApplicationHangTime.totalBucketCount) buckets")
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            Log.app
                .error(
                    "MetricKit diagnostics: crashes=\(payload.crashDiagnostics?.count ?? 0) hangs=\(payload.hangDiagnostics?.count ?? 0)"
                )
        }
    }
}
