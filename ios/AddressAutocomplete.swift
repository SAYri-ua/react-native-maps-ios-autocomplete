import Foundation
import MapKit
import CoreLocation
import React

@objc(AddressAutocomplete)
class AddressAutocomplete: NSObject, MKLocalSearchCompleterDelegate {

  private let completer = MKLocalSearchCompleter()
  private var suggestionsResolve: RCTPromiseResolveBlock?
  private var suggestionsReject: RCTPromiseRejectBlock?

  override init() {
    super.init()
    completer.delegate = self
  }

  // MARK: - JS API (селектори мають збігатись із .m)

  // AddressAutocomplete.m:
  // RCT_EXTERN_METHOD(getAddressSuggestions:(NSString *)address
  //                  withResolver:(RCTPromiseResolveBlock)resolve
  //                  withRejecter:(RCTPromiseRejectBlock)reject))
  @objc(getAddressSuggestions:withResolver:withRejecter:)
  func getAddressSuggestions(_ address: NSString,
                             withResolver resolve: @escaping RCTPromiseResolveBlock,
                             withRejecter reject: @escaping RCTPromiseRejectBlock) {
    suggestionsResolve = resolve
    suggestionsReject = reject
    
    // Запускаємо на головному потоці, щоб MKLocalSearchCompleter правильно отримував оновлення
    DispatchQueue.main.async {
      self.completer.queryFragment = address as String
    }
  }

  // AddressAutocomplete.m:
  // RCT_EXTERN_METHOD(getAddressDetails:(NSString *)address
  //                  withResolver:(RCTPromiseResolveBlock)resolve
  //                  withRejecter:(RCTPromiseRejectBlock)reject))
  @objc(getAddressDetails:withResolver:withRejecter:)
  func getAddressDetails(_ address: NSString,
                         withResolver resolve: @escaping RCTPromiseResolveBlock,
                         withRejecter reject: @escaping RCTPromiseRejectBlock) {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = address as String

    let search = MKLocalSearch(request: request)
    search.start { response, error in
      if let error = error {
        reject("address_details", error.localizedDescription, error)
        return
      }

      guard let item = response?.mapItems.first,
            let loc = item.placemark.location else {
        // Можеш повертати null або кидати помилку — на твій розсуд
        resolve(NSNull())
        return
      }

      let result: [String: Any] = [
        "latitude": loc.coordinate.latitude,
        "longitude": loc.coordinate.longitude,
        "name": item.name ?? "",
        "title": item.placemark.title ?? ""
      ]
      resolve(result)
    }
  }

  // AddressAutocomplete.m:
  // RCT_EXTERN_METHOD(reverseGeocodeLocation:(NSNumber *)longitude
  //                  withLatitude:(NSNumber *)latitude
  //                  withResolver:(RCTPromiseResolveBlock)resolve
  //                  withRejecter:(RCTPromiseRejectBlock)reject))
  @objc(reverseGeocodeLocation:withLatitude:withResolver:withRejecter:)
  func reverseGeocodeLocation(_ longitude: NSNumber,
                              withLatitude latitude: NSNumber,
                              withResolver resolve: @escaping RCTPromiseResolveBlock,
                              withRejecter reject: @escaping RCTPromiseRejectBlock) {

    let location = CLLocation(latitude: latitude.doubleValue,
                              longitude: longitude.doubleValue)

    CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
      if let error = error {
        reject("reverse_geocode", error.localizedDescription, error)
        return
      }

      guard let p = placemarks?.first else {
        resolve(NSNull())
        return
      }

      var result: [String: Any] = [
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
      ]
      if let name = p.name { result["name"] = name }
      if let city = p.locality { result["city"] = city }
      if let street = p.thoroughfare { result["street"] = street }
      if let house = p.subThoroughfare { result["streetNumber"] = house }
      if let postal = p.postalCode { result["postalCode"] = postal }
      if let iso = p.isoCountryCode { result["isoCountryCode"] = iso }

      resolve(result)
    }
  }

  // MARK: - MKLocalSearchCompleterDelegate

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    let items = completer.results.map { res in
      ["title": res.title, "subtitle": res.subtitle]
    }
    suggestionsResolve?(items)
    suggestionsResolve = nil
    suggestionsReject = nil
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    suggestionsReject?("address_autocomplete", error.localizedDescription, error)
    suggestionsResolve = nil
    suggestionsReject = nil
  }

  // MARK: - RN requirement (класовий метод!)
  @objc static func requiresMainQueueSetup() -> Bool {
    // Використовуємо MapKit/CoreLocation — безпечніше ініціалізувати на main queue
    return true
  }
}