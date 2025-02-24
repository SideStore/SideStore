//
//  StoreCollectionViewController.swift
//  SideStore
//
//  Created by mantou on 2025/2/17.
//  Copyright © 2025 SideStore. All rights reserved.
//

import UIKit

class StoreCollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    
    struct AppData: Decodable {
        let id: String
        let name: String
        let date: String
        let size: Int
        let version: String
        let build: String
        let icon: String
        let pkg: String
        let plist: String
    }

    private var apps: [AppData] = []
    private var deviceUUID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "未知设备"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "应用商店"
        collectionView.backgroundColor = .systemBackground
        collectionView.register(AppCell.self, forCellWithReuseIdentifier: "AppCell")
        fetchAppData()
    }

    private func fetchAppData() {
        guard let url = URL(string: "https://typecho.cloudmantoub.online/api/list") else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("数据请求失败：\(error?.localizedDescription ?? "未知错误")")
                return
            }
            do {
                self.apps = try JSONDecoder().decode([AppData].self, from: data)
                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                }
            } catch {
                print("JSON 解析失败：\(error.localizedDescription)")
            }
        }.resume()
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return apps.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AppCell", for: indexPath) as? AppCell else {
            return UICollectionViewCell()
        }
        let app = apps[indexPath.item]
        cell.configure(with: app)
        cell.onInstallTapped = { [weak self] in
            self?.handleInstall(for: app)
        }
        return cell
    }

    // 设置每个卡片的大小（宽度和高度）
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - 30 // 减去左右的间距
        let height: CGFloat = 90 // 固定每个卡片的高度为 50
        return CGSize(width: width, height: height)
    }

    private func handleInstall(for app: AppData) {
        // 你的处理逻辑
        if let firstApp = apps.first, firstApp.id == app.id {
                self.startInstallation(for: app)
                return
            }
        guard let cleanUUID = globalDeviceUUID?
                   .replacingOccurrences(of: "Optional(\"", with: "")
                   .replacingOccurrences(of: "\")", with: ""),
                   !cleanUUID.isEmpty else {
                   print("设备 UUID 无效")
                   return
               }

               let paymentCheckURL = "https://store.cloudmantoua.top/check-payment/\(cleanUUID)"
               guard let url = URL(string: paymentCheckURL) else { return }
               print("paymentCheckURL消息：\(paymentCheckURL)")
               URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                   guard let data = data, error == nil else {
                       print("查询支付状态失败：\(error?.localizedDescription ?? "未知错误")")
                       return
                   }
                   do {
                       let response = try JSONDecoder().decode(PaymentResponse.self, from: data)
                       DispatchQueue.main.async {
                           if response.isPaid {
                               print("用户已支付，开始安装")
                               self?.startInstallation(for: app)
                           } else {
                               print("用户未支付，提示输入解锁码")
                               self?.promptUnlockCode(for: app)
                           }
                       }
                   } catch {
                       print("解析支付状态响应时发生错误：\(error.localizedDescription)")
                   }
               }.resume()
           }

           private func promptUnlockCode(for app: AppData) {
               let alert = UIAlertController(title: "解锁码", message: "请输入解锁码以继续安装", preferredStyle: .alert)
               alert.addTextField { textField in
                   textField.placeholder = "请输入解锁码"
               }
               let confirmAction = UIAlertAction(title: "确定", style: .default) { [weak self] _ in
                   guard let unlockCode = alert.textFields?.first?.text, !unlockCode.isEmpty else {
                       print("解锁码为空")
                       return
                   }
                   self?.verifyUnlockCode(unlockCode, for: app)
               }
               let cancelAction = UIAlertAction(title: "取消", style: .cancel, handler: nil)
               alert.addAction(confirmAction)
               alert.addAction(cancelAction)
               present(alert, animated: true, completion: nil)
           }

           private func verifyUnlockCode(_ code: String, for app: AppData) {
               guard let cleanUUID = globalDeviceUUID?
                   .replacingOccurrences(of: "Optional(\"", with: "")
                   .replacingOccurrences(of: "\")", with: ""),
                   !cleanUUID.isEmpty else {
                   print("设备 UUID 无效")
                   return
               }
               let verifyURL = "https://store.cloudmantoua.top/verify-card"
               guard var components = URLComponents(string: verifyURL) else { return }
               components.queryItems = [
                   URLQueryItem(name: "UDID", value: cleanUUID),
                   URLQueryItem(name: "code", value: code)
               ]

               guard let url = components.url else {
                   print("构造 URL 失败")
                   return
               }

               var request = URLRequest(url: url)
               request.httpMethod = "POST"

               URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                   if let error = error {
                       print("请求失败：\(error.localizedDescription)")
                       return
                   }

                   guard let data = data else {
                       print("未收到数据")
                       return
                   }

                   do {
                       if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let message = json["message"] as? String {
                           DispatchQueue.main.async {
                               print("服务器返回消息：\(message)")
                               if message == "验证成功" {
                                   print("解锁码验证成功，开始安装")
                                   self?.startInstallation(for: app)
                               } else {
                                   print("验证失败：\(message)")
                               }
                           }
                       } else {
                           print("解析响应失败")
                       }
                   } catch {
                       print("JSON 解析失败：\(error.localizedDescription)")
                   }
               }.resume()
           }

    private func startInstallation(for app: AppData) {
        let alert = UIAlertController(
            title: "确认安装",
            message: "是否安装 \(app.name)？",
            preferredStyle: .alert
        )

        let installAction = UIAlertAction(title: "安装", style: .default) { _ in
            if let url = URL(string: "itms-services://?action=download-manifest&url=\(app.plist)") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        
        let cancelAction = UIAlertAction(title: "取消", style: .cancel, handler: nil)

        alert.addAction(installAction)
        alert.addAction(cancelAction)

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
}

// 自定义 Cell
class AppCell: UICollectionViewCell {
    private let appIcon = UIImageView()
    private let nameLabel = UILabel()
    private let versionLabel = UILabel()
    private let installButton = UIButton(type: .system)

    var onInstallTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 15
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .white
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        contentView.layer.shadowOpacity = 0.1
        contentView.layer.shadowRadius = 5

        let textStackView = UIStackView(arrangedSubviews: [nameLabel, versionLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 5
        textStackView.alignment = .leading

        let stackView = UIStackView(arrangedSubviews: [appIcon, textStackView, installButton])
        stackView.axis = .horizontal
        stackView.spacing = 15
        stackView.alignment = .center
        stackView.distribution = .fill

        contentView.addSubview(stackView)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15)
        ])

        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 70).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 70).isActive = true

        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .darkGray
        versionLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        versionLabel.textColor = .lightGray

        installButton.backgroundColor = .systemBlue
        installButton.layer.cornerRadius = 10
        installButton.setTitle("安装", for: .normal)
        installButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        installButton.tintColor = .white
        installButton.frame.size = CGSize(width: 100, height: 40)  // 固定按钮大小
        installButton.addTarget(self, action: #selector(installTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with app: StoreCollectionViewController.AppData) {
        nameLabel.text = app.name
        versionLabel.text = "版本 \(app.version) (Build \(app.build))"
        if let url = URL(string: app.icon) {
            loadImage(from: url, into: appIcon)
        }
    }

    @objc private func installTapped() {
        onInstallTapped?()
    }

    private func loadImage(from url: URL, into imageView: UIImageView) {
        DispatchQueue.global().async {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    imageView.image = image
                    imageView.layer.cornerRadius = imageView.frame.size.width / 2
                    imageView.clipsToBounds = true
                }
            }
        }
    }
}

// 数据模型
struct PaymentResponse: Decodable {
    let isPaid: Bool
}
