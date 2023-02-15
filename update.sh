#!/bin/bash
# https://github.com/BassT23/Proxmox

# Variable / Function
LOG_FILE=/var/log/update-$HOSTNAME.log    # <- change location for logfile if you want
VERSION="3.3"

#live
#SERVER_URL="https://raw.githubusercontent.com/BassT23/Proxmox/master"
#development
SERVER_URL="https://raw.githubusercontent.com/BassT23/Proxmox/beta"

# Colors
BL='\033[36m'
RD='\033[01;31m'
GN='\033[1;92m'
CL='\033[m'

# Header
function HEADER_INFO {
  clear
  echo -e "\n \
    https://github.com/BassT23/Proxmox"
  cat <<'EOF'
     ____
    / __ \_________  _  ______ ___  ____  _  __
   / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/
  / ____/ /  / /_/ />  </ / / / / / /_/ />  <
 /_/   /_/   \____/_/|_/_/ /_/ /_/\____/_/|_|
      __  __          __      __
     / / / /___  ____/ /___ _/ /____  ____
    / / / / __ \/ __  / __ `/ __/ _ \/ __/
   / /_/ / /_/ / /_/ / /_/ / /_/  __/ /
   \____/ .___/\____/\____/\__/\___/_/
       /_/
EOF
  echo -e "\n \
           *** Mode: $MODE ***"
  if [[ $HEADLESS == true ]]; then
    echo -e "            ***    Headless    ***"
  else
    echo -e "            ***  Interactive   ***"
  fi
  CHECK_ROOT
  VERSION_CHECK
}

# Check root
function CHECK_ROOT {
  if [[ $RICM != true && $EUID -ne 0 ]]; then
      echo -e "\n ${RD}--- Please run this as root ---${CL}\n"
      exit 2
  fi
}

function USAGE {
  if [[ $HEADLESS != true ]]; then
      echo -e "\nUsage: $0 [OPTIONS...] {COMMAND}\n"
      echo -e "[OPTIONS] Manages the Proxmox-Updater:"
      echo -e "======================================"
      echo -e "  -h --help            Show this help"
      echo -e "  -v --version         Show Proxmox-Updater Version"
      echo -e "  -s --silent          Silent / Headless Mode\n"
      echo -e "  -up                  Update Proxmox-Updater\n"
      echo -e "Commands:"
      echo -e "========="
      echo -e "  host                 Host-Mode"
      echo -e "  cluster              Cluster-Mode"
      echo -e "  uninstall            Uninstall Proxmox-Updater\n"
      echo -e "Report issues at: <https://github.com/BassT23/Proxmox/issues>\n"
  fi
}

function VERSION_CHECK {
  curl -s $SERVER_URL/update.sh > /root/update.sh
  SERVER_VERSION=$(awk -F'"' '/^VERSION=/ {print $2}' /root/update.sh)
  if [[ $VERSION != $SERVER_VERSION ]]; then
    echo -e "\n${RD}   *** A newer version is available ***${CL}\n \
      Installed: $VERSION / Server: $SERVER_VERSION\n"
    if [[ $HEADLESS != true ]]; then
      echo -e "${RD}Want to update first Proxmox-Updater?${CL}"
      read -p "Type [Y/y] or Enter for yes - enything else will skip " -n 1 -r -s
      if [[ $REPLY =~ ^[Yy]$ || $REPLY = "" ]]; then
        bash <(curl -s $SERVER_URL/install.sh) update
      fi
      echo
    fi
  else
    echo -e "\n             ${GN}Script is UpToDate${CL}\n \
             Version: $VERSION"
  fi
  rm -rf /root/update.sh
}

function UPDATE {
  bash <(curl -s $SERVER_URL/install.sh) update
  exit 2
}

function UNINSTALL {
  echo -e "\n${BL}[Info]${GN} Uninstall Proxmox-Updater${CL}\n"
  echo -e "${RD}Really want to remove Proxmox-Updater?${CL}"
  read -p "Type [Y/y] for yes - enything else will exit " -n 1 -r -s
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash <(curl -s $SERVER_URL/install.sh) uninstall
  else
    exit 2
  fi
}

# Extras
function EXTRAS {
  if [[ $HEADLESS != true ]]; then
    echo -e "--- Searching for extra updates ---\n"
    pct push "$CONTAINER" -- /root/Proxmox-Update-Scripts/update-extras.sh /root/update-extras.sh
    pct exec "$CONTAINER" -- bash -c "chmod +x /root/update-extras.sh && \
                                      /root/update-extras.sh && \
                                      rm -rf /root/update-extras.sh"
  else
    echo -e "--- Skip Extra Updates because of Headless Mode---\n"
  fi
}

# Host Update
function UPDATE_HOST {
  HOST=$1
  echo -e "\n${BL}[Info]${GN} Updating${CL} : ${GN}$HOST${CL}"
  ssh "$HOST" mkdir -p /root/Proxmox-Update-Scripts/
  scp /root/Proxmox-Update-Scripts/update-extras.sh "$HOST":/root/Proxmox-Update-Scripts/update-extras.sh
  if [[ $HEADLESS == true ]]; then
    ssh "$HOST" 'bash -s' < "$0" -- "-s -c host"
  else
    ssh "$HOST" 'bash -s' < "$0" -- "-c host"
  fi
}

# Host Update Start
function HOST_UPDATE_START {
  for HOST in $HOSTS; do
    UPDATE_HOST "$HOST"
  done
}

# Container Update
function UPDATE_CONTAINER {
  CONTAINER=$1
  NAME=$(pct exec "$CONTAINER" hostname)
  echo -e "${BL}[Info]${GN} Updating LXC ${BL}$CONTAINER${CL} : ${GN}$NAME${CL}\n"
  pct config "$CONTAINER" > temp
  os=$(awk '/^ostype/' temp | cut -d' ' -f2)
  case "$os" in
    "ubuntu" | "debian" | "devuan")
      pct exec "$CONTAINER" -- bash -c "echo -e --- APT UPDATE --- && \
                                        apt-get update && echo"
      if [[ $HEADLESS == true ]]; then
        pct exec "$CONTAINER" -- bash -c "echo -e --- APT UPGRADE HEADLESS --- && \
                                          DEBIAN_FRONTEND=noninteractive apt-get -o APT::Get::Always-Include-Phased-Updates=true dist-upgrade -y && echo"
      else
        pct exec "$CONTAINER" -- bash -c "echo -e --- APT UPGRADE --- && \
                                          apt-get -o APT::Get::Always-Include-Phased-Updates=true dist-upgrade -y && echo"
      fi
      pct exec "$CONTAINER" -- bash -c "echo -e --- APT CLEANING --- && \
                                        apt-get --purge autoremove -y && echo"
      EXTRAS
      ;;
    "fedora")
      pct exec "$CONTAINER" -- bash -c "echo -e --- DNF UPDATE --- && \
                                        dnf -y update && echo"
      pct exec "$CONTAINER" -- bash -c "echo -e --- DNF UPGRATE --- && \
                                        dnf -y upgrade && echo"
      pct exec "$CONTAINER" -- bash -c "echo -e --- DNF CLEANING --- && \
                                        dnf -y --purge autoremove && echo"
      EXTRAS
      ;;
    "archlinux")
      pct exec "$CONTAINER" -- bash -c "echo -e --- PACMAN UPDATE --- && \
                                        pacman -Syyu --noconfirm && echo"
      EXTRAS
      ;;
    "alpine")
      pct exec "$CONTAINER" -- ash -c "echo -e --- APK UPDATE --- && \
                                       apk -U upgrade && echo"
      EXTRAS
      ;;
    *)
      pct exec "$CONTAINER" -- bash -c "echo -e --- YUM UPDATE --- && \
                                        yum -y update && echo"
      EXTRAS
      ;;
  esac
}

# Container Update Start
function CONTAINER_UPDATE_START {
  # Get the list of containers
  CONTAINERS=$(pct list | tail -n +2 | cut -f1 -d' ')
  # Loop through the containers
  for CONTAINER in $CONTAINERS; do
    status=$(pct status "$CONTAINER")
    if [[ $status == "status: stopped" ]]; then
      echo -e "${BL}[Info]${GN} Starting${BL} $CONTAINER ${CL}\n"
      # Start the container
      pct start "$CONTAINER"
      echo -e "${BL}[Info]${GN} Waiting For${BL} $CONTAINER${CL}${GN} To Start ${CL}\n"
      sleep 5
      UPDATE_CONTAINER "$CONTAINER"
      echo -e "${BL}[Info]${GN} Shutting down${BL} $CONTAINER ${CL}\n"
      # Stop the container
      pct shutdown "$CONTAINER" &
    elif [[ $status == "status: running" ]]; then
      UPDATE_CONTAINER "$CONTAINER"
    fi
  done
  rm -rf temp
}

function UPDATE_HOST_ITSELF {
  echo -e "\n--- APT UPDATE ---" && apt-get update
  if [[ $HEADLESS == true ]]; then
    echo -e "\n--- APT UPGRADE HEADLESS ---" && \
            DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  else
    echo -e "\n--- APT UPGRADE ---" && \
            apt-get upgrade -y
  fi
  echo -e "\n--- APT CLEANING ---" && \
          apt-get --purge autoremove -y && echo
}

# Logging
if [[ $RICM != true ]]; then
  touch "$LOG_FILE"
  exec &> >(tee "$LOG_FILE")
fi
function CLEAN_LOGFILE {
  if [[ $RICM != true ]]; then
    tail -n +2 "$LOG_FILE" > tmp.log && mv tmp.log "$LOG_FILE"
    cat $LOG_FILE | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" | tee "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    if [[ -f ./tmp.log ]]; then
      rm -rf ./tmp.log
    fi
  fi
}

function EXIT {
  EXIT_CODE=$?
  # Exit direct
  if [[ $EXIT_CODE == 2 ]]; then
#    CLEAN_LOGFILE
    exit
  # Update Finish
  elif [[ $EXIT_CODE == 0 ]]; then
    if [[ $RICM != true ]]; then
      echo -e "${GN}Finished, All Containers Updated.${CL}\n"
      /root/Proxmox-Update-Scripts/exit/passed.sh
      CLEAN_LOGFILE
    fi
  # Update Error
  else
    if [[ $RICM != true ]]; then
      echo -e "${RD}Error during Update --- Exit Code: $EXIT_CODE${CL}\n"
      /root/Proxmox-Update-Scripts/exit/error.sh
      CLEAN_LOGFILE
    fi
  fi

}

# Exit Code
set -e
trap EXIT EXIT

# Check Cluster Mode
if [[ -f /etc/corosync/corosync.conf ]]; then
  HOSTS=$(awk '/ring0_addr/{print $2}' "/etc/corosync/corosync.conf")
fi

# Update Start
export TERM=xterm-256color
parse_cli()
{
  while test $# -gt -0
  do
    _key="$1"
    case "$_key" in
      -h|--help)
        USAGE
        exit 2
        ;;
      -s|--silent)
        HEADLESS=true
        ;;
      -v|--version)
        HEADLESS=true
        VERSION_CHECK
#        echo -e "  Proxmox-Updater version is v$VERSION (Latest: v$SERVER_VERSION)"
        exit 2
        ;;
      -c)
        RICM=true
        ;;
      host)
        COMMAND=true
        if [[ $RICM != true ]]; then
          MODE="  Host  "
          HEADER_INFO
          echo -e "\n${BL}[Info]${GN} Updating${CL} : ${GN}$HOSTNAME${CL}"
        fi
        UPDATE_HOST_ITSELF
        CONTAINER_UPDATE_START
        ;;
      cluster)
        COMMAND=true
        MODE=" Cluster"
        HEADER_INFO
        HOST_UPDATE_START
        ;;
      uninstall)
        COMMAND=true
        UNINSTALL
        exit 0
        ;;
      -up)
        COMMAND=true
        UPDATE
        exit 0
        ;;
      *)
        echo -e "${RD}Error: Got an unexpected argument \"$_key\"${CL}";
        USAGE;
        exit 2;
        ;;
    esac
    shift
  done
}
parse_cli "$@"

# Run without commands (Automatic Mode)
if [[ $COMMAND != true && $RICM != true ]]; then
  if [[ -f /etc/corosync/corosync.conf ]]; then
    MODE=" Cluster"
    HEADER_INFO
    HOST_UPDATE_START
  else
    MODE="  Host  "
    HEADER_INFO
    echo -e "\n${BL}[Info]${GN} Updating${CL} : ${GN}$HOSTNAME${CL}"
    UPDATE_HOST_ITSELF
    CONTAINER_UPDATE_START
  fi
fi

exit 0