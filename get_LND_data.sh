#!/bin/bash
chain=$1
color_green=$2
color_red=$3
ln_git_version=$4

echo -ne '\r### Loading LND data \r'

lnd_dir="/data/lnd"

if [ "${chain}" = "test" ]; then
  macaroon_path="${lnd_dir}/data/chain/bitcoin/testnet/readonly.macaroon"
else
  macaroon_path="${lnd_dir}/data/chain/bitcoin/mainnet/readonly.macaroon"
fi
lnd_running=$(systemctl is-active lnd)
lnd_color="${color_green}"
if [ -z "${lnd_running##*inactive*}" ]; then
  lnd_running="down"
  lnd_color="${color_red}\e[7m"
else
  if [ -z "${lnd_running##*failed*}" ]; then
    lnd_running="down"
    lnd_color="${color_red}\e[7m"
  else
    lnd_running="up"
  fi
fi
if [ -z "${lnd_running##*up*}" ] ; then
  lncli="/usr/local/bin/lncli --macaroonpath=${macaroon_path} --tlscertpath=${lnd_dir}/tls.cert"
  $lncli getinfo 2>&1 | grep "Please unlock" >/dev/null
  wallet_unlocked=$?
else
  wallet_unlocked=0
fi
printf "%0.s#" {1..63}
echo -ne '\r### Loading LND data \r'

if [ "$wallet_unlocked" -eq "0" ] ; then
  alias_color="${color_red}"
  ln_alias="Wallet Locked"
  ln_walletbalance="?"
  ln_channelbalance="?"
  ln_channels_online="?"
  ln_channels_total="?"
  ln_connect_addr=""
  ln_external=""
  ln_pendingopen="?"
  ln_pendingforce="?"
  ln_waitingclose="?"
  ln_pendinglocal="?"
  ln_sum_balance="?"
  if [ $lnd_running = "up" ]; then
    ln_connect_guidance="You must first unlock your wallet:   lncli unlock"
  else
    ln_connect_guidance="The LND service is down. Start the service:   sudo systemctl start lnd"
  fi
else
  alias_color="${color_grey}"
  ln_alias="$(${lncli} getinfo | jq -r '.alias')" 2>/dev/null
  ln_walletbalance="$(${lncli} walletbalance | jq -r '.confirmed_balance')" 2>/dev/null
  ln_channelbalance="$(${lncli} channelbalance | jq -r '.balance')" 2>/dev/null

  printf "%0.s#" {1..66}

  echo -ne '\r### Loading LND data \r'

  ln_channels_online="$(${lncli} getinfo | jq -r '.num_active_channels')" 2>/dev/null
  ln_channels_total="$(${lncli} listchannels | jq '.[] | length')" 2>/dev/null
  ln_connect_addr="$(${lncli} getinfo | jq -r '.uris[0]')" 2>/dev/null
  ln_connect_guidance="lncli connect ${ln_connect_addr}"
  ln_external="$(echo "${ln_connect_addr}" | tr "@" " " |  awk '{ print $2 }')" 2>/dev/null
  if [ -z "${ln_external##*onion*}" ]; then
    ln_external="Using TOR Address"
  fi

  printf "%0.s#" {1..70}
  echo -ne '\r### Loading LND data \r'

  ln_pendingopen=$($lncli pendingchannels  | jq '.pending_open_channels[].channel.local_balance|tonumber ' | awk '{sum+=$0} END{print sum}')
  if [ -z "${ln_pendingopen}" ]; then
    ln_pendingopen=0
  fi

  ln_pendingforce=$($lncli pendingchannels  | jq '.pending_force_closing_channels[].channel.local_balance|tonumber ' | awk '{sum+=$0} END{print sum}')
  if [ -z "${ln_pendingforce}" ]; then
    ln_pendingforce=0
  fi

  ln_waitingclose=$($lncli pendingchannels  | jq '.waiting_close_channels[].channel.local_balance|tonumber ' | awk '{sum+=$0} END{print sum}')
  if [ -z "${ln_waitingclose}" ]; then
    ln_waitingclose=0
  fi

  echo -ne '\r### Loading LND data \r'

  ln_pendinglocal=$((ln_pendingopen + ln_pendingforce + ln_waitingclose))

  ln_sum_balance=0
  if [ -n "${ln_channelbalance}" ]; then
    ln_sum_balance=$((ln_channelbalance + ln_sum_balance ))
  fi
  if [ -n "${ln_walletbalance}" ]; then
    ln_sum_balance=$((ln_walletbalance + ln_sum_balance ))
  fi
  if [ -n "$ln_pendinglocal" ]; then
    ln_sum_balance=$((ln_sum_balance + ln_pendinglocal ))
  fi
fi

#create variable lndversion
lndpi=$(lncli getinfo | sed -n 's/^\(.*\)=\(.\+\?\)"\(.*\)/\2/p')
if [ "${lndpi}" = "${ln_git_version}" ]; then
  lndversion="${lndpi}"
  lndversion_color="${color_green}"
else
  lndversion="${lndpi}"" Update!"
  lndversion_color="${color_red}"
fi

#get channel.db size
ln_channel_db_size=$(du -h ${lnd_dir}/data/graph/mainnet/channel.db | awk '{print $1}')

# Write to JSON file
lnd_infofile="${HOME}/.raspibolt.lndata.json"
lnd_color=$(echo $lnd_color | sed 's/\\/\\\\/g')
lndversion_color=$(echo $lndversion_color | sed 's/\\/\\\\/g')
alias_color=$(echo $alias_color| sed 's/\\/\\\\/g')
printf '{"ln_running":"%s","ln_version":"%s","ln_walletbalance":"%s","ln_channelbalance":"%s","ln_pendinglocal":"%s","ln_sum_balance":"%s","ln_channels_online":"%s","ln_channels_total":"%s","ln_channel_db_size":"%s","ln_color":"%s","ln_version_color":"%s","alias_color":"%s","ln_alias":"%s","ln_connect_guidance":"%s"}' "\
$lnd_running" "$lndversion" "$ln_walletbalance" "$ln_channelbalance" "$ln_pendinglocal" "$ln_sum_balance" "$ln_channels_online" "$ln_channels_total" "$ln_channel_db_size" "$lnd_color" "$lndversion_color" "$alias_color" "$ln_alias" "$ln_connect_guidance" > $lnd_infofile