#!/bin/bash -e

# Source the helpers for use with the script
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/etc-environment.sh

# Set ImageVersion and ImageOS env variables
set_etc_environment_variable "ImageVersion" "${IMAGE_VERSION}"
set_etc_environment_variable "ImageOS" "${IMAGE_OS}"

# Set the ACCEPT_EULA variable to Y value to confirm your acceptance of the End-User Licensing Agreement
set_etc_environment_variable "ACCEPT_EULA" "Y"

# This directory is supposed to be created in $HOME and owned by user(https://github.com/actions/runner-images/issues/491)
mkdir -p /etc/skel/.config/configstore
set_etc_environment_variable "XDG_CONFIG_HOME" '$HOME/.config'

# Change waagent entries to use /mnt for swapfile
#sed -i 's/ResourceDisk.Format=n/ResourceDisk.Format=y/g' /etc/waagent.conf
#sed -i 's/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g' /etc/waagent.conf
#sed -i 's/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=4096/g' /etc/waagent.conf

# Add localhost alias to ::1 IPv6
#sed -i 's/::1 ip6-localhost ip6-loopback/::1     localhost ip6-localhost ip6-loopback/g' /etc/hosts

# Prepare directory and env variable for toolcache
AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
mkdir $AGENT_TOOLSDIRECTORY
set_etc_environment_variable "AGENT_TOOLSDIRECTORY" "${AGENT_TOOLSDIRECTORY}"
chmod -R 777 $AGENT_TOOLSDIRECTORY

# https://www.elastic.co/guide/en/elasticsearch/reference/current/vm-max-map-count.html
# https://www.suse.com/support/kb/doc/?id=000016692
echo 'vm.max_map_count=262144' | tee -a /etc/sysctl.conf

# https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
echo 'fs.inotify.max_user_watches=655360' | tee -a /etc/sysctl.conf
echo 'fs.inotify.max_user_instances=1280' | tee -a /etc/sysctl.conf

# https://github.com/actions/runner-images/pull/7860
netfilter_rule='/etc/udev/rules.d/50-netfilter.rules'
rules_directory="$(dirname "${netfilter_rule}")"
mkdir -p $rules_directory
touch $netfilter_rule
echo 'ACTION=="add", SUBSYSTEM=="module", KERNEL=="nf_conntrack", RUN+="/usr/sbin/sysctl net.netfilter.nf_conntrack_tcp_be_liberal=1"' | tee -a $netfilter_rule

# Create symlink for tests running
chmod +x $HELPER_SCRIPTS/invoke-tests.sh
ln -s $HELPER_SCRIPTS/invoke-tests.sh /usr/local/bin/invoke_tests

# Disable motd updates metadata
sed -i 's/ENABLED=1/ENABLED=0/g' /etc/default/motd-news

if [[ -f "/etc/fwupd/daemon.conf" ]]; then
    sed -i 's/UpdateMotd=true/UpdateMotd=false/g' /etc/fwupd/daemon.conf
    systemctl mask fwupd-refresh.timer
fi

# Disable to load providers
# https://github.com/microsoft/azure-pipelines-agent/issues/3834
if is_ubuntu22; then
    sed -i 's/openssl_conf = openssl_init/#openssl_conf = openssl_init/g' /etc/ssl/openssl.cnf
fi

env | grep Image >> /etc/agent_environment
env | grep ANDROID_ >> /etc/agent_environment
env | grep JAVA_ >> /etc/agent_environment
env | grep HOMEBREW_ >> /etc/agent_environment
env | grep ANT_ >> /etc/agent_environment
env | grep GRADLE_ >> /etc/agent_environment
env | grep LEIN_ >> /etc/agent_environment
env | grep CONDA >> /etc/agent_environment
env | grep PIPX_ >> /etc/agent_environment
env | grep AGENT_ >> /etc/agent_environment
env | grep EDGEWEBDRIVER >> /etc/agent_environment
env | grep CHROMEWEBDRIVER >> /etc/agent_environment
env | grep CHROME_BIN >> /etc/agent_environment
env | grep BOOTSTRAP_ >> /etc/agent_environment
env | grep GHCUP_ >> /etc/agent_environment
env | grep NVM_ >> /etc/agent_environment
env | grep SELENIUM_ >> /etc/agent_environment
env | grep SWIFT_ >> /etc/agent_environment
env | grep VCPKG_ >> /etc/agent_environment
env | grep DOTNET_ >> /etc/agent_environment
env | grep LANG >> /etc/agent_environment
env | grep M2_ >> /etc/agent_environment
env | grep VSTS_ >> /etc/agent_environment
env | grep LD_ >> /etc/agent_environment
env | grep PERL5LIB >> /etc/agent_environment