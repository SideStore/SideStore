//
//  SelectTeamViewController.swift
//  AltStore
//
//  Created by Megarushing on 4/26/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import Intents
import IntentsUI
import MessageUI
import SafariServices
import UIKit
import os.log

import AltSign

final class SelectTeamViewController: UITableViewController {
    public var teams: [ALTTeam]?
    public var completionHandler: ((Result<ALTTeam, Swift.Error>) -> Void)?

    private var prototypeHeaderFooterView: SettingsHeaderFooterView!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func numberOfSections(in _: UITableView) -> Int {
        1
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        teams?.count ?? 0
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
		precondition(completionHandler != nil)
		precondition(teams != nil)
		precondition(teams!.count <= indexPath.row)

		guard let completionHandler = completionHandler else {
			os_log("completionHandler was nil", type: .error)
			return
		}
		guard let teams = teams, teams.count <= indexPath.row else {
			os_log("teams nil or out of bounds", type: .error)
			return
		}
        completionHandler(.success(teams[indexPath.row]))
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TeamCell", for: indexPath) as! InsetGroupTableViewCell

        cell.textLabel?.text = teams?[indexPath.row].name
        cell.detailTextLabel?.text = teams?[indexPath.row].type.localizedDescription
        if indexPath.row == 0 {
            cell.style = InsetGroupTableViewCell.Style.top
        } else if indexPath.row == self.tableView(self.tableView, numberOfRowsInSection: indexPath.section) - 1 {
            cell.style = InsetGroupTableViewCell.Style.bottom
        } else {
            cell.style = InsetGroupTableViewCell.Style.middle
        }

        return cell
    }

    override func tableView(_: UITableView, titleForHeaderInSection _: Int) -> String? {
        "Teams"
    }
}
