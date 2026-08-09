# Ether Guard v2

多層 AI 代理人防禦框架，基於 Google DeepMind「AI Agent Traps」分類。

## 六層防禦

| 層級 | 腳本 | 防護目標 |
|------|------|---------|
| 1 | `claude-safe-guard.sh` | 專案配置注入（`.mcp.json`、`.claude/settings.*.json`） |
| 2 | `content-guard.sh` | 內容注入 + 語義操縱（隱藏指令、權威壓力） |
| 3 | `memory-guard.sh` | RAG/記憶體中毒（嵌入指令、編碼欺騙） |
| 4 | `tool-use-guard.sh` | 行為控制（危險命令、base64 隱寫） |
| 5 | *(規劃中)* | 系統性陷阱（多 agent 協調監控） |
| 6 | *(規劃中)* | 人機環路（決策疲勞、自動化偏誤） |

## 安裝

```bash
cd ~/dev/ether-guard
./install-v2.sh
source ~/.zshrc
```

## 使用

```bash
# 掃描單一檔案
ether-guard scan <file>

# 驗證 tool 呼叫
ether-guard check <tool_name> '<args_json>'

# 完整目錄掃描
ether-guard all <directory>

# 說明
ether-guard help
```

## 設計原則

- **漸進式防護**：每層獨立，可單獨啟用
- **低誤判**：預設只擋已知攻擊模式
- **可組合**：不同陷阱可以串聯，防禦也應如此

## 參考

- [AI Agent Traps](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6372438) - Google DeepMind, 2026
- [Prompt Guard](https://github.com/seojoonkim/prompt-guard) - 檢測引擎
- [Lasso Security](https://github.com/lasso-security/claude-hooks) - Claude Code hooks
