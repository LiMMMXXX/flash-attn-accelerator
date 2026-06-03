# VS Code + Git Graph 团队协作教程

> 适用场景：多人共同开发 flash-attn-accelerator 硬件加速器
> 前置条件：VS Code + Git Graph 插件已安装

---

## 一、打开 Git Graph

### 方式 1 — 命令面板（最快）

`Ctrl+Shift+P` → 输入 `Git Graph: View Git Graph` → 回车

### 方式 2 — 状态栏

点击 VS Code 底部状态栏左侧的分支名称（如 `main`）→ "View Git Graph"

### 方式 3 — 文件右键

在任意文件上右键 → `Git: View Git Graph`

---

## 二、界面速览

打开后你会看到：

- **上方**: 分支树图形（每条线是一个分支，圆点是提交）
- **右侧**: 选中的提交详情（改动文件列表）
- **下方**: 选中文件的逐行 diff

### 颜色含义

| 颜色 | 含义 |
|---|---|
| 蓝色线 | 当前分支 |
| 绿色线 | 其他本地分支 |
| 橙色线 | 远程分支（如 origin/main） |
| 灰色点 | 已推送的提交 |
| 空心点 | 未推送的本地提交 |

---

## 三、核心操作

### 3.1 看别人改了什么

**看所有提交：**
1. 打开 Git Graph
2. 点击任意圆点 → 右侧显示该次提交改动的文件列表
3. 点击文件 → 下方显示逐行 diff（绿色=新增，红色=删除）

**看某个人的提交：**
- Git Graph 顶部搜索框输入 `author:张三`
- 或点击搜索图标 → "Find commits by author"

**看某个文件的历史：**
- 在 VS Code 文件浏览器中右键文件 → `Git: View File History`

**看某行是谁写的（git blame）：**
- 打开文件 → 在行号右侧悬停
- 或右键 → `Git: View Git Blame`

### 3.2 上传前确认

推代码前检查三遍：

**第一遍——看改了什么文件：**
```bash
git diff origin/main --stat
```

**第二遍——看逐行差异：**
1. 打开 Git Graph
2. 右键最新提交 → "Compare with main"
3. 逐行检查

**第三遍——看是否有冲突：**
```bash
git pull --rebase
```

### 3.3 提交代码

```bash
git switch main
git pull --rebase
git switch -c feat/add-rescale

# 写代码...

# 在 VS Code 源代码管理（Ctrl+Shift+G）
# → 看改动文件 → 点 + 暂存 → 写 message → Ctrl+Enter 提交

# 推送
git push -u origin feat/add-rescale
```

### 3.4 Code Review

1. 推送到远程分支
2. 去 GitHub 开 Pull Request
3. 同事在 PR 上看 diff、写评论
4. 通过后合并

### 3.5 解决冲突

`git pull --rebase` 报冲突 → VS Code 高亮冲突区域：

- `<<<<<<< HEAD` = 你的改动
- `=======` 分隔
- `>>>>>>> feat/xxx` = 远程改动

手动编辑保留正确代码 → 去掉标记行 → 保存 → `git add` → `git rebase --continue`

---

## 四、团队规范

### Commit 格式

```
<类型>: <标题>
  - <细节1>
  - <细节2>
```

类型: `feat` `fix` `hw` `doc` `refac` `test` `wip`

### 分支命名

`feat/xxx` `fix/xxx` `doc/xxx` `refac/xxx` `test/xxx`

### 推前清单

- [ ] `git pull --rebase` 无冲突
- [ ] `git diff origin/main` 检查无误
- [ ] 本地测试通过
- [ ] commit message 格式正确

---

## 五、快捷键

| 操作 | 快捷键 |
|---|---|
| 打开 Git Graph | `Ctrl+Shift+P` → "Git Graph" |
| 源代码管理 | `Ctrl+Shift+G` |
| 切换文件 | `Ctrl+P` |
| 提交 | `Ctrl+Enter` |
| 刷新 Git Graph | `F5` |

---

## 六、命令速查

```bash
git status                # 看改了啥
git diff                  # 看差异
git fetch                 # 下载远程信息
git pull --rebase         # 拉取并重放
git push                  # 推送
git log --oneline --graph --all  # 终端看分支图
git blame file.sv         # 某行谁写的
```
