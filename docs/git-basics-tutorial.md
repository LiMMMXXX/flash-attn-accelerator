# Git 零基础教程

> 目标：30 分钟搞懂 Git 的核心概念和日常操作

---

## 第一部分：Git 到底是什么

Git 本质上是一个**文件快照系统**。每次你 `git commit`，Git 就拍一张当前所有文件的照片（快照），存起来。

```
时间线:  [快照1] --- [快照2] --- [快照3] --- [快照4]
```

### Git 的三个工作区

```
┌──────────────┐  git add  ┌──────────┐  git commit  ┌──────────┐  git push  ┌──────────┐
│   工作区      │ ──────→  │  暂存区   │ ──────────→  │ 本地仓库  │ ────────→ │  GitHub  │
└──────────────┘          └──────────┘              └──────────┘           └──────────┘
```

关键理解：改文件 → git add → git commit → git push。

---

## 第二部分：逐句解释命令

### git push -u origin master

| 部分 | 含义 |
|---|---|
| git | 调用 Git |
| push | 推送本地提交到 GitHub |
| -u | 记住分支对应关系 |
| origin | 远程仓库的别名 |
| master | 分支名 |

### git pull --rebase

永远用 `--rebase`，保持历史直线。

---

## 第三部分：日常流程

### 每天开始
```bash
cd G:\code\flash-attn-accelerator
git pull --rebase
```

### 提交并推送
```bash
git status
git diff
git add -A
git commit -m "type: description"
git pull --rebase
git push
```

---

## 第四部分：救急

| 场景 | 命令 |
|---|---|
| 某行谁写的 | git blame 文件名 |
| 改到一半切分支 | git stash / git stash pop |
| 删错了 | git checkout -- 文件名 |
| add 错了 | git restore --staged 文件名 |

---

## 第五部分：推送前检查

1. git status
2. git diff
3. git pull --rebase
4. git push
