---
title: 命令执行卡死的两类根因：终端 TAB 展开污染 heredoc / 复用会话被挂起命令占死
tags: [tooling, terminal, session, sshpass, heredoc, quoting, workflow]
module: 工具链（super_admin:terminal / github:terminal_exec / super_admin:shell）
problem_type: tooling_failure
severity: P1
verified_on: 2026-09-25
verified_device: FriendlyARM NanoPi R5C / ImmortalWrt 25.12.1（kernel 6.12.94）
---

# 症状

两种表现，容易被误判为「工具坏了」：

1. **命令挂起不返回**：`github:terminal_exec` 调用后不返回结果，后续同工具的调用也再无返回（"工具结果缺失"），换命令、换目标都无效。
2. **命令被"改写"**：`cat > /tmp/x.sh <<'EOF' ... EOF` 类 heredoc 写入后，脚本内容出现目录清单（`.bashrc`、`node_modules`…）、`\u0007` 控制字符、空行错位，脚本不可执行。

关键观察：本次事故中**远端设备未被修改**——损坏只发生在本地脚本，因为 heredoc 尚未闭合，远端 ssh 根本没被触发。区分"本地损坏"与"远端已变更"是止损第一步。

# 根因

## 根因 A：命令字符串里的**真实制表符**被终端当作 TAB 补全键

JSON 里写 `"\t"` 是意图缩进，但到达终端时已被解析为真实 TAB 字符。终端输入层的 TAB 默认绑定为**行内补全**，于是：

- TAB 触发行内补全 → 候选列表（目录树）被"敲进"了命令流；
- 补全过程还会吞掉/重排字符，产生 `\u0007`（bell）等控制字符；
- heredoc 因此无法正常闭合，块内容污染。

**判定特征**：报错内容里出现当前工作目录的文件清单、且 `>` 续行提示重复翻滚。

## 根因 B：`github:terminal_exec` 的默认会话是**长期复用**的

该工具带 `sessionId`（如 `ec46e23c…`），多次调用复用同一 shell 会话。一条**无硬超时**的远端命令（本次是 `sshpass … ssh …` 卡在交互/等待）会永久占住该会话：

- 本会话后续调用全部排队 → 全部"无返回"；
- 报错文案是含糊的"工具结果缺失，不是用户取消"，不指向真实原因。

**判定特征**：同一工具、不同命令连续两次都无返回；而另一个终端环境（不同会话 ID）却能正常执行。

## 加剧因素：多层引号嵌套 + `eval` + `$(cat ...)`

第一次失败的探针用了 `eval $SSHP "... '$SSHP' ..."` 这类结构：

```
eval $SSHP "'... printf \"%-34s \" ... $p ...'"
```

单引号/双引号/命令替换三层交织，任何一层被 shell 提前展开都会改变语义；叠加 remote 侧 `read`/`printf` 的差异，极易进入"等待输入"而挂起——正是根因 B 的触发器。

# 解决方案

## 1) 远端命令一律加硬超时

```sh
timeout 40 sshpass -p 'PASS' ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=6 -o LogLevel=ERROR \
  root@HOST 'sh /tmp/task.sh'
```

`timeout` 是唯一可靠的兜底：即使对端 SSH 挂着，本地也会返回，**不会占死会话**。
`ssh` 侧同时给 `ConnectTimeout` / `ServerAliveInterval`，避免 TCP 半开时无限等待。

## 2) 多行脚本走「文件直传」，绝不用 heredoc 拼在命令里

已验证可行的三段式：

```sh
# ① 本地用文件工具写（绕过终端输入层，制表符/引号/中文全部免疫）
#    create_file -> /sdcard/Download/Operit/<task>/task.sh
#    create_file -> /sdcard/Download/Operit/<task>/payload.json
# ② 传到设备（/sdcard 两环境共享，Ubuntu 侧可直接读）
sshpass -p 'PASS' scp -o ... /sdcard/Download/Operit/<task>/task.sh root@HOST:/tmp/
# ③ 执行
sshpass -p 'PASS' ssh -o ... root@HOST 'sh /tmp/task.sh'
```

**为什么**：`create_file` 不经过终端的行编辑层，TAB/引号/反斜杠原样落盘；远端只执行一个文件名，引号层级降到零。

## 3) 结构性规避清单

- ❌ 不在终端命令里放**真实制表符**（JSON/YAML 缩进一律用空格）；
- ❌ 不用 `eval` + 嵌套引号拼远端命令；需要变量就落文件或用单层单引号；
- ❌ 不在命令里做 heredoc（`<<EOF`）——多行内容一律走文件直传；
- ✅ 远端脚本里自身加 `set -e` 之外，关键步骤单独打印 `xxx_exit=$?`，便于区分失败点；
- ✅ 命令幂等：`rm -f`、`cp`、`apk del` 重复执行安全，便于卡住后重放。

## 4) 卡住后的处置流程

```
① 停止在原会话重试（重试只会继续排队）
② 换终端环境：super_admin:terminal ↔ github:terminal_exec（各自独立 session）
③ 在健康环境先做只读取证：
   ls /tmp/task.sh、grep 目标文件、apk list -I …，
   确认"远端到底改了没有"，再决定是重放还是回滚
④ 若需重置原会话：该工具的 session 常可关闭/新建（github:terminal_exec 有 close 参数），
   关闭后重新发起；不可关闭时，本任务全程改用另一环境
```

## 5) 凭据卫生

- 密码/Token 只落临时文件并 `chmod 600`，任务结束即 `rm`；
- 优先在命令中内联一次性密码（`sshpass -p 'PASS'`），避免留下文件；
- 提交前检查暂存区无凭据文件（本仓库用 `grep -c 'GITHUB_TOKEN' .git/config` 类似手段校验）。

# 预防策略

1. **新建自动化任务时先选通道**：
   - 单行 + 简单引号 → 直接 `ssh 'cmd'`（加 `timeout`）；
   - 多行 / 含 TAB / 含中文 / 含复杂引号 → **必须**走文件直传三段式。
2. **每个远端命令都默认加 `timeout`**，把"挂起"降级为"超时失败"，失败可观测、可重放。
3. **看到"工具结果缺失"先怀疑会话占用**，不要怀疑网络或设备；换环境 + 只读取证是标准动作。
4. 事故复盘中明确区分 **本地损坏** 与 **远端变更**：只有后者才需要回滚。

# 相关沉淀

- 本次任务实体变更记录：`docs/solutions/build/`（菜单改挂、apk 移除/安装链）
- 同类陷阱：任何"命令字符串 → 终端行编辑 → shell 解析"的多层转义链路，都适用本文第 2、3 条
