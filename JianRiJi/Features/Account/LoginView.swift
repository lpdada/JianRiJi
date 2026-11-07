import SwiftUI

/// 账号页：未登录时是手机号 + 验证码登录；已登录时显示账号信息、改昵称、退出。
/// 服务端地址没填时，整个页只显示“未配置服务器”，不发任何请求。
struct LoginView: View {
    @EnvironmentObject private var cloud: CloudSync

    @State private var phone = ""
    @State private var code = ""
    @State private var devCode: String?
    @State private var busy = false
    @State private var errorMessage = ""
    @State private var cooldown = 0
    @State private var nicknameDraft = ""
    @State private var nicknameMessage = ""

    var body: some View {
        Form {
            if !cloud.isConfigured {
                Section {
                    Text("云端服务器地址还没填。去「设置 → 账号与同步」里填上地址，才能登录和同步。")
                        .foregroundStyle(Theme.muted)
                } header: {
                    Text("未配置服务器")
                }
            } else if let user = cloud.account {
                Section {
                    row("手机号", user.phone)
                    row("昵称", user.nickname)
                } header: {
                    Text("已登录")
                }

                Section {
                    TextField("新昵称（最多 20 字）", text: $nicknameDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack(spacing: 12) {
                        Button("保存昵称") {
                            saveNickname()
                        }
                        .disabled(nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        if !nicknameMessage.isEmpty {
                            Text(nicknameMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } header: {
                    Text("改昵称")
                }

                Section {
                    Button(role: .destructive) {
                        cloud.logout()
                    } label: {
                        Text("退出登录")
                    }
                } footer: {
                    Text("退出只清掉本机的登录 token，云端的进度还在。下次登录会先拉云端，新的合并进来。")
                }
            } else {
                Section {
                    TextField("手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: phone) { newValue in
                            let digits = newValue.filter { $0.isNumber }
                            phone = String(digits.prefix(11))
                        }

                    HStack(spacing: 12) {
                        TextField("6 位验证码", text: $code)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: code) { newValue in
                                let digits = newValue.filter { $0.isNumber }
                                code = String(digits.prefix(6))
                            }
                        Button(cooldown > 0 ? "重发 \(cooldown)s" : "发验证码") {
                            sendCode()
                        }
                        .disabled(!CloudAPI.isValidPhone(phone) || busy || cooldown > 0)
                    }

                    if let devCode {
                        Text("开发模式验证码：\(devCode)，已自动填入。服务端没接短信商，生产模式下这里不会有验证码。")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("手机号登录")
                } footer: {
                    Text("登录后进度会同步到云端，换设备不用重来。验证码 5 分钟有效，输错 5 次要重发。")
                }

                Section {
                    Button {
                        doLogin()
                    } label: {
                        Text(busy ? "正在登录…" : "登录")
                    }
                    .disabled(!CloudAPI.isValidPhone(phone) || code.count != 6 || busy)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("账号")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let user = cloud.account {
                nicknameDraft = user.nickname
            }
        }
        .task(id: cooldown > 0) {
            guard cooldown > 0 else { return }
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                cooldown -= 1
            }
        }
    }

    private func sendCode() {
        busy = true
        errorMessage = ""
        devCode = nil
        Task {
            do {
                let returned = try await cloud.requestCode(phone: phone)
                await MainActor.run {
                    busy = false
                    if let returned {
                        devCode = returned
                        code = returned
                    }
                    cooldown = 60
                }
            } catch {
                await MainActor.run {
                    busy = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func doLogin() {
        busy = true
        errorMessage = ""
        Task {
            do {
                try await cloud.login(phone: phone, code: code)
                await MainActor.run {
                    busy = false
                    nicknameDraft = cloud.account?.nickname ?? ""
                }
            } catch {
                await MainActor.run {
                    busy = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveNickname() {
        busy = true
        nicknameMessage = ""
        let name = nicknameDraft
        Task {
            do {
                try await cloud.rename(nickname: name)
                await MainActor.run {
                    busy = false
                    nicknameMessage = "已保存"
                }
            } catch {
                await MainActor.run {
                    busy = false
                    nicknameMessage = error.localizedDescription
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.muted)
        }
    }
}
