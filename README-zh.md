# AmphiLoop

[English](README.md) | 中文

[Bridgic](https://github.com/bitsky-tech) 生态的 Agent 技能与知识语料库 — 提供 skills、agents 和 commands，用于构建 LLM 驱动与确定性双模执行的项目。

## 什么是 AmphiLoop？

AmphiLoop 是一个**语料库**，将领域知识和执行方法论封装为三层结构：

| 层级 | 角色 | 描述 |
|------|------|------|
| **Skills** | 领域知识 | "是什么、怎么用" — 按需加载的参考文档 |
| **Agents** | 执行方法论 | "怎么做好" — 专业化的执行专家 |
| **Commands** | 编排调度 | 协调 agents 和 skills 的多步骤工作流 |

三者协同实现端到端流水线：**通过 CLI 探索网站** -> **生成双模 agent 项目** -> **验证执行** — 全程在 agent 内完成。

## 延伸阅读

关于 AmphiLoop 设计动机与思想的长文：

- 英文版 — [Beyond Autonomous: Why I'm Building an Amphibious Agent](https://pub.towardsai.net/beyond-autonomous-why-im-building-an-amphibious-agent-fcae9a409220)
- 中文版 — [万字长文！两栖模式构建Agent，与OpenClaw/Hermes不一样的解法——开源AmphiLoop](https://zhangtielei.com/posts/blog-bridgic-amphiloop.html)

## 安装

```bash
# 第一步：注册 marketplace（仅需一次）
claude plugin marketplace add bitsky-tech/AmphiLoop

# 第二步：安装插件
claude plugin install AmphiLoop
```

或从本地仓库安装（把 `marketplace add` 指向本地目录即可——本仓库自带 `.claude-plugin/marketplace.json`，会被识别为 marketplace）：

```bash
git clone https://github.com/bitsky-tech/AmphiLoop.git

claude plugin marketplace add /path/to/AmphiLoop
claude plugin install AmphiLoop
```

安装后，skills、agents 和 commands（如 `/build`）会自动在 Claude Code 中可用。

## 使用

### Commands

Commands 是用户可直接调用的工作流，使用 `/` 前缀触发：

#### `/AmphiLoop:build`

统一流水线。描述任意任务，列出 agent 应读取的领域参考（SKILL、CLI 帮助、SDK 文档、风格指南），然后要求生成一个可运行项目：

```
/AmphiLoop:build

我想把 ~/data/inputs 下所有 `orders_*.csv` 汇总成一个 summary.csv —
按 customer 聚合出每个客户的总额。
```

**领域标志（可选）** — 在命令后追加 `--<domain>`，即可注入 `domain-context/<domain>/` 下预先蒸馏好的领域上下文。当前已支持：`--browser`。

```
/AmphiLoop:build --browser

打开 https://example.com，搜索 "product"，提取前 5 条结果。
我需要一个能稳定运行的项目。
```

不带标志时，`/build` 会根据 `TASK.md` 自动识别领域（若没有匹配则回退到通用流程）。用户可随时在 `TASK.md` 中补充额外领域参考。

**执行流程：**

1. **Initialize Task** — 生成 `TASK.md` 模板，用户填写目标、预期输出、**领域参考**；若未带标志则自动识别领域
2. **Configure Pipeline** — 项目模式（Workflow / Amphiflow）、按需的 LLM 配置，以及任何领域特定配置（例如 `--browser` 模式下询问浏览器环境模式）
3. **Setup Environment** — 检查 `uv`，执行 `uv init`
4. **Explore** — 委派 `amphibious-explore` agent 读取用户提供的领域参考并探索环境
5. **Generate** — 委派 `amphibious-code` agent 生成完整项目及所有源文件
6. **Verify** — 委派 `amphibious-verify` agent 注入调试插桩、运行项目、验证结果

### Agents

Agents 是由 commands 调度的执行专家，不由用户直接调用：

| Agent | 功能 |
|-------|------|
| **amphibious-explore** | 通过领域工具集系统性探索目标环境，生成带稳定性标注的可执行操作序列与关键快照 |
| **amphibious-code** | 根据任务描述和探索报告生成完整的 bridgic-amphibious 项目 |
| **amphibious-verify** | 注入调试插桩、监控运行、验证结果、清理环境 |

### Skills

Skills 是领域知识参考，agent 会根据对话上下文自动加载，无需手动调用：

| Skill | 触发场景 |
|-------|---------|
| **bridgic-browser** | 使用浏览器自动化 CLI（`bridgic-browser ...`）或 Python SDK（`from bridgic.browser`） |
| **bridgic-amphibious** | 使用双模框架（`AmphibiousAutoma`、`CognitiveWorker`、`on_agent`/`on_workflow`） |
| **bridgic-llms** | 初始化 LLM 提供商（`OpenAILlm`、`OpenAILikeLlm`、`VllmServerLlm`） |

## 架构

```
AmphiLoop/
├── .claude-plugin/
│   ├── plugin.json              # 插件注册
│   └── marketplace.json         # Marketplace 元数据
├── skills/                      # 领域知识（3 个 skills）
│   ├── manifest.ini             #   Skill 来源注册表（repo、ref、paths）
│   ├── README.md                #   Manifest 文档 + 自动生成的 skill 表格
│   ├── bridgic-browser/         #   浏览器自动化 CLI + SDK
│   ├── bridgic-amphibious/      #   双模 Agent 框架
│   └── bridgic-llms/            #   LLM 提供商集成
├── agents/                      # 执行方法论（3 个 agents）
│   ├── amphibious-explore.md    #   抽象探索方法论
│   ├── amphibious-code.md       #   代码生成专家
│   └── amphibious-verify.md     #   项目验证专家
├── commands/                    # 用户可调用的工作流
│   └── build.md                 #   统一流水线（可选 --<domain> 标志）
├── domain-context/              # /build 注入的预蒸馏领域上下文
│   └── browser/                 #   intent.md / config.md / explore.md / code.md / verify.md（含 script/）
├── templates/                   # 命令使用的静态模板（不会被自动扫描）
│   └── build-task-template.md         #   /build 使用的统一 TASK.md 模板
├── hooks/                       # 自动加载的事件处理器
│   └── hooks.json
└── scripts/                     # Hook 与工具脚本
    ├── hook/
    │   └── inject-command-paths.sh
    ├── run/
    │   ├── setup-env.sh         #   校验 uv 工具链；在 PROJECT_ROOT 执行 uv init --bare
    │   ├── check-dotenv.sh      #   LLM 模型配置校验
    │   └── monitor.sh           #   amphibious-verify 的 run-and-monitor 脚本
    └── maintenance/
        └── sync-skills.sh       #   从源仓库同步 skills（基于 manifest.ini）
```

### 各层如何协作

```
用户调用 command
        |
        v
  +-----------+        读取       +--------+
  |  Command  | ----------------> | Skills |
  +-----------+                   +--------+
        |
        | 委派给
        v
  +-----------+        读取       +--------+
  |  Agents   | ----------------> | Skills |
  +-----------+                   +--------+
        |
        | 使用
        v
  +-----------+
  |   Hooks   |  （向子 agent 注入插件上下文）
  +-----------+
```

### 社区

欢迎加入我们，反馈建议、交流问题、获取最新动态：

- 🐦 Twitter / X：[@bridgic](https://x.com/bridgic)
- 💬 Discord：[加入我们的服务器](https://discord.gg/4NyKjXGKEh)

## 许可证

详见 [LICENSE](LICENSE)。
