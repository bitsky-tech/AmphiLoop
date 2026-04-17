# AmphiLoop

[English](README.md) | 中文

AmphiLoop，全称是Amphibious Loop （两栖循环），是一套全新的AI智能体构建方法论、技术栈和工具链。它允许我们使用自然语言对任务进行描述和编排，由一个「探路 - 编码- 验证」循环来引导代码生成和构建过程，并且产物具备运行时在workflow模式和agent模式之间自动切换的能力。

AmphiLoop 将领域知识和执行方法论封装为三层结构：

| 层级 | 角色 | 描述 |
|------|------|------|
| **Skills** | 领域知识 | "是什么、怎么用" — 按需加载的参考文档 |
| **Agents** | 执行方法论 | "怎么做好" — 专业化的执行专家 |
| **Commands** | 编排调度 | 协调 agents 和 skills 的多步骤工作流 |

三者协同实现端到端流水线：**通过 CLI 探索网站** -> **生成双模 agent 项目** -> **验证执行** — 全程在 agent 内完成。

## 安装

```bash
# 第一步：注册 marketplace（仅需一次）
claude plugin marketplace add bitsky-tech/AmphiLoop

# 第二步：安装插件
claude plugin install AmphiLoop
```

或从本地仓库直接安装：

```bash
git clone https://github.com/bitsky-tech/AmphiLoop.git
claude plugin install /path/to/AmphiLoop
```

安装后，skills、agents 和 commands（如 `/build-browser`）会自动在 Claude Code 中可用。

## 使用

### Commands

Commands 是用户可直接调用的工作流，使用 `/` 前缀触发：

#### `/AmphiLoop:build-browser`

描述一个浏览器自动化任务，并要求生成一个稳定可运行的项目：

```
/AmphiLoop:build-browser

打开 https://example.com，搜索 "product"，提取前 5 条结果。
我需要一个能稳定运行的项目。
```

你的输入应包含两个关键意图：
1. **浏览器自动化任务** — 在目标网站上要做什么（导航、点击、提取等）
2. **生成稳定项目的请求** — 你需要一个能可靠运行的程序/项目

**执行流程：**

1. **Parse** — 从任务描述中提取 URL、目标和预期输出
2. **Setup** — 检查环境（uv、依赖、`.env`）
3. **Explore** — 委派 `browser-explorer` agent 通过 CLI 系统性探索目标网站
4. **Generate** — 委派 `amphibious-generator` agent 生成完整项目及所有源文件
5. **Verify** — 委派 `amphibious-verify` agent 注入调试插桩、运行项目、验证结果

### Agents

Agents 是由 commands 调度的执行专家，不由用户直接调用：

| Agent | 功能 |
|-------|------|
| **browser-explorer** | 通过 CLI 系统性探索网站，生成结构化的探索报告和快照 |
| **amphibious-generator** | 根据任务描述和探索报告生成完整的 bridgic-amphibious 项目 |
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
│   ├── browser-explorer.md      #   CLI 探索专家
│   ├── amphibious-generator.md  #   代码生成专家
│   └── amphibious-verify.md     #   项目验证专家
├── commands/                    # 用户可调用的工作流
│   └── build-browser.md         #   端到端流水线
├── examples/                    # 静态示例文档（不会被自动扫描）
│   ├── build-browser-code-patterns.md
│   └── build-browser-task-template.md
├── hooks/                       # 自动加载的事件处理器
│   └── hooks.json
└── scripts/                     # Hook 与工具脚本
    ├── hook/
    │   └── inject-command-paths.sh
    ├── run/
    │   ├── setup-env.sh         #   环境配置（uv、依赖、playwright）
    │   ├── check-dotenv.sh      #   LLM 模型配置校验
    │   └── monitor.sh
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
