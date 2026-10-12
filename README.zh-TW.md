# Ether Guard v2

[English](README.md) | **繁體中文**

以 Google DeepMind「AI Agent Traps」分類為基礎的多層 AI 代理人防禦框架。每一層都是
獨立的 Bash 腳本：可以整套安裝，也可以單獨執行。

## 快速安裝

```bash
git clone https://github.com/royalskynet/ether-guard.git && cd ether-guard && ./install-v2.sh
```

安裝完再開一個新的終端機視窗，讓 `ether-guard` 指令生效：

```bash
source ~/.zshrc
```

安裝程式會把所有防護腳本複製到 `~/.claude/scripts/`、加上執行權限，並把
`ether-guard` shell wrapper 寫進 `~/.zshrc` 與 `~/.bashrc`。只會修改「已經存在」的
shell 設定檔，不會寫入家目錄以外的位置，重複執行也不會出錯。

## 兩支安裝程式

| 腳本 | 安裝內容 |
|------|----------|
| `install-v2.sh` | 全部五支防護腳本，加上 `ether-guard` wrapper 函式（建議用這支） |
| `install.sh` | 只裝 `claude-safe-guard.sh`，並加上在啟動 `claude` 前掃描目前目錄的 wrapper |

## 六層防禦

| 層級 | 腳本 | 防護目標 |
|------|------|----------|
| 1 | `claude-safe-guard.sh` | 專案配置注入（`.mcp.json`、`.claude/settings.*.json`） |
| 2 | `content-guard.sh` | 內容注入 + 語義操縱（隱藏指令、權威壓力） |
| 3 | `memory-guard.sh` | RAG／記憶體中毒（嵌入指令、編碼欺騙） |
| 4 | `tool-use-guard.sh` | 行為控制（危險指令、base64 隱寫） |
| 5 | *(規劃中)* | 系統性陷阱（多 agent 協調監控） |
| 6 | *(規劃中)* | 人機環路（決策疲勞、自動化偏誤） |

## 使用方式

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

沒有安裝也可以直接在 clone 下來的目錄執行：

```bash
bash ether-guard.sh help
bash ether-guard.sh check Bash '{"command":"rm -rf ~"}'
```

所有模式的結束代碼一致：`0` 乾淨、`1` 警告、`2` 阻擋。

## 已知限制

以下是腳本目前的實際行為，不是設計目標：

- `scan` 會把**第一個參數當成數值型的分數門檻**，所以 `ether-guard scan <file>`
  會讓第二層印出 `integer expression expected` 並以 `1` 結束；要真的阻擋請用
  `ether-guard scan 1 <file>`（結束代碼 `2`）。
- `all` 只會走第一到第三層；第四層要透過 `check` 才會執行。
- 第三層在掃描目錄時，分數是在管線的子殼層裡累加，會被丟掉，因此目錄掃描結果永遠
  顯示乾淨。
- 第三層的編碼檢查使用 `grep -P`，macOS 內建的 BSD `grep` 不支援 `-P`，該項檢查會
  被靜默略過。
- 第一層是字串比對的 `grep`，不是 JSON 解析器（腳本自己的註解也這麼寫），刻意
  偽造的設定檔有可能閃過；若需要抗閃過能力，可改用 `jq` 檢查。

## 設計原則

- **漸進式防護**：每層獨立，可單獨啟用。
- **低誤判**：預設只擋已知攻擊模式。
- **可組合**：不同陷阱可以串聯，防禦也應如此。

## 參考

- [AI Agent Traps](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6372438) - Google DeepMind, 2026
- [Prompt Guard](https://github.com/seojoonkim/prompt-guard) - 偵測引擎參考
- [Lasso Security](https://github.com/lasso-security/claude-hooks) - Claude Code hooks 參考

## 授權

MIT，詳見 [LICENSE](LICENSE)。