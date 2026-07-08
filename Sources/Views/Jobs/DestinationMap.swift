import SwiftUI
import MapKit
import CoreLocation

/// Geocodes a destination (address + postcode) with CLGeocoder and shows it on a
/// map with an "Open in Maps" action. Hides itself if geocoding fails.
struct DestinationMap: View {
    let address: String?
    let postcode: String?
    let title: String

    @State private var coordinate: CLLocationCoordinate2D?

    /// Session-lifetime cache so the same destination geocodes once, not on every
    /// detail open (CLGeocoder is rate-limited by Apple). NSCache is thread-safe.
    private final class CoordinateBox { let coordinate: CLLocationCoordinate2D; init(_ c: CLLocationCoordinate2D) { coordinate = c } }
    private static let cache = NSCache<NSString, CoordinateBox>()

    var body: some View {
        Group {
            if let coordinate {
                VStack(alignment: .leading, spacing: 0) {
                    Map(initialPosition: .region(region(coordinate))) {
                        Marker(title, coordinate: coordinate)
                            .tint(Theme.accent)
                    }
                    .frame(height: 170)
                    .allowsHitTesting(false)

                    Button {
                        openInMaps(coordinate)
                    } label: {
                        Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            } else {
                EmptyView()
            }
        }
        .task(id: query) { await geocode() }
    }

    private var query: String {
        [address?.nilIfBlank, postcode?.nilIfBlank].compactMap { $0 }.joined(separator: ", ")
    }

    private func region(_ c: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))
    }

    private func geocode() async {
        guard !query.isEmpty, coordinate == nil else { return }
        let key = query as NSString
        if let cached = Self.cache.object(forKey: key) {
            coordinate = cached.coordinate
            return
        }
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.geocodeAddressString(query + ", UK"),
           let loc = placemarks.first?.location {
            coordinate = loc.coordinate
            Self.cache.setObject(CoordinateBox(loc.coordinate), forKey: key)
        }
    }

    private func openInMaps(_ c: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
