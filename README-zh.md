# Bridgic Corpus

[English](README.md) | 中文

[Bridgic](https://github.com/bitsky-tech) 生态的 Agent 技能与知识语料库 — 提供 skills、agents 和 commands，用于构建 LLM 驱动与确定性双模执行的项目。

## 什么是 Bridgic Corpus？

Bridgic Corpus 是一个**语料库**，将领域知识和执行方法论封装为三层结构：

| 层级 | 角色 | 描述 |
|------|------|------|
| **Skills** | 领域知识 | "是什么、怎么用" — 按需加载的参考文档 |
| **Agents** | 执行方法论 | "怎么做好" — 专业化的执行专家 |
| **Commands** | 编排调度 | 协调 agents 和 skills 的多步骤工作流 |

三者协同实现端到端流水线：**通过 CLI 探索网站** -> **生成双模 agent 项目** -> **验证执行** — 全程在 agent 内完成。

## 安装

### 方式一：Claude Code 插件（完整体验 — skills + agents + commands）

```bash
# 第一步：注册 marketplace（仅需一次）
claude plugin marketplace add bitsky-tech/bridgic-corpus

# 第二步：安装插件
claude plugin install bridgic-corpus
```

或从本地仓库直接安装：

```bash
git clone https://github.com/bitsky-tech/bridgic-corpus.git
claude plugin install /path/to/bridgic-corpus
```

安装后，skills、agents 和 commands（如 `/browser-to-amphibious`）会自动在 Claude Code 中可用。

### 方式二：npx skills（单独安装 skills — 支持 40+ 种 Agent 产品）

将 skills 安装到任何支持的 agent 产品中（Claude Code、Cursor、Copilot、Cline 及[更多](https://github.com/vercel-labs/skills)）：

```bash
# 从 GitHub 安装单个 skill
npx skills add bitsky-tech/bridgic-corpus --skill bridgic-browser

# 一次安装全部 skills
npx skills add bitsky-tech/bridgic-corpus --all

# 从本地仓库安装
npx skills add . --skill bridgic-browser
```

可用的 skills：

| 名称 | 描述 |
|------|------|
| `bridgic-basic` | Bridgic 核心框架（Worker、Automa、GraphAutoma、ASL） |
| `bridgic-browser` | 浏览器自动化（CLI 或 Python SDK） |
| `bridgic-browser-agent` | 浏览器 Agent 模式（OOP + 动态 ref 解析） |
| `bridgic-amphibious` | 双模 Agent 框架（LLM 驱动 + 确定性执行） |
| `bridgic-llms` | LLM 提供商集成（OpenAI、OpenAILike、vLLM） |

> **注意：** `npx skills` 方式**仅安装 skills**。如需完整体验（agents、commands、hooks），请使用 Claude Code 插件安装。

## 使用

### Commands

Commands 是用户可直接调用的工作流：

#### `/browser-to-amphibious`

```
/browser-to-amphibious

Task: Go to https://example.com, search for "product", and extract the first 5 results
```

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
| **bridgic-basic** | 使用 Bridgic 核心框架（Worker、Automa、GraphAutoma、ASL） |
| **bridgic-browser** | 使用浏览器自动化 CLI（`bridgic-browser ...`）或 Python SDK（`from bridgic.browser`） |
| **bridgic-browser-agent** | 构建浏览器自动化 Agent（OOP 模式 + 动态 ref 解析） |
| **bridgic-amphibious** | 使用双模框架（`AmphibiousAutoma`、`CognitiveWorker`、`on_agent`/`on_workflow`） |
| **bridgic-llms** | 初始化 LLM 提供商（`OpenAILlm`、`OpenAILikeLlm`、`VllmServerLlm`） |

## 架构

```
bridgic-corpus/
├── .claude-plugin/
│   └── plugin.json              # 插件注册
├── skills/                      # 领域知识（5 个 skills）
│   ├── bridgic-basic/           #   核心框架概念
│   ├── bridgic-browser/         #   浏览器自动化 CLI + SDK
│   ├── bridgic-browser-agent/   #   浏览器 Agent 模式
│   ├── bridgic-amphibious/      #   双模 Agent 框架
│   └── bridgic-llms/            #   LLM 提供商集成
├── agents/                      # 执行方法论（3 个 agents）
│   ├── browser-explorer.md      #   CLI 探索专家
│   ├── amphibious-generator.md  #   代码生成专家
│   └── amphibious-verify.md     #   项目验证专家
├── commands/                    # 用户可调用的工作流
│   ├── browser-to-amphibious.md #   端到端流水线
│   └── references/
│       └── browser-code-patterns.md
├── hooks/                       # 自动加载的事件处理器
│   └── hooks.json
└── scripts/                     # Hook 与工具脚本
    ├── hook/
    │   └── inject-command-paths.sh
    └── run/
        ├── setup-env.sh            #   环境配置（uv、依赖、playwright）
        ├── check-dotenv.sh         #   LLM 模型配置校验
        └── monitor.sh
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

## 许可证

详见 [LICENSE](LICENSE)。
