// lockcheck.swift — 讀取當前螢幕鎖定狀態（不需 TCC / 不需 pyobjc）
// 用法: lockcheck   → 輸出 1（已鎖）/ 0（未鎖）
// 安裝時 install.sh 編譯成 ~/.eguard/bin/lockcheck 小二進位，guard.sh 迴圈直接呼叫（避免每次 poll 重編譯）
import CoreGraphics
import Foundation

let d = CGSessionCopyCurrentDictionary()
var locked = 0
if let d = d as? [String: Any] {
    locked = (d["CGSSessionScreenIsLocked"] as? Int) ?? 0
}
print(locked)