#!/bin/bash
# /etc/systemd/system/raspibolt-pulse.sh
set -u

# make executable and copy script to /etc/update-motd.d/
# user must be able to execute bitcoin-cli and lncli

# Script configuration
# ------------------------------------------------------------------------------

# set datadir
bitcoin_dir="/data/bitcoin"
# Chose between LND and CLN
ln_implemenation="LND"

# set to mount point of secondary storage. This is used to calculate secondary USB usage %
ext_storage2nd="/mnt/ext"

# set to network device name (usually "eth0" for ethernet, and "wlan0" for wifi)
network_name="eth0"
#network_name="enp0s31f6"


# Helper functionality
# ------------------------------------------------------------------------------

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_grey='\033[0;37m'
color_orange='\033[38;5;208m'

# controlled abort on Ctrl-C
trap_ctrlC() {
  echo -e "\r"
  printf "%0.s " {1..80}
  printf "\n"
  exit
}

trap trap_ctrlC SIGINT SIGTERM

# print usage information for script
usage() {
  echo "RaspiBolt Welcome: system status overview
usage: bbb-cmd.sh [--help] [--mock]

This script can be run on startup: make it executable and
copy the script to /etc/update-motd.d/
"
}

# check script arguments
mockmode=0
if [[ ${#} -gt 0 ]]; then
  if [[ "${1}" == "-m" ]] || [[ "${1}" == "--mock" ]]; then
    mockmode=1
  else
    usage
    exit 0
  fi
fi


# Print first welcome message
# ------------------------------------------------------------------------------
printf "
${color_yellow}RaspiBolt %s:${color_grey} Sovereign \033[1m"₿"\033[22mitcoin full node
${color_yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
" "3"

# Gather system data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..40}
echo -ne '\r### Loading System data \r'

# get uptime & load
load=$(w|head -1|sed -E 's/.*load average: (.*)/\1/')
uptime=$(w|head -1|sed -E 's/.*up (.*),.*user.*/\1/'|sed -E 's/([0-9]* days).*/\1/')

# get CPU temp
cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
# cpu=$(cat /sys/class/thermal/thermal_zone3/temp)

temp=$((cpu/1000))
if [ ${temp} -gt 60 ]; then
  color_temp="${color_red}\e[7m"
elif [ ${temp} -gt 50 ]; then
  color_temp="${color_yellow}"
else
  color_temp="${color_green}"
fi

# get memory
ram_avail=$(free --mebi | grep Mem | awk '{ print $7 }')

if [ "${ram_avail}" -lt 100 ]; then
  color_ram="${color_red}\e[7m"
else
  color_ram=${color_green}
fi

# get storage
storage_free_ratio=$(printf "%.0f" "$(df | grep "/$" | awk '{ print $4/$2*100 }')") 2>/dev/null
storage=$(printf "%s" "$(df -h|grep '/$'|awk '{print $4}')") 2>/dev/null

if [ "${storage_free_ratio}" -lt 10 ]; then
  color_storage="${color_red}\e[7m"
else
  color_storage=${color_green}
fi

storage2nd_free_ratio=$(printf "%.0f" "$(df  | grep ${ext_storage2nd} | awk '{ print $4/$2*100 }')") 2>/dev/null
storage2nd=$(printf "%s" "$(df -h|grep ${ext_storage2nd}|awk '{print $4}')") 2>/dev/null

if [ -z "${storage2nd}" ]; then
  storage2nd="none"
  color_storage2nd=${color_grey}
else
  storage2nd="${storage2nd} free"
  if [ "${storage2nd_free_ratio}" -lt 10 ]; then
    color_storage2nd="${color_red}\e[7m"
  else
    color_storage2nd=${color_green}
  fi
fi

# get network traffic
network_rx=$(ip -h -s link show dev ${network_name} | grep -A1 RX | tail -1 | awk '{print $1}')
network_tx=$(ip -h -s link show dev ${network_name} | grep -A1 TX | tail -1 | awk '{print $1}')

# set lightning git repo URL
if [ $ln_implemenation = "CLN" ]; then
  ln_git_repo_url="https://api.github.com/repos/ElementsProject/lightning/releases/latest"
fi

if [ $ln_implemenation = "LND" ]; then
  ln_git_repo_url="https://api.github.com/repos/lightningnetwork/lnd/releases/latest"
fi

# Gather application versions
# ------------------------------------------------------------------------------

# GitHub calls for version info, limited to once a day
gitstatusfile="${HOME}/.raspibolt.versions"
gitupdate="0"
if [ ! -f "$gitstatusfile" ]; then
  gitupdate="1"
else
  gitupdate=$(find "${gitstatusfile}" -mtime +1 | wc -l)
fi
if [ "${gitupdate}" -eq "1" ]; then
  # Calls to github
  btcgit=$(curl -s https://api.github.com/repos/bitcoin/bitcoin/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')

  ln_git_version=$(curl -s $ln_git_repo_url | grep -oP '"tag_name": "\K(.*)(?=")')
  # Electrs, RPC Explorer and RTL dont have a latest release, just tags
  electrsgit=$(curl -s https://api.github.com/repos/romanz/electrs/tags | jq -r '.[0].name')
  btcrpcexplorergit=$(curl -s https://api.github.com/repos/janoside/btc-rpc-explorer/tags | jq -r '.[0].name')
  rtlgit=$(curl -s https://api.github.com/repos/Ride-The-Lightning/RTL/tags | jq -r '.[] | select(.name | test("rc") | not) | .name' | head -n 1)
  # write to file TODO: convert to JSON for sanity
  printf "%s\n%s\n%s\n%s\n%s\n" "${btcgit}" "${ln_git_version}" "${electrsgit}" "${btcrpcexplorergit}" "${rtlgit}" > "${gitstatusfile}"
else
  # read from file
  btcgit=$(sed -n '1p' < "${gitstatusfile}")
  ln_git_version=$(sed -n '2p' < "${gitstatusfile}")
  electrsgit=$(sed -n '3p' < "${gitstatusfile}")
  btcrpcexplorergit=$(sed -n '4p' < "${gitstatusfile}")
  rtlgit=$(sed -n '5p' < "${gitstatusfile}")

  # fill if not yet set
  if [ -z "$btcgit" ]; then
    btcgit=$(curl -s https://api.github.com/repos/bitcoin/bitcoin/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
  fi
  if [ -z "$ln_git_version" ]; then
    ln_git_version=$(curl -s $ln_git_repo_url | grep -oP '"tag_name": "\K(.*)(?=")')
  fi
  if [ -z "$electrsgit" ]; then
    electrsgit=$(curl -s https://api.github.com/repos/romanz/electrs/tags | jq -r '.[0].name')
  fi
  if [ -z "$btcrpcexplorergit" ]; then
    btcrpcexplorergit=$(curl -s https://api.github.com/repos/janoside/btc-rpc-explorer/tags | jq -r '.[0].name')
  fi
  if [ -z "$rtlgit" ]; then
    rtlgit=$(curl -s https://api.github.com/repos/Ride-The-Lightning/RTL/tags | jq -r '.[] | select(.name | test("rc") | not) | .name' | head -n 1)
  fi
  printf "%s\n%s\n%s\n%s\n%s\n" "${btcgit}" "${ln_git_version}" "${electrsgit}" "${btcrpcexplorergit}" "${rtlgit}" > "${gitstatusfile}"
fi

# create variable btcversion
btcpi=$(bitcoin-cli -version |sed -n 's/^.*version //p')
case "${btcpi}" in
  *"${btcgit}"*)
    btcversion="$btcpi"
    btcversion_color="${color_green}"
    ;;
  *)
    btcversion="$btcpi"" Update!"
    btcversion_color="${color_red}"
    ;;
esac


# Gather Bitcoin Core data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..50}
echo -ne '\r### Loading Bitcoin Core data \r'

bitcoind_running=$(systemctl is-active bitcoind)
bitcoind_color="${color_green}"
if [ -z "${bitcoind_running##*inactive*}" ]; then
  bitcoind_running="down"
  bitcoind_color="${color_red}\e[7m"
else
  bitcoind_running="up"
fi
btc_path=$(command -v bitcoin-cli)
if [ -n "${btc_path}" ]; then
  btc_title="itcoin"
  chain="$(bitcoin-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.chain')"

  btc_title="${btc_title} (${chain}net)"

  # get sync status
  block_chain="$(bitcoin-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.headers')"
  block_verified="$(bitcoin-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.blocks')"
  block_diff=$(("${block_chain}" - "${block_verified}"))

  progress="$(bitcoin-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.verificationprogress')"
  sync_percentage=$(printf "%.2f%%" "$(echo "${progress}" | awk '{print 100 * $1}')")

  if [ "${block_diff}" -eq 0 ]; then      # fully synced
    sync="OK"
    sync_color="${color_green}"
    sync_behind="[#${block_chain}]"
  elif [ "${block_diff}" -eq 1 ]; then    # fully synced
    sync="OK"
    sync_color="${color_green}"
    sync_behind="-1 block"
  elif [ "${block_diff}" -le 10 ]; then   # <= 10 blocks behind
    sync="Behind"
    sync_color="${color_red}"
    sync_behind="-${block_diff} blocks"
  else
    sync="In progress"
    sync_color="${color_red}"
    sync_behind="${sync_percentage}"
  fi

  # get mem pool transactions
  mempool="$(bitcoin-cli -datadir=${bitcoin_dir} getmempoolinfo | jq -r '.size')"

  # get connection info
  connections="$(bitcoin-cli -datadir=${bitcoin_dir} getnetworkinfo | jq .connections)"
  inbound="$(bitcoin-cli -datadir=${bitcoin_dir} getpeerinfo | jq '.[] | select(.inbound == true)' | jq -s 'length')"
  outbound="$(bitcoin-cli -datadir=${bitcoin_dir} getpeerinfo | jq '.[] | select(.inbound == false)' | jq -s 'length')"
fi

# create variable btcversion
btcpi=$(bitcoin-cli -version |sed -n 's/^.*version //p')
case "${btcpi}" in
  *"${btcgit}"*)
    btcversion="$btcpi"
    btcversion_color="${color_green}"
    ;;
  *)
    btcversion="$btcpi"" Update!"
    btcversion_color="${color_red}"
    ;;
esac


# Gather LN data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..60}
"/usr/local/bin/get_"$ln_implemenation"_data.sh" $chain $color_green $color_red $ln_git_version

lnd_infofile="${HOME}/.raspibolt.lndata.json"
ln_file_content=$(cat $lnd_infofile)
ln_color="$(echo $ln_file_content | jq -r '.ln_color')"
ln_version_color="$(echo $ln_file_content | jq -r '.ln_version_color')"
alias_color="$(echo $ln_file_content | jq -r '.alias_color')"
ln_running="$(echo $ln_file_content | jq -r '.ln_running')"
ln_version="$(echo $ln_file_content | jq -r '.ln_version')"
ln_walletbalance="$(echo $ln_file_content | jq -r '.ln_walletbalance')"
ln_channelbalance="$(echo $ln_file_content | jq -r '.ln_channelbalance')"
ln_pendinglocal="$(echo $ln_file_content | jq -r '.ln_pendinglocal')"
ln_sum_balance="$(echo $ln_file_content | jq -r '.ln_sum_balance')"
ln_channels_online="$(echo $ln_file_content | jq -r '.ln_channels_online')"
ln_channels_total="$(echo $ln_file_content | jq -r '.ln_channels_total')"
ln_channel_db_size="$(echo $ln_file_content | jq -r '.ln_channel_db_size')"
ln_connect_guidance="$(echo $ln_file_content | jq -r '.ln_connect_guidance')"
ln_alias="$(echo $ln_file_content | jq -r '.ln_alias')"






# Gather Electrs data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..74}
echo -ne '\r### Loading Electrum data \r'

electrs_running=$(systemctl is-active electrs)
electrs_color="${color_green}"
if [ -z "${electrs_running##*inactive*}" ]; then
  electrs_running="down"
  electrs_color="${color_red}\e[7m"
  electrsversion=""
  electrsversion_color="${color_red}"
else
  electrs_running="up"
  electrspi=$(echo '{"jsonrpc": "2.0", "method": "server.version", "params": [ "raspibolt", "1.4" ], "id": 0}' | netcat 127.0.0.1 50001 -q 1 | jq -r '.result[0]' | awk '{print "v"substr($1,9)}')
  if [ "$electrspi" = "$electrsgit" ]; then
    electrsversion="$electrspi"
    electrsversion_color="${color_green}"
  else
    electrsversion="$electrspi"" Update!"
    electrsversion_color="${color_red}"
  fi
fi


# Gather Bitcoin Explorer data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..76}
echo -ne '\r### Loading Block Explorer data \r'

#btcrpcexplorer
btcrpcexplorer_running=$(systemctl is-active btcrpcexplorer)
btcrpcexplorer_color="${color_green}"
if [ -z "${btcrpcexplorer_running##*inactive*}" ]; then
  btcrpcexplorer_running="down"
  btcrpcexplorer_color="${color_red}\e[7m"
  btcrpcexplorerversion=""
  btcrpcexplorerversion_color="${color_red}"
else
  btcrpcexplorer_running="up"
  btcrpcexplorerpi=v$(cd /home/btcrpcexplorer/btc-rpc-explorer; npm version | grep -oP "'btc-rpc-explorer': '\K(.*)(?=')")
  if [ "$btcrpcexplorerpi" = "$btcrpcexplorergit" ]; then
    btcrpcexplorerversion="$btcrpcexplorerpi"
    btcrpcexplorerversion_color="${color_green}"
  else
    btcrpcexplorerversion="$btcrpcexplorerpi"" Update!"
    btcrpcexplorerversion_color="${color_red}"
  fi
fi

# Gather RTL data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..78}
echo -ne '\r### Loading RTL data \r'

#rtl
rtl_running=$(systemctl is-active rtl)
rtl_color="${color_green}"
if [ -z "${rtl_running##*inactive*}" ]; then
  rtl_running="down"
  rtl_color="${color_red}\e[7m"
  rtlversion=""
  rtlversion_color="${color_red}"
else
  rtl_running="up"
  rtlpi=v$(cd /home/rtl/RTL; npm version | grep -oP "rtl: '\K(.*)(?=-beta')")
  if [ "$rtlpi" = "$rtlgit" ]; then
    rtlversion="$rtlpi"
    rtlversion_color="${color_green}"
  else
    rtlversion="$rtlpi"" Update!"
    rtlversion_color="${color_red}"
  fi
fi

# Mockmode overrides data for documentation images
# ------------------------------------------------------------------------------

if [ "${mockmode}" -eq 1 ]; then
  ln_alias="MyRaspiBolt-version3"
  ln_walletbalance="100000"
  ln_channelbalance="200000"
  ln_pendinglocal="50000"
  sum_balance="350000"
  ln_channels_online="34"
  ln_channels_total="36"
  ln_connect_guidance="lncli connect c55c05e9148e4e0f120835a6384348dd4d91f77bb1adf256694391bf81a07f03ef@klra7gtbc1j322399pq87bk47ny38brjomvfdg3vb6k3ggahan2dzlyd.onion:9735"
fi

# Render output
# ------------------------------------------------------------------------------

echo -ne "\033[2K"
printf "${color_grey}cpu temp: ${color_temp}%-2s°C${color_grey}  tx: %-10s storage:   ${color_storage}%-11s ${color_grey}  load: %s
${color_grey}up: %-10s  rx: %-10s 2nd drive: ${color_storage2nd}%-11s${color_grey}   available mem: ${color_ram}%sM
${color_yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${color_green}     .~~.   .~~.      ${color_yellow}\033[1m"₿"\033[22m%-19s${bitcoind_color}%-4s${color_grey}   ${color_yellow}%-20s${lnd_color}%-4s
${color_green}    '. \ ' ' / .'     ${btcversion_color}%-26s ${ln_version_color}%-24s
${color_red}     .~ .~~~${color_yellow}.${color_red}.~.      ${color_grey}Sync    ${sync_color}%-18s ${alias_color}%-24s
${color_red}    : .~.'${color_yellow}／/${color_red}~. :     ${color_grey}Mempool %-18s ${color_orange}\033[1m"₿"\033[22m${color_grey}%17s sat
${color_red}   ~ (  ${color_yellow}／ /_____${color_red}~    ${color_grey}Peers   %-22s ${color_grey}⚡%16s sat
${color_red}  ( : ${color_yellow}／____   ／${color_red} )                              ${color_grey}⏳%16s sat
${color_red}   ~ .~ (  ${color_yellow}/ ／${color_red}. ~    ${color_yellow}%-20s${electrs_color}%-4s   ${color_grey}∑%17s sat
${color_red}    (  : '${color_yellow}/／${color_red}:  )     ${electrsversion_color}%-26s ${color_grey}%s/%s channels
${color_red}     '~ .~${color_yellow}°${color_red}~. ~'                                 ${color_grey}Channel.db size: ${color_green}%s
${color_red}         '~'          ${color_yellow}%-20s${color_grey}${btcrpcexplorer_color}%-4s
${color_red}                      ${btcrpcexplorerversion_color}%-24s   ${color_yellow}%-20s${rtl_color}%-4s
${color_red}                                                 ${rtlversion_color}%-24s

${color_grey}For others to connect to this lightning node
${color_grey}%s

" \
"${temp}" "${network_tx}" "${storage} free" "${load}" \
"${uptime}" "${network_rx}" "${storage2nd}" "${ram_avail}" \
"${btc_title}" "${bitcoind_running}" "Lightning ($ln_implemenation)" "${ln_running}" \
"${btcversion}" "${ln_version}" \
"${sync} ${sync_behind}" "${ln_alias}" \
"${mempool} tx" "${ln_walletbalance}" \
"${connections} (📥${inbound} /📤${outbound})" "${ln_channelbalance}" \
"${ln_pendinglocal}" \
"Electrum" "${electrs_running}" "${ln_sum_balance}" \
"${electrsversion}" "${ln_channels_online}" "${ln_channels_total}" \
"${ln_channel_db_size}" \
"Block Explorer" "${btcrpcexplorer_running}" \
"${btcrpcexplorerversion}" "RTL" "${rtl_running}" \
"${rtlversion}" \
"${ln_connect_guidance}"
