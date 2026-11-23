#!/bin/bash
# locate.sh — 定位層（IP 主 + BSSID 街廓條件增強）
# 主力: ip-api.com  城市/ISP級, 不需權限    闔蓋睡後停
# 增強: BSSID→Apple WPS  街廓級, 需拿到BSSID（新版macOS多半遮罩→優雅降級）
# 兜底/精確: Apple Find My 靠另一台裝置查，本機不做
# 來源: source locate.sh （需先 source log.sh）

LOCATE_CACHE=""
LOCATE_CITY_ONLY="${LOCATE_CITY_ONLY:-1}"   # log 內只留城市級，遮精確座標

# IP 定位（城市級）— ip-api 免費層 IPv4 需 http（https 要付費 key）
locate_ip() {
  local r
  r="$(curl -m8 -s "http://ip-api.com/json/" 2>/dev/null)"
  [ -z "$r" ] && { la_log_to locate WARN locate "ip-api no response"; return 1; }
  # status:fail 用不可用
  if printf '%s' "$r" | grep -q '"status":"fail"'; then
    la_log_to locate WARN locate "ip-api status:fail"
    return 1
  fi
  local lat lon city region country isp
  lat="$(printf '%s' "$r" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("lat",0))
except: print("")' 2>/dev/null)"
  lon="$(printf '%s' "$r" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("lon",0))
except: print("")' 2>/dev/null)"
  city="$(printf '%s' "$r" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("city",""))
except: print("")' 2>/dev/null)"
  region="$(printf '%s' "$r" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("regionName",""))
except: print("")' 2>/dev/null)"
  country="$(printf '%s' "$r" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("country",""))
except: print("")' 2>/dev/null)"
  isp="$(printf '%s' "$r" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("isp",""))
except: print("")' 2>/dev/null)"
  la_log_to locate INFO locate "ip: ${city},${region}(${country}) isp=${isp}"   # 座標本身不落 log（遮）
  printf 'city=%s\nregion=%s\ncountry=%s\nlat=%s\nlon=%s\nisp=%s\n' "$city" "$region" "$country" "$lat" "$lon" "$isp"
  return 0
}

# 取 Wi-Fi BSSID（新版 macOS 需 Location TCC，拿不到→空，讀者自行降級）
locate_bssid() {
  local iface bssid
  iface="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline;print $2}')"
  [ -z "$iface" ] && { la_log_to locate WARN locate "bssid: no wifi iface"; return 1; }
  bssid="$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null \
    | awk '/BSSID/{print $2}')"
  [ -z "$bssid" ] || [ "$bssid" = "00:00:00:00:00:00" ] && {
    la_log_to locate WARN locate "bssid: masked/denied (new macOS)"
    # 優雅降級：不放錯誤，靜默回空
    return 1
  }
  printf '%s\n' "$bssid"
}

# BSSID 條件增強（僅當能拿到 BSSID 才走 Apple WPS 街廓定位）
locate_wps() {
  local bssid; bssid="$(locate_bssid)" || return 1
  # acheong08/apple-corelocation-experiments BSSID→WPS 想法（本機多半天遮罩，列可選不主線）
  # Apple WPS 需要 wifi provider + 協定；此處留 seam，實作放 deploy checklist 附註
  la_log_to locate INFO locate "bssid=$bssid → wps seam (進階)"
  printf 'bssid=%s\n' "$bssid"
}

# 統一入口
locate_once() {
  if [ "${LOCATE_WPS_ENABLED:-0}" = "1" ]; then
    local b; b="$(locate_wps 2>/dev/null)" && { printf '%s\n' "$b"; return 0; }
  fi
  locate_ip
}