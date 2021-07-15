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
BLUE="\\033[38;5;27m"
SEA="\\033[38;5;49m"
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

function create_swap() {
  echo -e "${YELLOW}Creating swap if none detected...${NC}"
  if ! grep -q "swapfile" /etc/fstab; then
    if whiptail --yesno "No swapfile detected would you like to create one?" 8 54; then
      sudo fallocate -l 4G /swapfile
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile
      sudo swapon /swapfile
      echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
      echo -e "${YELLOW}Created ${SEA}4G${YELLOW} swapfile${NC}"
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

function create_conf() {
  if [[ -f $HOME/$CONFIG_DIR/$CONFIG_FILE ]]; then
    echo -e "${CYAN}Existing conf file found backing up to $COIN_NAME.old ...${NC}"
    mv $HOME/$CONFIG_DIR/$CONFIG_FILE $HOME/$CONFIG_DIR/$COIN_NAME.old;
  fi
  RPCUSER=$(pwgen -1 8 -n)
  PASSWORD=$(pwgen -1 20 -n)
  smartnodeblsprivkey=$(whiptail --inputbox "Enter your SmartNode BLS Privkey" 8 75 3>&1 1>&2 2>&3)
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
      SECURITY_ANS=1
    fi
  elif [[ ! -z $SECURITY_ANS ]]; then
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
      BOOTSTRAP_ANS=1
    fi
  elif [[ ! -z $BOOTSTRAP_ANS ]]; then
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
      CRON_ANS=1
      PROTX_HASH=$(whiptail --inputbox "Please enter your protx hash for this SmartNode" 8 51 3>&1 1>&2 2>&3)
    fi
  elif [[ ! -z $CRON_ANS ]]; then
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
  sleep 4
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
  sudo chmod 775 update.sh
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
BLUE="\\033[38;5;27m"
SEA="\\033[38;5;49m"
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
THREAD=""
TUNE="--tune-full"
# If $1 is provided, just ask about bootstrap.
function gr_miner () {
  if [[ ! -z $1 ]]; then
    if whiptail --yesno "Would you like to install the miner?" 8 40; then
      if whiptail --yesno "Please take notice that most cloud services do not allow mining and could result in your account being banned. Please read the provider's ToS before starting mining service. Would you like to install the miner?" 8 40; then
        MINER_ANS=1
        echo -e "${YELLOW}Checking hardware..."
        CPU=$(lscpu | grep -i 'Model name:' | cut -d ':' -f2 | sed 's/^[ \t]*//')
        if [[ $(lscpu) = *Intel* ]]; then
          if whiptail --yesno "Detected $CPU. Would you like to use avx2?" 8 50; then
            MINER_INST="cpuminer-avx2"
          else
            MINER_CHOICE=$(whiptail --menu "Select miner to use" 12 24 4 \
              "1" "avx512" \
              "2" "sse2" \
              "3" "sse42" \
              "4" "ssse3" 3>&1 1>&2 2>&3)
            case $MINER_CHOICE in
              1)
                echo -e "You have selected to use avx512"
                MINER_INST="cpuminer-avx512"
              ;;
              2)
                echo -e "You have selected to use sse2"
                MINER_INST="cpuminer-sse2"
                TUNE=""
              ;;
              3)
                echo -e "You have selected to use sse42"
                MINER_INST="cpuminer-sse42"
                TUNE=""
              ;;
              4)
                echo -e "You have selected to use ssse3"
                MINER_INST="cpuminer-ssse3"
                TUNE=""
              ;;
            esac
          fi
        elif [[ $(lscpu) = *AMD* ]]; then
          if whiptail --yesno "Detected $CPU. Would you like to use zen2?" 8 50; then
            MINER_INST="cpuminer-zen2"
          else
            MINER_CHOICE=$(whiptail --menu "Select miner to use" 10 24 2 \
              "1" "zen" \
              "2" "zen3" 3>&1 1>&2 2>&3)
            case $MINER_CHOICE in
              1)
                echo -e "You have selected to use zen"
                MINER_INST="cpuminer-zen"
              ;;
              2)
                echo -e "You have selected to use zen3"
                MINER_INST="cpuminer-zen3"
              ;;
            esac
          fi
        fi
        POOL_CHOICE=$(whiptail --menu "Select pool to use" 14 55 6 \
          "1" "stratum+tcp://r-pool.net:3008" \
          "2" "stratum+tcp://r-pool.net:3032" \
          "3" "stratum+tcp://rtm.suprnova.cc:6273" \
          "4" "stratum+tcp://stratum.us-la1.suprnova.cc:6273" \
          "5" "stratum+tcp://stratum.us-ny1.suprnova.cc:6273" \
          "6" "stratum+tcp://stratum.apac-hkg1.suprnova.cc:6273" 3>&1 1>&2 2>&3)
        case $POOL_CHOICE in
          1)
            echo -e "Selected r-pool for miners with <1kh/s."
            POOL="stratum+tcp://r-pool.net:3008"
          ;;
          2)
            echo -e "Selected r-pool for miners with >1kh/s."
            POOL="stratum+tcp://r-pool.net:3032"
          ;;
          3)
            echo -e "Selected EU Suprnova pool."
            POOL="stratum+tcp://rtm.suprnova.cc:6273"
          ;;
          4)
            echo -e "Selected West Coast US Suprnova pool."
            POOL="stratum+tcp://stratum.us-la1.suprnova.cc:6273"
          ;;
          5)
            echo -e "Selected East Coast US Suprnova pool."
            POOL="stratum+tcp://stratum.us-ny1.suprnova.cc:6273"
          ;;
          6)
            echo -e "Selected Asia Suprnova pool."
            POOL="stratum+tcp://stratum.apac-hkg1.suprnova.cc:6273"
          ;;
        esac
        WORKER_ADDRESS=$(whiptail --inputbox "Please enter RTM address you want pool to payout to" 8 55 3>&1 1>&2 2>&3)
        WORKER_NAME=$(whiptail --inputbox "Enter a worker name" 8 35 3>&1 1>&2 2>&3)
        THREAD_COUNT=$(grep -c processor /proc/cpuinfo)
        THREADS=$(whiptail --inputbox "Detected server has $THREAD_COUNT threads to use. How many threads would you like to mine with?" 8 50 3>&1 1>&2 2>&3)
      fi
    fi
  elif [[ ! -z $MINER_ANS ]]; then
    echo -e "${YELLOW}Setting up miner installation...${NC}"
    echo -e "Creating directory..."
    mkdir $HOME/miner
    echo -e "Installing required libraries..."
    sudo apt-get install unzip jq p7zip-full libssl-dev libcurl4-openssl-dev libjansson-dev libgmp-dev libnuma-dev -y
    echo -e "Checking distro version..."
    if [[ $(lsb_release -r) = *18.04* ]]; then
      echo -e "Detected Ubuntu 18.04 and will fetch latest release of compiled miner for this distro...${NC}"
      curl -L $(curl -s https://api.github.com/repos/WyvernTKC/cpuminer-gr-avx2/releases/latest | jq -r '.assets[] | select(.name|test("ubuntu_18")) | .browser_download_url') -o miner.7z
      7z e miner.7z -o$HOME/miner && rm miner.7z
    elif [[ $(lsb_release -r) = *20.04* ]]; then
      echo -e "Detected Ubuntu 20.04 and will fetch latest release of compiled miner for this distro...${NC}"
      curl -L $(curl -s https://api.github.com/repos/WyvernTKC/cpuminer-gr-avx2/releases/latest | jq -r '.assets[] | select(.name|test("ubuntu_20")) | .browser_download_url') -o miner.7z
      7z e miner.7z -o$HOME/miner && rm miner.7z
    fi
    echo -e "Creating script for service to use..."
    touch $HOME/miner.sh
    cat << EOF > $HOME/miner.sh
#!/bin/bash
miner -a gr -o $POOL -u $WORKER_ADDRESS.$WORKER_NAME -t $THREADS $TUNE
EOF
    sudo chmod 775 miner.sh
    sudo mv $HOME/miner.sh $COIN_PATH

    sudo sysctl -w vm.nr_hugepages=$(($THREAD_COUNT*4))

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
ExecStart=$COIN_PATH/miner.sh
ExecStop=/usr/bin/killall miner
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    sudo chown root:root /etc/systemd/system/miner.service
    sudo systemctl daemon-reload
    sudo systemctl enable miner

    echo -e "Creating script to update miner...${NC}"
    touch $HOME/update_miner.sh
    cat << EOF > $HOME/update_miner.sh
#!/bin/bash
MINER=$MINER_INST
sudo systemctl stop miner
echo "removing old miner"
rm \$HOME/miner/*
echo "Removing old mining bin"
sudo rm /usr/local/bin/miner
if [[ \$(lsb_release -r) = *18.04* ]]; then
  curl -L \$(curl -s https://api.github.com/repos/WyvernTKC/cpuminer-gr-avx2/releases/latest | jq -r '.assets[] | select(.name|test("ubuntu_18")) | .browser_download_url') -o miner.7z
  7z e miner.7z -o\$HOME/miner && rm miner.7z
elif [[ \$(lsb_release -r) = *20.04* ]]; then
  curl -L \$(curl -s https://api.github.com/repos/WyvernTKC/cpuminer-gr-avx2/releases/latest | jq -r '.assets[] | select(.name|test("ubuntu_20")) | .browser_download_url') -o miner.7z
  7z e miner.7z -o\$HOME/miner && rm miner.7z
fi
sudo cp \$HOME/miner/\$MINER /usr/local/bin/miner
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

# Ask about about things first for quick setup.
  ssh_port
  ip_confirm
  create_swap
  create_conf
  basic_security true
  bootstrap true
  cron_job true
  gr_miner true

#Run functions.
  install_packages
  install_bins
  bootstrap
  create_service
  basic_security
  start_daemon
  cron_job
  log_rotate
  update_script
  create_motd
  gr_miner
