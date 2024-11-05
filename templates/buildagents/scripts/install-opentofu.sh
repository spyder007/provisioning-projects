#!/bin/bash -e
################################################################################
##  File:  install-opentofu.sh
##  Desc:  Install opentofu
################################################################################

# Source the helpers for use with the script
source $HELPER_SCRIPTS/etc-environment.sh

# Install Miniconda
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh \
    && chmod +x install-opentofu.sh \
    && ./install-opentofu.sh --install-method deb \
    && rm install-opentofu.sh

set_etc_environment_variable "OPENTOFU" "/usr/bin/tofu"

