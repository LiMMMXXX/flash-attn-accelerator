# Flash Attention 硬件加速器 -- 团队开发流程

> 目标: 从拿到需求到代码合并上线的完整流程

---

## 一、项目结构

flash-attn-accelerator/
  rtl/         <- 硬件 RTL (Verilog/SystemVerilog)
    pe/       <- 处理单元
    sram_ctrl/ <- SRAM 控制器
    softmax/  <- 在线 Softmax
    top/      <- 顶层集成
  src/         <- 软件驱动 (C/C++)
  docs/        <- 文档和架构图
  scripts/     <- 构建脚本
  tests/       <- 测试用例


---

## 分支详解

### 什么是分支

分支就是一条独立的时间线。默认在 main 上，git switch -c xxx 就新建一条。

```
main:     A---B---C---D---E---F
                        ^
feat-x:                 X---Y---Z
```

main 和 feat-x 互不干扰，各自提交各自的。

### 为什么需要分支

没有分支时，所有人都在 main 上改，天天冲突。
有分支时各改各的，最后合并。

```
main:          A---B---C
                        |
你(feat/a):           D---E
张三(feat/b):         F---G
```

### 分支的完整生命周期

1. git switch -c feat/xxx       # 创建分支
2. 开发 + git commit             # 在分支上开发
3. git push -u origin feat/xxx   # 推送到 GitHub
4. 在 GitHub 开 PR                # 请求合并
5. 同事 Review -> Merge           # 审查通过后合并
6. git branch -d feat/xxx         # 删除本地分支
7. git push origin --delete feat/xxx  # 删除远程分支

### 分支命名规范

main                    主分支，永远稳定
feat/add-rescale        新功能
fix/softmax-bug         修 bug
doc/architecture-v2     文档
refac/tile-controller   重构
test/online-softmax     测试

原则：一个分支只做一件事，做完就删。

### 常见问题

Q: 分支改到一半，main 上同事合了新代码？
A: git pull --rebase，你的提交自动放到最前面。

Q: 分支上改坏了想放弃？
A: git checkout main 切回去，分支删掉重建。
---

## 二、分支命名规范

所有分支从 main 创建, 合并回 main:

main                <- 主分支, 随时可发布
feat/add-rescale    <- 新功能
fix/softmax-bug     <- 修 bug
doc/architecture-v2 <- 文档
refac/controller    <- 重构
test/online-softmax <- 测试

原则: 一个分支只做一件事, 做完就删。

---

## 三、完整开发流程

### 第 1 步: 同步最新代码

git checkout main
git pull --rebase

### 第 2 步: 创建功能分支

git switch -c feat/add-rescale

### 第 3 步: 开发

小步提交, 每完成一个子功能就 commit:

git add rtl/softmax/rescale.sv
git commit -m hw: add rescale module

### 第 4 步: 推送远程分支

git push -u origin feat/add-rescale

### 第 5 步: 开 Pull Request

1. 打开 GitHub 仓库页面, 点 Compare & pull request
2. 填标题和描述, 指定 Reviewers
3. 创建 PR

### 第 6 步: Code Review

审查重点: 逻辑正确? 边界条件? 命名清晰? 接口匹配?
发现问题 -> 本地修 -> git add/commit/push (PR 自动更新)

### 第 7 步: 合并到 main

在 GitHub PR 页面点 Merge pull request
或本地: git merge feat/add-rescale 然后 git push

### 第 8 步: 删除分支

git branch -d feat/add-rescale           # 删本地
git push origin --delete feat/add-rescale # 删远程

---

## 四、提交规范

格式: <类型>: <标题>

类型:
  feat   新功能    feat: add tiling scheduler
  fix    修 bug     fix: wrong softmax index
  hw     硬件改动   hw: add systolic array PE
  doc    文档       doc: update architecture
  refac  重构       refac: split top module
  test   测试       test: add softmax tb

好: hw: add online softmax rescale unit
不好: update / fix / wip (仅允许临时用)

---

## 五、RTL 开发指南

命名规范:
  - 模块名: 小写+下划线, 如 softmax_rescale
  - 文件名: 与模块名一致, 如 softmax_rescale.sv
  - 信号名: 小写+下划线, 如 data_valid
  - 参数名: 大写, 如 DATA_WIDTH

推前检查:
  [ ] 模块有 endmodule
  [ ] 端口完整 (clk, rst_n)
  [ ] 参数有默认值
  [ ] 本地仿真通过
  [ ] commit message 格式正确
  [ ] git pull --rebase 无冲突

---

## 六、版本发布

git checkout main
git pull --rebase
git tag -a v0.1.0 -m v0.1.0: initial release
git push origin v0.1.0

然后在 GitHub 上 Create Release, 填写变更日志。

版本号: v0.1.0 -> v0.2.0 -> v0.2.1 -> v1.0.0

---

## 七、完整 PR 周期

1. git switch -c feat/xxx
2. 开发 + git commit
3. git push -u origin feat/xxx
4. 在 GitHub 开 PR
5. 同事 Code Review
6. Merge 到 main
7. git branch -d feat/xxx

---

## 附录: VS Code 快捷键

Ctrl+Shift+P 输入 Git Graph  -> 打开 Git Graph
Ctrl+Shift+G               -> 源代码管理
Ctrl+P                     -> 切换文件
Ctrl+Enter                 -> 提交
右键 -> Git: View File History -> 文件历史

---

> 分享给团队新成员, 第一次会议一起过一遍。
