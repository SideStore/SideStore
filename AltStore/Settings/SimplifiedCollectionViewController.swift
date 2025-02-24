//
//  SimplifiedCollectionViewController.swift
//  SideStore
//
//  Created by mantou on 2025/2/17.
//  Copyright © 2025 SideStore. All rights reserved.
//

//
//  SimplifiedCollectionViewController.swift
//  SideStore
//
//  Created by mantou on 2025/2/16.
//  Copyright © 2025 SideStore. All rights reserved.
//

import UIKit
import AltSign
import AltStoreCore

class SimplifiedCollectionViewController: UICollectionViewController {
  
        // 定义有序的分区顺序
        var sectionOrder = ["账户", "个人信息", "设置", "群组链接"]
        
        // 定义数据源
        var settings: [String: [String]] = [
            "账户": ["登录", "退出登录"],
            "个人信息": ["Name: 未知", "Email: 未知", "Type: 未知"],
            "设置": ["清除缓存", "清除配置文件"],
            "群组链接": []
        ]
        
        
        var groupLinks: [(name: String, url: String)] = []
        
        override func viewDidLoad() {
            super.viewDidLoad()
            
            // 设置标题
            title = "设置"
            
            // 初始化布局
            let layout = UICollectionViewFlowLayout()
            layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize // 动态高度
            layout.minimumLineSpacing = 16
            layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            layout.headerReferenceSize = CGSize(width: view.bounds.width, height: 50)
            collectionView.collectionViewLayout = layout
            
            collectionView.backgroundColor = UIColor.systemGroupedBackground
            
            // 注册 Cell 和 Header
            collectionView.register(SettingCell.self, forCellWithReuseIdentifier: "SettingCell")
            collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "SectionHeaderView")
            
            updateUserInfo()
            fetchGroupLinks()
        }
        
        // MARK: - UICollectionView 数据源方法
        
        override func numberOfSections(in collectionView: UICollectionView) -> Int {
            return sectionOrder.count
        }
        
        override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            let sectionTitle = sectionOrder[section]
            
            if sectionTitle == "群组链接" {
                return groupLinks.count
            }
            return settings[sectionTitle]?.count ?? 0
        }
        
        override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SettingCell", for: indexPath) as! SettingCell
            
            let sectionTitle = sectionOrder[indexPath.section]
            
            if sectionTitle == "群组链接" {
                let link = groupLinks[indexPath.row]
                cell.configure(title: link.name, isLink: true)
            } else {
                guard let items = settings[sectionTitle] else { return cell }
                let item = items[indexPath.row]
                cell.configure(title: item, isLink: false)
            }
            
            return cell
        }
        
        // MARK: - UICollectionView 代理方法
        
        override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)
            
            let sectionTitle = sectionOrder[indexPath.section]
            
            switch sectionTitle {
            case "账户":
                handleAccountAction(indexPath.row)
            case "设置":
                handleSettingsAction(indexPath.row)
            case "群组链接":
                openGroupLink(indexPath.row)
            default:
                break
            }
        }
        
        override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            guard kind == UICollectionView.elementKindSectionHeader else { return UICollectionReusableView() }
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "SectionHeaderView", for: indexPath) as! SectionHeaderView
            
            let sectionTitle = sectionOrder[indexPath.section]
            header.titleLabel.text = sectionTitle
            
            return header
        }
        
        // MARK: - Action Handlers
        
        private func handleAccountAction(_ index: Int) {
            switch index {
            case 0: signIn()
            case 1: signOut()
            default: break
            }
        }
        
        private func handleSettingsAction(_ index: Int) {
            switch index {
            case 0: clearCache()
            case 1: clearConfigurationFile()
            default: break
            }
        }
        
        private func openGroupLink(_ index: Int) {
            guard index < groupLinks.count else { return }
            let link = groupLinks[index]
            if let url = URL(string: link.url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        
    // 登录逻辑更新
    private func signIn() {
        AppManager.shared.authenticate(presentingViewController: self) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(OperationError.cancelled):
                    break // 用户取消操作
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                case .success:
                    print("登录成功")
                    self.updateUserInfo()
                    // 更新登录按钮标题
                    self.updateLoginStatus(isLoggedIn: true)
                }
            }
        }
    }

    // 退出登录逻辑
    private func signOut() {
        DatabaseManager.shared.signOut { error in
            DispatchQueue.main.async {
                if let error = error {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                } else {
                    self.clearUserInfo()
                    // 更新登录按钮标题
                    self.updateLoginStatus(isLoggedIn: false)
                }
            }
        }
    }

    // 更新登录状态
    private func updateLoginStatus(isLoggedIn: Bool) {
        if isLoggedIn {
            settings["账户"] = ["已登录", "退出登录"]
        } else {
            settings["账户"] = ["登录", "退出登录"]
        }
        collectionView.reloadData()
    }

    // 更新用户信息
    private func updateUserInfo() {
        if let team = DatabaseManager.shared.activeTeam() {
            settings["个人信息"] = [
                "Name: \(team.name)",
                "Email: \(team.account.appleID)",
                "Type: \(team.type.localizedDescription)"
            ]
        } else {
            clearUserInfo()
        }
        collectionView.reloadData()
    }

    // 清除用户信息
    private func clearUserInfo() {
        settings["个人信息"] = ["Name: 未知", "Email: 未知", "Type: 未知"]
        collectionView.reloadData()
    }
        
        // MARK: - 清除缓存逻辑
        private func clearCache() {
            let alertController = UIAlertController(title: "您确定要清除缓存吗？", message: "这将删除所有临时文件以及已卸载应用的备份。", preferredStyle: .actionSheet)
            alertController.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            alertController.addAction(UIAlertAction(title: "清除缓存", style: .destructive) { _ in
                AppManager.shared.clearAppCache { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            print("缓存已清除")
                        case .failure(let error):
                            let errorAlert = UIAlertController(title: "无法清除缓存", message: error.localizedDescription, preferredStyle: .alert)
                            errorAlert.addAction(UIAlertAction(title: "确定", style: .default, handler: nil))
                            self.present(errorAlert, animated: true)
                        }
                    }
                }
            })
            self.present(alertController, animated: true)
        }
        
        // MARK: - 清除配置文件逻辑
        private func clearConfigurationFile() {
            let filename = "ALTPairingFile.mobiledevicepairing"
            let fm = FileManager.default
            let documentsPath = fm.documentsDirectory.appendingPathComponent("/\(filename)")
            
            let alertController = UIAlertController(title: "您确定要清除配置文件吗？", message: "这将删除配对文件，您需要重新登录。", preferredStyle: .actionSheet)
            alertController.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            alertController.addAction(UIAlertAction(title: "清除配置文件", style: .destructive) { _ in
                if fm.fileExists(atPath: documentsPath.path) {
                    try? fm.removeItem(atPath: documentsPath.path)
                    print("配置文件已清除")
                    self.clearUserInfo()
                }
            })
            self.present(alertController, animated: true)
        }
        
        // MARK: - 群组链接获取
        private func fetchGroupLinks() {
            guard let url = URL(string: "https://appflex.cloudmantoua.top/appflex/appflex.json") else { return }
            
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard let data = data else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                        self.groupLinks = json.map { (name: $0.key, url: $0.value) }
                        DispatchQueue.main.async {
                            self.collectionView.reloadData()
                        }
                    }
                } catch {
                    print("解析群组链接失败: \(error)")
                }
            }.resume()
        }
    }

    // MARK: - 自定义 Cell
class SettingCell: UICollectionViewCell {
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayout() {
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        titleLabel.textAlignment = .left // 确保文本左对齐
    }
    
    func configure(title: String, isLink: Bool) {
        titleLabel.text = title
        
        if isLink {
            // 群组链接的图标
            switch title {
            case "QQ群":
                iconImageView.image = UIImage(systemName: "message.fill")
            case "电报群":
                iconImageView.image = UIImage(systemName: "paperplane.fill")
            case "公众号":
                iconImageView.image = UIImage(systemName: "bubble.right.fill")
            default:
                iconImageView.image = UIImage(systemName: "link")
            }
        } else {
            // 普通设置项的图标
            switch title {
            case "登录":
                iconImageView.image = UIImage(systemName: "person.fill")
            case "退出登录":
                iconImageView.image = UIImage(systemName: "arrow.backward.square.fill")
            case "Name: 未知", "Email: 未知", "Type: 未知":
                iconImageView.image = UIImage(systemName: "person.crop.circle.fill")
            case "清除缓存":
                iconImageView.image = UIImage(systemName: "trash.fill")
            case "清除配置文件":
                iconImageView.image = UIImage(systemName: "folder.badge.minus")
            default:
                iconImageView.image = UIImage(systemName: "gear")
            }
        }
    }
}

    // MARK: - 自定义 Header
    class SectionHeaderView: UICollectionReusableView {
        
        let titleLabel: UILabel = {
            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
            label.textColor = .label
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayout()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupLayout() {
            addSubview(titleLabel)
            
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
            ])
        }
    }
