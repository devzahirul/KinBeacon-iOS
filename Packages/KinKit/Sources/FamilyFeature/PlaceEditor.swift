import DesignSystem
import Domain
import MapKit
import SwiftUI

/// Add or edit a safe place: drag the map under the fixed pin, name it, pick a radius.
struct PlaceEditor: View {
    @State private var place: Place
    @State private var camera: MapCameraPosition
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    let save: (Place) async throws -> Void

    init(place: Place, save: @escaping (Place) async throws -> Void) {
        _place = State(initialValue: place)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
            latitudinalMeters: max(place.radius * 6, 800),
            longitudinalMeters: max(place.radius * 6, 800)
        )))
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Map(position: $camera) {
                        MapCircle(
                            center: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
                            radius: place.radius
                        )
                        .foregroundStyle(KinColor.brand.opacity(0.15))
                        .stroke(KinColor.brand, lineWidth: 1.5)
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        place.coordinate = Coordinate(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                    }
                    .overlay {
                        Image(systemName: "mappin").font(.title.weight(.bold)).foregroundStyle(KinColor.danger).offset(y: -12)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Move the map so the pin sits on the place.")
                }
                Section {
                    TextField("Name (e.g. Home, Lincoln Elementary)", text: $place.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("place.name")
                    Picker("Type", selection: $place.kind) {
                        ForEach(PlaceKind.allCases, id: \.self) { Label($0.shortName, systemImage: $0.symbol).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Radius: \(Int(place.radius)) m")
                        Slider(value: $place.radius, in: Place.minimumRadius ... 1000, step: 25)
                    }
                    Toggle("Alert on arrival", isOn: $place.notifiesOnArrival)
                    Toggle("Alert on departure", isOn: $place.notifiesOnDeparture)
                }
                if let error {
                    Section { InlineBanner(.error, message: error) }
                }
            }
            .tint(KinColor.brand)
            .navigationTitle(place.name.isEmpty ? "New place" : place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await commit() } }
                        .disabled(place.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("place.save")
                }
            }
        }
    }

    private func commit() async {
        isSaving = true
        defer { isSaving = false }
        do {
            place.name = place.name.trimmingCharacters(in: .whitespaces)
            try await save(place)
            dismiss()
        } catch {
            self.error = (error as? KinError)?.errorDescription ?? error.localizedDescription
        }
    }
}
