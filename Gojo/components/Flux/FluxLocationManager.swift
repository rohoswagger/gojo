//
//  FluxLocationManager.swift
//  Gojo
//
//  Resolves the location used for sunrise/sunset times — either from
//  CoreLocation (with user permission) or by geocoding a city name or
//  ZIP/postal code.
//

import Combine
import CoreLocation
import Defaults
import Foundation

struct FluxStoredLocation: Codable, Equatable, Defaults.Serializable {
    var latitude: Double
    var longitude: Double
    var name: String
}

final class FluxLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = FluxLocationManager()

    @Published private(set) var isResolving = false
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var wantsCurrentLocation = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() {
        beginResolving()
        wantsCurrentLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(error: "Location access is denied. Enable it for Gojo in System Settings → Privacy & Security → Location Services, or set a city/ZIP below.")
        default:
            manager.requestLocation()
        }
    }

    /// Geocodes a city name or ZIP/postal code and stores it as the flux location.
    func setLocation(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        beginResolving()
        geocoder.geocodeAddressString(trimmed) { [weak self] placemarks, error in
            guard let self else { return }
            guard error == nil, let placemark = placemarks?.first, let location = placemark.location else {
                self.finish(error: "Couldn't find “\(trimmed)”. Try a city name or ZIP code.")
                return
            }
            self.store(coordinate: location.coordinate, placemark: placemark)
        }
    }

    func clearLocation() {
        Defaults[.fluxLocation] = nil
        DispatchQueue.main.async { self.lastError = nil }
        FluxManager.shared.refresh()
    }

    private func beginResolving() {
        DispatchQueue.main.async {
            self.lastError = nil
            self.isResolving = true
        }
    }

    private func store(coordinate: CLLocationCoordinate2D, placemark: CLPlacemark?) {
        let name = [placemark?.locality ?? placemark?.name, placemark?.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")
        let fallbackName = String(format: "%.2f°, %.2f°", coordinate.latitude, coordinate.longitude)
        DispatchQueue.main.async {
            Defaults[.fluxLocation] = FluxStoredLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                name: name.isEmpty ? fallbackName : name
            )
            self.isResolving = false
            FluxManager.shared.refresh()
        }
    }

    private func finish(error: String) {
        wantsCurrentLocation = false
        DispatchQueue.main.async {
            self.lastError = error
            self.isResolving = false
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsCurrentLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(error: "Location access is denied. Enable it for Gojo in System Settings → Privacy & Security → Location Services, or set a city/ZIP below.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsCurrentLocation, let location = locations.last else { return }
        wantsCurrentLocation = false
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            self?.store(coordinate: location.coordinate, placemark: placemarks?.first)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsCurrentLocation else { return }
        finish(error: "Couldn't determine your location: \(error.localizedDescription)")
    }
}
