#!/bin/bash

COIN_NAME='raptoreum'

#wallet information
BOOTSTRAP_TAR='https://www.dropbox.com/s/y885aysstdmro4n/rtm-bootstrap.tar.gz'
CONFIG_DIR='.raptoreumcore'
CONFIG_FILE='raptoreum.conf'
PORT='10226'
SSHPORT='22'
COIN_DAEMON='raptoreumd'
COIN_CLI='raptoreum-cli'
COIN_TX='raptoreum-tx'
COIN_PATH='/usr/local/bin'
USERNAME="$(whoami)"

#color codes
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[38;5;27m'
SEA='\033[38;5;49m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
BLINKRED='\033[1;31;5m'
NC='\033[0m'
STOP='\e[0m'

#emoji codes
X_POINT="${BLINKRED}\xE2\x9D\x97${NC}"

#end of required details
#


echo -e "${YELLOW}==========================================================="
echo -e 'RTM Smartnode Setup'
echo -e "===========================================================${NC}"
echo -e "${BLUE}July 2021, created and updated by dk808 from AltTank${NC}"
echo -e "${BLUE}With Smartnode healthcheck by Delgon${NC}"
echo -e
echo -e "${CYAN}Node setup starting, press [CTRL-C] to cancel.${NC}"
sleep 5
if [ "$USERNAME" = "root" ]; then
  echo -e "${CYAN}You are currently logged in as ${NC}root${CYAN}, please switch to a sudo user.${NC}"
  exit
fi

#functions
function wipe_clean() {
  echo -e "${YELLOW}Removing any instances of RTM...${NC}"
  sudo systemctl stop $COIN_NAME > /dev/null 2>&1
  sudo $COIN_CLI stop > /dev/null 2>&1
  sudo killall $COIN_DAEMON > /dev/null 2>&1
  sudo rm /usr/local/bin/$COIN_NAME* > /dev/null 2>&1
  sudo rm /usr/bin/$COIN_NAME* > /dev/null 2>&1
  sudo systemctl stop miner > /dev/null 2>&1
  sudo killall miner > /dev/null 2>&1
  rm -rf $HOME/$CONFIG_DIR > /dev/null 2>&1
  rm -rf $HOME/miner > /dev/null 2>&1
  rm update.sh check.sh update_miner.sh > /dev/null 2>&1
  rm -rf sentinel
}

function ssh_port() {
  echo -e "${YELLOW}Detecting SSH port being used...${NC}"
  SSHPORT=$(grep -w Port /etc/ssh/sshd_config | sed -e 's/.*Port //')
  if ! whiptail --yesno "Detected you are using $SSHPORT for SSH is this correct?" 8 56; then
    SSHPORT=$(whiptail --inputbox "Please enter port you are using for SSH" 8 43 3>&1 1>&2 2>&3)
    echo -e "${YELLOW}Using SSH port:${SEA} $SSHPORT${NC}"
  else
    echo -e "${YELLOW}Using SSH port:${SEA} $SSHPORT${NC}"
  fi
}

function ip_confirm() {
  echo -e "${YELLOW}Detecting IP address being used...${NC}"
  WANIP=$(wget http://ipecho.net/plain -O - -q)
  if ! whiptail --yesno "Detected IP address is $WANIP is this correct?" 8 60; then
    WANIP=$(whiptail --inputbox "        Enter IP address" 8 36 3>&1 1>&2 2>&3)
  fi
}

FORCE_SWAP=""
function create_swap() {
  echo -e "${YELLOW}Creating swap if none detected...${NC}"
  if ! grep -q "swapfile" /etc/fstab; then
    if [[ $FORCE_SWAP == "true" ]]; then
      sudo fallocate -l 4G /swapfile
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile
      sudo swapon /swapfile
      echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
      echo -e "${YELLOW}Created ${SEA}4G${YELLOW} swapfile${NC}"
    elif [[ -z $FORCE_SWAP ]]; then
      if whiptail --yesno "No swapfile detected would you like to create one?" 8 54; then
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        echo -e "${YELLOW}Created ${SEA}4G${YELLOW} swapfile${NC}"
      fi
    fi
  fi
}


function spinning_timer() {
  animation=( ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏ )
  end=$((SECONDS+NUM))
  while [ $SECONDS -lt $end ]; do
    for i in "${animation[@]}"; do
      echo -ne "${RED}\r$i ${CYAN}${MSG1}${NC}"
      sleep 0.1
    done
  done
  echo -e "${MSG2}"
}

smartnodeblsprivkey=""
function create_conf() {
  if [[ ! -z $1 ]]; then
    while [[ -z $smartnodeblsprivkey ]]; do
      smartnodeblsprivkey=$(whiptail --inputbox "Enter your SmartNode BLS Privkey" 8 75 3>&1 1>&2 2>&3)
    done
    return
  fi
  if [[ -f $HOME/$CONFIG_DIR/$CONFIG_FILE ]]; then
    echo -e "${CYAN}Existing conf file found backing up to $COIN_NAME.old ...${NC}"
    mv $HOME/$CONFIG_DIR/$CONFIG_FILE $HOME/$CONFIG_DIR/$COIN_NAME.old;
  fi
  RPCUSER=$(pwgen -1 8 -n)
  PASSWORD=$(pwgen -1 20 -n)
  while [[ -z $smartnodeblsprivkey ]]; do
    smartnodeblsprivkey=$(whiptail --inputbox "Enter your SmartNode BLS Privkey" 8 75 3>&1 1>&2 2>&3)
  done
  echo -e "${YELLOW}Creating Conf File...${NC}"
  mkdir $HOME/$CONFIG_DIR > /dev/null 2>&1
  touch $HOME/$CONFIG_DIR/$CONFIG_FILE
  cat << EOF > $HOME/$CONFIG_DIR/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$PASSWORD
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
port=$PORT
server=1
daemon=1
listen=1
smartnodeblsprivkey=$smartnodeblsprivkey
externalip=$WANIP
addnode=explorer.raptoreum.com
addnode=raptor.mopsus.com
maxconnections=256
EOF
}

SECURITY_ANS=""
# If $1 is provided, just ask about bootstrap.
function basic_security() {
  if [[ ! -z $1 ]]; then
    if whiptail --yesno "Would you like to setup basic firewall and fail2ban?" 8 56; then
      SECURITY_ANS="true"
    fi
  elif [[ $SECURITY_ANS == "true" ]]; then
    echo -e "${YELLOW}Configuring firewall and enabling fail2ban...${NC}"
    sudo apt-get install ufw fail2ban -y
    sudo ufw allow $SSHPORT/tcp
    sudo ufw allow $PORT/tcp
    sudo ufw logging on
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw limit OpenSSH
    echo "y" | sudo ufw enable > /dev/null 2>&1
    sudo touch /etc/fail2ban/jail.local
    sudo chown $USERNAME:$USERNAME /etc/fail2ban/jail.local
    cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $SSHPORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    sudo chown root:root /etc/fail2ban/jail.local
    sudo systemctl restart fail2ban > /dev/null 2>&1
    sudo systemctl enable fail2ban > /dev/null 2>&1
  else
    echo -e "${YELLOW}Skipping basic security...${NC}"
  fi
}

BOOTSTRAP_ANS=""
# If $1 is provided, just ask about bootstrap.
function bootstrap() {
  if [[ ! -z $1 ]]; then
    if whiptail --yesno "Would you like to bootstrap the chain?" 8 42; then
      BOOTSTRAP_ANS="true"
    fi
  elif [[ $BOOTSTRAP_ANS == "true" ]]; then
    echo -e "${YELLOW}Downloading wallet bootstrap please be patient...${NC}"
    curl -L $BOOTSTRAP_TAR | tar xz -C $HOME/$CONFIG_DIR
  else
    echo -e "${YELLOW}Skipping bootstrap...${NC}"
  fi
}

CRON_ANS=""
PROTX_HASH=""
# If $1 is provided, just ask about bootstrap.
function cron_job() {
  if [[ ! -z $1 ]]; then
    if whiptail --yesno "Would you like Cron to check on daemon's health every 15 minutes?" 8 63; then
      CRON_ANS="true"
      PROTX_HASH=$(whiptail --inputbox "Please enter your protx hash for this SmartNode" 8 51 3>&1 1>&2 2>&3)
    fi
  elif [[ $CRON_ANS == "true" ]]; then
    cat <(curl -s https://raw.githubusercontent.com/michal-zurkowski/Raptoreum_Smartnode/miner/check.sh) >$HOME/check.sh 
    sed -i "s/#NODE_PROTX=/NODE_PROTX=\"${PROTX_HASH}\"/g" $HOME/check.sh
    sudo chmod 775 $HOME/check.sh
    crontab -l | grep -v "SHELL=/bin/bash" | crontab -
    crontab -l | grep -v "RAPTOREUM_CLI=$(which $COIN_CLI)" | crontab -
    crontab -l | grep -v "HOME=$HOME" | crontab -
    crontab -l | grep -v "$HOME/check.sh >> $HOME/check.log" | crontab -
    crontab -l > tempcron
    echo "SHELL=/bin/bash" >> tempcron
    echo "RAPTOREUM_CLI=$(which $COIN_CLI)" >> tempcron
    echo "HOME=$HOME" >> tempcron
    echo "*/15 * * * * $HOME/check.sh >> $HOME/check.log" >> tempcron
    crontab tempcron
    rm tempcron
    rm -f /tmp/height 2>/dev/null
    rm -f /tmp/pose_score 2>/dev/null
    rm -f /tmp/was_stuck 2>/dev/null
    rm -f /tmp/prev_stuck 2>/dev/null
  fi
}

function install_packages() { 
  echo -e "${YELLOW}Installing Packages...${NC}"
  sudo apt-get update -y
  sudo apt-get upgrade -y
  sudo apt-get install nano htop pwgen figlet unzip jq -y
  echo -e "${YELLOW}Packages complete...${NC}"
}

function install_bins() {
  echo -e "${YELLOW}Installing latest binaries...${NC}"
  WALLET_TAR=$(curl -s https://api.github.com/repos/Raptor3um/raptoreum/releases/latest | jq -r '.assets[] | select(.name|test("ubuntu18.")) | .browser_download_url')
  mkdir temp
  curl -L $WALLET_TAR | tar xz -C ./temp; sudo mv ./temp/$COIN_DAEMON ./temp/$COIN_CLI ./temp/$COIN_TX $COIN_PATH
  sudo chmod 755 ${COIN_PATH}/${COIN_NAME}*
  rm -rf temp
}

function create_service() {
  echo -e "${YELLOW}Creating RTM service...${NC}"
  sudo touch /etc/systemd/system/$COIN_NAME.service
  sudo chown $USERNAME:$USERNAME /etc/systemd/system/$COIN_NAME.service
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
Type=forking
User=$USERNAME
Group=$USERNAME
WorkingDirectory=/home/$USERNAME/$CONFIG_DIR/
ExecStart=$COIN_PATH/$COIN_DAEMON -datadir=/home/$USERNAME/$CONFIG_DIR/ -conf=/home/$USERNAME/$CONFIG_DIR/$CONFIG_FILE -daemon
ExecStop=$COIN_PATH/$COIN_CLI stop
Restart=always
RestartSec=3
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF
  sudo chown root:root /etc/systemd/system/$COIN_NAME.service
  sudo systemctl daemon-reload
  sudo systemctl enable $COIN_NAME > /dev/null 2>&1
}

function start_daemon() {
  NUM='180'
  MSG1='Starting daemon service & syncing chain please be patient this will take few min...'
  MSG=''
  if sudo systemctl start $COIN_NAME > /dev/null 2>&1; then
    echo && spinning_timer
    NUM='5'
    MSG1='Getting blockchain info...'
    MSG2=''
    echo && spinning_timer
    echo
    $COIN_CLI getblockchaininfo
  else
    echo -e "${RED}Something is not right the daemon did not start. Will exit out so try and run the script again.${NC}"
    exit
  fi
}

function log_rotate() {
  echo -e "${YELLOW}Configuring logrotate function for debug log...${NC}"
  if [ -f /etc/logrotate.d/rtmdebuglog ]; then
    echo -e "${YELLOW}Existing log rotate conf found, backing up to ~/rtmdebuglogrotate.old ...${NC}"
    sudo mv /etc/logrotate.d/rtmdebuglog ~/rtmdebuglogrotate.old
  fi
  sudo touch /etc/logrotate.d/rtmdebuglog
  sudo chown $USERNAME:$USERNAME /etc/logrotate.d/rtmdebuglog
  cat << EOF > /etc/logrotate.d/rtmdebuglog
/home/$USERNAME/.raptoreumcore/debug.log {
  compress
  copytruncate
  missingok
  daily
  rotate 7
}
EOF
  sudo chown root:root /etc/logrotate.d/rtmdebuglog
}

function update_script() {
  echo -e "${YELLOW}Creating a script to update binaries for future updates...${NC}"
  touch $HOME/update.sh
  cat << EOF > $HOME/update.sh
#!/bin/bash
WALLET_TAR=\$(curl -s https://api.github.com/repos/Raptor3um/raptoreum/releases/latest | jq -r '.assets[] | select(.name|test("ubuntu18.")) | .browser_download_url')
COIN_NAME='raptoreum'
COIN_DAEMON='raptoreumd'
COIN_CLI='raptoreum-cli'
COIN_TX='raptoreum-tx'
COIN_PATH='/usr/local/bin'
sudo systemctl stop \$COIN_NAME
\$COIN_CLI stop > /dev/null 2>&1 && sleep 2
sudo killall \$COIN_DAEMON > /dev/null 2>&1
mkdir temp
curl -L \$WALLET_TAR | tar xz -C ./temp; sudo mv ./temp/\$COIN_DAEMON ./temp/\$COIN_CLI ./temp/\$COIN_TX \$COIN_PATH
rm -rf temp
sudo chmod 755 \${COIN_PATH}/\${COIN_NAME}*
sudo systemctl start \$COIN_NAME > /dev/null 2>&1
EOF
  sudo chmod 775 $HOME/update.sh
}

function create_motd() {
  touch $HOME/99-smartnode
  sudo cat << EOF >$HOME/99-smartnode
#!/bin/bash
COIN_NAME='raptoreum'
COIN_CLI='raptoreum-cli'

#color codes
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[38;5;27m'
SEA='\033[38;5;49m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
BLINKRED='\033[1;31;5m'
NC='\033[0m'
STOP='\e[0m'
X_POINT="\${BLINKRED}\xE2\x9D\x97\${NC}"

printf "\${BLUE}"
figlet -t -k "RTM  SMARTNODES"
printf "\${STOP}"

echo -e "\${YELLOW}================================================================================================"
echo -e "\${CYAN}COURTESY OF DK808 FROM ALTTANK ARMY\${NC}"
echo -e "\${CYAN}Smartnode healthcheck by Delgon\${NC}"
echo
echo -e "\${YELLOW}Commands to manage \$COIN_NAME service\${NC}"
echo -e "  TO START- \${CYAN}sudo systemctl start \$COIN_NAME\${NC}"
echo -e "  TO STOP - \${CYAN}sudo systemctl stop \$COIN_NAME\${NC}"
echo -e "  STATUS  - \${CYAN}sudo systemctl status \$COIN_NAME\${NC}"
echo -e "In the event server \${RED}reboots\${NC} daemon service will \${GREEN}auto-start\${NC}"
echo
echo -e "\${X_POINT}\${X_POINT} \${YELLOW}To use \$COIN_CLI simply start command with \$COIN_CLI" \${X_POINT}\${X_POINT}
echo -e "     \${YELLOW}E.g \${CYAN}\$COIN_CLI getblockchaininfo\${NC}"
echo -e "     \${YELLOW}E.g \${CYAN}\$COIN_CLI smartnode status\${NC}"
echo
echo -e "\${YELLOW}To update binaries when new ones are released enter \${SEA}./update.sh\${NC}"
echo -e "\${YELLOW}================================================================================================\${NC}"
EOF
  sudo chmod 775 $HOME/99-smartnode
  bash $HOME/99-smartnode
  sudo cp $HOME/99-smartnode /etc/update-motd.d 2>/dev/null
  sudo chown root:root /etc/update-motd.d 2>/dev/null
  rm $HOME/99-smartnode
}


MINER_ANS=""
MINER_INST=""
POOL=""
WORKER_ADDRESS=""
WORKER_NAME=""
THREAD_COUNT=$(nproc)
THREADS=""
TUNE="--tune-full"
# If $1 is provided, just ask about bootstrap.
function gr_miner () {
  if [[ ! -z $1 ]]; then
    if whiptail --yesno "Would you like to install the miner?" 8 40; then
      if whiptail --yesno "\
Please take notice that most cloud services do not allow\n\
mining and could result in your account being banned.\n\
Please read the provider's ToS before starting mining service.\n\
Would you like to install the miner anyway?" 11 67; then
        MINER_ANS="true"
        echo -e "${YELLOW}Checking hardware..."
        
        POOL_CHOICE=$(whiptail --menu "Select MAIN pool to use" 14 55 6 \
          "1" "stratum+tcp://eu.flockpool.com:4444" \
          "2" "stratum+tcp://us.flockpool.com:4444" \
          "3" "stratum+tcp://asia.flockpool.com:4444" \
          "4" "stratum+tcp://r-pool.net:3008" \
          "5" "stratum+tcp://r-pool.net:3032" \
          "6" "stratum+tcp://rtm.suprnova.cc:6273" \
          "7" "stratum+tcp://stratum.us-la1.suprnova.cc:6273" \
          "8" "stratum+tcp://stratum.us-ny1.suprnova.cc:6273" \
          "9" "stratum+tcp://stratum.apac-hkg1.suprnova.cc:6273" 3>&1 1>&2 2>&3)
        case $POOL_CHOICE in
          1)
            echo -e "Selected EU Flockpool"
            POOL="stratum+tcp:\/\/eu.flockpool.com:4444"
          ;;
          2)
            echo -e "Selected US Flockpool"
            POOL="stratum+tcp:\/\/us.flockpool.com:4444"
          ;;
          3)
            echo -e "Selected ASIA Flockpool"
            POOL="stratum+tcp:\/\/asia.flockpool.com:4444"
          ;;
          4)
            echo -e "Selected r-pool for miners with <1kh/s."
            POOL="stratum+tcp:\/\/r-pool.net:3008"
          ;;
          5)
            echo -e "Selected r-pool for miners with >1kh/s."
            POOL="stratum+tcp:\/\/r-pool.net:3032"
          ;;
          6)
            echo -e "Selected EU Suprnova pool."
            POOL="stratum+tcp:\/\/rtm.suprnova.cc:6273"
          ;;
          7)
            echo -e "Selected West Coast US Suprnova pool."
            POOL="stratum+tcp:\/\/stratum.us-la1.suprnova.cc:6273"
          ;;
          8)
            echo -e "Selected East Coast US Suprnova pool."
            POOL="stratum+tcp:\/\/stratum.us-ny1.suprnova.cc:6273"
          ;;
          9)
            echo -e "Selected Asia Suprnova pool."
            POOL="stratum+tcp:\/\/stratum.apac-hkg1.suprnova.cc:6273"
          ;;
        esac
        BACKUP_POOL_CHOICE=$(whiptail --menu "Select BACKUP pool to use" 14 55 6 \
          "1" "stratum+tcp://eu.flockpool.com:4444" \
          "2" "stratum+tcp://us.flockpool.com:4444" \
          "3" "stratum+tcp://asia.flockpool.com:4444" \
          "4" "stratum+tcp://r-pool.net:3008" \
          "5" "stratum+tcp://r-pool.net:3032" \
          "6" "stratum+tcp://rtm.suprnova.cc:6273" \
          "7" "stratum+tcp://stratum.us-la1.suprnova.cc:6273" \
          "8" "stratum+tcp://stratum.us-ny1.suprnova.cc:6273" \
          "9" "stratum+tcp://stratum.apac-hkg1.suprnova.cc:6273" 3>&1 1>&2 2>&3)
        case $BACKUP_POOL_CHOICE in
          1)
            echo -e "Selected EU Flockpool"
            BACKUP_POOL="stratum+tcp:\/\/eu.flockpool.com:4444"
          ;;
          2)
            echo -e "Selected US Flockpool"
            BACKUP_POOL="stratum+tcp:\/\/us.flockpool.com:4444"
          ;;
          3)
            echo -e "Selected ASIA Flockpool"
            BACKUP_POOL="stratum+tcp:\/\/asia.flockpool.com:4444"
          ;;
          4)
            echo -e "Selected r-pool for miners with <1kh/s."
            BACKUP_POOL="stratum+tcp:\/\/r-pool.net:3008"
          ;;
          5)
            echo -e "Selected r-pool for miners with >1kh/s."
            BACKUP_POOL="stratum+tcp:\/\/r-pool.net:3032"
          ;;
          6)
            echo -e "Selected EU Suprnova pool."
            BACKUP_POOL="stratum+tcp:\/\/rtm.suprnova.cc:6273"
          ;;
          7)
            echo -e "Selected West Coast US Suprnova pool."
            BACKUP_POOL="stratum+tcp:\/\/stratum.us-la1.suprnova.cc:6273"
          ;;
          8)
            echo -e "Selected East Coast US Suprnova pool."
            BACKUP_POOL="stratum+tcp:\/\/stratum.us-ny1.suprnova.cc:6273"
          ;;
          9)
            echo -e "Selected Asia Suprnova pool."
            BACKUP_POOL="stratum+tcp:\/\/stratum.apac-hkg1.suprnova.cc:6273"
          ;;
        esac
        WORKER_ADDRESS=$(whiptail --inputbox "Please enter RTM address you want pool to payout to" 8 55 3>&1 1>&2 2>&3)
        WORKER_NAME=$(whiptail --inputbox "Enter a worker name" 8 35 3>&1 1>&2 2>&3)
        THREAD_COUNT=$(grep -c processor /proc/cpuinfo)
        THREADS=$(whiptail --inputbox "Detected server has $THREAD_COUNT threads to use. How many threads would you like to mine with?" 8 50 3>&1 1>&2 2>&3)
        if [[ -z $THREADS ]]; then
          THREADS=$THREAD_COUNT
        fi
      fi
    fi
  elif [[ $MINER_ANS == "true" ]]; then
    echo -e "${YELLOW}Setting up miner installation...${NC}"
    echo -e "Creating directory..."
    rm -f $HOME/miner.sh 2>/dev/null
    echo -e "Installing required libraries..."
    sudo apt-get install unzip jq p7zip-full libssl-dev libcurl4-openssl-dev libjansson-dev libgmp-dev libnuma-dev -y
    echo -e "Checking distro version..."
    echo -e "Detected linux and will fetch latest release of compiled miner for this distro...${NC}"
    rm -rf /tmp/miner 2>/dev/null
    mkdir /tmp/miner 
    rm -rf $HOME/miner 2>/dev/null
    mkdir $HOME/miner
    pushd /tmp/miner
    curl -L $(curl -s https://api.github.com/repos/WyvernTKC/cpuminer-gr-avx2/releases/latest | jq -r '.assets[] | select(.name|test("linux")) | .browser_download_url') -o miner.7z
    7z x miner.7z
    cp -r cpuminer*/* $HOME/miner/
    popd
    rm -rf /tmp/miner 2>/dev/null
    sudo chmod -R 755  $HOME/miner/binaries/
    sudo chmod -R 755  $HOME/miner/cpuminer.sh

    echo -e "Update miner config for service to use..."
    if [[ ! -z $WORKER_NAME ]]; then
      WORKER_NAME=".$WORKER_NAME"
    fi

# Update config.json with proper pool, backup pool, wallet.worker, tune-full and log.
    sed -i "s/\"url\":.*/\"url\": \"${POOL}\",/g" $HOME/miner/config.json
    sed -i "s/\"url-backup\":.*/\"url-backup\": \"${BACKUP_POOL}\",/g" $HOME/miner/config.json
    sed -i "s/\"user\":.*/\"user\": \"${WORKER_ADDRESS}${WORKER_NAME}\",/g" $HOME/miner/config.json
    sed -i "s/\"tune-full\":.*/\"tune-full\": true,/g" $HOME/miner/config.json
    sed -i "s/\"threads\":.*/\"threads\": ${THREADS},/g" $HOME/miner/config.json
    sed -i "s/.*can be used to create logfile.*/\"log\": \"mining.log\",/g" $HOME/miner/config.json

    sudo sysctl -w vm.nr_hugepages=$(($THREADS*4))

    echo -e "${YELLOW}Creating service for the miner...${NC}"
    sudo touch /etc/systemd/system/miner.service
    sudo chown $USERNAME:$USERNAME /etc/systemd/system/miner.service
    cat << EOF > /etc/systemd/system/miner.service
[Unit]
Description=GhostRider Miner
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$HOME/miner
ExecStart=$HOME/miner/cpuminer.sh
ExecStop=/usr/bin/pkill cpuminer
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    sudo chown root:root /etc/systemd/system/miner.service
    sudo systemctl daemon-reload
    sudo systemctl enable miner
    sudo systemctl start miner

    echo -e "Creating script to update miner...${NC}"
    touch $HOME/update_miner.sh
    cat << EOF > $HOME/update_miner.sh
#!/bin/bash
sudo systemctl stop miner
echo "Removing old miner binaries"
rm \$HOME/miner/binaries/*

rm -rf /tmp/miner 2>/dev/null
mkdir /tmp/miner 
pushd /tmp/miner
curl -L \$(curl -s https://api.github.com/repos/WyvernTKC/cpuminer-gr-avx2/releases/latest | jq -r '.assets[] | select(.name|test("linux")) | .browser_download_url') -o miner.7z
7z x miner.7z
cp -r cpuminer*/binaries/* \$HOME/miner/binaries
cp -r cpuminer*/cpuminer.sh \$HOME/miner/
popd
rm -rf /tmp/miner 2>/dev/null

sudo systemctl start miner
EOF
    sudo chmod 775 $HOME/update_miner.sh
  else
    echo -e "${YELLOW}Skipping miner installation...${NC}"
  fi
}

#
#end of functions

# Clean the enviroment from possibly previous setup.
  wipe_clean

# Use arguments for super quick setup of the node.
# $1  SSH port
# $2  IP address
# $3  true, false to create swap if needed.
# $4  BLS privkey
# $5  true, false to set fail2ban etc
# $6  true, false to bootstrap.
# $7  true, false to set cronjob.
# $8  (if $7 is true) ProTX hash of the node.
#   -1 if $7 is false
# $9  true, false to Install miner
# $10 main pool: stratum+tcp://eu.flockpool.com:4444
# $11 backup pool: stratum+tcp://us.flockpool.com:4444
# $12 Wallet address: Rxxxxx
# $13 Worker Name: Node0X
# $14 threads: 4

QUICK_SETUP=""
if [[ $# == 14 || $# == 13 || $# == 9 || $# == 8 ]]; then
  echo -e "${YELLOW}Starting quick setup!${NC}"
  SSHPORT=${1}
  WANIP=${2}
  FORCE_SWAP=${3}
  smartnodeblsprivkey=${4}
  SECURITY_ANS=${5}
  BOOTSTRAP_ANS=${6}
  CRON_ANS=${7}
  if [[ $CRON_ANS == "true" ]]; then
    PROTX_HASH=${8}
    shift
  fi
  MINER_ANS=${8}
  
  POOL="$(echo ${9} | sed 's/\/\//\\\/\\\//g')"
  BACKUP_POOL="$(echo ${10} | sed 's/\/\//\\\/\\\//g')"
  WORKER_ADDRESS="${11}"
  WORKER_NAME="${12}"
  THREADS="${13}"

  echo -e  "${CYAN}SSH Port:${YELLOW} $SSHPORT ${NC}"
  echo -e  "${CYAN}IP addr:${YELLOW} $WANIP ${NC}"
  echo -e  "${CYAN}Force swap:${YELLOW} $FORCE_SWAP ${NC}"
  echo -e  "${CYAN}BLS Key:${YELLOW} $smartnodeblsprivkey ${NC}"
  echo -e  "${CYAN}Setup Fail2Ban:${YELLOW} $SECURITY_ANS ${NC}"
  echo -e  "${CYAN}Bootstrap chain:${YELLOW} $BOOTSTRAP_ANS ${NC}"
  echo -e  "${CYAN}Node healthcheck:${YELLOW} $CRON_ANS ${NC}"
  if [[ $CRON_ANS == "true" ]]; then
    echo -e  "${CYAN}ProTX Hash:${YELLOW} $PROTX_HASH ${NC}"
  fi

  echo -e  "${CYAN}Setup Miner:${YELLOW} $MINER_ANS ${NC}"
  if [[ $MINER_ANS == "true" ]]; then
    echo -e  "${CYAN}Miner main pool${YELLOW} $POOL  ${NC}"
    echo -e  "${CYAN}Miner backup pool${YELLOW} $BACKUP_POOL  ${NC}"
    echo -e  "${CYAN}Miner address${YELLOW} $WORKER_ADDRESS ${NC}"
    echo -e  "${CYAN}Miner worker${YELLOW} $WORKER_NAME ${NC}"
    echo -e  "${CYAN}Miner threads${YELLOW} $THREADS  ${NC}"
  fi

  echo -e "${CYAN}Node setup starting, press enter to start or [CTRL-C] to cancel.${NC}"
  read TMP
  QUICK_SETUP=1
fi

# Ask about about things first for quick setup.
if [[ -z $QUICK_SETUP ]]; then
  ssh_port
  ip_confirm
  create_swap
  create_conf true
  basic_security true
  bootstrap true
  cron_job true
  gr_miner true
else
  create_swap
fi

#Run functions.
  install_packages
  install_bins
  create_conf
  bootstrap
  create_service
  basic_security
  start_daemon
  cron_job
  log_rotate
  update_script
  gr_miner
  create_motd
