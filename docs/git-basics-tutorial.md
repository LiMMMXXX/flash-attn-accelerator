# Git 零基础教程（详细版）

> 目标：搞懂 Git 每一行命令在做什么
> 适用：Flash Attention 硬件加速器团队

---

## 零、Git 核心概念

Git 是一个文件快照系统。每次 git commit 就把当前所有文件拍一张照片存起来。

### 三个工作区（最重要的一张图）

```
工作区 --git add---> 暂存区 --git commit---> 本地仓库 --git push---> GitHub
(编辑器里看到)         (staging)              (.git目录)              (远程)
```

把文件从上一个区域推到下一个区域，就是 Git 的全部操作。

---

## 一、git status — 看当前状态

最常用的命令，没有之一。告诉你当前改了哪些文件、在哪个分支。

```
$ git status

On branch master        <- 当前在 master 分支
Your branch is up to date. <- 本地和远程一致

Changes not staged:      <- 改了但还没 add
  modified:   rtl/top.sv

Untracked files:        <- 新增文件，Git 还没跟踪
  docs/new-feature.md
```

任何时候不确定就敲 git status，没有副作用。

---

## 二、git diff — 看具体改了哪几行

对比当前文件和最近一次 commit，逐行显示差异。

```
$ git diff rtl/top.sv

--- a/rtl/top.sv          <- 改动前（仓库里的版本）
+++ b/rtl/top.sv          <- 改动后（你当前的文件）
@@ -10,6 +10,8 @@        <- 第10行开始，原来6行变8行

 wire clk;                <- 没颜色的行 = 没改动
+reg [31:0] counter;      <- 绿色+号 = 新增的行
 assign data = ...
```

常用变体：

```bash
git diff              # 看所有文件的改动
git diff --cached     # 看已 add 的改动
git diff --stat       # 只看统计：改了几个文件，加了几行
```

每次 git add 之前，先用 git diff 确认一遍自己的修改。

---

## 三、git add — 把文件放入暂存区

告诉 Git：这个文件的改动我要留下来。把文件从工作区搬到暂存区。

几种用法：

```bash
git add rtl/top.sv          # 只暂存这一个文件
git add docs/               # 暂存整个目录
git add -A                  # 暂存所有改动（最常用）
```

输出解释：

```
$ git add -A
（没有输出 = 执行成功）

$ git status
On branch master
Changes to be committed:    <- 注意这里变了
  new file:   docs/new.md    <- 绿字：已暂存
  modified:   rtl/top.sv     <- 绿字：已暂存
```

红字变绿字 = 从工作区进入了暂存区。

如果 add 错了：

```bash
git restore --staged rtl/top.sv   # 退回工作区，不改内容
```

---

## 四、git commit -- 拍快照

把暂存区的改动永久存到本地仓库。相当于拍一张照片。

用法：

```bash
git commit -m "hw: add counter register"
```

输出解释：

[master cbcfa95] doc: add  <- [分支名] 提交hash
 1 file changed, 81 insertions(+)  <- 1个文件，加了81行

注意：commit 只是存到本地。需要下一步 git push 到 GitHub。

---

## 五、git push -- 推送到 GitHub

把本地仓库的提交上传到 GitHub，让队友看到。

用法：

```bash
git push -u origin master    # 第一次，-u 记住对应关系
git push                     # 以后直接 push
```

输出逐行解释：

```
$ git push
Enumerating objects: 6, done.    <- 数要上传多少包
Counting objects: 6/6, done.     <- 6个对象
Writing objects: 4/4, 1.28 KiB   <- 上传中
To https://github.com/xxx.git    <- 推送到这个地址
   old..new master -> master      <- 旧版本..新版本
```

最后一行是关键：表示 GitHub 上的版本从旧前进到了新。


---

## 六、git pull --rebase

把 GitHub 上别人新提交的代码下载到本地。

为什么必须做？

你本地: A-B-C, 远程: A-B-D-E。直接 git push 会被拒绝。
必须先 git pull --rebase 再 push。

--rebase 的意思：

不用 rebase: 会多出一个合并节点 M，历史变乱
用 rebase: 你的提交被放到远程提交后面，一条直线

本质：把你的提交拔起来，插到远程最新提交的后面。

团队纪律：永远用 git pull --rebase

也可以设为默认：

git config --global pull.rebase true

以后直接 git pull 就等于 git pull --rebase。

---

## 七、完整的一天工作流

每天开始：

cd G:\code\flash-attn-accelerator
git pull --rebase
git log --oneline --since=yesterday  (看队友昨天改了啥)

写代码...

准备推送：

git status         (看改了哪些文件)
git diff           (逐行确认)
git add -A         (暂存所有改动)
git commit -m "hw: add xxx"  (提交)
git pull --rebase  (再拉一次防冲突)
git push           (推送到 GitHub)

---

## 八、常用命令速查

| 命令 | 什么时候用 |
|---|---|
| git status | 任何时候不确定当前状态 |
| git diff | 看具体改了哪几行 |
| git add -A | 暂存所有改动 |
| git commit -m | 拍快照 |
| git pull --rebase | 拉取远程最新代码 |
| git push | 推送到 GitHub |
| git log --oneline | 看提交历史 |
| git blame 文件名 | 某行代码谁写的 |
| git stash / pop | 改到一半切出去 |
| git checkout -- 文件名 | 撤销修改 |
| git restore --staged 文件名 | add 错了退回 |

---

## 推送前检查清单

1. git status -- 看改了啥
2. git diff -- 逐行确认
3. git pull --rebase -- 无冲突
4. git push -- 推送

---

# 教程结束


---

## 附：解决冲突

两个人改了同一段代码时，git pull --rebase 会报：

CONFLICT (content): Merge conflict in docs/git-basics-tutorial.md

VS Code 中会看到：
<<<<<<< HEAD        <- 你的改动
=======             <- 分隔线
>>>>>>> origin/main <- 远程的改动

手动编辑保留正确代码，去掉标记行，然后：
git add 文件名
git rebase --continue
