public import Domain
public import MapKit
public import Observation
public import Session
public import SwiftUI
import Foundation
import KinCore

@MainActor
@Observable
public final class FamilyMapModel {
    public var camera: MapCameraPosition = .automatic
    public var selectedMemberID: MemberID?
    public private(set) var arrivalAlerts: Set<MemberID> = []
    public private(set) var toast: String?
    public private(set) var isSendingCheckIn = false
    public var mapStyleIsHybrid = false

    @ObservationIgnored public let store: FamilyStore
    @ObservationIgnored private let controls: any ParentControlService
    @ObservationIgnored private var didFrame = false

    public init(store: FamilyStore, controls: any ParentControlService) {
        self.store = store
        self.controls = controls
    }

    public var snapshot: FamilySnapshot? {
        store.snapshot
    }

    /// Members that have a known position, children first.
    public var mappableMembers: [FamilyMember] {
        guard let snapshot else { return [] }
        return snapshot.members
            .filter { snapshot.status($0.id)?.location != nil }
            .sorted { ($0.role == .child ? 0 : 1, $0.name) < ($1.role == .child ? 0 : 1, $1.name) }
    }

    public var selectedMember: FamilyMember? {
        let id = selectedMemberID ?? store.selectedChildID ?? mappableMembers.first?.id
        return id.flatMap { snapshot?.member($0) }
    }

    public func select(_ member: FamilyMember) {
        selectedMemberID = member.id
        if member.role == .child {
            store.selectedChildID = member.id
        }
        guard let coordinate = snapshot?.status(member.id)?.location?.coordinate else { return }
        withAnimation(.smooth) {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(coordinate),
                latitudinalMeters: 1600,
                longitudinalMeters: 1600
            ))
        }
    }

    /// Frames everyone once, when the first snapshot arrives — later updates must not yank the user's camera.
    public func frameEveryoneIfNeeded() {
        guard !didFrame,
              let region = Self.region(fitting: mappableMembers.compactMap { snapshot?.status($0.id)?.location?.coordinate })
        else { return }
        didFrame = true
        camera = .region(region)
    }

    public func frameEveryone() {
        guard let region = Self.region(fitting: mappableMembers.compactMap { snapshot?.status($0.id)?.location?.coordinate })
        else { return }
        withAnimation(.smooth) { camera = .region(region) }
    }

    public func requestCheckIn() async {
        guard let member = selectedMember else { return }
        isSendingCheckIn = true
        defer { isSendingCheckIn = false }
        do {
            try await controls.send(.requestCheckIn, to: member.id)
            show(String(localized: "Asked \(member.name) to check in"))
        } catch {
            show((error as? KinError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func toggleArrivalAlerts() {
        guard let member = selectedMember else { return }
        if arrivalAlerts.contains(member.id) {
            arrivalAlerts.remove(member.id)
            show(String(localized: "Arrival alerts off for \(member.name)"))
        } else {
            arrivalAlerts.insert(member.id)
            show(String(localized: "We’ll notify you when \(member.name) arrives or leaves"))
        }
    }

    public func openDirections() {
        guard let member = selectedMember, let coordinate = snapshot?.status(member.id)?.location?.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(coordinate)))
        item.name = member.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message {
                toast = nil
            }
        }
    }

    static func region(fitting coordinates: [Coordinate]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        // Extra room at the bottom for the member card.
        let latSpan = max((maxLat - minLat) * 2.4, 0.012)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * 0.15, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: max((maxLon - minLon) * 1.8, 0.012))
        )
    }
}

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
