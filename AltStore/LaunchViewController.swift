//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas
import EmotionalDamage
import minimuxer

import AltStoreCore
import UniformTypeIdentifiers

import SwiftUI


let pairingFileName = "ALTPairingFile.mobiledevicepairing"

final class LaunchViewController: RSTLaunchViewController, UIDocumentPickerDelegate
{
    private var didFinishLaunching = false
    
    private var destinationViewController: UIViewController!
    
    override var launchConditions: [RSTLaunchCondition] {
        let isDatabaseStarted = RSTLaunchCondition(condition: { DatabaseManager.shared.isStarted }) { (completionHandler) in
            DatabaseManager.shared.start(completionHandler: completionHandler)
        }

        return [isDatabaseStarted]
    }
    
    override var childForStatusBarStyle: UIViewController? {
        return self.children.first
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return self.children.first
    }
    
    override func viewDidLoad()
    {
        defer {
            // Create destinationViewController now so view controllers can register for receiving Notifications.
            self.destinationViewController = self.storyboard!.instantiateViewController(withIdentifier: "tabBarController") as! TabBarController
        }
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        #if !targetEnvironment(simulator)
        start_em_proxy(bind_addr: Consts.Proxy.serverURL)
        
        guard let pf = fetchPairingFile() else {
            displayError("Device pairing file not found.")
            return
        }
        start_minimuxer_threads(pf)
        #endif
    }
    
    func fetchPairingFile() -> String? {
        return UIPasteboard.general.string
    }

    func displayError(_ msg: String) {
        print(msg)
        // Create a new alert
        let dialogMessage = UIAlertController(title: "Error launching SideStore", message: msg, preferredStyle: .alert)

        // Present alert to user
        self.present(dialogMessage, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        let isSecuredURL = url.startAccessingSecurityScopedResource() == true

        do {
            // Read to a string
            let data1 = try Data(contentsOf: urls[0])
            let pairing_string = String(bytes: data1, encoding: .utf8)
            if pairing_string == nil {
                displayError("Unable to read pairing file")
            }
            
            // Save to a file for next launch
            let pairingFile = FileManager.default.documentsDirectory.appendingPathComponent("\(pairingFileName)")
            try pairing_string?.write(to: pairingFile, atomically: true, encoding: String.Encoding.utf8)
            
            // Start minimuxer now that we have a file
            start_minimuxer_threads(pairing_string!)
        } catch {
            displayError("Unable to read pairing file")
        }
        
        if (isSecuredURL) {
            url.stopAccessingSecurityScopedResource()
        }
        controller.dismiss(animated: true, completion: nil)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        displayError("Choosing a pairing file was cancelled. Please re-open the app and try again.")
    }
    
    func start_minimuxer_threads(_ pairing_file: String) {
        target_minimuxer_address()
        let documentsDirectory = FileManager.default.documentsDirectory.absoluteString
        do {
            try start(pairing_file, documentsDirectory)
        } catch {
            try! FileManager.default.removeItem(at: FileManager.default.documentsDirectory.appendingPathComponent("\(pairingFileName)"))
            displayError("minimuxer failed to start, please restart SideStore. \((error as? LocalizedError)?.failureReason ?? "UNKNOWN ERROR!!!!!! REPORT TO GITHUB ISSUES!")")
        }
        if #available(iOS 17, *) {
            // TODO: iOS 17 and above have a new JIT implementation that is completely broken in SideStore :(
        }
        else {
            start_auto_mounter(documentsDirectory)
        }
    }
}

extension LaunchViewController
{
    override func handleLaunchError(_ error: Error)
    {
        do
        {
            throw error
        }
        catch let error as NSError
        {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch SideStore", comment: "")
            
            let errorDescription: String
            
            if #available(iOS 14.5, *)
            {
                let errorMessages = [error.debugDescription] + error.underlyingErrors.map { ($0 as NSError).debugDescription }
                errorDescription = errorMessages.joined(separator: "\n\n")
            }
            else
            {
                errorDescription = error.debugDescription
            }
            
            let alertController = UIAlertController(title: title, message: errorDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default, handler: { (action) in
                self.handleLaunchConditions()
            }))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    override func finishLaunching()
    {
        super.finishLaunching()
        
        guard !self.didFinishLaunching else { return }
        

        // Add view controller as child (rather than presenting modally)
        // so tint adjustment + card presentations works correctly.
        self.destinationViewController.view.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        self.destinationViewController.view.alpha = 0.0
        self.addChild(self.destinationViewController)
        self.view.addSubview(self.destinationViewController.view, pinningEdgesWith: .zero)
        self.destinationViewController.didMove(toParent: self)
        
        UIView.animate(withDuration: 0.2) {
            self.destinationViewController.view.alpha = 1.0
        }
        
        self.didFinishLaunching = true
    }
}
