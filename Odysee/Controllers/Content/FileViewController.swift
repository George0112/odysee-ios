//
//  FileViewController.swift
//  Odysee
//
//  Created by Akinwale Ariwodola on 06/11/2020.
//

import AVKit
import AVFoundation
import CoreData
import Firebase
import SafariServices
import UIKit

class FileViewController: UIViewController, UIGestureRecognizerDelegate, UITableViewDelegate, UITableViewDataSource {
    
    var claim: Claim?
    var claimUrl: LbryUri?
    var subscribeUnsubscribeInProgress = false
    var relatedContent: [Claim] = []
    var loadingRelated = false
    var fileViewLogged = false
    var loggingInProgress = false
    var playRequestTime: Int64 = 0
    var playerObserverAdded = false
    
    @IBOutlet weak var titleArea: UIView!
    @IBOutlet weak var publisherArea: UIView!
    @IBOutlet weak var titleAreaIconView: UIImageView!
    @IBOutlet weak var descriptionArea: UIView!
    @IBOutlet weak var descriptionDivider: UIView!
    
    @IBOutlet weak var mediaView: UIView!
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var viewCountLabel: UILabel!
    @IBOutlet weak var timeAgoLabel: UILabel!
    
    @IBOutlet weak var publisherActionsArea: UIView!
    @IBOutlet weak var publisherImageView: UIImageView!
    @IBOutlet weak var publisherTitleLabel: UILabel!
    @IBOutlet weak var publisherNameLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    
    @IBOutlet weak var followLabel: UILabel!
    @IBOutlet weak var followUnfollowIconView: UIImageView!
    @IBOutlet weak var bellView: UIView!
    @IBOutlet weak var bellIconView: UIImageView!
    
    @IBOutlet weak var loadingRelatedView: UIActivityIndicatorView!
    @IBOutlet weak var relatedContentListView: UITableView!
    @IBOutlet weak var relatedContentListHeightConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var resolvingView: UIView!
    @IBOutlet weak var resolvingImageView: UIImageView!
    @IBOutlet weak var resolvingLoadingIndicator: UIActivityIndicatorView!
    @IBOutlet weak var resolvingLabel: UILabel!
    @IBOutlet weak var resolvingCloseButton: UIButton!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.mainController.toggleHeaderVisibility(hidden: true)
        appDelegate.mainController.toggleMiniPlayer(hidden: true)
        
        if claim != nil {
            checkFollowing()
            checkNotificationsDisabled()
        }
    }
    
    func checkRepost() {
        if claim != nil && claim?.repostedClaim != nil {
            claim = claim?.repostedClaim
            if (claim!.name!.starts(with: "@")) {
                // reposted channel, simply dismiss the view and show a channel view controller instead
                self.navigationController?.popViewController(animated: false)
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                let vc = appDelegate.mainController.storyboard?.instantiateViewController(identifier: "channel_view_vc") as! ChannelViewController
                vc.channelClaim = claim
                appDelegate.mainNavigationController?.pushViewController(vc, animated: true)

                return
            }
            
            claim = claim?.repostedClaim
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: "File", AnalyticsParameterScreenClass: "FileViewController"])
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.mainController.updateMiniPlayer()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let currentVc = UIApplication.currentViewController()
        if (currentVc as? FileViewController) != nil {
            if appDelegate.player != nil {
                appDelegate.player?.pause()
            }
            return
        }
        if (appDelegate.player != nil) {
            appDelegate.mainController.toggleMiniPlayer(hidden: false)
            if playerObserverAdded {
                appDelegate.player!.removeObserver(self, forKeyPath: "timeControlStatus")
                playerObserverAdded = false
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkRepost()
        relatedContentListView.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
        
        // Do any additional setup after loading the view.
        if claim == nil && claimUrl != nil {
            resolveAndDisplayClaim()
        } else if claim != nil {
            displayClaim()
            loadAndDisplayViewCount()
            loadRelatedContent()
        } else {
            displayNothingAtLocation()
        }
    }
    
    func showClaimAndCheckFollowing() {
        displayClaim()
        loadAndDisplayViewCount()
        loadRelatedContent()
        
        checkFollowing()
        checkNotificationsDisabled()
    }
    
    func resolveAndDisplayClaim() {
        displayResolving()
        
        let url = claimUrl!.description
        if Lbry.claimCacheByUrl[url] != nil {
            self.claim = Lbry.claimCacheByUrl[url]
            DispatchQueue.main.async {
                self.showClaimAndCheckFollowing()
            }
            return
        }
        
        var params: Dictionary<String, Any> = Dictionary<String, Any>()
        params["urls"] = [url]
        
        Lbry.apiCall(method: Lbry.methodResolve, params: params, connectionString: Lbry.lbrytvConnectionString, completion: { data, error in
            guard let data = data, error == nil else {
                self.displayNothingAtLocation()
                return
            }
            
            let result = data["result"] as! NSDictionary
            for (_, claimData) in result {
                let data = try! JSONSerialization.data(withJSONObject: claimData, options: [.prettyPrinted, .sortedKeys])
                do {
                    let claim: Claim? = try JSONDecoder().decode(Claim.self, from: data)
                    if claim != nil && !(claim!.claimId ?? "").isBlank {
                        Lbry.addClaimToCache(claim: claim)
                        self.claim = claim
                        DispatchQueue.main.async {
                            self.showClaimAndCheckFollowing()
                        }
                    } else {
                        self.displayNothingAtLocation()
                    }
                } catch let error {
                    print(error)
                }
                
                break
            }
        })
    }
    
    func displayResolving() {
        DispatchQueue.main.async {
            self.resolvingView.isHidden = false
            self.resolvingLoadingIndicator.isHidden = false
            self.resolvingImageView.image = UIImage.init(named: "spaceman_happy")
            self.resolvingLabel.text = String.localized("Resolving content...")
            self.resolvingCloseButton.isHidden = true
        }
    }
    
    func displayNothingAtLocation() {
        DispatchQueue.main.async {
            self.resolvingView.isHidden = false
            self.resolvingLoadingIndicator.isHidden = true
            self.resolvingImageView.image = UIImage.init(named: "spaceman_sad")
            self.resolvingLabel.text = String.localized("There's nothing at this location.")
            self.resolvingCloseButton.isHidden = false
        }
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    func displayClaim() {
        resolvingView.isHidden = true
        descriptionArea.isHidden = true
        descriptionDivider.isHidden = true
        displayRelatedPlaceholders()
        
        titleLabel.text = claim?.value?.title
        
        let releaseTime: Double = Double(claim?.value?.releaseTime ?? "0")!
        let date: Date = NSDate(timeIntervalSince1970: releaseTime) as Date // TODO: Timezone check / conversion?
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        timeAgoLabel.text = formatter.localizedString(for: date, relativeTo: Date())
        
        // publisher
        var thumbnailUrl: URL? = nil
        publisherImageView.rounded()
        if (claim?.signingChannel != nil) {
            publisherTitleLabel.text = claim?.signingChannel?.value?.title
            publisherNameLabel.text = claim?.signingChannel?.name
            if (claim?.signingChannel?.value != nil && claim?.signingChannel?.value?.thumbnail != nil) {
                thumbnailUrl = URL(string: (claim!.signingChannel!.value!.thumbnail!.url!))!
            }
        } else {
            publisherTitleLabel.text = String.localized("Anonymous")
            publisherActionsArea.isHidden = true
        }
        
        if thumbnailUrl != nil {
            publisherImageView.load(url: thumbnailUrl!)
        } else {
            publisherImageView.image = UIImage.init(named: "spaceman")
            publisherImageView.backgroundColor = Helper.lightPrimaryColor
        }
        
        if (claim?.value?.description ?? "").isBlank {
            descriptionArea.isHidden = true
            descriptionDivider.isHidden = true
        } else {
            // details
            descriptionLabel.text = claim?.value?.description
        }
            
        // display video content
        let avpc: AVPlayerViewController = AVPlayerViewController()
        self.addChild(avpc)
        avpc.view.frame = self.mediaView.bounds
        self.mediaView.addSubview(avpc.view)
        avpc.didMove(toParent: self)
        
        do {
            // enable audio in silent mode
            try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch {
            // pass
        }
        
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if (appDelegate.player != nil && appDelegate.currentClaim != nil && appDelegate.currentClaim?.claimId == claim?.claimId) {
            avpc.player = appDelegate.player
            return
        }
        
        appDelegate.currentClaim = claim
        if (appDelegate.player != nil) {
            appDelegate.player?.pause()
        }
        let videoUrl = URL(string: getStreamingUrl(claim: claim!))
        appDelegate.player = AVPlayer(url: videoUrl!)
        avpc.player = appDelegate.player
        avpc.player!.addObserver(self, forKeyPath: "timeControlStatus", options: [.old, .new], context: nil)
        playerObserverAdded = true
        playRequestTime = Int64(Date().timeIntervalSince1970 * 1000.0)
        avpc.player?.play()
    }
    
    func displayRelatedPlaceholders() {
        relatedContent = []
        for _ in 1...15 {
            let placeholder = Claim()
            placeholder.claimId = "placeholder"
            relatedContent.append(placeholder)
        }
        relatedContentListView.reloadData()
    }
    
    func checkTimeToStart() {
        if (fileViewLogged || loggingInProgress) {
            return
        }
        
        let timeToStartMs = Int64(Date().timeIntervalSince1970 * 1000.0) - playRequestTime
        let timeToStartSeconds = Int64(Double(timeToStartMs) / 1000.0)
        let url = claim!.permanentUrl!
        
        Analytics.logEvent("play", parameters: [
            "url": url,
            "time_to_start_ms": timeToStartMs,
            "time_to_start_seconds": timeToStartSeconds
        ])
     
        logFileView(url: url, timeToStart: timeToStartMs)
    }
    
    func logFileView(url: String, timeToStart: Int64) {
        if (loggingInProgress) {
            return
        }
        
        loggingInProgress = true
        
        var options = Dictionary<String, String>()
        options["uri"] = url
        options["claim_id"] = claim?.claimId!
        options["outpoint"] = String(format: "%@:%d", claim!.txid!, claim!.nout!)
        if (timeToStart > 0) {
            options["time_to_start"] = String(timeToStart)
        }
        
        do {
            try Lbryio.call(resource: "file", action: "view", options: options, method: Lbryio.methodPost, completion: { data, error in
                // no need to check for errors here
                self.loggingInProgress = false
                self.fileViewLogged = true
            })
        } catch {
            // pass
        }
    }
    
    func getStreamingUrl(claim: Claim) -> String {
        let claimName: String = claim.name!
        let claimId: String = claim.claimId!
        return String(format: "https://cdn.lbryplayer.xyz/content/claims/%@/%@/stream", claimName, claimId);
    }
    
    func loadAndDisplayViewCount() {
        var options = Dictionary<String, String>()
        options["claim_id"] = claim?.claimId
        try! Lbryio.call(resource: "file", action: "view_count", options: options, method: Lbryio.methodGet, completion: { data, error in
            if (error != nil) {
                // could load the view count for display
                DispatchQueue.main.async {
                    self.viewCountLabel.isHidden = true
                }
                return
            }
            DispatchQueue.main.async {
                let formatter = NumberFormatter()
                formatter.usesGroupingSeparator = true
                formatter.locale = Locale.current
                formatter.numberStyle = .decimal
                
                let viewCount = (data as! NSArray)[0] as! Int
                self.viewCountLabel.isHidden = false
                self.viewCountLabel.text = String(format: viewCount == 1 ? String.localized("%@ view") : String.localized("%@ views"), formatter.string(for: viewCount)!)
            }
        })
    }
    
    func loadRelatedContent() {
        if (loadingRelated) {
            return
        }
        
        loadingRelated = true
        loadingRelatedView.isHidden = false
        let query = claim?.value?.title!
        Lighthouse.search(rawQuery: query!, size: 16, from: 0, relatedTo: claim!.claimId!, completion: { results, error in
            if (results == nil || results!.count == 0) {
                //self.checkNoResults()
                self.loadingRelatedView.isHidden = true
                return
            }
            
            var resolveUrls: [String] = []
            for item in results! {
                let lbryUri = LbryUri.tryParse(url: String(format: "%@#%@", item["name"] as! String, item["claimId"] as! String), requireProto: false)
                if (lbryUri != nil) {
                    resolveUrls.append(lbryUri!.description)
                }
            }
            
            self.resolveAndDisplayRelatedContent(urls: resolveUrls)
        })
    }
    
    func resolveAndDisplayRelatedContent(urls: [String]) {
        var params: Dictionary<String, Any> = Dictionary<String, Any>()
        params["urls"] = urls
        
        Lbry.apiCall(method: Lbry.methodResolve, params: params, connectionString: Lbry.lbrytvConnectionString, completion: { data, error in
            guard let data = data, error == nil else {
                // display no results
                self.loadingRelatedView.isHidden = true
                //self.checkNoResults()
                return
            }
            
            var claimResults: [Claim] = []
            let result = data["result"] as! NSDictionary
            self.relatedContent = []
            for (_, claimData) in result {
                let data = try! JSONSerialization.data(withJSONObject: claimData, options: [.prettyPrinted, .sortedKeys])
                do {
                    let claim: Claim? = try JSONDecoder().decode(Claim.self, from: data)
                    if (claim != nil && !(claim?.claimId ?? "").isBlank && self.claim!.claimId != claim!.claimId &&
                            !self.relatedContent.contains(where: { $0.claimId == claim?.claimId })) {
                        Lbry.addClaimToCache(claim: claim)
                        claimResults.append(claim!)
                    }
                } catch {
                    // pass
                }
            }
            self.relatedContent.append(contentsOf: claimResults)
            self.loadingRelated = false
            
            DispatchQueue.main.async {
                self.loadingRelatedView.isHidden = true
                self.relatedContentListView.reloadData()
            }
        })
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if object as AnyObject? === appDelegate.player {
            if keyPath == "timeControlStatus" && appDelegate.player!.timeControlStatus == .playing {
                checkTimeToStart()
                return
            }
        }
        if keyPath == "contentSize" {
            if (change?[.newKey]) != nil {
                let contentHeight: CGFloat = relatedContentListView.contentSize.height
                relatedContentListHeightConstraint.constant = contentHeight
            }
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return relatedContent.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "claim_cell", for: indexPath) as! ClaimTableViewCell
        
        let claim: Claim = relatedContent[indexPath.row]
        cell.setClaim(claim: claim)
            
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let claim: Claim = relatedContent[indexPath.row]
        if claim.claimId == "placeholder" {
            return
        }
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let vc = storyboard?.instantiateViewController(identifier: "file_view_vc") as! FileViewController
        vc.claim = claim
        appDelegate.mainNavigationController?.view.layer.add(Helper.buildFileViewTransition(), forKey: kCATransition)
        appDelegate.mainNavigationController?.pushViewController(vc, animated: false)
    }
    
    @IBAction func closeTapped(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func publisherTapped(_ sender: Any) {
        if claim!.signingChannel != nil {
            let channelClaim = claim!.signingChannel!
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            let vc = appDelegate.mainController.storyboard?.instantiateViewController(identifier: "channel_view_vc") as! ChannelViewController
            vc.channelClaim = channelClaim
            appDelegate.mainNavigationController?.pushViewController(vc, animated: true)
        }
    }
    
    func showUAView() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let vc = storyboard?.instantiateViewController(identifier: "ua_vc") as! UserAccountViewController
        appDelegate.mainNavigationController?.pushViewController(vc, animated: true)
    }
    
    @IBAction func followUnfollowTapped(_ sender: Any) {
        if (!Lbryio.isSignedIn()) {
            showUAView()
            return
        }
        
        if claim?.signingChannel == nil {
            return
        }
        let channelClaim = claim!.signingChannel!
        subscribeOrUnsubscribe(claim: channelClaim, notificationsDisabled: Lbryio.isNotificationsDisabledForSub(claim: channelClaim), unsubscribing: Lbryio.isFollowing(claim: channelClaim))
    }
    
    @IBAction func bellTapped(_ sender: Any) {
        if (!Lbryio.isSignedIn()) {
            // shouldn't be able to access this action if the user is not signed in, but just in case
            showUAView()
            return
        }
        
        if claim?.signingChannel == nil {
            return
        }
        let channelClaim = claim!.signingChannel!
        subscribeOrUnsubscribe(claim: channelClaim, notificationsDisabled: !Lbryio.isNotificationsDisabledForSub(claim: channelClaim), unsubscribing: false)
    }
    
    func checkFollowing() {
        if claim?.signingChannel == nil {
            return
        }
        
        let channelClaim = claim!.signingChannel!
        DispatchQueue.main.async {
            if (Lbryio.isFollowing(claim: channelClaim)) {
                // show unfollow and bell icons
                self.followLabel.isHidden = true
                self.bellView.isHidden = false
                self.followUnfollowIconView.image = UIImage.init(systemName: "heart.slash.fill")
                self.followUnfollowIconView.tintColor = UIColor.label
            } else {
                self.followLabel.isHidden = false
                self.bellView.isHidden = true
                self.followUnfollowIconView.image = UIImage.init(systemName: "heart")
                self.followUnfollowIconView.tintColor = UIColor.systemRed
            }
        }
    }
    
    func checkNotificationsDisabled() {
        if claim?.signingChannel == nil {
            return
        }
        
        let channelClaim = claim!.signingChannel!
        if (!Lbryio.isFollowing(claim: channelClaim)) {
            return
        }
        
        DispatchQueue.main.async {
            if (Lbryio.isNotificationsDisabledForSub(claim: channelClaim)) {
                self.bellIconView.image = UIImage.init(systemName: "bell.fill")
            } else {
                self.bellIconView.image = UIImage.init(systemName: "bell.slash.fill")
            }
        }
    }
    
    // TODO: Refactor into a more reusable call to prevent code duplication
    func subscribeOrUnsubscribe(claim: Claim?, notificationsDisabled: Bool, unsubscribing: Bool) {
        if (subscribeUnsubscribeInProgress) {
            return
        }
        
        subscribeUnsubscribeInProgress = true
        do {
            var options = Dictionary<String, String>()
            options["claim_id"] = claim?.claimId!
            if (!unsubscribing) {
                options["channel_name"] = claim?.name
                options["notifications_disabled"] = String(notificationsDisabled)
            }
            
            let subUrl: LbryUri = try LbryUri.parse(url: (claim?.permanentUrl!)!, requireProto: false)
            try Lbryio.call(resource: "subscription", action: unsubscribing ? "delete" : "new", options: options, method: Lbryio.methodGet, completion: { data, error in
                self.subscribeUnsubscribeInProgress = false
                guard let _ = data, error == nil else {
                    self.showError(error: error)
                    self.checkFollowing()
                    self.checkNotificationsDisabled()
                    return
                }

                if (!unsubscribing) {
                    Lbryio.addSubscription(sub: LbrySubscription.fromClaim(claim: claim!, notificationsDisabled: notificationsDisabled), url: subUrl.description)
                    self.addSubscription(url: subUrl.description, channelName: subUrl.channelName!, isNotificationsDisabled: notificationsDisabled, reloadAfter: true)
                } else {
                    Lbryio.removeSubscription(subUrl: subUrl.description)
                    self.removeSubscription(url: subUrl.description, channelName: subUrl.channelName!)
                }
                
                self.checkFollowing()
                self.checkNotificationsDisabled()
            })
        } catch let error {
            showError(error: error)
        }
    }
    
    func addSubscription(url: String, channelName: String, isNotificationsDisabled: Bool, reloadAfter: Bool) {
        // persist the subscription to CoreData
        DispatchQueue.main.async {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            let context: NSManagedObjectContext! = appDelegate.persistentContainer.viewContext
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let subToSave = Subscription(context: context)
            subToSave.url = url
            subToSave.channelName = channelName
            subToSave.isNotificationsDisabled = isNotificationsDisabled
            
            appDelegate.saveContext()
        }
    }
    
    func removeSubscription(url: String, channelName: String) {
        // remove the subscription from CoreData
        DispatchQueue.main.async {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            let context: NSManagedObjectContext! = appDelegate.persistentContainer.viewContext
            let subToDelete = Subscription(context: context)
            subToDelete.url = url
            subToDelete.channelName = channelName
            
            context.delete(subToDelete)
        }
    }
    
    func showError(error: Error?) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.mainController.showError(error: error)
    }
    
    func showMessage(message: String?) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.mainController.showMessage(message: message)
    }
    
    @IBAction func dismissFileViewTapped(_ sender: Any) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let transition = CATransition()
        transition.duration = 0.2
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        transition.type = .push
        transition.subtype = .fromBottom
        appDelegate.mainNavigationController?.view.layer.add(transition, forKey: kCATransition)
        self.navigationController?.popViewController(animated: false)
    }
    
    @IBAction func shareActionTapped(_ sender: Any) {
        let url = LbryUri.tryParse(url: claim!.shortUrl!, requireProto: false)
        if (url != nil) {
            let items = [url!.odyseeString]
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            present(vc, animated: true)
        }
    }
    
    @IBAction func supportActionTapped(_ sender: Any) {
        if !Lbryio.isSignedIn() {
            showUAView()
            return
        }
        
        let vc = storyboard?.instantiateViewController(identifier: "support_vc") as! SupportViewController
        vc.claim = claim!
        vc.modalPresentationStyle = .overCurrentContext
        present(vc, animated: true)
    }
    
    @IBAction func downloadActionTapped(_ sender: Any) {
        showMessage(message: String.localized("This feature is not yet available."))
    }
    
    @IBAction func reportActionTapped(_ sender: Any) {
        if let url = URL(string: String(format: "https://lbry.com/dmca/%@", claim!.claimId!)) {
            let vc = SFSafariViewController(url: url)
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.mainController.present(vc, animated: true, completion: nil)
        }
    }
    
    @IBAction func titleAreaTapped(_ sender: Any) {
        if descriptionArea.isHidden {
            descriptionArea.isHidden = false
            descriptionDivider.isHidden = false
            titleAreaIconView.image = UIImage.init(systemName: "chevron.up")
        } else {
            descriptionArea.isHidden = true
            descriptionDivider.isHidden = true
            titleAreaIconView.image = UIImage.init(systemName: "chevron.down")
        }
    }
}
