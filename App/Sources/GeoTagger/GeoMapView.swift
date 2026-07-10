import SwiftUI
import MapKit
import GeoTaggerCore

/// MapKit ラッパ: GPX トラック（白縁取り＋黒線）・写真ピン（赤/選択中は青）・
/// ピン⇔テーブル行の双方向選択連動・標準/衛星切替。元 mapHandler.ts の Leaflet 実装を移植。
struct GeoMapView: View {
    let mergedGpx: GpxData?
    let matchResults: [MatchResult]
    @Binding var selection: URL?

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7),
                            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20))
    )
    @State private var isSatellite = false
    /// fitBounds はトラック読み込み時（点列が変わった時）のみ実行するためのキー。
    @State private var lastFittedPointCount: Int = -1

    /// 表示用に間引いたトラック座標（マッチングは Core 側で全点のまま行われる。ここは描画のみ）。
    private var displayTrackCoordinates: [CLLocationCoordinate2D] {
        guard let points = mergedGpx?.points, !points.isEmpty else { return [] }
        let maxPoints = 5000
        guard points.count > maxPoints else {
            return points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        }
        let stride = Double(points.count) / Double(maxPoints)
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(maxPoints)
        var i = 0.0
        while Int(i) < points.count {
            let p = points[Int(i)]
            result.append(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
            i += stride
        }
        return result
    }

    private var pins: [(result: MatchResult, coordinate: CLLocationCoordinate2D)] {
        matchResults.compactMap { r in
            guard let match = r.match else { return nil }
            return (r, CLLocationCoordinate2D(latitude: match.point.lat, longitude: match.point.lon))
        }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if !displayTrackCoordinates.isEmpty {
                MapPolyline(coordinates: displayTrackCoordinates)
                    .stroke(.white, lineWidth: 6)
                MapPolyline(coordinates: displayTrackCoordinates)
                    .stroke(.black, lineWidth: 2)
            }

            ForEach(pins, id: \.result.id) { pin in
                Annotation(pin.result.photo.url.lastPathComponent, coordinate: pin.coordinate) {
                    Circle()
                        .fill(pin.result.photo.url == selection ? Color.blue : Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .onTapGesture { selection = pin.result.photo.url }
                }
            }
        }
        .mapStyle(isSatellite ? .hybrid : .standard)
        .mapControls {
            MapZoomStepper()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button("全体表示") { fitBounds() }
                Button(isSatellite ? "地図" : "衛星") { isSatellite.toggle() }
            }
            .buttonStyle(.borderedProminent)
            .padding(8)
        }
        .onChange(of: mergedGpx?.points.count ?? 0) { _, newCount in
            fitBoundsIfNeeded(newCount)
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue, let pin = pins.first(where: { $0.result.photo.url == newValue }) else { return }
            panTo(pin.coordinate)
        }
    }

    /// トラック読み込み時（点列が変わった時）のみ自動 fit する。
    private func fitBoundsIfNeeded(_ pointCount: Int) {
        guard pointCount != lastFittedPointCount else { return }
        lastFittedPointCount = pointCount
        fitBounds()
    }

    /// 「全体表示」ボタンなど、変化検知に関わらず常に実行する fit 本体。
    private func fitBounds() {
        guard let points = mergedGpx?.points, !points.isEmpty else { return }

        var minLat = points[0].lat, maxLat = points[0].lat
        var minLon = points[0].lon, maxLon = points[0].lon
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }

        // 経度の単純な min/max は180度子午線をまたぐ軌跡（例: 日本→米国の渡航ログ）で
        // 破綻する（例: 139°E と -110°W の中点が本来太平洋上のはずが、単純平均だと
        // ヨーロッパ付近になってしまう）。素な span が180度を超える場合は太平洋越えと
        // みなし、負の経度を +360 して連続な数直線上で min/max を取り直す。
        if maxLon - minLon > 180 {
            let shifted = points.map { $0.lon < 0 ? $0.lon + 360 : $0.lon }
            minLon = shifted.min()!
            maxLon = shifted.max()!
        }
        var centerLon = (minLon + maxLon) / 2
        if centerLon > 180 { centerLon -= 360 }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLon)
        // パディング分（元実装の [20, 20] px 相当）としてスパンを 1.3 倍余分に取る。
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.01)
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    /// ズームは維持したままパンのみ行う（元実装の `map.panTo`）。
    private func panTo(_ coordinate: CLLocationCoordinate2D) {
        withAnimation {
            if let region = cameraPosition.region {
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: region.span))
            } else {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }
}
