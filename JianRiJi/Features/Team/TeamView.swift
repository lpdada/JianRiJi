import SwiftUI

/// 组队打卡：创建队伍 / 按编号加入 / 看队员今日状态 / 打卡 / 看历史。
/// 规则照词屿服务端：每人同时只能在一个未结束的队伍里，队伍最多 10 人；
/// 创建后状态一直是 pending（服务端没有开始/结算的接口），建队就能打卡；
/// 押金只记个数，不走支付，钱线下自己转。
struct TeamView: View {
    @EnvironmentObject private var cloud: CloudSync

    @State private var newName = ""
    @State private var days = 30
    @State private var deposit = 0
    @State private var joinCode = ""
    @State private var busy = false
    @State private var message = ""
    @State private var showLeaveConfirm = false

    var body: some View {
        Form {
            if !cloud.isConfigured {
                Section {
                    Text("云端服务器地址还没填。去「设置 → 账号与同步」里填上地址，才能组队。")
                        .foregroundStyle(Theme.muted)
                } header: {
                    Text("未配置服务器")
                }
            } else if cloud.account == nil {
                Section {
                    Text("组队要先登录。登录后进度也会同步到云端。")
                        .foregroundStyle(Theme.muted)
                    NavigationLink {
                        LoginView()
                    } label: {
                        Text("去登录")
                    }
                } header: {
                    Text("未登录")
                }
            } else if let team = cloud.team {
                Section {
                    row("队伍", team.name)
                    row("编号", team.code)
                    row("周期", "\(team.days) 天")
                    row("押金", team.deposit > 0 ? "\(team.deposit) 元" : "无")
                    row("人数", "\(team.memberCount) / 10")
                } header: {
                    Text("我的队伍")
                } footer: {
                    Text("把编号发给队友，对方在下面「加入队伍」里填编号就能进来。押金只记账，不走支付。")
                }

                Section {
                    if cloud.members.isEmpty {
                        Text("正在拉队员…")
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(cloud.members) { member in
                            HStack {
                                Text(member.nickname)
                                Spacer()
                                Text(member.hasCheckedToday ? "已打卡" : "未打卡")
                                    .foregroundStyle(member.hasCheckedToday ? Theme.accent : Theme.muted)
                                Text("\(member.totalDays) 天")
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                } header: {
                    Text("队员今日状态")
                } footer: {
                    if team.allDoneToday {
                        Text("全员今日已打卡。")
                    } else {
                        let missing = cloud.members.filter { !$0.hasCheckedToday }.count
                        Text(missing > 0 ? "还差 \(missing) 人打卡，全员打了当天才算有效。" : "")
                    }
                }

                Section {
                    Button {
                        checkin()
                    } label: {
                        Text(busy ? "正在打卡…" : "今日打卡")
                    }
                    .disabled(busy)

                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                if !cloud.teamHistory.isEmpty {
                    Section {
                        ForEach(cloud.teamHistory.prefix(30), id: \.self) { date in
                            Text(date)
                        }
                    } header: {
                        Text("我的打卡记录")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Text("退出队伍")
                    }
                } footer: {
                    Text("队伍开始后不能退——服务端只在 pending 时放行，建队就是 pending，所以现在能退。")
                }
            } else {
                Section {
                    TextField("队伍名（最多 20 字）", text: $newName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Stepper(value: $days, in: 7...100) {
                        row("周期", "\(days) 天")
                    }
                    Stepper(value: $deposit, in: 0...10_000, step: 10) {
                        row("押金", deposit > 0 ? "\(deposit) 元" : "无")
                    }
                    Button {
                        createTeam()
                    } label: {
                        Text(busy ? "正在创建…" : "创建队伍")
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                } header: {
                    Text("创建队伍")
                } footer: {
                    Text("押金只记个数，不走支付。周期 7–100 天，队伍最多 10 人。")
                }

                Section {
                    TextField("6 位编号，如 AB12CD", text: $joinCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: joinCode) { newValue in
                            joinCode = newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6).description
                        }
                    Button {
                        joinTeam()
                    } label: {
                        Text(busy ? "正在加入…" : "加入队伍")
                    }
                    .disabled(joinCode.count != 6 || busy)
                } header: {
                    Text("加入队伍")
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("组队打卡")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloud.refreshTeam()
            await cloud.loadHistory()
        }
        .refreshable {
            await cloud.refreshTeam()
            await cloud.loadHistory()
        }
        .confirmationDialog("退出队伍？", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("退出", role: .destructive) {
                leaveTeam()
            }
            Button("算了", role: .cancel) {}
        } message: {
            Text("退出后要重新加队才能回来。")
        }
    }

    private func createTeam() {
        busy = true
        message = ""
        Task {
            do {
                try await cloud.createTeam(name: newName, days: days, deposit: deposit)
                await MainActor.run {
                    busy = false
                    message = "队伍建好了，把编号发给队友。"
                    newName = ""
                }
            } catch {
                await MainActor.run {
                    busy = false
                    message = error.localizedDescription
                }
            }
        }
    }

    private func joinTeam() {
        busy = true
        message = ""
        Task {
            do {
                try await cloud.joinTeam(code: joinCode)
                await MainActor.run {
                    busy = false
                    message = "已加入队伍。"
                    joinCode = ""
                }
            } catch {
                await MainActor.run {
                    busy = false
                    message = error.localizedDescription
                }
            }
        }
    }

    private func leaveTeam() {
        busy = true
        message = ""
        Task {
            do {
                try await cloud.leaveTeam()
                await MainActor.run {
                    busy = false
                    message = "已退出队伍。"
                }
            } catch {
                await MainActor.run {
                    busy = false
                    message = error.localizedDescription
                }
            }
        }
    }

    private func checkin() {
        busy = true
        message = ""
        Task {
            do {
                let already = try await cloud.checkin()
                await MainActor.run {
                    busy = false
                    message = already ? "今天已经打过卡了。" : "打卡成功。"
                }
            } catch {
                await MainActor.run {
                    busy = false
                    message = error.localizedDescription
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
