//
//  ViewController.swift
//  MapPlay
//
//  Created by Jay Bailey on 30/08/2016.
//  Copyright © 2016 Dragonflied. All rights reserved.
//

import UIKit
import MapKit

let apiServerKey: String = ""

extension CLLocation {
    class func distance(from: CLLocationCoordinate2D, to:CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let to = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return from.distanceFromLocation(to)
    }
}

//
//  GooglePlace Class
//
//  Created by Jay Bailey on 30/08/2016.
//  Copyright © 2016 Dragonflied. All rights reserved.
//

class GooglePlace: NSObject, MKAnnotation {
    
    let title: String?
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let placeType: String?
    let photoReference: String?
    var photo: UIImage?
    var routed: Bool = false
    
    init(dictionary:NSDictionary)
    {
        self.title = dictionary["name"] as? String
        
        self.address = dictionary["address"] as? String
        
        let location = dictionary["geometry"]?["location"] as! NSDictionary
        let lat = location["lat"] as! CLLocationDegrees
        let lng = location["lng"] as! CLLocationDegrees
        self.coordinate = CLLocationCoordinate2DMake(lat, lng)
        
        if let photos = dictionary["photos"] as? NSArray {
            self.photoReference = photos.firstObject?["photo_reference"] as? String
        } else {
            self.photoReference = nil
        }
        
        if let types = (dictionary["types"] as? [String])?.first {
            // Quick type clean up removing _ and capitalisation
            var array = types.componentsSeparatedByString("_")
            for i in 0...array.count - 1 {
                let word = array[i]
                array[i] = word.substringFromIndex(word.startIndex).capitalizedString
            }
            
            self.placeType = array.joinWithSeparator(" ")
        } else {
            self.placeType = nil
        }
        
        self.photo = nil
    }
    
    var subtitle: String? {
        return placeType
    }
}

//
//  ViewController
//
//  Created by Jay Bailey on 30/08/2016.
//  Copyright © 2016 Dragonflied. All rights reserved.
//

class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate, UIGestureRecognizerDelegate {
    
    @IBOutlet weak var mapView: MKMapView!
    
    var locationManager: CLLocationManager!
    let searchRadius: Double = 1000
    
    var placesTask: NSURLSessionDataTask?
    var session: NSURLSession {
        return NSURLSession.sharedSession()
    }
    var placesArray = [GooglePlace]()
    var photoCache = [String:UIImage]()
    
    let mapPlace = UIImage(named: "mapPlace")!
    
    var currentAnnotation = MKPointAnnotation()
    var overlayPoints = [CLLocationCoordinate2D]()
    var polyline: MKPolyline? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(_:)))
        gestureRecognizer.delegate = self
        mapView.addGestureRecognizer(gestureRecognizer)
        
        setupLocationManager()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - Location Manager
    
    func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        if (locationManager.respondsToSelector(#selector(CLLocationManager.requestWhenInUseAuthorization))) {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationManager.stopUpdatingLocation()
        
        if let location = locations.last {
            let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let region = MKCoordinateRegionMakeWithDistance(center, searchRadius * 2.0, searchRadius * 2.0)
            
            mapView.setRegion(region, animated: true)
            
            fetchNearbyPlaces(center)
        }
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        NSLog("Unresolved error - locationManager, \(error.localizedDescription)")
    }
    
    // MARK: - Google Places Web API Search
    
    func fetchNearbyPlaces(coordinate: CLLocationCoordinate2D){
        var urlString = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?key=\(apiServerKey)&location=\(coordinate.latitude),\(coordinate.longitude)&radius=\(searchRadius)&rankby=prominence&sensor=true"
        urlString = urlString.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())!
        
        if let task = placesTask where task.taskIdentifier > 0 && task.state == .Running {
            task.cancel()
        }
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        placesTask = session.dataTaskWithURL(NSURL(string: urlString)!) {data, response, error in
            if error == nil {
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                self.placesArray.removeAll(keepCapacity: true)
                var dictionary: NSDictionary?
                do {
                    dictionary = try NSJSONSerialization.JSONObjectWithData(data!, options: []) as? NSDictionary
                } catch {
                    NSLog("Unresolved error - fetchNearbyPlaces, \(error)")
                }
                
                if let json = dictionary {
                    if let results = json["results"] as? NSArray {
                        let itemLimit = min(results.count, 20)
                        for i in 0...itemLimit - 1 {
                            if let rawPlace = results[i] as? NSDictionary {
                                let place = GooglePlace(dictionary: rawPlace as NSDictionary)
                                self.placesArray.append(place)
                                
                                if let reference = place.photoReference {
                                    self.fetchPhotoFromReference(reference) { image in
                                        place.photo = image
                                    }
                                }
                            }
                        }
                    }
                }
                
                dispatch_async(dispatch_get_main_queue()) {
                    if self.polyline != nil {
                        self.mapView.removeOverlay(self.polyline!)
                    }
                    self.mapView.removeAnnotations(self.mapView.annotations)
                    self.mapView.addAnnotations(self.placesArray)
                }
            }
        }
        placesTask?.resume()
    }
    
    func fetchPhotoFromReference(reference: String, completion: ((UIImage?) -> Void)) -> ()
    {
        if let photo = photoCache[reference] as UIImage! {
            completion(photo)
        } else {
            let urlString = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=200&photoreference=\(reference)&key=\(apiServerKey)"
            
            UIApplication.sharedApplication().networkActivityIndicatorVisible = true
            session.downloadTaskWithURL(NSURL(string: urlString)!) {url, response, error in
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                if let photoUrl = url {
                    let downloadedPhoto = UIImage(data: NSData(contentsOfURL: photoUrl)!)
                    self.photoCache[reference] = downloadedPhoto
                    dispatch_async(dispatch_get_main_queue()) {
                        completion(downloadedPhoto)
                    }
                }
                }.resume()
        }
    }
    
    //MARK: - MKMapview Delegate
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        if (annotation is GooglePlace) {
            if let current = annotation as? GooglePlace {
                var annotationView = mapView.dequeueReusableAnnotationViewWithIdentifier("place")
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: "place")
                } else {
                    annotationView!.annotation = current
                }
                
                annotationView!.image = mapPlace
                
                annotationView!.enabled = true
                annotationView!.canShowCallout = true
                annotationView!.draggable = false
                
                return annotationView
            }
        }
        
        return nil
    }
    
    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let lineView = MKPolylineRenderer(overlay: overlay)
            lineView.strokeColor = UIColor.greenColor()
            
            return lineView
        } else {
            return MKOverlayRenderer()
        }
    }
    
    // MARK: - Tap Gesture
    
    func handleTap(gestureReconizer: UILongPressGestureRecognizer) {
        let location = gestureReconizer.locationInView(mapView)
        let coordinate = mapView.convertPoint(location,toCoordinateFromView: mapView)
        
        self.mapView.removeAnnotation(currentAnnotation)
        
        currentAnnotation.coordinate = coordinate
        mapView.addAnnotation(currentAnnotation)
        
        drawPath()
    }
    
    // MARK: - Draw Path
    
    func drawPath() {
        if polyline != nil {
            mapView.removeOverlay(polyline!)
        }
        
        // reset all places
        for item in placesArray {
            item.routed = false
        }
        
        overlayPoints.removeAll(keepCapacity: true)
        overlayPoints.append(currentAnnotation.coordinate);
        
        // find new route from new coordinates
        let maxRoutes = placesArray.count
        var i = 0
        
        var minDistanceID: Int = -1
        var distance: CLLocationDistance = -1
        var currentCoordinate = currentAnnotation.coordinate
        
        while i < maxRoutes {
            minDistanceID = -1
            distance = -1
            
            for j in 0...placesArray.count - 1 {
                let item = placesArray[j]
                
                if !item.routed {
                    let length = CLLocation.distance(currentCoordinate, to: item.coordinate)
                    
                    if distance == -1 || length < distance {
                        distance = length
                        minDistanceID = j
                    }
                }
            }
            
            if minDistanceID != -1 {
                let item = placesArray[minDistanceID]
                item.routed = true
                
                overlayPoints.append(item.coordinate)
                currentCoordinate = item.coordinate
            }
            
            i += 1
        }
        
        // Return to start
        overlayPoints.append(currentAnnotation.coordinate);
        
        // Draw route
        polyline = MKPolyline(coordinates: &overlayPoints, count: overlayPoints.count)
        self.mapView.addOverlay(polyline!)
    }
    
    // MARK: - Actions
    
    @IBAction func centerToUserLocationTapped(sender: AnyObject) {
        setupLocationManager()
    }
}

