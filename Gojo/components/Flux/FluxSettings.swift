//
//  FluxSettings.swift
//  Gojo
//
//  Settings tab for the Flux night shift feature.
//

import Defaults
import SwiftUI

struct FluxSettings: View {
    @ObservedObject var fluxManager = FluxManager.shared
    @ObservedObject var locationManager = FluxLocationManager.shared
    @Default(.fluxEnabled) var fluxEnabled
    @Default(.fluxLocation) var fluxLocation
    @Default(.fluxBedtimeMinutes) var bedtimeMinutes
    @Default(.fluxWindDownMinutes) var windDownMinutes
    @Default(.fluxDayKelvin) var dayKelvin
    @Default(.fluxSunsetKelvin) var sunsetKelvin
    @Default(.fluxBedtimeKelvin) var bedtimeKelvin

    @State private var locationQuery = ""

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .fluxEnabled) {
                    Text("Enable night shift")
                }
                if fluxEnabled {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(statusDescription)
                            .foregroundStyle(.secondary)
                    }
                    if fluxManager.isPaused {
                        Button("Resume now") {
                            fluxManager.resume()
                        }
                    } else {
                        Button("Disable for one hour") {
                            fluxManager.pause()
                        }
                    }
                }
                Defaults.Toggle(key: .fluxShowInNotch) {
                    Text("Show toggle in notch")
                }
            } header: {
                Text("General")
            }

            Section {
                HStack {
                    Text("Location")
                    Spacer()
                    Text(fluxLocation?.name ?? "Not set — assuming 7 AM sunrise / 7 PM sunset")
                        .foregroundStyle(.secondary)
                }
                if let solarDescription {
                    HStack {
                        Text("Today")
                        Spacer()
                        Text(solarDescription)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("City or ZIP code", text: $locationQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitLocationQuery)
                    Button("Set") {
                        submitLocationQuery()
                    }
                    .disabled(locationQuery.trimmingCharacters(in: .whitespaces).isEmpty || locationManager.isResolving)
                }
                HStack {
                    Button("Use Current Location") {
                        locationManager.requestCurrentLocation()
                    }
                    .disabled(locationManager.isResolving)
                    if locationManager.isResolving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    if fluxLocation != nil {
                        Button("Clear") {
                            locationManager.clearLocation()
                        }
                    }
                }
                if let error = locationManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Your location is only used to calculate sunrise and sunset times and never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Location")
            }

            Section {
                DatePicker("Bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                Picker("Wind-down duration", selection: $windDownMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                }
                Text("The screen gradually warms from the evening temperature to the bedtime temperature as bedtime approaches, then holds it until sunrise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Schedule")
            }

            Section {
                kelvinSlider("Daytime", value: $dayKelvin, in: 5000...6500)
                kelvinSlider("After sunset", value: $sunsetKelvin, in: 2700...5000)
                kelvinSlider("Bedtime", value: $bedtimeKelvin, in: 1900...3400)
            } header: {
                Text("Color Temperature")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Night Shift")
    }

    private var statusDescription: String {
        if let pausedUntil = fluxManager.pausedUntil, fluxManager.isPaused {
            return "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
        }
        return "\(fluxManager.currentPhase.rawValue) · \(Int(fluxManager.currentKelvin.rounded()))K"
    }

    private var solarDescription: String? {
        guard let events = FluxManager.solarEventsToday() else { return nil }
        switch events {
        case .regular(let sunriseMinutes, let sunsetMinutes):
            return "Sunrise \(formatMinutes(sunriseMinutes)) · Sunset \(formatMinutes(sunsetMinutes))"
        case .polarDay:
            return "Sun is up all day (polar day)"
        case .polarNight:
            return "Sun is down all day (polar night)"
        }
    }

    private var bedtimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: bedtimeMinutes / 60,
                minute: bedtimeMinutes % 60,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            bedtimeMinutes = (components.hour ?? 23) * 60 + (components.minute ?? 0)
        }
    }

    private func submitLocationQuery() {
        let query = locationQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        locationManager.setLocation(query: query)
        locationQuery = ""
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let date = Calendar.current.date(
            bySettingHour: (total / 60) % 24, minute: total % 60, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func kelvinSlider(
        _ label: String, value: Binding<Double>, in range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue))K")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 50)
        }
    }
}

#Preview {
    FluxSettings()
}
